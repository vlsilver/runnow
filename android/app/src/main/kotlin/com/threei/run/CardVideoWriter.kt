package com.threei.run

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Ghi lá thẻ xoay thành MP4 H.264 cho màn khoe thẻ (run_card_share.dart).
 * Dart đẩy từng khung RGBA ngay khi chụp; mọi việc chạy trên một luồng riêng
 * nên các lệnh tới theo đúng thứ tự gọi.
 */
class CardVideoWriter private constructor() : MethodChannel.MethodCallHandler {
    companion object {
        fun register(messenger: BinaryMessenger) {
            MethodChannel(messenger, "runnow/card_video").setMethodCallHandler(CardVideoWriter())
        }

        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val TIMEOUT_US = 10_000L
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var path: String? = null
    private var track = -1
    private var width = 0
    private var height = 0
    private var fps = 30
    private var frameIndex = 0L
    private val info = MediaCodec.BufferInfo()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        worker.execute {
            try {
                when (call.method) {
                    "start" -> start(call)
                    "frame" -> append(call.arguments as ByteArray)
                    "finish" -> finish()
                    "cancel" -> cancel()
                    else -> {
                        main.post { result.notImplemented() }
                        return@execute
                    }
                }
                main.post { result.success(null) }
            } catch (e: Exception) {
                if (call.method != "cancel") cancel()
                main.post { result.error("card_video", e.toString(), null) }
            }
        }
    }

    private fun start(call: MethodCall) {
        cancel()
        val p = call.argument<String>("path")!!
        val w = call.argument<Int>("width")!!
        val h = call.argument<Int>("height")!!
        val f = call.argument<Int>("fps")!!
        val format = MediaFormat.createVideoFormat(MIME, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, call.argument<Int>("bitRate")!!)
            setInteger(MediaFormat.KEY_FRAME_RATE, f)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        File(p).delete()
        val c = MediaCodec.createEncoderByType(MIME)
        try {
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            c.start()
        } catch (e: Exception) {
            c.release()
            throw e
        }
        codec = c
        muxer = MediaMuxer(p, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        path = p
        track = -1
        width = w
        height = h
        fps = f
        frameIndex = 0
    }

    private fun append(rgba: ByteArray) {
        val c = codec ?: error("chưa start")
        require(rgba.size == width * height * 4) { "khung ${rgba.size} byte, cần ${width * height * 4}" }
        val index = dequeueInput(c)
        val image = c.getInputImage(index) ?: error("bộ mã hoá không cho ảnh đầu vào")
        writeYuv(rgba, image)
        c.queueInputBuffer(index, 0, width * height * 3 / 2, ptsUs(frameIndex), 0)
        frameIndex++
        drain(c, endOfStream = false)
    }

    private fun finish() {
        val c = codec ?: error("chưa start")
        val index = dequeueInput(c)
        c.queueInputBuffer(index, 0, 0, ptsUs(frameIndex), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(c, endOfStream = true)
        c.stop()
        c.release()
        codec = null
        muxer?.stop()
        muxer?.release()
        muxer = null
        path = null
    }

    /** Bỏ video đang ghi dở và xoá file. */
    private fun cancel() {
        codec?.let { runCatching { it.stop() }; it.release() }
        codec = null
        muxer?.let { runCatching { it.release() } }
        muxer = null
        path?.let { File(it).delete() }
        path = null
    }

    private fun ptsUs(frame: Long) = frame * 1_000_000L / fps

    /** Chờ ô đầu vào trống, vừa chờ vừa lấy dữ liệu đã mã hoá ra cho bộ mã hoá có chỗ. */
    private fun dequeueInput(c: MediaCodec): Int {
        repeat(500) {
            val index = c.dequeueInputBuffer(TIMEOUT_US)
            if (index >= 0) return index
            drain(c, endOfStream = false)
        }
        error("bộ mã hoá không nhận khung")
    }

    private fun drain(c: MediaCodec, endOfStream: Boolean) {
        var idle = 0
        while (true) {
            val index = c.dequeueOutputBuffer(info, TIMEOUT_US)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) return
                    if (++idle > 500) error("bộ mã hoá không trả hết video")
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val m = muxer!!
                    track = m.addTrack(c.outputFormat)
                    m.start()
                }
                index >= 0 -> {
                    val buffer = c.getOutputBuffer(index)!!
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (!config && info.size > 0 && track >= 0) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        muxer!!.writeSampleData(track, buffer, info)
                    }
                    c.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /** RGBA sang YUV 4:2:0 BT.601 dải hẹp, theo stride của từng plane mà máy cho. */
    private fun writeYuv(rgba: ByteArray, image: android.media.Image) {
        val (yPlane, uPlane, vPlane) = image.planes
        val y = yPlane.buffer
        val u = uPlane.buffer
        val v = vPlane.buffer
        for (row in 0 until height) {
            for (col in 0 until width) {
                val i = (row * width + col) * 4
                val r = rgba[i].toInt() and 0xff
                val g = rgba[i + 1].toInt() and 0xff
                val b = rgba[i + 2].toInt() and 0xff
                y.put(row * yPlane.rowStride + col * yPlane.pixelStride,
                    (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                if (row % 2 == 0 && col % 2 == 0) {
                    val cr = row / 2
                    val cc = col / 2
                    u.put(cr * uPlane.rowStride + cc * uPlane.pixelStride,
                        (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte())
                    v.put(cr * vPlane.rowStride + cc * vPlane.pixelStride,
                        (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte())
                }
            }
        }
    }
}
