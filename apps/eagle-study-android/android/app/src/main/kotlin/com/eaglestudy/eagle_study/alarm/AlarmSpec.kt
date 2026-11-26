package com.eaglestudy.eagle_study.alarm

import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

/**
 * Everything the native engine needs to schedule and ring one alarm. The
 * Dart side owns alarms (SQLite) and pushes them here; this copy exists so
 * alarms still ring, repeat and survive reboots while Flutter is not running.
 */
data class AlarmSpec(
    val id: String,
    val hour: Int,
    val minute: Int,
    /** ISO weekdays, 1 = Monday … 7 = Sunday. Empty means ring once. */
    val days: Set<Int>,
    val message: String,
    val sound: String,
    val volume: Float,
    val vibrate: Boolean,
    val recordingPath: String?,
    val zone: String,
    /** Fixed instant instead of a wall-clock time (timer end, snooze). */
    val atMillis: Long? = null,
    val kind: Kind = Kind.ALARM,
) {
    enum class Kind { ALARM, TIMER, SNOOZE }

    val repeats: Boolean get() = atMillis == null && days.isNotEmpty()

    init {
        require(hour in 0..23 && minute in 0..59) { "Invalid time $hour:$minute" }
        require(days.all { it in 1..7 }) { "Invalid weekday in $days" }
        require(volume in 0.05f..1f) { "Invalid volume $volume" }
        require(TimeZone.getAvailableIDs().contains(zone)) { "Unknown timezone $zone" }
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("hour", hour)
        put("minute", minute)
        put("days", JSONArray(days.sorted()))
        put("message", message)
        put("sound", sound)
        put("volume", volume.toDouble())
        put("vibrate", vibrate)
        put("recordingPath", recordingPath ?: JSONObject.NULL)
        put("zone", zone)
        put("atMillis", atMillis ?: JSONObject.NULL)
        put("kind", kind.name)
    }

    companion object {
        fun fromJson(o: JSONObject): AlarmSpec {
            val days = o.getJSONArray("days")
            return AlarmSpec(
                id = o.getString("id"),
                hour = o.getInt("hour"),
                minute = o.getInt("minute"),
                days = (0 until days.length()).map { days.getInt(it) }.toSet(),
                message = o.getString("message"),
                sound = o.getString("sound"),
                volume = o.getDouble("volume").toFloat(),
                vibrate = o.getBoolean("vibrate"),
                recordingPath = if (o.isNull("recordingPath")) null else o.getString("recordingPath"),
                zone = o.getString("zone"),
                atMillis = if (o.isNull("atMillis")) null else o.getLong("atMillis"),
                kind = Kind.valueOf(o.optString("kind", Kind.ALARM.name)),
            )
        }

        /** From a Flutter method-channel map (see Alarm.toNative in Dart). */
        fun fromMap(m: Map<*, *>): AlarmSpec = AlarmSpec(
            id = m["id"] as String,
            hour = (m["hour"] as Number).toInt(),
            minute = (m["minute"] as Number).toInt(),
            days = (m["days"] as? List<*>).orEmpty().map { (it as Number).toInt() }.toSet(),
            message = m["message"] as? String ?: "",
            sound = m["sound"] as? String ?: "classic",
            volume = (m["volume"] as? Number)?.toFloat() ?: 0.8f,
            vibrate = m["vibrate"] as? Boolean ?: true,
            recordingPath = m["recordingPath"] as? String,
            zone = m["zone"] as? String ?: "Asia/Kolkata",
        )
    }
}
