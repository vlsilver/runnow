package com.threei.run

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CardVideoWriter.register(flutterEngine.dartExecutor.binaryMessenger)
        ScreenClipRecorder.register(this, flutterEngine.dartExecutor.binaryMessenger)
        RunFileInbox.register(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Xoay màn hình tạo lại activity với cùng intent: chỉ nhận file lần đầu.
        if (savedInstanceState == null) RunFileInbox.receive(this, intent)
    }

    // Cờ flutter_deeplinking_enabled đang đặt ở <application> nên Flutter không
    // đọc thấy và vẫn coi data của intent là route đầu. Mở app bằng file thì
    // data là content://, go_router báo không có trang: tắt riêng cho ca này.
    override fun shouldHandleDeeplinking(): Boolean =
        !RunFileInbox.isRunFile(this, intent) && super.shouldHandleDeeplinking()

    override fun onNewIntent(intent: Intent) {
        if (RunFileInbox.receive(this, intent)) {
            setIntent(intent)
            return
        }
        super.onNewIntent(intent)
    }

    @Deprecated("Hộp hỏi quyền MediaProjection trả kết quả qua đây.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (ScreenClipRecorder.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
