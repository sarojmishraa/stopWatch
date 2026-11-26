package com.eaglestudy.eagle_study.study

import kotlin.math.ceil
import org.json.JSONObject

/**
 * Pause/resume on the persisted timer JSON, used when a notification button
 * is tapped while the Flutter app is not running. Mirrors
 * StudyTimerController.pause/startOrResume in Dart (same field names, same
 * timestamp rules) and is unit-tested against the same expectations.
 */
object TimerStateMath {
    fun pause(state: JSONObject, nowMs: Long): JSONObject {
        if (!state.optBoolean("isRunning")) return state
        val copy = JSONObject(state.toString())
        if (isCountdown(state)) {
            copy.put("accumulatedSeconds", remainingSeconds(state, nowMs))
            copy.put("countdownEndAtMs", JSONObject.NULL)
        } else {
            copy.put("accumulatedSeconds", elapsedSeconds(state, nowMs))
            copy.put("segmentStartedAtMs", JSONObject.NULL)
        }
        copy.put("isRunning", false)
        copy.put("pausedAtMs", nowMs)
        return copy
    }

    fun resume(state: JSONObject, nowMs: Long): JSONObject {
        if (state.optBoolean("isRunning") || state.isNull("sessionId")) return state
        val copy = JSONObject(state.toString())
        if (isCountdown(state)) {
            val accumulated = state.optInt("accumulatedSeconds")
            val remaining = if (accumulated > 0) accumulated else duration(state)
            copy.put("accumulatedSeconds", remaining)
            copy.put("countdownEndAtMs", nowMs + remaining * 1000L)
        } else {
            copy.put("segmentStartedAtMs", nowMs)
        }
        copy.put("isRunning", true)
        copy.put("pausedAtMs", JSONObject.NULL)
        return copy
    }

    fun isCountdown(state: JSONObject) = state.optString("mode") == "countdown"

    fun duration(state: JSONObject) = state.optInt("countdownDurationSeconds", 1500)

    /** Stopwatch: focused seconds so far. */
    fun elapsedSeconds(state: JSONObject, nowMs: Long): Int {
        val accumulated = state.optInt("accumulatedSeconds")
        if (!state.optBoolean("isRunning") || state.isNull("segmentStartedAtMs")) return accumulated
        val started = state.getLong("segmentStartedAtMs")
        return accumulated + ((nowMs - started) / 1000).coerceAtLeast(0).toInt()
    }

    /** Countdown: seconds left. */
    fun remainingSeconds(state: JSONObject, nowMs: Long): Int {
        if (!state.optBoolean("isRunning") || state.isNull("countdownEndAtMs")) {
            return state.optInt("accumulatedSeconds")
        }
        val end = state.getLong("countdownEndAtMs")
        return ceil((end - nowMs) / 1000.0).toInt().coerceIn(0, duration(state))
    }
}
