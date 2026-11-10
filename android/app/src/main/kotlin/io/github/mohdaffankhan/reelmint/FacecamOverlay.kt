package io.github.mohdaffankhan.reelmint

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import kotlin.math.abs

/**
 * Round, draggable front-camera bubble drawn over other apps (and therefore
 * captured in the recording). Tap to cycle S → M → L.
 */
class FacecamOverlay(private val ctx: Context, initialSize: String = "m") : LifecycleOwner {
    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).toInt()

    private val sizes = listOf("s" to 96, "m" to 136, "l" to 196)
    private var sizeIndex = sizes.indexOfFirst { it.first == initialSize }.coerceAtLeast(1)
    private var root: FrameLayout? = null
    private var provider: ProcessCameraProvider? = null
    var isShown = false
        private set

    private val params = WindowManager.LayoutParams(
        0, 0,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = ctx.resources.displayMetrics.widthPixels - dp(sizes[sizeIndex].second) - dp(16)
        y = dp(260)
    }

    fun show() {
        if (isShown) return
        val sizePx = dp(sizes[sizeIndex].second)
        params.width = sizePx; params.height = sizePx
        val preview = PreviewView(ctx).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE // TextureView: clips to a circle
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        val ring = View(ctx).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setStroke(dp(3), Color.WHITE)
                setColor(Color.TRANSPARENT)
            }
        }
        val frame = FrameLayout(ctx).apply {
            clipToOutline = true
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) = outline.setOval(0, 0, view.width, view.height)
            }
            elevation = dp(10).toFloat()
            setBackgroundColor(Color.BLACK)
            addView(preview, FrameLayout.LayoutParams(-1, -1))
            addView(ring, FrameLayout.LayoutParams(-1, -1))
        }
        attachDrag(frame)
        wm.addView(frame, params)
        root = frame
        isShown = true
        registry.currentState = Lifecycle.State.RESUMED

        val future = ProcessCameraProvider.getInstance(ctx)
        future.addListener({
            if (!isShown) return@addListener
            runCatching {
                val p = future.get()
                provider = p
                val useCase = Preview.Builder().build().also { it.surfaceProvider = preview.surfaceProvider }
                p.unbindAll()
                val selector = if (p.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) CameraSelector.DEFAULT_FRONT_CAMERA
                else CameraSelector.DEFAULT_BACK_CAMERA
                p.bindToLifecycle(this, selector, useCase)
            }.onFailure { RecorderBus.emitError("Facecam unavailable: ${it.message}") }
        }, ContextCompat.getMainExecutor(ctx))
    }

    fun hide() {
        if (!isShown) return
        isShown = false
        runCatching { provider?.unbindAll() }
        registry.currentState = Lifecycle.State.CREATED
        root?.let { runCatching { wm.removeView(it) } }
        root = null
    }

    private fun cycleSize() {
        sizeIndex = (sizeIndex + 1) % sizes.size
        val px = dp(sizes[sizeIndex].second)
        params.width = px; params.height = px
        root?.let { runCatching { wm.updateViewLayout(it, params) } }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachDrag(v: View) {
        var sx = 0; var sy = 0; var tx = 0f; var ty = 0f; var moved = false
        v.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> { sx = params.x; sy = params.y; tx = e.rawX; ty = e.rawY; moved = false }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - tx; val dy = e.rawY - ty
                    if (abs(dx) > dp(4) || abs(dy) > dp(4)) moved = true
                    params.x = sx + dx.toInt(); params.y = sy + dy.toInt()
                    root?.let { runCatching { wm.updateViewLayout(it, params) } }
                }
                MotionEvent.ACTION_UP -> if (!moved) cycleSize()
            }
            true
        }
    }
}
