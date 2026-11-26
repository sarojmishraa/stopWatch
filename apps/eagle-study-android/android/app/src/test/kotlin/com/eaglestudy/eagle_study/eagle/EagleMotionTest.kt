package com.eaglestudy.eagle_study.eagle

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EagleMotionTest {
    private fun run(motion: EagleMotion, seconds: Double, dt: Double = 1 / 30.0): EagleMotion.Pose {
        var pose = motion.step(0.0)
        var t = 0.0
        while (t < seconds) {
            pose = motion.step(dt)
            t += dt
        }
        return pose
    }

    @Test fun moodChangesEaseInRatherThanJump() {
        val motion = EagleMotion(EagleMood.IDLE)
        motion.setMood(EagleMood.FOCUS)
        motion.step(1 / 30.0)
        val afterOneFrame = motion.current.flapSpeed
        assertTrue("no instant jump", afterOneFrame < 0.5f)
        run(motion, 2.0)
        assertEquals(1.0f, motion.current.flapSpeed, 0.01f)
    }

    @Test fun focusFlapsFasterThanIdleAndRestSlowest() {
        fun speedAfter(mood: EagleMood): Double {
            val motion = EagleMotion(mood)
            run(motion, 4.0)
            return motion.animationTime
        }
        val rest = speedAfter(EagleMood.REST)
        val idle = speedAfter(EagleMood.IDLE)
        val focus = speedAfter(EagleMood.FOCUS)
        assertTrue("rest < idle < focus: $rest $idle $focus", rest < idle && idle < focus)
    }

    @Test fun celebrationSpinsThenSettlesBackWhenItEnds() {
        val motion = EagleMotion(EagleMood.IDLE)
        motion.setMood(EagleMood.CELEBRATE)
        run(motion, 1.5)
        assertTrue("spinning", motion.spinDeg > 30)
        motion.setMood(EagleMood.IDLE)
        run(motion, 3.0)
        assertTrue("spin settles: ${motion.spinDeg}", abs(motion.spinDeg) < 5)
    }

    @Test fun pokeWigglesBrieflyThenStops() {
        val motion = EagleMotion(EagleMood.IDLE)
        run(motion, 2.0)
        val before = motion.animationTime
        motion.poke()
        run(motion, 0.3)
        val burst = motion.animationTime - before
        assertTrue("faster flapping during poke: $burst", burst > 0.3 * 0.35 * 1.5)
        val settled = run(motion, 2.0)
        assertTrue("wiggle gone: ${settled.yawDeg}", abs(settled.yawDeg) < 1f)
    }

    @Test fun restSitsLowerThanFocus() {
        val rest = EagleMotion(EagleMood.REST).also { run(it, 3.0) }.current.lift
        val focus = EagleMotion(EagleMood.FOCUS).also { run(it, 3.0) }.current.lift
        assertTrue(rest < 0 && focus > 0)
    }

    @Test fun shortestAngleNeverUnwindsAFullTurn() {
        assertEquals(-10.0, EagleMotion.shortestAngle(350.0), 1e-9)
        assertEquals(10.0, EagleMotion.shortestAngle(10.0), 1e-9)
        assertEquals(-90.0, EagleMotion.shortestAngle(270.0), 1e-9)
    }

    @Test fun parsesMoodNames() {
        assertEquals(EagleMood.FOCUS, EagleMotion.parse("focus"))
        assertEquals(EagleMood.CELEBRATE, EagleMotion.parse("celebrate"))
        assertEquals(EagleMood.IDLE, EagleMotion.parse("nonsense"))
        assertEquals(EagleMood.IDLE, EagleMotion.parse(null))
    }
}
