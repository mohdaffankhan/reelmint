package io.github.mohdaffankhan.reelmint

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout

/**
 * Full-screen annotation layer: draw over anything while recording.
 * Toolbar: colours, undo, clear, done.
 */
class DrawOverlay(private val ctx: Context, private val onClosed: () -> Unit) {
    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).toInt()

    private var root: FrameLayout? = null
    var isShown = false
        private set

    private val colors = listOf(0xFFFF4D6D, 0xFFFFD43B, 0xFF2EE6A8, 0xFF4DABF7, 0xFFFFFFFF, 0xFF7C5CFF).map { it.toInt() }
    private var color = colors.first()

    private inner class Canvasview : View(ctx) {
        val strokes = mutableListOf<Pair<Path, Paint>>()
        private var current: Path? = null

        private fun paint() = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            strokeWidth = dp(6).toFloat()
            color = this@DrawOverlay.color
            setShadowLayer(dp(2).toFloat(), 0f, 0f, Color.argb(90, 0, 0, 0))
        }

        private var lx = 0f; private var ly = 0f

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(e: MotionEvent): Boolean {
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    current = Path().apply { moveTo(e.x, e.y) }
                    strokes += current!! to paint()
                    lx = e.x; ly = e.y
                }
                MotionEvent.ACTION_MOVE -> {
                    current?.quadTo(lx, ly, (e.x + lx) / 2, (e.y + ly) / 2)
                    lx = e.x; ly = e.y
                }
                MotionEvent.ACTION_UP -> { current?.lineTo(e.x, e.y); current = null }
            }
            invalidate()
            return true
        }

        override fun onDraw(canvas: Canvas) {
            for ((p, paint) in strokes) canvas.drawPath(p, paint)
        }
    }

    fun show() {
        if (isShown) return
        val canvas = Canvasview().apply { setLayerType(View.LAYER_TYPE_SOFTWARE, null) }
        val bar = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(8), dp(10), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(28).toFloat()
                setColor(Color.argb(235, 18, 16, 28))
                setStroke(dp(1), Color.argb(60, 255, 255, 255))
            }
            elevation = dp(8).toFloat()
        }
        val swatches = mutableListOf<View>()
        fun refreshSwatches() = swatches.forEachIndexed { i, v ->
            (v.background as GradientDrawable).setStroke(dp(if (colors[i] == color) 3 else 0), Color.WHITE)
        }
        for (c in colors) {
            val sw = View(ctx).apply {
                background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(c) }
                layoutParams = LinearLayout.LayoutParams(dp(26), dp(26)).apply { marginEnd = dp(8) }
                setOnClickListener { color = c; refreshSwatches() }
            }
            swatches += sw; bar.addView(sw)
        }
        refreshSwatches()
        bar.addView(tool(R.drawable.ic_undo) { if (canvas.strokes.isNotEmpty()) { canvas.strokes.removeAt(canvas.strokes.lastIndex); canvas.invalidate() } })
        bar.addView(tool(R.drawable.ic_delete) { canvas.strokes.clear(); canvas.invalidate() })
        bar.addView(tool(R.drawable.ic_check, tint = 0xFF2EE6A8.toInt()) { hide(); onClosed() })

        val frame = FrameLayout(ctx).apply {
            addView(canvas, FrameLayout.LayoutParams(-1, -1))
            addView(bar, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
                bottomMargin = dp(56)
            })
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        wm.addView(frame, params)
        root = frame
        isShown = true
    }

    fun hide() {
        if (!isShown) return
        isShown = false
        root?.let { runCatching { wm.removeView(it) } }
        root = null
    }

    private fun tool(res: Int, tint: Int = Color.WHITE, onClick: () -> Unit) = ImageView(ctx).apply {
        setImageResource(res)
        setColorFilter(tint)
        setPadding(dp(7), dp(7), dp(7), dp(7))
        layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply { marginStart = dp(4) }
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(40, 255, 255, 255)) }
        setOnClickListener { onClick() }
    }
}
