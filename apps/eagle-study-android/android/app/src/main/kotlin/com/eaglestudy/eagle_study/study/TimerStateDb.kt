package com.eaglestudy.eagle_study.study

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject

/**
 * Reads and writes the persisted timer (`app_state` row `timer`) in the
 * same SQLite file the Flutter app uses (sqflite: databases/eagle_study.db).
 * Only used while Flutter is not running, so the two never write at once.
 */
class TimerStateDb(private val context: Context) {
    fun read(): JSONObject? = open()?.use { db ->
        db.rawQuery("SELECT value FROM app_state WHERE key = 'timer'", null).use { cursor ->
            if (cursor.moveToFirst()) runCatching { JSONObject(cursor.getString(0)) }.getOrNull() else null
        }
    }

    fun write(state: JSONObject) {
        open()?.use { db ->
            db.insertWithOnConflict(
                "app_state",
                null,
                ContentValues().apply {
                    put("key", "timer")
                    put("value", state.toString())
                },
                SQLiteDatabase.CONFLICT_REPLACE,
            )
        }
    }

    private fun open(): SQLiteDatabase? {
        val file = context.getDatabasePath("eagle_study.db")
        if (!file.exists()) return null
        return try {
            SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
        } catch (e: Exception) {
            Log.w("EagleStudy", "Cannot open study database", e)
            null
        }
    }
}
