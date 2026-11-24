package com.threei.run

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Nhận file .gpx, .tcx, .fit người dùng mở hoặc chia sẻ sang 3i Run để xem lại 3D. Giữ
 * nội dung file tới khi Dart gọi `take`; báo `opened` để app đang chạy lấy
 * ngay, còn lúc mở app từ đầu thì Dart tự gọi `take` khi sẵn sàng.
 */
object RunFileInbox {
    private const val TAG = "RunFileInbox"
    private var channel: MethodChannel? = null
    private var pending: ByteArray? = null
    private val mimeTypes =
        setOf("application/gpx+xml", "application/vnd.garmin.tcx+xml", "application/vnd.ant.fit")
    private val extensions = listOf(".gpx", ".tcx", ".fit")

    /** Bằng `runFileMaxBytes` bên Dart. */
    private const val MAX_BYTES = 32 * 1024 * 1024

    /** Tăng mỗi lần nhận file; lượt đọc nào không còn là lượt mới nhất thì bỏ kết quả. */
    private var generation = 0

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "runnow/run_file_inbox").apply {
            setMethodCallHandler { call, result ->
                if (call.method != "take") return@setMethodCallHandler result.notImplemented()
                result.success(pending)
                pending = null
            }
        }
    }

    /**
     * Trả true khi intent là một file .gpx, .tcx hay .fit. Đọc ở thread riêng vì provider ở
     * cloud (Drive) có thể tải file lúc mở, đọc trên main thread sẽ ANR. Đọc xong mới báo
     * `opened`; Dart gọi `take` sớm hơn thì chỉ nhận null. File quá lớn hay đọc hỏng thì
     * giao mảng rỗng để Dart báo không đọc được, không im lặng.
     */
    fun receive(activity: Activity, intent: Intent?): Boolean {
        val uri = runFileUri(activity, intent) ?: return false
        val resolver = activity.contentResolver
        val mine = ++generation
        Thread {
            val bytes = try {
                resolver.openInputStream(uri)?.use(::readUpToLimit)
                    ?: ByteArray(0).also { Log.w(TAG, "không mở được $uri") }
            } catch (e: Throwable) {
                // Throwable để cả OutOfMemoryError cũng chỉ thành "không đọc được".
                Log.w(TAG, "không đọc được $uri", e)
                ByteArray(0)
            }
            activity.runOnUiThread {
                if (mine != generation) return@runOnUiThread
                pending = bytes
                channel?.invokeMethod("opened", null)
            }
        }.start()
        return true
    }

    /** Đọc hết [input]; quá [MAX_BYTES] thì trả mảng rỗng mà không giữ phần đã đọc. */
    private fun readUpToLimit(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val read = input.read(buffer)
            if (read < 0) return out.toByteArray()
            if (out.size() + read > MAX_BYTES) {
                Log.w(TAG, "file quá $MAX_BYTES byte")
                return ByteArray(0)
            }
            out.write(buffer, 0, read)
        }
    }

    /** Intent mở hay chia sẻ một file buổi chạy, chưa đọc nội dung. */
    fun isRunFile(activity: Activity, intent: Intent?): Boolean = runFileUri(activity, intent) != null

    private fun runFileUri(activity: Activity, intent: Intent?): Uri? {
        if (intent == null) return null
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } ?: return null
        val type = intent.type ?: activity.contentResolver.getType(uri)
        if (type in mimeTypes) return uri
        val name = displayName(activity, uri)?.lowercase() ?: return null
        return uri.takeIf { extensions.any(name::endsWith) }
    }

    private fun displayName(activity: Activity, uri: Uri): String? =
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
        } catch (e: Exception) {
            Log.w(TAG, "không đọc được tên $uri", e)
            null
        }
}
