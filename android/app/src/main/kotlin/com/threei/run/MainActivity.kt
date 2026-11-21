package com.threei.run

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CardVideoWriter.register(flutterEngine.dartExecutor.binaryMessenger)
        ScreenClipRecorder.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    @Deprecated("Hộp hỏi quyền MediaProjection trả kết quả qua đây.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (ScreenClipRecorder.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
