package com.eaglestudy.eagle_study.alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.RingtoneManager
import android.os.Build

object AlarmNotifications {
    /** Ringing alarms. Silent channel: AlarmPlayer makes the sound. */
    const val CHANNEL_ID = "alarms_ringing"

    /** Used only if the ringing service could not start; the channel rings. */
    const val FALLBACK_CHANNEL_ID = "alarms_fallback"

    const val RINGING_NOTIFICATION_ID = 4242
    const val FALLBACK_NOTIFICATION_ID = 4243

    fun title(spec: AlarmSpec): String = when (spec.kind) {
        AlarmSpec.Kind.TIMER -> "Focus session complete"
        AlarmSpec.Kind.SNOOZE -> "Snoozed alarm"
        AlarmSpec.Kind.ALARM -> "EAGLE STUDY alarm"
    }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Ringing alarms and focus-timer completion"
                setSound(null, null)
                enableVibration(false)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(FALLBACK_CHANNEL_ID, "Alarms (backup)", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Used when the alarm sound service cannot start"
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                    AlarmPlayer.ALARM_AUDIO,
                )
                enableVibration(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            },
        )
    }
}
