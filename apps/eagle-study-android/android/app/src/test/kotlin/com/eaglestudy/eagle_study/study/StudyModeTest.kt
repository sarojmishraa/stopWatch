package com.eaglestudy.eagle_study.study

import android.app.NotificationManager.INTERRUPTION_FILTER_ALARMS
import android.app.NotificationManager.INTERRUPTION_FILTER_ALL
import android.app.NotificationManager.INTERRUPTION_FILTER_PRIORITY
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class TimerStateMathTest {
    private val t0 = 1_800_000_000_000L
    private fun min(m: Int) = m * 60_000L

    private fun stopwatchRunning() = JSONObject(
        """{"mode":"stopwatch","isRunning":true,"accumulatedSeconds":0,"segmentStartedAtMs":$t0,
           "countdownEndAtMs":null,"countdownDurationSeconds":1500,"sessionId":"s1",
           "sessionStartedAtMs":$t0,"pausedAtMs":null,"subject":"Go","laps":[]}""",
    )

    private fun countdownRunning() = JSONObject(
        """{"mode":"countdown","isRunning":true,"accumulatedSeconds":1500,"segmentStartedAtMs":null,
           "countdownEndAtMs":${t0 + min(25)},"countdownDurationSeconds":1500,"sessionId":"s2",
           "sessionStartedAtMs":$t0,"pausedAtMs":null,"subject":null,"laps":[]}""",
    )

    @Test fun stopwatchPauseBanksElapsedAndResumeExcludesTheBreak() {
        val paused = TimerStateMath.pause(stopwatchRunning(), t0 + min(10))
        assertFalse(paused.getBoolean("isRunning"))
        assertEquals(600, paused.getInt("accumulatedSeconds"))
        assertTrue(paused.isNull("segmentStartedAtMs"))
        assertEquals(t0 + min(10), paused.getLong("pausedAtMs"))

        val resumed = TimerStateMath.resume(paused, t0 + min(15)) // 5-minute break
        assertEquals(t0 + min(15), resumed.getLong("segmentStartedAtMs"))
        assertTrue(resumed.isNull("pausedAtMs"))
        assertEquals(1200, TimerStateMath.elapsedSeconds(resumed, t0 + min(25)))
    }

    @Test fun countdownPauseKeepsRemainingAndResumeMovesTheEnd() {
        val paused = TimerStateMath.pause(countdownRunning(), t0 + min(10))
        assertEquals(900, paused.getInt("accumulatedSeconds"))
        assertTrue(paused.isNull("countdownEndAtMs"))

        val resumed = TimerStateMath.resume(paused, t0 + min(12))
        assertEquals(t0 + min(27), resumed.getLong("countdownEndAtMs"))
        assertEquals(900, TimerStateMath.remainingSeconds(resumed, t0 + min(12)))
    }

    @Test fun pausingTwiceOrResumingWithoutASessionChangesNothing() {
        val paused = TimerStateMath.pause(stopwatchRunning(), t0 + min(1))
        assertSame(paused, TimerStateMath.pause(paused, t0 + min(2)))
        val idle = JSONObject("""{"mode":"stopwatch","isRunning":false,"sessionId":null}""")
        assertSame(idle, TimerStateMath.resume(idle, t0))
    }

    @Test fun otherFieldsSurvive() {
        val paused = TimerStateMath.pause(stopwatchRunning(), t0 + min(3))
        assertEquals("Go", paused.getString("subject"))
        assertEquals("s1", paused.getString("sessionId"))
    }

    @Test fun notificationClockFormat() {
        assertEquals("05:07", StudyNotification.clock(307))
        assertEquals("1:02:03", StudyNotification.clock(3723))
    }
}

class DndRestoreTest {
    @Test fun restoresWhatTheUserHadBefore() =
        assertEquals(INTERRUPTION_FILTER_ALL, DndController.restoreDecision(
            applied = INTERRUPTION_FILTER_ALARMS, current = INTERRUPTION_FILTER_ALARMS, previous = INTERRUPTION_FILTER_ALL,
        ))

    @Test fun leavesItAloneIfTheUserChangedDndWhileStudying() =
        assertNull(DndController.restoreDecision(
            applied = INTERRUPTION_FILTER_ALARMS, current = INTERRUPTION_FILTER_PRIORITY, previous = INTERRUPTION_FILTER_ALL,
        ))

    @Test fun nothingToDoIfDndWasAlreadyThatWay() =
        assertNull(DndController.restoreDecision(
            applied = INTERRUPTION_FILTER_PRIORITY, current = INTERRUPTION_FILTER_PRIORITY, previous = INTERRUPTION_FILTER_PRIORITY,
        ))
}
