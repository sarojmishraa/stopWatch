package com.eaglestudy.eagle_study.alarm

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * Foreground service that rings an alarm until it is dismissed, snoozed, or
 * five minutes pass. Runs as a foreground service so Android does not kill
 * the sound, and shows a full-screen alarm over the lock screen when the
 * full-screen-intent permission is granted (otherwise a heads-up
 * notification with the same buttons).
 */
class AlarmService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: AlarmPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val autoStop = Runnable { stopRinging() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RING -> ring(intent.getStringExtra(AlarmReceiver.EXTRA_ID))
            ACTION_SNOOZE -> snooze()
            ACTION_DISMISS -> stopRinging()
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun ring(id: String?) {
        val spec = id?.let { AlarmStore(this).find(it) }
        if (spec == null) {
            stopSelf()
            return
        }
        player?.stop()
        AlarmNotifications.ensureChannels(this)
        val notification = buildNotification(spec)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                AlarmNotifications.RINGING_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(AlarmNotifications.RINGING_NOTIFICATION_ID, notification)
        }
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "EagleStudy:alarm")
            .apply { acquire(MAX_RING_MS + 10_000) }

        ringing = spec
        player = AlarmPlayer(this, spec).also { it.start() }
        handler.removeCallbacks(autoStop)
        handler.postDelayed(autoStop, MAX_RING_MS)
        afterFired(this, spec)
    }

    private fun snooze() {
        val spec = ringing
        stopRinging()
        if (spec == null || spec.kind == AlarmSpec.Kind.TIMER) return
        val snoozed = spec.copy(
            id = "snooze-${spec.id.removePrefix("snooze-")}",
            atMillis = System.currentTimeMillis() + SNOOZE_MS,
            kind = AlarmSpec.Kind.SNOOZE,
        )
        AlarmStore(this).addSnooze(snoozed)
        AlarmScheduler(this).schedule(snoozed)
    }

    private fun stopRinging() {
        handler.removeCallbacks(autoStop)
        player?.stop()
        player = null
        ringing = null
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        onStopped?.invoke()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStop)
        player?.stop()
        wakeLock?.takeIf { it.isHeld }?.release()
        ringing = null
        super.onDestroy()
    }

    private fun buildNotification(spec: AlarmSpec): Notification {
        val fullScreen = PendingIntent.getActivity(
            this,
            1,
            Intent(this, AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, AlarmNotifications.CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        }
        builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(AlarmNotifications.title(spec))
            .setContentText(spec.message)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setContentIntent(fullScreen)
            .setFullScreenIntent(fullScreen, true)
        if (spec.kind != AlarmSpec.Kind.TIMER) {
            builder.addAction(action("Snooze 10 min", ACTION_SNOOZE, 2))
        }
        builder.addAction(action(if (spec.kind == AlarmSpec.Kind.TIMER) "Stop" else "Dismiss", ACTION_DISMISS, 3))
        return builder.build()
    }

    private fun action(title: String, action: String, requestCode: Int): Notification.Action {
        val pending = PendingIntent.getService(
            this,
            requestCode,
            Intent(this, AlarmService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        return Notification.Action.Builder(null, title, pending).build()
    }

    companion object {
        const val ACTION_RING = "com.eaglestudy.eagle_study.alarm.RING"
        const val ACTION_SNOOZE = "com.eaglestudy.eagle_study.alarm.SNOOZE"
        const val ACTION_DISMISS = "com.eaglestudy.eagle_study.alarm.DISMISS"
        const val MAX_RING_MS = 5 * 60_000L
        const val SNOOZE_MS = 10 * 60_000L

        /** The alarm currently ringing, for [AlarmActivity]. */
        @Volatile var ringing: AlarmSpec? = null
            private set

        /** Lets [AlarmActivity] close itself when ringing stops. */
        @Volatile var onStopped: (() -> Unit)? = null

        /**
         * Bookkeeping once an alarm has fired: repeating alarms are scheduled
         * for their next day, one-time ones are retired and reported to Dart.
         */
        fun afterFired(context: Context, spec: AlarmSpec) {
            val store = AlarmStore(context)
            when (spec.kind) {
                AlarmSpec.Kind.ALARM -> if (spec.repeats) {
                    // A minute ahead, so an alarm delivered a little early is
                    // not rescheduled for the same minute.
                    AlarmScheduler(context).schedule(spec, System.currentTimeMillis() + 60_000)
                } else {
                    store.removeAlarm(spec.id)
                    store.markFired(spec.id)
                }
                AlarmSpec.Kind.TIMER -> {
                    store.setTimer(null)
                    // The countdown is over: drop its "running" notification.
                    com.eaglestudy.eagle_study.study.StudyNotification.cancel(context)
                }
                AlarmSpec.Kind.SNOOZE -> store.removeSnooze(spec.id)
            }
        }
    }
}
