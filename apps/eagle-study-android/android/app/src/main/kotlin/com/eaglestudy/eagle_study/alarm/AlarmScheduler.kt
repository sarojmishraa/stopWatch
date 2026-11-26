package com.eaglestudy.eagle_study.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log

/**
 * Registers alarms with AlarmManager.
 *
 * With exact-alarm permission it uses setAlarmClock(): the most reliable
 * API (exempt from Doze, shows the alarm icon, allows the ringing service to
 * start from the background). Without it, it falls back to
 * setAndAllowWhileIdle(), which Android may delay by several minutes; the
 * app tells the user so instead of pretending the alarm is exact.
 */
class AlarmScheduler(private val context: Context) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    fun canScheduleExact(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    /** Schedules [spec]; returns the trigger time in epoch millis. */
    fun schedule(spec: AlarmSpec, nowMillis: Long = System.currentTimeMillis()): Long {
        val at = NextTrigger.compute(spec, nowMillis)
        val fire = firePendingIntent(spec.id)
        if (canScheduleExact()) {
            alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(at, showAppPendingIntent()), fire)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, fire)
        }
        Log.i(TAG, "Scheduled ${spec.kind} ${spec.id} at $at (exact=${canScheduleExact()})")
        return at
    }

    fun cancel(id: String) = alarmManager.cancel(firePendingIntent(id))

    /** After boot, app update, clock or timezone change, or permission change. */
    fun rescheduleAll(store: AlarmStore) {
        val now = System.currentTimeMillis()
        store.alarms().forEach { runCatching { schedule(it, now) } }
        store.timer()?.let { timer ->
            if ((timer.atMillis ?: 0) > now) schedule(timer, now) else store.setTimer(null)
        }
        store.snoozes().forEach { snooze ->
            if ((snooze.atMillis ?: 0) > now) schedule(snooze, now) else store.removeSnooze(snooze.id)
        }
    }

    private fun firePendingIntent(id: String): PendingIntent = PendingIntent.getBroadcast(
        context,
        id.hashCode(),
        Intent(context, AlarmReceiver::class.java)
            .setAction(AlarmReceiver.ACTION_FIRE)
            // Data makes each alarm's PendingIntent distinct (extras do not).
            .setData(Uri.parse("eagle-alarm://$id"))
            .putExtra(AlarmReceiver.EXTRA_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun showAppPendingIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        context.packageManager.getLaunchIntentForPackage(context.packageName),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        private const val TAG = "EagleAlarm"
    }
}
