import Accelerate
import AVFoundation
import Flutter
import ReplayKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CardVideoWriter") {
      CardVideoWriter.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenClipRecorder") {
      ScreenClipRecorder.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RunFileInbox") {
      RunFileInbox.register(with: registrar)
    }
  }
}

/// Ghi lá thẻ xoay thành MP4 H.264 cho màn khoe thẻ (run_card_share.dart).
/// Dart đẩy từng khung RGBA ngay khi chụp; mọi việc chạy trên một hàng đợi
/// riêng nên các lệnh tới theo đúng thứ tự gọi.
final class CardVideoWriter: NSObject, FlutterPlugin {
  private let queue = DispatchQueue(label: "runnow.card-video")
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var width = 0
  private var height = 0
  private var fps: Int32 = 30
  private var frameIndex: Int64 = 0

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "runnow/card_video", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CardVideoWriter(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    queue.async {
      let reply: Any?
      do {
        switch call.method {
        case "start":
          try self.start(call.arguments as? [String: Any] ?? [:])
          reply = nil
        case "frame":
          guard let data = call.arguments as? FlutterStandardTypedData else {
            throw CardVideoError("frame cần bytes RGBA")
          }
          try self.append(data.data)
          reply = nil
        case "finish":
          try self.finish()
          reply = nil
        case "cancel":
          self.cancel()
          reply = nil
        default:
          reply = FlutterMethodNotImplemented
        }
      } catch {
        reply = FlutterError(
          code: "card_video", message: "\(error)", details: nil)
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  private func start(_ args: [String: Any]) throws {
    cancel()
    guard let path = args["path"] as? String,
      let w = args["width"] as? Int, let h = args["height"] as? Int,
      let fps = args["fps"] as? Int, let bitRate = args["bitRate"] as? Int
    else { throw CardVideoError("start thiếu tham số") }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: w,
        AVVideoHeightKey: h,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: bitRate,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
          AVVideoMaxKeyFrameIntervalKey: fps,
        ],
      ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: w,
        kCVPixelBufferHeightKey as String: h,
      ])
    guard writer.canAdd(input) else { throw CardVideoError("không thêm được luồng video") }
    writer.add(input)
    guard writer.startWriting() else {
      throw CardVideoError("không mở được file: \(String(describing: writer.error))")
    }
    writer.startSession(atSourceTime: .zero)
    (self.writer, self.input, self.adaptor) = (writer, input, adaptor)
    (width, height, self.fps, frameIndex) = (w, h, Int32(fps), 0)
  }

  private func append(_ rgba: Data) throws {
    guard let writer, let input, let adaptor else { throw CardVideoError("chưa start") }
    guard rgba.count == width * height * 4 else {
      throw CardVideoError("khung \(rgba.count) byte, cần \(width * height * 4)")
    }
    // Ghi không theo thời gian thực nên chỉ cần chờ bộ mã hoá rảnh.
    var waited = 0
    while !input.isReadyForMoreMediaData {
      guard writer.status == .writing, waited < 5000 else {
        throw CardVideoError("bộ mã hoá không nhận khung: \(String(describing: writer.error))")
      }
      usleep(1000)
      waited += 1
    }
    guard let pool = adaptor.pixelBufferPool else { throw CardVideoError("chưa có pixel buffer") }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { throw CardVideoError("không cấp được pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    var status: vImage_Error = kvImageNoError
    rgba.withUnsafeBytes { raw in
      var src = vImage_Buffer(
        data: UnsafeMutableRawPointer(mutating: raw.baseAddress!),
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: width * 4)
      var dst = vImage_Buffer(
        data: CVPixelBufferGetBaseAddress(buffer),
        height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: CVPixelBufferGetBytesPerRow(buffer))
      // RGBA của Flutter sang BGRA của pixel buffer.
      status = vImagePermuteChannels_ARGB8888(&src, &dst, [2, 1, 0, 3], vImage_Flags(kvImageNoFlags))
    }
    guard status == kvImageNoError else { throw CardVideoError("đổi màu lỗi \(status)") }
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps)) else {
      throw CardVideoError("không ghi được khung: \(String(describing: writer.error))")
    }
    frameIndex += 1
  }

  private func finish() throws {
    guard let writer, let input else { throw CardVideoError("chưa start") }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    (self.writer, self.input, self.adaptor) = (nil, nil, nil)
    guard writer.status == .completed else {
      throw CardVideoError("không đóng được video: \(String(describing: writer.error))")
    }
  }

  /// Bỏ video đang ghi dở và xoá file.
  private func cancel() {
    guard let writer else { return }
    writer.cancelWriting()
    try? FileManager.default.removeItem(at: writer.outputURL)
    (self.writer, self.input, self.adaptor) = (nil, nil, nil)
  }
}

struct CardVideoError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

/// Quay màn hình app thành MP4 cho màn xem lại buổi chạy 3D
/// (route_replay_screen.dart). Map 3D là view native nên Flutter không chụp
/// được từng khung như lá thẻ. ReplayKit lấy khung từ bộ dựng hình của hệ
/// thống nên không chặn main thread, map vẫn chạy mượt trong lúc quay; đổi lại
/// iOS hỏi quyền quay màn hình ở mỗi lượt. Khung ReplayKit giao là cả màn
/// hình, ở đây cắt lấy vùng 9:16 mà màn replay yêu cầu, không phóng thu.
final class ScreenClipRecorder: NSObject, FlutterPlugin {
  private struct Crop {
    let x: Int, y: Int, width: Int, height: Int
  }

  /// ReplayKit giao khung trên luồng của nó; mọi trạng thái dưới đây chỉ đụng
  /// tới trong hàng đợi này.
  private let queue = DispatchQueue(label: "runnow.screen-clip")
  private var url: URL?
  /// Vùng cần quay theo tỉ lệ so với cả màn hình (0...1).
  private var region = CGRect.zero
  private var crop: Crop?
  private var writer: AVAssetWriter?
  private var input: AVAssetWriterInput?
  private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
  private var failure: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "runnow/screen_clip", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ScreenClipRecorder(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    func reply(_ failure: String?) {
      result(failure.map { FlutterError(code: "screen_clip", message: $0, details: nil) })
    }
    switch call.method {
    case "start":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        let left = args["left"] as? Double, let top = args["top"] as? Double,
        let width = args["width"] as? Double, let height = args["height"] as? Double,
        width > 0, height > 0
      else { return reply("start cần path và vùng quay left, top, width, height") }
      start(
        URL(fileURLWithPath: path),
        region: CGRect(x: left, y: top, width: width, height: height), reply)
    case "stop":
      stop(reply)
    case "cancel":
      cancel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// [region] tính bằng điểm trong cửa sổ app. [done] chạy trên main sau khi
  /// người dùng trả lời hộp hỏi quyền: nil là đang quay, ngược lại là lý do.
  private func start(_ url: URL, region: CGRect, _ done: @escaping (String?) -> Void) {
    let recorder = RPScreenRecorder.shared()
    guard recorder.isAvailable else { return done("máy đang không cho quay màn hình") }
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    guard let screen = window?.bounds.size, screen.width > 0, screen.height > 0 else {
      return done("không tìm thấy cửa sổ app")
    }
    let unit = CGRect(
      x: region.minX / screen.width, y: region.minY / screen.height,
      width: region.width / screen.width, height: region.height / screen.height
    ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    let begin = {
      self.queue.sync {
        self.discard()
        try? FileManager.default.removeItem(at: url)
        (self.url, self.region) = (url, unit)
      }
      recorder.isMicrophoneEnabled = false
      recorder.startCapture(
        handler: { [weak self] sample, type, error in
          guard let self, type == .video else { return }
          self.queue.async {
            if let error {
              self.failure = self.failure ?? error.localizedDescription
            } else {
              self.append(sample)
            }
          }
        },
        completionHandler: { error in
          DispatchQueue.main.async { done(error?.localizedDescription) }
        })
    }
    // Lượt trước bị bỏ dở mà hệ thống chưa dừng xong thì chờ nó dừng đã.
    if recorder.isRecording {
      recorder.stopCapture { _ in DispatchQueue.main.async(execute: begin) }
    } else {
      begin()
    }
  }

  /// Chỉ gọi trong [queue].
  private func append(_ sample: CMSampleBuffer) {
    guard failure == nil, let url, CMSampleBufferDataIsReady(sample),
      let frame = CMSampleBufferGetImageBuffer(sample)
    else { return }
    if writer == nil {
      // Cỡ và định dạng khung chỉ biết khi khung đầu tới.
      do {
        try open(url, frame, at: CMSampleBufferGetPresentationTimeStamp(sample))
      } catch {
        failure = "\(error)"
        return
      }
    }
    // Bộ mã hoá chưa kịp thì bỏ khung này, video vẫn đúng thời gian thật.
    guard let input, let adaptor, let crop, input.isReadyForMoreMediaData else { return }
    guard let pool = adaptor.pixelBufferPool else { return }
    var made: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
    guard let cut = made else {
      failure = "không cấp được pixel buffer"
      return
    }
    Self.copy(frame, crop, into: cut)
    if !adaptor.append(cut, withPresentationTime: CMSampleBufferGetPresentationTimeStamp(sample)) {
      failure = "không ghi được khung: \(String(describing: writer?.error))"
    }
  }

  private func open(_ url: URL, _ frame: CVPixelBuffer, at time: CMTime) throws {
    // ReplayKit giao khung YCbCr hai mặt phẳng (Y, rồi CbCr nửa độ phân giải).
    // Cắt theo cách của định dạng đó, gặp định dạng khác thì báo chứ không đoán.
    let format = CVPixelBufferGetPixelFormatType(frame)
    guard
      format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    else { throw CardVideoError("khung quay có định dạng lạ \(format)") }
    let full = (width: CVPixelBufferGetWidth(frame), height: CVPixelBufferGetHeight(frame))
    // CbCr dùng chung cho từng ô 2×2 nên mép cắt và cỡ cắt phải chẵn.
    let x = Int(region.minX * CGFloat(full.width)) & ~1
    let y = Int(region.minY * CGFloat(full.height)) & ~1
    let crop = Crop(
      x: x, y: y,
      width: min(Int(region.width * CGFloat(full.width)), full.width - x) & ~1,
      height: min(Int(region.height * CGFloat(full.height)), full.height - y) & ~1)
    guard crop.width > 0, crop.height > 0 else { throw CardVideoError("vùng quay rỗng") }
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: crop.width,
        AVVideoHeightKey: crop.height,
        AVVideoCompressionPropertiesKey: [
          AVVideoAverageBitRateKey: 8_000_000,
          AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
      ])
    input.expectsMediaDataInRealTime = true
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: format,
        kCVPixelBufferWidthKey as String: crop.width,
        kCVPixelBufferHeightKey as String: crop.height,
      ])
    guard writer.canAdd(input) else { throw CardVideoError("không thêm được luồng video") }
    writer.add(input)
    guard writer.startWriting() else {
      throw CardVideoError("không mở được file: \(String(describing: writer.error))")
    }
    writer.startSession(atSourceTime: time)
    (self.writer, self.input, self.adaptor, self.crop) = (writer, input, adaptor, crop)
  }

  /// Chép vùng [crop] của [frame] sang [cut], cả hai là YCbCr hai mặt phẳng.
  private static func copy(_ frame: CVPixelBuffer, _ crop: Crop, into cut: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(frame, .readOnly)
    CVPixelBufferLockBaseAddress(cut, [])
    defer {
      CVPixelBufferUnlockBaseAddress(cut, [])
      CVPixelBufferUnlockBaseAddress(frame, .readOnly)
    }
    for plane in 0..<2 {
      // Mặt CbCr thưa một nửa theo chiều dọc; theo chiều ngang mỗi cặp Cb, Cr
      // chiếm 2 byte cho 2 điểm ảnh, nên độ lệch và độ dài tính bằng byte vẫn
      // bằng của mặt Y.
      let step = plane == 0 ? 1 : 2
      guard let from = CVPixelBufferGetBaseAddressOfPlane(frame, plane),
        let to = CVPixelBufferGetBaseAddressOfPlane(cut, plane)
      else { continue }
      let fromRow = CVPixelBufferGetBytesPerRowOfPlane(frame, plane)
      let toRow = CVPixelBufferGetBytesPerRowOfPlane(cut, plane)
      for row in 0..<(crop.height / step) {
        memcpy(
          to + row * toRow, from + (crop.y / step + row) * fromRow + crop.x, crop.width)
      }
    }
    CVBufferPropagateAttachments(frame, cut)
  }

  /// Dừng quay và đóng file; [done] chạy trên main, nhận nil khi video dùng
  /// được, ngược lại là lý do.
  private func stop(_ done: @escaping (String?) -> Void) {
    RPScreenRecorder.shared().stopCapture { error in
      self.queue.async {
        func finish(_ failure: String?) { DispatchQueue.main.async { done(failure) } }
        if let failure = self.failure ?? error?.localizedDescription {
          self.discard()
          return finish(failure)
        }
        guard let writer = self.writer, let input = self.input else {
          self.discard()
          return finish("ReplayKit không giao khung hình nào")
        }
        (self.url, self.writer, self.input, self.adaptor, self.crop) = (nil, nil, nil, nil, nil)
        input.markAsFinished()
        writer.finishWriting {
          finish(
            writer.status == .completed
              ? nil : "không đóng được video: \(String(describing: writer.error))")
        }
      }
    }
  }

  /// Bỏ video đang quay dở và xoá file.
  private func cancel() {
    let recorder = RPScreenRecorder.shared()
    if recorder.isRecording { recorder.stopCapture { _ in } }
    queue.async { self.discard() }
  }

  /// Chỉ gọi trong [queue].
  private func discard() {
    writer?.cancelWriting()
    if let url { try? FileManager.default.removeItem(at: url) }
    (url, writer, input, adaptor, crop, failure) = (nil, nil, nil, nil, nil, nil)
  }
}

/// Nhận file .gpx, .tcx, .fit người dùng mở bằng 3i Run (Files, Garmin, Strava) để xem lại
/// 3D. Giữ nội dung file tới khi Dart gọi `take`; báo `opened` để app đang chạy
/// lấy ngay, còn lúc mở app từ đầu thì Dart tự gọi `take` khi sẵn sàng.
final class RunFileInbox: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?
  private var pending: FlutterStandardTypedData?

  static func register(with registrar: FlutterPluginRegistrar) {
    let inbox = RunFileInbox()
    let channel = FlutterMethodChannel(
      name: "runnow/run_file_inbox", binaryMessenger: registrar.messenger())
    inbox.channel = channel
    registrar.addMethodCallDelegate(inbox, channel: channel)
    registrar.addSceneDelegate(inbox)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "take" else { return result(FlutterMethodNotImplemented) }
    result(pending)
    pending = nil
  }

  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    receive(connectionOptions?.urlContexts ?? [])
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    receive(URLContexts)
  }

  private func receive(_ contexts: Set<UIOpenURLContext>) -> Bool {
    guard
      let url = contexts.map(\.url).first(where: {
        $0.isFileURL && ["gpx", "tcx", "fit"].contains($0.pathExtension.lowercased())
      })
    else { return false }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    // Quá runFileMaxBytes (Dart) hay đọc hỏng thì giao rỗng để Dart báo không đọc được.
    let maxBytes = 32 * 1024 * 1024
    var data = Data()
    do {
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let read = try handle.read(upToCount: maxBytes + 1) ?? Data()
      if read.count <= maxBytes { data = read }
    } catch {
      NSLog("RunFileInbox: không đọc được \(url.lastPathComponent): \(error)")
    }
    pending = FlutterStandardTypedData(bytes: data)
    // iOS chép file vào Documents/Inbox của app; đọc xong thì xoá cho khỏi đầy.
    try? FileManager.default.removeItem(at: url)
    channel?.invokeMethod("opened", arguments: nil)
    return true
  }
}
