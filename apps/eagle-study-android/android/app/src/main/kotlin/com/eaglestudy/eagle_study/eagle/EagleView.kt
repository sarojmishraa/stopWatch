package com.eaglestudy.eagle_study.eagle

import android.app.ActivityManager
import android.content.Context
import android.opengl.Matrix
import android.util.Log
import android.view.Choreographer
import android.view.TextureView
import android.view.View
import com.google.android.filament.Colors
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.android.UiHelper
import com.google.android.filament.utils.ModelViewer
import com.google.android.filament.utils.Utils
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Renders the eagle GLB with Google Filament inside a Flutter platform view.
 * Transparent background, built-in lighting (no environment-map assets),
 * 30 fps cap to limit battery use. Mood and taps arrive over a per-view
 * MethodChannel; load failures are reported so Flutter can fall back to 2D.
 */
class EagleView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    params: Map<*, *>,
) : PlatformView, Choreographer.FrameCallback {

    private val textureView = TextureView(context).apply { isOpaque = false }
    private val channel = MethodChannel(messenger, "eagle_study/eagle_view_$viewId")
    private val viewer: ModelViewer
    private val motion = EagleMotion(EagleMotion.parse(params["mood"] as? String))
    private val baseYawDeg = (params["baseYawDeg"] as? Number)?.toFloat() ?: 0f
    private val baseTransform = FloatArray(16)
    private var lastFrameNanos = 0L
    private var running = false
    private var disposed = false
    private val lights = mutableListOf<Int>()

    init {
        val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK).apply { isOpaque = false }
        viewer = ModelViewer(textureView, uiHelper = uiHelper)
        configureScene()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setMood" -> {
                    motion.setMood(EagleMotion.parse(call.arguments as? String))
                    result.success(null)
                }
                "poke" -> {
                    motion.poke()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val asset = params["asset"] as? String ?: "assets/models/eagle.glb"
        if (load(context, asset)) start()
    }

    private fun configureScene() {
        viewer.view.blendMode = com.google.android.filament.View.BlendMode.TRANSLUCENT
        viewer.renderer.clearOptions = viewer.renderer.clearOptions.apply {
            clear = true
            clearColor = doubleArrayOf(0.0, 0.0, 0.0, 0.0)
        }
        viewer.scene.skybox = null
        // Soft ambient from spherical harmonics (band 0 only): neutral, cool.
        viewer.scene.indirectLight = IndirectLight.Builder()
            .irradiance(1, floatArrayOf(0.9f, 0.95f, 1.05f))
            .intensity(32_000f)
            .build(viewer.engine)
        // Warm key light from upper left, cool rim from behind.
        lights += light(Colors.cct(5600f, FloatArray(3)), 95_000f, floatArrayOf(-0.5f, -1f, -0.6f))
        lights += light(floatArrayOf(0.55f, 0.75f, 1f), 40_000f, floatArrayOf(0.4f, -0.2f, 1f))
    }

    private fun light(color: FloatArray, lux: Float, direction: FloatArray): Int {
        val entity = EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(color[0], color[1], color[2])
            .intensity(lux)
            .direction(direction[0], direction[1], direction[2])
            .castShadows(false)
            .build(viewer.engine, entity)
        viewer.scene.addEntity(entity)
        return entity
    }

    private fun load(context: Context, asset: String): Boolean = try {
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(asset)
        val bytes = context.assets.open(key).use { it.readBytes() }
        val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder()).put(bytes).apply { rewind() }
        viewer.loadModelGlb(buffer)
        viewer.transformToUnitCube()
        val tm = viewer.engine.transformManager
        tm.getTransform(tm.getInstance(viewer.asset!!.root), baseTransform)
        if ((viewer.animator?.animationCount ?: 0) == 0) Log.w(TAG, "Model has no animations")
        channel.invokeMethod("loaded", viewer.animator?.animationCount ?: 0)
        true
    } catch (e: Exception) {
        Log.e(TAG, "Cannot load $asset", e)
        channel.invokeMethod("error", e.message ?: e.javaClass.simpleName)
        false
    }

    private fun start() {
        if (running || disposed) return
        running = true
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running || disposed) return
        Choreographer.getInstance().postFrameCallback(this)
        val elapsed = if (lastFrameNanos == 0L) 0L else frameTimeNanos - lastFrameNanos
        if (lastFrameNanos != 0L && elapsed < MIN_FRAME_NANOS) return // 30 fps cap
        lastFrameNanos = frameTimeNanos
        val pose = motion.step(elapsed / 1e9)
        applyPose(pose)
        viewer.animator?.let { animator ->
            if (animator.animationCount > 0) {
                val duration = animator.getAnimationDuration(0).toDouble().coerceAtLeast(0.001)
                animator.applyAnimation(0, (motion.animationTime % duration).toFloat())
                animator.updateBoneMatrices()
            }
        }
        viewer.render(frameTimeNanos)
    }

    private fun applyPose(pose: EagleMotion.Pose) {
        val asset = viewer.asset ?: return
        val motionMatrix = FloatArray(16)
        Matrix.setIdentityM(motionMatrix, 0)
        Matrix.translateM(motionMatrix, 0, 0f, pose.lift, 0f)
        Matrix.rotateM(motionMatrix, 0, baseYawDeg + pose.yawDeg, 0f, 1f, 0f)
        Matrix.rotateM(motionMatrix, 0, pose.pitchDeg, 1f, 0f, 0f)
        val out = FloatArray(16)
        Matrix.multiplyMM(out, 0, motionMatrix, 0, baseTransform, 0)
        val tm = viewer.engine.transformManager
        tm.setTransform(tm.getInstance(asset.root), out)
    }

    override fun getView(): View = textureView

    override fun dispose() {
        if (disposed) return
        disposed = true
        running = false
        Choreographer.getInstance().removeFrameCallback(this)
        channel.setMethodCallHandler(null)
        lights.forEach {
            viewer.scene.remove(it)
            viewer.engine.destroyEntity(it)
        }
        viewer.destroyModel()
        viewer.scene.indirectLight?.let { viewer.engine.destroyIndirectLight(it) }
    }

    companion object {
        private const val TAG = "EagleView"
        private const val MIN_FRAME_NANOS = 1_000_000_000L / 31
        const val VIEW_TYPE = "eagle_study/eagle_view"

        init {
            Utils.init()
        }

        /** Filament needs OpenGL ES 3.0; skip 3D on low-RAM devices too. */
        fun isSupported(context: Context): Boolean {
            val am = context.getSystemService(ActivityManager::class.java)
            return am.deviceConfigurationInfo.reqGlEsVersion >= 0x30000 && !am.isLowRamDevice
        }
    }
}

class EagleViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        EagleView(context, messenger, viewId, args as? Map<*, *> ?: emptyMap<String, Any>())
}
