package com.eaglestudy.eagle_study.alarm

import java.time.Instant
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Same cases as test/features/alarms/alarm_test.dart, so the Dart preview of
 * "next alarm" and the native schedule cannot drift apart.
 */
class NextTriggerTest {
    // Tue 1 Dec 2026, 10:00 in Asia/Kolkata.
    private val now = Instant.parse("2026-12-01T04:30:00Z").toEpochMilli()

    private fun spec(hour: Int, minute: Int, days: Set<Int> = emptySet(), zone: String = "Asia/Kolkata") =
        AlarmSpec(
            id = "a", hour = hour, minute = minute, days = days, message = "m",
            sound = "classic", volume = 0.8f, vibrate = true, recordingPath = null, zone = zone,
        )

    private fun next(spec: AlarmSpec) = Instant.ofEpochMilli(NextTrigger.compute(spec, now)).toString()

    @Test fun oneShotLaterToday() = assertEquals("2026-12-01T05:30:00Z", next(spec(11, 0)))

    @Test fun oneShotEarlierTimeRingsTomorrow() = assertEquals("2026-12-02T03:30:00Z", next(spec(9, 0)))

    @Test fun exactlyNowIsNotNow() = assertEquals("2026-12-02T04:30:00Z", next(spec(10, 0)))

    @Test fun weekdaysSkipToWednesday() =
        assertEquals("2026-12-02T01:30:00Z", next(spec(7, 0, setOf(1, 2, 3, 4, 5))))

    @Test fun weekendOnlyWaitsForSaturday() =
        assertEquals("2026-12-05T01:30:00Z", next(spec(7, 0, setOf(6, 7))))

    @Test fun sameWeekdayAlreadyPassedRingsNextWeek() =
        assertEquals("2026-12-08T04:30:00Z", next(spec(10, 0, setOf(2))))

    @Test fun fixedInstantIsUsedAsIs() {
        val at = now + 25 * 60_000
        assertEquals(at, NextTrigger.compute(spec(0, 0).copy(atMillis = at), now))
    }

    @Test fun otherZonesUseTheirOwnClock() =
        assertEquals("2026-12-01T06:00:00Z", next(spec(7, 0, zone = "Europe/Berlin")))

    @Test fun isoWeekdayMapping() {
        val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
        cal.timeInMillis = Instant.parse("2026-11-30T12:00:00Z").toEpochMilli() // Monday
        assertEquals(1, NextTrigger.isoWeekday(cal))
        cal.timeInMillis = Instant.parse("2026-12-06T12:00:00Z").toEpochMilli() // Sunday
        assertEquals(7, NextTrigger.isoWeekday(cal))
    }

    @Test fun specSurvivesJsonRoundTrip() {
        val original = spec(6, 45, setOf(1, 3, 5)).copy(
            sound = "ghost", recordingPath = "/data/x.m4a", atMillis = 123L, kind = AlarmSpec.Kind.SNOOZE,
        )
        assertEquals(original, AlarmSpec.fromJson(JSONObject(original.toJson().toString())))
    }

    @Test fun invalidInputIsRejected() {
        assertThrows(IllegalArgumentException::class.java) { spec(24, 0) }
        assertThrows(IllegalArgumentException::class.java) { spec(7, 0, setOf(0)) }
        assertThrows(IllegalArgumentException::class.java) { spec(7, 0, zone = "Mars/Base") }
    }
}
