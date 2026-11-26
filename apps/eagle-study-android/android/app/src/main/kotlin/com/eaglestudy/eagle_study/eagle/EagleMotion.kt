package com.eaglestudy.eagle_study.eagle

import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * How the eagle moves for each study state. The free model has a single
 * flight animation, so moods are expressed by its playback speed plus
 * whole-body motion (height, bob, pitch, spin). Pure Kotlin so it is
 * unit-testable on the JVM.
 */
enum class EagleMood { IDLE, FOCUS, REST, CELEBRATE }

data class MotionParams(
    /** Flight animation playback speed (1 = original). */
    val flapSpeed: Float,
    /** Vertical offset in model units (model fits a unit cube). */
    val lift: Float,
    /** Bob amplitude and frequency (Hz). */
    val bobAmplitude: Float,
    val bobHz: Float,
    /** Nose up (+) / down (−), degrees. */
    val pitchDeg: Float,
    /** Continuous spin, degrees per second (celebration). */
    val spinDegPerSec: Float,
) {
    fun lerp(to: MotionParams, t: Float) = MotionParams(
        flapSpeed + (to.flapSpeed - flapSpeed) * t,
        lift + (to.lift - lift) * t,
        bobAmplitude + (to.bobAmplitude - bobAmplitude) * t,
        bobHz + (to.bobHz - bobHz) * t,
        pitchDeg + (to.pitchDeg - pitchDeg) * t,
        spinDegPerSec + (to.spinDegPerSec - spinDegPerSec) * t,
    )

    companion object {
        fun forMood(mood: EagleMood) = when (mood) {
            EagleMood.IDLE -> MotionParams(0.35f, 0f, 0.025f, 0.35f, 0f, 0f)
            EagleMood.FOCUS -> MotionParams(1.0f, 0.06f, 0.04f, 0.6f, -6f, 0f)
            EagleMood.REST -> MotionParams(0.12f, -0.08f, 0.012f, 0.2f, 4f, 0f)
            EagleMood.CELEBRATE -> MotionParams(1.9f, 0.14f, 0.06f, 1.2f, -10f, 240f)
        }
    }
}

/** Per-frame state: eases toward the mood's parameters, never jumps. */
class EagleMotion(initial: EagleMood = EagleMood.IDLE) {
    var mood: EagleMood = initial
        private set
    var current: MotionParams = MotionParams.forMood(initial)
        private set

    /** Seconds into the flight animation (advanced by flapSpeed). */
    var animationTime = 0.0
        private set
    var spinDeg = 0.0
        private set
    private var clock = 0.0
    private var pokeRemaining = 0.0

    fun setMood(next: EagleMood) {
        mood = next
    }

    /** A tap: brief burst of flapping and a head-turn wiggle. */
    fun poke() {
        pokeRemaining = POKE_SECONDS
    }

    /** Advances by [dt] seconds; returns the body pose for this frame. */
    fun step(dt: Double): Pose {
        val easing = (1 - exp(-dt / TRANSITION_TIME_CONSTANT)).toFloat()
        current = current.lerp(MotionParams.forMood(mood), easing)
        clock += dt
        pokeRemaining = (pokeRemaining - dt).coerceAtLeast(0.0)
        val poke = (pokeRemaining / POKE_SECONDS).toFloat()

        animationTime += dt * (current.flapSpeed + poke * 1.5f)
        spinDeg = if (current.spinDegPerSec > SPIN_SETTLE_DEG_PER_SEC) {
            (spinDeg + current.spinDegPerSec * dt) % 360.0
        } else {
            // Settle by the shortest way back to facing forward, never by
            // unwinding a whole turn backwards.
            shortestAngle(spinDeg) * (1 - easing)
        }

        val bob = current.bobAmplitude * sin(2 * PI * current.bobHz * clock).toFloat()
        val wiggle = 12f * poke * sin(2 * PI * 4 * clock).toFloat()
        return Pose(
            lift = current.lift + bob,
            pitchDeg = current.pitchDeg,
            yawDeg = spinDeg.toFloat() + wiggle,
        )
    }

    data class Pose(val lift: Float, val pitchDeg: Float, val yawDeg: Float)

    companion object {
        /** ~95% of a mood change completes in 3 × this many seconds. */
        const val TRANSITION_TIME_CONSTANT = 0.35
        const val POKE_SECONDS = 0.9
        private const val SPIN_SETTLE_DEG_PER_SEC = 20f

        /** Same angle expressed in (−180, 180]. */
        fun shortestAngle(deg: Double): Double = ((deg + 180.0) % 360.0 + 360.0) % 360.0 - 180.0

        fun parse(name: String?) = when (name) {
            "focus" -> EagleMood.FOCUS
            "rest" -> EagleMood.REST
            "celebrate" -> EagleMood.CELEBRATE
            else -> EagleMood.IDLE
        }
    }
}
