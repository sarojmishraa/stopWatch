package com.eaglestudy.eagle_study.study

import android.app.NotificationManager
import android.content.Context

/**
 * Do Not Disturb for Study Mode, only with the user's explicit
 * notification-policy access. The previous filter is saved before changing
 * it and restored afterwards, unless the user changed DND themselves in the
 * meantime (their choice wins). State is persisted so a killed app can
 * still restore on its next start.
 *
 * Android 15+ represents app-set DND as a mode named after the app; the
 * same calls still turn it on and off.
 */
class DndController(context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val prefs = context.applicationContext.getSharedPreferences("eagle_study_mode", Context.MODE_PRIVATE)

    fun hasAccess(): Boolean = manager.isNotificationPolicyAccessGranted

    fun isActive(): Boolean = prefs.contains(KEY_APPLIED)

    /** [mode] is "alarms" or "priority". Returns false without access. */
    fun enter(mode: String): Boolean {
        if (!hasAccess()) return false
        val filter = when (mode) {
            "alarms" -> NotificationManager.INTERRUPTION_FILTER_ALARMS
            "priority" -> NotificationManager.INTERRUPTION_FILTER_PRIORITY
            else -> throw IllegalArgumentException("Unsupported Do Not Disturb mode: $mode")
        }
        val current = manager.currentInterruptionFilter
        if (!isActive()) {
            prefs.edit().putInt(KEY_PREVIOUS, current).putInt(KEY_APPLIED, filter).commit()
        } else {
            prefs.edit().putInt(KEY_APPLIED, filter).commit()
        }
        if (current != filter) manager.setInterruptionFilter(filter)
        return true
    }

    /** Restores the saved filter. Returns what happened, for the UI. */
    fun exit(): String {
        if (!isActive()) return "inactive"
        val previous = prefs.getInt(KEY_PREVIOUS, NotificationManager.INTERRUPTION_FILTER_ALL)
        val applied = prefs.getInt(KEY_APPLIED, NotificationManager.INTERRUPTION_FILTER_ALL)
        prefs.edit().remove(KEY_PREVIOUS).remove(KEY_APPLIED).commit()
        if (!hasAccess()) return "no_access"
        val decision = restoreDecision(applied, manager.currentInterruptionFilter, previous)
        if (decision != null) manager.setInterruptionFilter(decision)
        return if (decision != null) "restored" else "kept_user_change"
    }

    companion object {
        private const val KEY_PREVIOUS = "dnd_previous_filter"
        private const val KEY_APPLIED = "dnd_applied_filter"

        /**
         * The filter to restore, or null to leave things alone because the
         * user changed DND while studying.
         */
        fun restoreDecision(applied: Int, current: Int, previous: Int): Int? =
            if (current == applied && current != previous) previous else null
    }
}
