package com.eduai.eduaiapp

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDefaultNotificationChannel()
    }

    // Push notifications arrive on "eduai_default" (the FCM message names it,
    // and the manifest makes it the default). Android 8+ drops notifications
    // for a channel that does not exist, so it is created up front;
    // re-creating an existing channel only refreshes its name.
    private fun createDefaultNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            "eduai_default",
            getString(R.string.notification_channel_default_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        manager.createNotificationChannel(channel)
    }
}
