package com.threei.run

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Foreground service loại mediaProjection mà Android 14 đòi phải chạy trước
 * khi app lấy MediaProjection. Service không làm gì ngoài giữ thông báo "đang
 * quay"; ScreenClipRecorder bật và tắt nó quanh mỗi lượt quay.
 */
class ScreenClipService : Service() {
    companion object {
        private const val CHANNEL = "screen_clip"
        private const val NOTIFICATION = 4232

        /** Chạy trên main ngay sau khi service đã lên foreground. */
        var onReady: (() -> Unit)? = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Quay video replay", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Đang quay video replay")
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION, notification)
        }
        Handler(Looper.getMainLooper()).post { onReady?.invoke() }
        return START_NOT_STICKY
    }
}
