package com.fuseos.app.core

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.fuseos.app.R

/**
 * Brings an activity up for something the Mac asked for — a consent dialog, the camera, a
 * link — while FuseOS is in the background.
 *
 * Android blocks background activity starts, with an exemption for apps holding the overlay
 * permission (the island's). With it the activity opens at once; without it a high-priority
 * notification is the way in, and the user taps it.
 */
object BackgroundLaunch {
    private const val CHANNEL = "fuseos_mac_requests"

    fun start(context: Context, intent: Intent, title: String, text: String, notificationId: Int) {
        val app = context.applicationContext
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Settings.canDrawOverlays(app) && runCatching { app.startActivity(intent) }.isSuccess) return

        val manager = app.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Requests from your Mac", NotificationManager.IMPORTANCE_HIGH),
            )
        }
        val tap = PendingIntent.getActivity(
            app, notificationId, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        manager.notify(
            notificationId,
            NotificationCompat.Builder(app, CHANNEL)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(text)
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build(),
        )
    }
}
