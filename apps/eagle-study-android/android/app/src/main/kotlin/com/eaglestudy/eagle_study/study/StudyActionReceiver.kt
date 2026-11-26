package com.eaglestudy.eagle_study.study

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.eaglestudy.eagle_study.alarm.AlarmChannel
import com.eaglestudy.eagle_study.alarm.AlarmScheduler
import com.eaglestudy.eagle_study.alarm.AlarmSpec
import com.eaglestudy.eagle_study.alarm.AlarmStore

/**
 * Pause / Resume from the session notification. If the Flutter app is
 * running, Dart handles it (single source of truth). Otherwise the persisted
 * timer is updated here with the same rules, and the focus-timer alarm is
 * cancelled or moved to the new end time.
 */
class StudyActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = when (intent.action) {
            ACTION_PAUSE -> "pause"
            ACTION_RESUME -> "resume"
            else -> return
        }
        if (StudyModeChannel.deliver(action)) return

        val db = TimerStateDb(context)
        val state = db.read() ?: return
        val now = System.currentTimeMillis()
        val updated = if (action == "pause") TimerStateMath.pause(state, now) else TimerStateMath.resume(state, now)
        db.write(updated)
        StudyNotification.show(context, updated, now)
        retargetTimerAlarm(context, updated)
    }

    private fun retargetTimerAlarm(context: Context, state: org.json.JSONObject) {
        if (!TimerStateMath.isCountdown(state)) return
        val store = AlarmStore(context)
        val scheduler = AlarmScheduler(context)
        if (!state.optBoolean("isRunning")) {
            scheduler.cancel(AlarmChannel.TIMER_ID)
            store.setTimer(null)
            return
        }
        val template = store.timerTemplate() ?: return
        val spec = template.copy(atMillis = state.getLong("countdownEndAtMs"), kind = AlarmSpec.Kind.TIMER)
        store.setTimer(spec)
        scheduler.schedule(spec)
    }

    companion object {
        const val ACTION_PAUSE = "com.eaglestudy.eagle_study.study.PAUSE"
        const val ACTION_RESUME = "com.eaglestudy.eagle_study.study.RESUME"
    }
}
