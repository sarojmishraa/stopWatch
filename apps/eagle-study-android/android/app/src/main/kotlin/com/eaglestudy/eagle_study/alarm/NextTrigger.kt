package com.eaglestudy.eagle_study.alarm

import java.util.Calendar
import java.util.TimeZone

/**
 * When an alarm next rings, strictly after [nowMillis], in the alarm's IANA
 * timezone. Mirrors `nextTrigger` in lib/features/alarms/domain/alarm.dart;
 * both are tested against the same cases.
 */
object NextTrigger {
    fun compute(spec: AlarmSpec, nowMillis: Long): Long {
        spec.atMillis?.let { return it }
        val calendar = Calendar.getInstance(TimeZone.getTimeZone(spec.zone))
        for (offset in 0..7) {
            calendar.timeInMillis = nowMillis
            calendar.add(Calendar.DAY_OF_YEAR, offset)
            calendar.set(Calendar.HOUR_OF_DAY, spec.hour)
            calendar.set(Calendar.MINUTE, spec.minute)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            val candidate = calendar.timeInMillis
            if (candidate <= nowMillis) continue
            if (spec.days.isEmpty() || isoWeekday(calendar) in spec.days) return candidate
        }
        error("No trigger within a week for alarm ${spec.id}")
    }

    /** Calendar.SUNDAY = 1 … SATURDAY = 7  →  ISO Monday = 1 … Sunday = 7. */
    fun isoWeekday(calendar: Calendar): Int = (calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
}
