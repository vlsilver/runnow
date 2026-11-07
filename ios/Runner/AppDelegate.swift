import Accelerate
import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CardVideoWriter") {
      CardVideoWriter.register(with: registrar)
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
