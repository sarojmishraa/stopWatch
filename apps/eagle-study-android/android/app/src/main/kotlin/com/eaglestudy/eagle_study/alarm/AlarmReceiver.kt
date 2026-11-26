package com.eaglestudy.eagle_study.alarm

import android.app.Notification
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/** AlarmManager fires here; ringing happens in [AlarmService]. */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_FIRE) return
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val spec = AlarmStore(context).find(id) ?: return
        val service = Intent(context, AlarmService::class.java)
            .setAction(AlarmService.ACTION_RING)
            .putExtra(EXTRA_ID, id)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
        } catch (e: IllegalStateException) {
            // Android 12+ refuses background foreground-service starts for
            // inexact alarms (no exact-alarm permission). Still make noise:
            // post a high-priority notification that uses the channel sound.
            Log.w("EagleAlarm", "Could not start ringing service; notifying instead", e)
            notifyFallback(context, spec)
        }
    }

    private fun notifyFallback(context: Context, spec: AlarmSpec) {
        val manager = context.getSystemService(NotificationManager::class.java)
        AlarmNotifications.ensureChannels(context)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, AlarmNotifications.FALLBACK_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_MAX)
        }
        manager.notify(
            AlarmNotifications.FALLBACK_NOTIFICATION_ID,
            builder
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(AlarmNotifications.title(spec))
                .setContentText(spec.message)
                .setCategory(Notification.CATEGORY_ALARM)
                .setAutoCancel(true)
                .build(),
        )
        AlarmService.afterFired(context, spec)
    }

    companion object {
        const val ACTION_FIRE = "com.eaglestudy.eagle_study.alarm.FIRE"
        const val EXTRA_ID = "alarm_id"
    }
}
