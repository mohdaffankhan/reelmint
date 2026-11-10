package io.github.mohdaffankhan.reelmint

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * Draggable recording bubble shown over other apps.
 *  • dot + timer: tap to collapse to a dot
 *  • pause/resume · stop · ⋮ expands: mic mute, facecam, draw on screen
 *
 * The bubble docks to the left or right edge. Its window is anchored to that edge and its
 * contents are mirrored, so the menu always unfolds towards the middle of the screen and
 * never off-screen. It can be dragged from anywhere, even from a button: as soon as the
 * finger moves past the touch slop the press is cancelled, so drags never become clicks.
 */
class FloatingControls(private val ctx: Context, private val usesMic: Boolean) {
    companion object {
        /** The bubble currently on screen (for the in-app state and on-device tests). */
        @Volatile var current: FloatingControls? = null
            private set
    }

    private val wm = ctx.getSystemService(WindowManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val density = ctx.resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).toInt()
    private val edgeMargin get() = dp(8)

    private lateinit var root: DragLayout
    private lateinit var dot: View
    private lateinit var timer: TextView
    private lateinit var pauseBtn: ImageView
    private lateinit var stopBtn: ImageView
    private lateinit var moreBtn: ImageView
    private lateinit var micBtn: ImageView
    private lateinit var camBtn: ImageView
    private lateinit var penBtn: ImageView
    private var collapsed = false
    private var expanded = false
    private var dockRight = false
    private var snap: ValueAnimator? = null
    var isShown = false
        private set

    private val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = dp(8); y = dp(140)
    }

    private val tick = object : Runnable {
        override fun run() {
            render()
            main.postDelayed(this, 250)
        }
    }

    fun show() {
        if (isShown) return
        build()
        wm.addView(root, params)
        isShown = true
        current = this
        main.post(tick)
    }

    fun hide() {
        if (!isShown) return
        snap?.cancel()
        main.removeCallbacks(tick)
        runCatching { wm.removeView(root) }
        isShown = false
        if (current === this) current = null
    }

    // ------------------------------------------------------------------ views

    private fun build() {
        root = DragLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                cornerRadius = dp(28).toFloat()
                setColor(Color.argb(240, 18, 16, 28))
                setStroke(dp(1), Color.argb(60, 255, 255, 255))
            }
            elevation = dp(8).toFloat()
        }
        dot = View(ctx).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(0xFFFF4D6D.toInt()) }
            layoutParams = LinearLayout.LayoutParams(dp(10), dp(10))
        }
        timer = TextView(ctx).apply {
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            text = "00:00"
            textDirection = View.TEXT_DIRECTION_LTR
            setPaddingRelative(0, 0, dp(6), 0)
        }
        pauseBtn = iconButton(R.drawable.ic_pause) {
            val action = if (RecorderBus.state == RecorderBus.State.PAUSED) RecorderService.ACTION_RESUME
            else RecorderService.ACTION_PAUSE
            RecorderService.command(ctx, action)
        }
        stopBtn = iconButton(R.drawable.ic_stop, tint = 0xFFFF4D6D.toInt()) {
            RecorderService.command(ctx, RecorderService.ACTION_STOP)
        }
        micBtn = iconButton(R.drawable.ic_mic) { RecorderService.command(ctx, RecorderService.ACTION_TOGGLE_MIC) }
        camBtn = iconButton(R.drawable.ic_videocam) { RecorderService.command(ctx, RecorderService.ACTION_TOGGLE_FACECAM) }
        penBtn = iconButton(R.drawable.ic_pen) { RecorderService.command(ctx, RecorderService.ACTION_TOGGLE_DRAW) }
        moreBtn = iconButton(R.drawable.ic_more) { expanded = !expanded; layoutButtons() }

        listOf(dot, timer, pauseBtn, stopBtn, micBtn, camBtn, penBtn, moreBtn).forEach(root::addView)
        layoutButtons()
    }

    private fun layoutButtons() {
        val mainVis = if (collapsed) View.GONE else View.VISIBLE
        timer.visibility = mainVis; pauseBtn.visibility = mainVis; stopBtn.visibility = mainVis; moreBtn.visibility = mainVis
        val extra = if (!collapsed && expanded) View.VISIBLE else View.GONE
        micBtn.visibility = if (usesMic) extra else View.GONE
        camBtn.visibility = extra
        penBtn.visibility = extra
        moreBtn.rotation = if (expanded) 90f else 0f
        (dot.layoutParams as LinearLayout.LayoutParams).marginEnd = if (collapsed) 0 else dp(8)
        // Mirror when docked right: the dot sits at the screen edge and buttons extend inwards.
        root.layoutDirection = if (dockRight) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        root.setPaddingRelative(if (collapsed) dp(10) else dp(12), dp(10), if (collapsed) dp(10) else dp(8), dp(10))
        root.requestLayout()
        // Keep it on screen vertically after a size change.
        root.post { clampY(); update() }
    }

    private fun iconButton(res: Int, tint: Int = Color.WHITE, onClick: () -> Unit) = ImageView(ctx).apply {
        setImageResource(res)
        setColorFilter(tint)
        setPadding(dp(8), dp(8), dp(8), dp(8))
        layoutParams = LinearLayout.LayoutParams(dp(36), dp(36)).apply { marginStart = dp(2) }
        background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.argb(40, 255, 255, 255)) }
        setOnClickListener { onClick() }
    }

    // ------------------------------------------------------------------ drag

    private fun screen(): Rect =
        if (Build.VERSION.SDK_INT >= 30) wm.currentWindowMetrics.bounds
        else ctx.resources.displayMetrics.let { Rect(0, 0, it.widthPixels, it.heightPixels) }

    private fun update() {
        if (isShown) runCatching { wm.updateViewLayout(root, params) }
    }

    private fun clampY() {
        val maxY = (screen().height() - root.height - edgeMargin).coerceAtLeast(0)
        params.y = params.y.coerceIn(edgeMargin, maxY)
    }

    /** Distance of the bubble's left edge from the screen's left edge. */
    private fun absLeft(): Int = if (dockRight) screen().width() - params.x - root.width else params.x

    private fun onDragStart() {
        snap?.cancel()
        root.animate().scaleX(1.06f).scaleY(1.06f).setDuration(120).start()
    }

    private fun onDrag(startX: Int, startY: Int, dx: Float, dy: Float) {
        params.x = if (dockRight) startX - dx.toInt() else startX + dx.toInt()
        params.y = startY + dy.toInt()
        clampY()
        update()
    }

    private fun onDragEnd() {
        root.animate().scaleX(1f).scaleY(1f).setDuration(160).start()
        val w = screen().width()
        val left = absLeft()
        val goRight = left + root.width / 2 > w / 2
        if (goRight != dockRight) {
            // Re-anchor to the other edge without moving on screen, then mirror the contents.
            dockRight = goRight
            params.gravity = Gravity.TOP or (if (dockRight) Gravity.END else Gravity.START)
            params.x = if (dockRight) w - left - root.width else left
            layoutButtons()
        }
        val from = params.x
        snap = ValueAnimator.ofInt(from, edgeMargin).apply {
            duration = 260
            interpolator = OvershootInterpolator(0.9f)
            addUpdateListener { params.x = it.animatedValue as Int; update() }
            start()
        }
    }

    private fun onTap() {
        collapsed = !collapsed
        layoutButtons()
    }

    /**
     * Intercepts touches from its children once the finger travels past the touch slop, so the
     * whole bubble is a drag handle and a drag never triggers a button.
     */
    @SuppressLint("ViewConstructor", "ClickableViewAccessibility")
    private inner class DragLayout(c: Context) : LinearLayout(c) {
        private val slop = ViewConfiguration.get(c).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        private fun begin(e: MotionEvent) {
            downX = e.rawX; downY = e.rawY
            startX = params.x; startY = params.y
            dragging = false
        }

        private fun pastSlop(e: MotionEvent) = abs(e.rawX - downX) > slop || abs(e.rawY - downY) > slop

        override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> begin(e)
                MotionEvent.ACTION_MOVE -> if (!dragging && pastSlop(e)) {
                    dragging = true
                    onDragStart()
                    return true // children get ACTION_CANCEL: no accidental click
                }
            }
            return dragging
        }

        override fun onTouchEvent(e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> begin(e)
                MotionEvent.ACTION_MOVE -> {
                    if (!dragging && pastSlop(e)) { dragging = true; onDragStart() }
                    if (dragging) onDrag(startX, startY, e.rawX - downX, e.rawY - downY)
                }
                MotionEvent.ACTION_UP -> {
                    if (dragging) onDragEnd() else onTap()
                    dragging = false
                }
                MotionEvent.ACTION_CANCEL -> {
                    if (dragging) onDragEnd()
                    dragging = false
                }
            }
            return true
        }
    }

    /** Screen-space geometry, used by on-device tests to drive the bubble with real touches. */
    fun geometry(): Map<String, Any?> {
        fun center(v: View): List<Int>? {
            if (v.visibility != View.VISIBLE || v.width == 0) return null
            val p = IntArray(2).also(v::getLocationOnScreen)
            return listOf(p[0] + v.width / 2, p[1] + v.height / 2)
        }
        val p = IntArray(2).also(root::getLocationOnScreen)
        val s = screen()
        return mapOf(
            "left" to p[0], "top" to p[1], "right" to p[0] + root.width, "bottom" to p[1] + root.height,
            "screenWidth" to s.width(), "screenHeight" to s.height(),
            "dockRight" to dockRight, "expanded" to expanded, "collapsed" to collapsed,
            "dot" to center(dot), "pause" to center(pauseBtn), "stop" to center(stopBtn),
            "more" to center(moreBtn), "pen" to center(penBtn),
            "animating" to (snap?.isRunning == true),
        )
    }

    // ------------------------------------------------------------------ state

    private var lastText = ""
    private var lastPaused: Boolean? = null
    private var lastMuted: Boolean? = null
    private var lastCam: Boolean? = null
    private var lastDraw: Boolean? = null

    private fun highlight(v: ImageView, on: Boolean, onColor: Int) {
        v.setColorFilter(if (on) onColor else Color.WHITE)
        (v.background as GradientDrawable).setColor(
            if (on) Color.argb(70, Color.red(onColor), Color.green(onColor), Color.blue(onColor)) else Color.argb(40, 255, 255, 255)
        )
    }

    /** Only touches views whose state actually changed: avoids relayouts while dragging. */
    private fun render() {
        val paused = RecorderBus.state == RecorderBus.State.PAUSED
        val s = RecorderBus.elapsedMs / 1000
        val text = if (s >= 3600) "%d:%02d:%02d".format(s / 3600, (s / 60) % 60, s % 60) else "%02d:%02d".format(s / 60, s % 60)
        if (text != lastText) { timer.text = text; lastText = text }
        if (paused != lastPaused) {
            pauseBtn.setImageResource(if (paused) R.drawable.ic_play else R.drawable.ic_pause)
            lastPaused = paused
        }
        if (RecorderBus.micMuted != lastMuted) {
            lastMuted = RecorderBus.micMuted
            micBtn.setImageResource(if (RecorderBus.micMuted) R.drawable.ic_mic_off else R.drawable.ic_mic)
            highlight(micBtn, RecorderBus.micMuted, 0xFFFFA94D.toInt())
        }
        if (RecorderBus.facecamOn != lastCam) {
            lastCam = RecorderBus.facecamOn
            highlight(camBtn, RecorderBus.facecamOn, 0xFF2EE6A8.toInt())
        }
        if (RecorderBus.drawOn != lastDraw) {
            lastDraw = RecorderBus.drawOn
            highlight(penBtn, RecorderBus.drawOn, 0xFF4DABF7.toInt())
        }
        dot.alpha = if (paused) 0.35f else if ((System.currentTimeMillis() / 500) % 2 == 0L) 1f else 0.45f
    }
}
