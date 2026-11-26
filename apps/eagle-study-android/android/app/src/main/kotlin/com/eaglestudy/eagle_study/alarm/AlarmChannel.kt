package com.eaglestudy.eagle_study.alarm

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/** Flutter ⇄ native alarm engine (Dart side: lib/features/alarms/data/alarm_bridge.dart). */
class AlarmChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "eagle_study/alarms").also {
        it.setMethodCallHandler(this)
    }
    private val store = AlarmStore(context)
    private val scheduler = AlarmScheduler(context)
    private var preview: AlarmPlayer? = null
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "sync" -> result.success(sync(call.argument<List<Map<*, *>>>("alarms").orEmpty()))
                "scheduleTimerEnd" -> {
                    scheduleTimerEnd(call)
                    result.success(null)
                }
                "cancelTimerEnd" -> {
                    scheduler.cancel(TIMER_ID)
                    store.setTimer(null)
                    result.success(null)
                }
                "consumeFiredOneShots" -> result.success(store.consumeFired())
                "permissions" -> result.success(permissions())
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
                    } else {
                        openAppNotificationSettings()
                    }
                    result.success(null)
                }
                "requestMicrophone" -> {
                    activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 42)
                    result.success(null)
                }
                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        open(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri()))
                    }
                    result.success(null)
                }
                "openFullScreenSettings" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        open(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri()))
                    } else {
                        openAppNotificationSettings()
                    }
                    result.success(null)
                }
                "openBatterySettings" -> {
                    open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    result.success(null)
                }
                "preview" -> {
                    stopPreview()
                    val spec = AlarmSpec.fromMap(call.arguments as Map<*, *>).copy(vibrate = false)
                    preview = AlarmPlayer(context, spec, maxMillis = PREVIEW_MS).also { it.start() }
                    result.success(null)
                }
                "stopPreview" -> {
                    stopPreview()
                    result.success(null)
                }
                "startRecording" -> result.success(startRecording())
                "stopRecording" -> {
                    stopRecording()
                    result.success(null)
                }
                "deleteRecording" -> {
                    deleteRecording(call.argument<String>("path"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: IllegalArgumentException) {
            result.error("invalid", e.message, null)
        } catch (e: Exception) {
            Log.e("EagleAlarm", "${call.method} failed", e)
            result.error("failed", e.message, null)
        }
    }

    /** Replaces the schedule; returns id → next trigger (epoch millis). */
    private fun sync(raw: List<Map<*, *>>): Map<String, Long> {
        val specs = raw.map(AlarmSpec::fromMap) // validates before touching anything
        val keep = specs.map { it.id }.toSet()
        store.alarms().filterNot { it.id in keep }.forEach { scheduler.cancel(it.id) }
        store.setAlarms(specs)
        return specs.associate { it.id to scheduler.schedule(it) }
    }

    private fun scheduleTimerEnd(call: MethodCall) {
        val at = call.argument<Number>("atMillis")!!.toLong()
        val spec = AlarmSpec(
            id = TIMER_ID,
            hour = 0,
            minute = 0,
            days = emptySet(),
            message = call.argument<String>("message") ?: "Focus session complete.",
            sound = call.argument<String>("sound") ?: "classic",
            volume = 0.9f,
            vibrate = true,
            recordingPath = null,
            zone = "UTC",
            atMillis = at,
            kind = AlarmSpec.Kind.TIMER,
        )
        store.setTimer(spec)
        store.setTimerTemplate(spec)
        scheduler.schedule(spec)
    }

    private fun permissions(): Map<String, Boolean> {
        val notifications = context.getSystemService(NotificationManager::class.java)
        val power = context.getSystemService(PowerManager::class.java)
        val notificationsAllowed = notifications.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                granted(Manifest.permission.POST_NOTIFICATIONS))
        return mapOf(
            "notifications" to notificationsAllowed,
            "exactAlarms" to scheduler.canScheduleExact(),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || notifications.canUseFullScreenIntent()),
            "batteryUnrestricted" to power.isIgnoringBatteryOptimizations(context.packageName),
            "microphone" to granted(Manifest.permission.RECORD_AUDIO),
        )
    }

    private fun startRecording(): String {
        if (!granted(Manifest.permission.RECORD_AUDIO)) {
            throw SecurityException("Microphone permission is required to record a voice.")
        }
        stopPreview()
        recorder?.runCatching { release() }
        val file = File(recordingsDir(), "${UUID.randomUUID()}.m4a")
        recorder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()).apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioEncodingBitRate(96_000)
            setAudioSamplingRate(44_100)
            setMaxDuration(MAX_RECORDING_MS)
            setOutputFile(file.absolutePath)
            prepare()
            start()
        }
        recordingFile = file
        return file.absolutePath
    }

    private fun stopRecording() {
        val active = recorder ?: return
        recorder = null
        try {
            active.stop()
        } catch (e: RuntimeException) {
            // stop() throws when nothing was captured (released too quickly).
            recordingFile?.delete()
            throw IllegalArgumentException("Recording was too short. Hold for at least a second.")
        } finally {
            active.release()
        }
    }

    /** Deletes only files this app recorded, never an arbitrary path. */
    private fun deleteRecording(path: String?) {
        val file = path?.let(::File) ?: return
        if (file.canonicalFile.parentFile == recordingsDir().canonicalFile) file.delete()
    }

    private fun stopPreview() {
        preview?.stop()
        preview = null
    }

    fun dispose() {
        stopPreview()
        recorder?.runCatching { release() }
        recorder = null
        channel.setMethodCallHandler(null)
    }

    private fun recordingsDir() = File(context.filesDir, "alarm_recordings").apply { mkdirs() }

    private fun granted(permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun packageUri(): Uri = Uri.parse("package:${context.packageName}")

    private fun openAppNotificationSettings() = open(
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName),
    )

    private fun open(intent: Intent) = activity.startActivity(intent)

    companion object {
        const val TIMER_ID = "timer-end"
        private const val PREVIEW_MS = 8_000L
        private const val MAX_RECORDING_MS = 30_000
    }
}
