package com.threei.run

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.PixelFormat
import android.graphics.Rect
import android.hardware.HardwareBuffer
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Quay màn hình app thành MP4 cho màn xem lại buổi chạy 3D
 * (route_replay_screen.dart), bản Android của ScreenClipRecorder trong
 * AppDelegate.swift. Map 3D là view native nên Flutter không chụp được từng
 * khung. MediaProjection đổ cả màn hình vào [ImageReader]; mỗi khung được cắt
 * lấy vùng 9:16 Dart yêu cầu rồi vẽ lên surface của bộ mã hoá bằng canvas phần
 * cứng, không chép điểm ảnh qua CPU. Android hỏi quyền ở mỗi lượt quay, và từ
 * Android 14 phải có foreground service loại mediaProjection chạy trước.
 *
 * Cần Android 10 (API 29): bọc khung [Image] thành [Bitmap] phần cứng.
 */
class ScreenClipRecorder private constructor(
    private val activity: FlutterActivity,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val REQUEST = 4231
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC

        /** Cạnh ngắn của video không quá chừng này, để bộ mã hoá máy nào cũng nhận. */
        private const val MAX_WIDTH = 1080

        private var instance: ScreenClipRecorder? = null

        fun register(activity: FlutterActivity, messenger: BinaryMessenger) {
            instance?.cancel()
            val recorder = ScreenClipRecorder(activity)
            instance = recorder
            MethodChannel(messenger, "runnow/screen_clip").setMethodCallHandler(recorder)
        }

        /** MainActivity chuyển kết quả hộp hỏi quyền về đây. */
        fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
            if (requestCode != REQUEST) return false
            instance?.onConsent(resultCode, data)
            return true
        }
    }

    /** Một lượt quay đang chạy; mọi thứ của lượt đó gói ở đây để huỷ cho gọn. */
    private class Session(val file: File, val crop: Rect, val scale: Float) {
        /** Luồng quay: vẽ khung, nhận khung đã mã hoá và dọn dẹp đều chạy ở đây. */
        var thread: HandlerThread? = null
        var handler: Handler? = null
        var projection: MediaProjection? = null
        var display: VirtualDisplay? = null
        var reader: ImageReader? = null
        var codec: MediaCodec? = null
        var input: Surface? = null
        var muxer: MediaMuxer? = null
        var track = -1
        var frames = 0

        /** Khung đã vẽ ở lượt trước; giữ tới khung sau mới đóng vì GPU có thể còn đọc. */
        var shown: Image? = null

        /** Đã dừng nhận khung: [draw] bỏ qua, MediaProjection dừng không tính là lỗi. */
        @Volatile var stopped = false

        @Volatile var failure: String? = null
        val ended = CountDownLatch(1)
    }

    private val main = Handler(Looper.getMainLooper())
    private var session: Session? = null
    private var pending: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            "stop" -> stop(result)
            "cancel" -> {
                cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return result.error("screen_clip", "cần Android 10 trở lên", null)
        }
        val path = call.argument<String>("path")
        val left = call.argument<Double>("left")
        val top = call.argument<Double>("top")
        val width = call.argument<Double>("width")
        val height = call.argument<Double>("height")
        if (path == null || left == null || top == null || width == null || height == null ||
            width <= 0 || height <= 0
        ) {
            return result.error("screen_clip", "start cần path và vùng quay left, top, width, height", null)
        }
        cancel()
        val screen = screenSize()
        // Dart đo theo điểm logic trong FlutterView; đổi ra điểm ảnh trên màn hình.
        val density = activity.resources.displayMetrics.density
        val origin = IntArray(2)
        activity.findViewById<android.view.View>(FlutterActivity.FLUTTER_VIEW_ID)
            ?.getLocationOnScreen(origin)
        val region = Rect(
            (origin[0] + left * density).roundToInt(),
            (origin[1] + top * density).roundToInt(),
            (origin[0] + (left + width) * density).roundToInt(),
            (origin[1] + (top + height) * density).roundToInt(),
        )
        if (!region.intersect(0, 0, screen.width(), screen.height())) {
            return result.error("screen_clip", "vùng quay nằm ngoài màn hình", null)
        }
        // Màn hình lớn thì cho hệ thống thu nhỏ cả khung trước khi giao, video
        // không vượt [MAX_WIDTH] mà vẫn giữ đúng tỉ lệ.
        val scale = min(1f, MAX_WIDTH.toFloat() / region.width())
        // Bộ mã hoá H.264 của nhiều máy chỉ nhận cạnh chia hết cho 16.
        val outWidth = ((region.width() * scale).toInt() / 16) * 16
        val outHeight = ((region.height() * scale).toInt() / 16) * 16
        if (outWidth <= 0 || outHeight <= 0) {
            return result.error("screen_clip", "vùng quay rỗng", null)
        }
        val crop = Rect(
            (region.left * scale).toInt(),
            (region.top * scale).toInt(),
            (region.left * scale).toInt() + outWidth,
            (region.top * scale).toInt() + outHeight,
        )
        val file = File(path).apply { delete() }
        session = Session(file, crop, scale)
        pending = result
        val manager = activity.getSystemService(MediaProjectionManager::class.java)
        // Android 14 trở lên mặc định hỏi "chia sẻ một app" rồi bắt chọn app.
        // Vùng cắt tính theo toàn màn hình nên xin luôn cả màn, hộp thoại chỉ
        // còn một nút đồng ý.
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        activity.startActivityForResult(intent, REQUEST)
    }

    /** Kết quả hộp hỏi quyền; trả lời lệnh start đang chờ. */
    private fun onConsent(resultCode: Int, data: Intent?) {
        val result = pending ?: return
        pending = null
        val current = session ?: return result.error("screen_clip", "lượt quay đã bị huỷ", null)
        if (resultCode != Activity.RESULT_OK || data == null) {
            cancel()
            return result.error("screen_clip", "bạn chưa cho quay màn hình", null)
        }
        // Android 14 đòi foreground service loại mediaProjection chạy trước khi
        // lấy MediaProjection.
        ScreenClipService.onReady = {
            ScreenClipService.onReady = null
            if (session !== current) {
                result.error("screen_clip", "lượt quay đã bị huỷ", null)
            } else {
                try {
                    begin(current, resultCode, data)
                    result.success(null)
                } catch (error: Exception) {
                    cancel()
                    result.error("screen_clip", error.message ?: error.toString(), null)
                }
            }
        }
        try {
            activity.startForegroundService(Intent(activity, ScreenClipService::class.java))
        } catch (error: Exception) {
            cancel()
            result.error("screen_clip", "không bật được dịch vụ quay: ${error.message}", null)
        }
    }

    private fun begin(s: Session, resultCode: Int, data: Intent) {
        val worker = HandlerThread("runnow-screen-clip").apply { start() }
        val handler = Handler(worker.looper)
        s.thread = worker
        s.handler = handler

        val format = MediaFormat.createVideoFormat(MIME, s.crop.width(), s.crop.height()).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, 8_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val codec = MediaCodec.createEncoderByType(MIME)
        s.codec = codec
        codec.setCallback(EncoderSink(s), handler)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        s.input = codec.createInputSurface()
        s.muxer = MediaMuxer(s.file.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        codec.start()

        val screen = screenSize()
        val width = (screen.width() * s.scale).toInt()
        val height = (screen.height() * s.scale).toInt()
        val reader = ImageReader.newInstance(
            width, height, PixelFormat.RGBA_8888, 3,
            HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT,
        )
        s.reader = reader
        reader.setOnImageAvailableListener({ draw(s, it) }, handler)

        val manager = activity.getSystemService(MediaProjectionManager::class.java)
        val projection = manager.getMediaProjection(resultCode, data)
            ?: throw IllegalStateException("không lấy được MediaProjection")
        s.projection = projection
        // Android 14 bắt đăng ký callback trước khi tạo VirtualDisplay.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                // Người dùng bấm dừng ở thanh trạng thái, hay khoá máy.
                if (!s.stopped && s.failure == null) s.failure = "quay màn hình bị dừng giữa chừng"
            }
        }, handler)
        val dpi = (activity.resources.displayMetrics.densityDpi * s.scale).toInt()
        s.display = projection.createVirtualDisplay(
            "runnow-screen-clip", width, height, dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.surface, null, handler,
        )
    }

    /** Chạy trên luồng quay: cắt vùng của khung mới nhất rồi vẽ sang bộ mã hoá. */
    private fun draw(s: Session, reader: ImageReader) {
        val image = try {
            reader.acquireLatestImage()
        } catch (_: IllegalStateException) {
            null
        } ?: return
        val surface = s.input
        val buffer = image.hardwareBuffer
        if (surface == null || buffer == null || s.stopped || s.failure != null) {
            buffer?.close()
            image.close()
            return
        }
        try {
            val bitmap = Bitmap.wrapHardwareBuffer(buffer, ColorSpace.get(ColorSpace.Named.SRGB))
                ?: throw IllegalStateException("không đọc được khung hình")
            val canvas = surface.lockHardwareCanvas()
            try {
                canvas.drawBitmap(bitmap, s.crop, Rect(0, 0, s.crop.width(), s.crop.height()), null)
            } finally {
                surface.unlockCanvasAndPost(canvas)
            }
            s.frames++
        } catch (error: Exception) {
            if (s.failure == null) s.failure = "không ghi được khung: ${error.message}"
        } finally {
            buffer.close()
            s.shown?.close()
            s.shown = image
        }
    }

    /** Ghi khung đã mã hoá vào MP4; báo [Session.ended] khi gặp khung cuối. */
    private class EncoderSink(private val s: Session) : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) = Unit

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            val muxer = s.muxer ?: return
            s.track = muxer.addTrack(format)
            muxer.start()
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            try {
                val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                if (!config && info.size > 0 && s.track >= 0) {
                    val data = codec.getOutputBuffer(index)
                    if (data != null) s.muxer?.writeSampleData(s.track, data, info)
                }
                codec.releaseOutputBuffer(index, false)
            } catch (error: Exception) {
                if (s.failure == null) s.failure = "không ghi được video: ${error.message}"
            }
            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) s.ended.countDown()
        }

        override fun onError(codec: MediaCodec, error: MediaCodec.CodecException) {
            if (s.failure == null) s.failure = "bộ mã hoá lỗi: ${error.diagnosticInfo}"
            s.ended.countDown()
        }
    }

    /** Dừng quay và đóng file; trả lỗi nếu video không dùng được. */
    private fun stop(result: MethodChannel.Result) {
        val s = session ?: return result.error("screen_clip", "chưa quay", null)
        session = null
        Thread {
            halt(s)
            val failure = s.failure ?: run {
                if (s.frames == 0) return@run "không nhận được khung hình nào"
                s.codec?.signalEndOfInputStream()
                if (!s.ended.await(5, TimeUnit.SECONDS)) "bộ mã hoá không đóng kịp" else s.failure
            }
            val closed = release(s, keepFile = failure == null)
            val reason = failure ?: closed
            main.post {
                stopService()
                if (reason == null) result.success(null) else result.error("screen_clip", reason, null)
            }
        }.start()
    }

    /** Bỏ lượt quay đang có (cả lúc đang chờ hỏi quyền) và xoá file. */
    private fun cancel() {
        pending?.error("screen_clip", "lượt quay đã bị huỷ", null)
        pending = null
        ScreenClipService.onReady = null
        val s = session ?: return
        session = null
        stopService()
        Thread {
            halt(s)
            release(s, keepFile = false)
        }.start()
    }

    /**
     * Ngừng nhận khung. Chạy phần dừng trên luồng quay rồi chờ, để sau khi hàm
     * này trả về không còn lần [draw] nào đang dở. Không gọi trên luồng quay.
     */
    private fun halt(s: Session) {
        val done = CountDownLatch(1)
        val posted = s.handler?.post {
            s.stopped = true
            s.reader?.setOnImageAvailableListener(null, null)
            s.display?.release()
            done.countDown()
        } ?: false
        if (posted) done.await(2, TimeUnit.SECONDS)
        s.stopped = true
        s.projection?.stop()
    }

    /** Đóng mọi thứ của [s] sau [halt]; trả lý do nếu không đóng được file MP4. */
    private fun release(s: Session, keepFile: Boolean): String? {
        var failure: String? = null
        try {
            s.codec?.stop()
        } catch (_: Exception) {
        }
        s.codec?.release()
        s.input?.release()
        try {
            if (s.track >= 0) s.muxer?.stop()
        } catch (error: Exception) {
            failure = "không đóng được video: ${error.message}"
        }
        s.muxer?.release()
        s.reader?.close()
        s.shown?.close()
        s.shown = null
        s.thread?.quitSafely()
        if (!keepFile || failure != null) s.file.delete()
        return failure
    }

    private fun stopService() {
        activity.stopService(Intent(activity, ScreenClipService::class.java))
    }

    /** Cỡ thật của màn hình tính bằng điểm ảnh, gồm cả thanh hệ thống. */
    private fun screenSize(): Rect =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.windowManager.maximumWindowMetrics.bounds
        } else {
            val metrics = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.getRealMetrics(metrics)
            Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
        }
}
