package com.eaglestudy.eagle_study.alarm

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Full-screen alarm shown over the lock screen. Plain Android views so it
 * appears instantly, without starting the Flutter engine.
 */
class AlarmActivity : Activity() {
    private val closeSelf: () -> Unit = { runOnUiThread { finish() } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        val spec = AlarmService.ringing
        if (spec == null) {
            finish()
            return
        }
        AlarmService.onStopped = closeSelf
        setContentView(buildLayout(spec))
    }

    override fun onDestroy() {
        if (AlarmService.onStopped === closeSelf) AlarmService.onStopped = null
        super.onDestroy()
    }

    private fun buildLayout(spec: AlarmSpec): LinearLayout {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#07182A"))
            setPadding(dp(32), dp(48), dp(32), dp(48))

            addView(text(SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date()), 72f, "#F2F7FC", light = true))
            addView(text(AlarmNotifications.title(spec).uppercase(Locale.getDefault()), 13f, "#56D9F5", spacing = 0.15f))
            addView(text(spec.message, 20f, "#F2F7FC").apply { setPadding(0, dp(20), 0, dp(48)) })

            if (spec.kind != AlarmSpec.Kind.TIMER) {
                addView(button("SNOOZE 10 MIN", "#24364D") { send(AlarmService.ACTION_SNOOZE) }, buttonParams(dp(12)))
            }
            addView(
                button(if (spec.kind == AlarmSpec.Kind.TIMER) "STOP" else "DISMISS", "#FF548E") {
                    send(AlarmService.ACTION_DISMISS)
                },
                buttonParams(0),
            )
        }
    }

    private fun send(action: String) {
        startService(Intent(this, AlarmService::class.java).setAction(action))
        finish()
    }

    private fun text(value: String, sizeSp: Float, color: String, light: Boolean = false, spacing: Float = 0f) =
        TextView(this).apply {
            text = value
            textSize = sizeSp
            setTextColor(Color.parseColor(color))
            gravity = Gravity.CENTER
            letterSpacing = spacing
            typeface = if (light) Typeface.create("sans-serif-light", Typeface.NORMAL) else Typeface.DEFAULT_BOLD
        }

    private fun button(label: String, color: String, onClick: () -> Unit) = Button(this).apply {
        text = label
        setTextColor(Color.WHITE)
        textSize = 16f
        background = GradientDrawable().apply {
            setColor(Color.parseColor(color))
            cornerRadius = 28 * resources.displayMetrics.density
        }
        setOnClickListener { onClick() }
    }

    private fun buttonParams(bottomMargin: Int) = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        (56 * resources.displayMetrics.density).toInt(),
    ).apply { this.bottomMargin = bottomMargin }
}
