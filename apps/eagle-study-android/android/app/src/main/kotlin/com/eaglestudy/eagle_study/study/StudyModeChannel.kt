package com.eaglestudy.eagle_study.study

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Flutter ⇄ Study Mode (Dart side: lib/features/study/data/study_mode_bridge.dart). */
class StudyModeChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "eagle_study/study_mode").also {
        it.setMethodCallHandler(this)
    }
    private val dnd = DndController(context)

    init {
        active = this
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "showNotification" -> {
                    StudyNotification.show(context, JSONObject(call.arguments as Map<*, *>))
                    result.success(null)
                }
                "cancelNotification" -> {
                    StudyNotification.cancel(context)
                    result.success(null)
                }
                "dndAccess" -> result.success(dnd.hasAccess())
                "openDndSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                    result.success(null)
                }
                "enterDnd" -> result.success(dnd.enter(call.argument<String>("mode")!!))
                "exitDnd" -> result.success(dnd.exit())
                "dndActive" -> result.success(dnd.isActive())
                "setKeepScreenOn" -> {
                    if (call.argument<Boolean>("on") == true) {
                        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "takePendingAction" -> {
                    result.success(pendingAction)
                    pendingAction = null
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("invalid", e.message, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (active === this) active = null
    }

    companion object {
        @Volatile private var active: StudyModeChannel? = null

        /** Action from a notification that opened the app (e.g. "finish"). */
        @Volatile var pendingAction: String? = null

        /**
         * Hands a notification action to Dart if the app is running.
         * Returns false when Flutter is not attached.
         */
        fun deliver(action: String): Boolean {
            val target = active ?: return false
            Handler(Looper.getMainLooper()).post {
                target.channel.invokeMethod("notificationAction", action)
            }
            return true
        }
    }
}
