package com.eaglestudy.eagle_study.alarm

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Native copy of the schedule, readable without Flutter (boot, alarm fire).
 * Writes use commit() so they are on disk before a receiver returns.
 */
class AlarmStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences("eagle_alarm_engine", Context.MODE_PRIVATE)

    fun alarms(): List<AlarmSpec> = readList(KEY_ALARMS)

    fun setAlarms(alarms: List<AlarmSpec>) = writeList(KEY_ALARMS, alarms)

    fun removeAlarm(id: String) = setAlarms(alarms().filterNot { it.id == id })

    fun timer(): AlarmSpec? = prefs.getString(KEY_TIMER, null)
        ?.let { runCatching { AlarmSpec.fromJson(JSONObject(it)) }.getOrNull() }

    fun setTimer(spec: AlarmSpec?) {
        prefs.edit().apply {
            if (spec == null) remove(KEY_TIMER) else putString(KEY_TIMER, spec.toJson().toString())
        }.commit()
    }

    /** Message/sound for the focus-timer alarm, to re-arm it on a resume
     *  from the notification while Flutter is not running. */
    fun timerTemplate(): AlarmSpec? = prefs.getString(KEY_TIMER_TEMPLATE, null)
        ?.let { runCatching { AlarmSpec.fromJson(JSONObject(it)) }.getOrNull() }

    fun setTimerTemplate(spec: AlarmSpec) {
        prefs.edit().putString(KEY_TIMER_TEMPLATE, spec.toJson().toString()).commit()
    }

    fun snoozes(): List<AlarmSpec> = readList(KEY_SNOOZES)

    fun addSnooze(spec: AlarmSpec) =
        writeList(KEY_SNOOZES, snoozes().filterNot { it.id == spec.id } + spec)

    fun removeSnooze(id: String) = writeList(KEY_SNOOZES, snoozes().filterNot { it.id == id })

    fun find(id: String): AlarmSpec? =
        alarms().firstOrNull { it.id == id }
            ?: timer()?.takeIf { it.id == id }
            ?: snoozes().firstOrNull { it.id == id }

    /** One-time alarm that rang; Dart turns it off next time it runs. */
    fun markFired(id: String) {
        val fired = prefs.getStringSet(KEY_FIRED, emptySet()).orEmpty() + id
        prefs.edit().putStringSet(KEY_FIRED, fired).commit()
    }

    fun consumeFired(): List<String> {
        val fired = prefs.getStringSet(KEY_FIRED, emptySet()).orEmpty().toList()
        prefs.edit().remove(KEY_FIRED).commit()
        return fired
    }

    private fun readList(key: String): List<AlarmSpec> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        val array = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
        return (0 until array.length()).mapNotNull {
            runCatching { AlarmSpec.fromJson(array.getJSONObject(it)) }.getOrNull()
        }
    }

    private fun writeList(key: String, specs: List<AlarmSpec>) {
        val array = JSONArray().apply { specs.forEach { put(it.toJson()) } }
        prefs.edit().putString(key, array.toString()).commit()
    }

    companion object {
        private const val KEY_ALARMS = "alarms"
        private const val KEY_TIMER = "timer"
        private const val KEY_SNOOZES = "snoozes"
        private const val KEY_FIRED = "fired_one_shots"
        private const val KEY_TIMER_TEMPLATE = "timer_template"
    }
}
