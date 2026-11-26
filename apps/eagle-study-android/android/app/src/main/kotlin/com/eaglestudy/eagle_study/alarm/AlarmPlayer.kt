package com.eaglestudy.eagle_study.alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.io.File

/**
 * Makes the noise for one alarm on the ALARM stream, so it follows the
 * phone's alarm volume and still plays in silent mode.
 *
 * Voice styles are Android text-to-speech with different pitch and speed;
 * they read the alarm message, so no audio files are bundled. If speech is
 * unavailable, or a recording is missing, it falls back to the classic tone
 * rather than staying silent.
 */
class AlarmPlayer(
    private val context: Context,
    private val spec: AlarmSpec,
    /** Stop automatically after this long (previews); null = until stop(). */
    private val maxMillis: Long? = null,
) {
    private val handler = Handler(Looper.getMainLooper())
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private var media: MediaPlayer? = null
    private var tts: TextToSpeech? = null
    private var vibrator: Vibrator? = null
    private var focusRequest: AudioFocusRequest? = null
    @Volatile private var stopped = false

    fun start() {
        requestFocus()
        if (spec.vibrate) vibrate()
        when (spec.sound) {
            "classic" -> playUri(defaultAlarmUri())
            "recording" -> {
                val file = spec.recordingPath?.let(::File)?.takeIf { it.exists() && it.length() > 0 }
                playUri(file?.let(Uri::fromFile) ?: defaultAlarmUri())
            }
            else -> speak()
        }
        maxMillis?.let { handler.postDelayed({ stop() }, it) }
    }

    fun stop() {
        if (stopped) return
        stopped = true
        handler.removeCallbacksAndMessages(null)
        media?.runCatching { stop(); release() }
        media = null
        tts?.runCatching { stop(); shutdown() }
        tts = null
        vibrator?.cancel()
        abandonFocus()
    }

    private fun playUri(uri: Uri) {
        if (stopped) return
        try {
            media = MediaPlayer().apply {
                setAudioAttributes(ALARM_AUDIO)
                setDataSource(context, uri)
                isLooping = true
                setVolume(spec.volume, spec.volume)
                prepare()
                start()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Cannot play $uri", e)
            media?.release()
            media = null
            val fallback = Settings.System.DEFAULT_NOTIFICATION_URI
            if (uri != fallback) playUri(fallback)
        }
    }

    private fun speak() {
        val style = VOICE_STYLES[spec.sound] ?: VOICE_STYLES.getValue("voice")
        tts = TextToSpeech(context.applicationContext) { status ->
            handler.post {
                val engine = tts
                if (stopped || engine == null) return@post
                if (status != TextToSpeech.SUCCESS) {
                    Log.w(TAG, "Text-to-speech unavailable; using the classic tone")
                    playUri(defaultAlarmUri())
                    return@post
                }
                engine.setAudioAttributes(ALARM_AUDIO)
                engine.setPitch(style.pitch)
                engine.setSpeechRate(style.rate)
                engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit

                    override fun onDone(utteranceId: String?) {
                        if (utteranceId?.endsWith(":last") == true && !stopped) {
                            handler.postDelayed({ speakOnce(style) }, PAUSE_BETWEEN_REPEATS_MS)
                        }
                    }

                    @Deprecated("Required override on older APIs")
                    override fun onError(utteranceId: String?) {
                        handler.post { if (!stopped && media == null) playUri(defaultAlarmUri()) }
                    }
                })
                speakOnce(style)
            }
        }
    }

    private fun speakOnce(style: VoiceStyle) {
        val engine = tts ?: return
        if (stopped) return
        val loud = Bundle().apply {
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, spec.volume * style.volume)
        }
        if (style.echo) {
            val quiet = Bundle().apply {
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, spec.volume * style.volume * 0.35f)
            }
            engine.speak(spec.message, TextToSpeech.QUEUE_FLUSH, loud, "eagle:first")
            engine.speak(spec.message, TextToSpeech.QUEUE_ADD, quiet, "eagle:last")
        } else {
            engine.speak(spec.message, TextToSpeech.QUEUE_FLUSH, loud, "eagle:last")
        }
    }

    private fun vibrate() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Vibrator::class.java)
        }
        val pattern = longArrayOf(0, 700, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0), ALARM_AUDIO)
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun requestFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(ALARM_AUDIO)
                .build()
                .also { audioManager.requestAudioFocus(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }

    private fun defaultAlarmUri(): Uri =
        RingtoneManager.getActualDefaultRingtoneUri(context, RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: Settings.System.DEFAULT_NOTIFICATION_URI

    private data class VoiceStyle(val pitch: Float, val rate: Float, val volume: Float, val echo: Boolean)

    companion object {
        private const val TAG = "EagleAlarm"
        private const val PAUSE_BETWEEN_REPEATS_MS = 1500L

        val ALARM_AUDIO: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        private val VOICE_STYLES = mapOf(
            "voice" to VoiceStyle(pitch = 1.0f, rate = 0.95f, volume = 1.0f, echo = false),
            "ghost" to VoiceStyle(pitch = 0.55f, rate = 0.7f, volume = 1.0f, echo = true),
            "monster" to VoiceStyle(pitch = 0.3f, rate = 0.65f, volume = 1.0f, echo = false),
            "whisper" to VoiceStyle(pitch = 1.5f, rate = 0.6f, volume = 0.6f, echo = true),
        )
    }
}
