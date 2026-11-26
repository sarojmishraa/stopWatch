package com.eaglestudy.eagle_study.study

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.eaglestudy.eagle_study.MainActivity
import org.json.JSONObject

/**
 * Ongoing notification for a study session. Android's own chronometer keeps
 * the time ticking, so no foreground service or wake-ups are needed and the
 * time shown always comes from the persisted timestamps.
 *
 * Note: since Android 14 users can swipe away ongoing notifications that do
 * not belong to a foreground service. Timing is unaffected; the notification
 * reappears on the next pause/resume.
 */
object StudyNotification {
    private const val CHANNEL_ID = "study_session"
    private const val NOTIFICATION_ID = 5151

    /** Shows or updates the notification for [state] (persisted timer JSON). */
    fun show(context: Context, state: JSONObject, nowMs: Long = System.currentTimeMillis()) {
        if (state.isNull("sessionId")) {
            cancel(context)
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        ensureChannel(manager)
        val running = state.optBoolean("isRunning")
        val countdown = TimerStateMath.isCountdown(state)
        val subject = state.optString("subject").takeUnless { state.isNull("subject") || it.isBlank() }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }
        builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(
                listOfNotNull(if (countdown) "Focus session" else "Study session", subject).joinToString(" · "),
            )
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setCategory(Notification.CATEGORY_STOPWATCH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openApp(context, null, 10))

        if (running) {
            builder.setUsesChronometer(true)
            if (countdown) {
                builder.setWhen(state.getLong("countdownEndAtMs"))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) builder.setChronometerCountDown(true)
                builder.setContentText("Remaining")
            } else {
                builder.setWhen(nowMs - TimerStateMath.elapsedSeconds(state, nowMs) * 1000L)
                builder.setContentText("Focused")
            }
            builder.addAction(action(context, "Pause", StudyActionReceiver.ACTION_PAUSE, 11))
        } else {
            val seconds = if (countdown) {
                TimerStateMath.remainingSeconds(state, nowMs)
            } else {
                TimerStateMath.elapsedSeconds(state, nowMs)
            }
            builder.setUsesChronometer(false)
                .setContentText("Paused · ${clock(seconds)}${if (countdown) " left" else ""}")
            builder.addAction(action(context, "Resume", StudyActionReceiver.ACTION_RESUME, 12))
        }
        builder.addAction(
            @Suppress("DEPRECATION")
            Notification.Action.Builder(null, "Finish", openApp(context, "finish", 13)).build(),
        )
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Study session", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows the running study timer with pause and finish buttons"
                setShowBadge(false)
            },
        )
    }

    private fun action(context: Context, title: String, action: String, code: Int): Notification.Action {
        val intent = PendingIntent.getBroadcast(
            context,
            code,
            Intent(context, StudyActionReceiver::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        return Notification.Action.Builder(null, title, intent).build()
    }

    /** Opens the app; [studyAction] ("finish") is delivered to Dart. */
    private fun openApp(context: Context, studyAction: String?, code: Int): PendingIntent =
        PendingIntent.getActivity(
            context,
            code,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .apply { studyAction?.let { putExtra(MainActivity.EXTRA_STUDY_ACTION, it) } },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    fun clock(seconds: Int): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }
}
