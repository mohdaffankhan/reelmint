package io.github.mohdaffankhan.reelmint

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * Process-wide recording state. The foreground service writes to it, the Flutter
 * event channel and the floating controls observe it.
 */
object RecorderBus {
    enum class State { IDLE, COUNTDOWN, RECORDING, PAUSED, STOPPING }

    @Volatile var state: State = State.IDLE
        private set
    @Volatile var countdown: Int = 0
        private set

    private var startedAt = 0L          // elapsedRealtime when recording started
    private var pausedAt = 0L           // elapsedRealtime when the current pause began
    private var pausedTotal = 0L        // accumulated paused time

    private val main = Handler(Looper.getMainLooper())

    /** Set by the service/activity so state changes can refresh the Quick Settings tile. */
    @Volatile var appContext: Context? = null

    // Live overlay state (shown in app + floating controls).
    @Volatile var micMuted = false
    @Volatile var facecamOn = false
    @Volatile var drawOn = false

    fun overlays(): Map<String, Any?> =
        mapOf("type" to "overlays", "micMuted" to micMuted, "facecam" to facecamOn, "draw" to drawOn)

    fun emitOverlays() = emit(overlays())
    private val listeners = mutableSetOf<(Map<String, Any?>) -> Unit>()

    fun addListener(l: (Map<String, Any?>) -> Unit) {
        main.post { listeners.add(l); l(snapshot()) }
    }

    fun removeListener(l: (Map<String, Any?>) -> Unit) {
        main.post { listeners.remove(l) }
    }

    val elapsedMs: Long
        get() = when (state) {
            State.RECORDING -> SystemClock.elapsedRealtime() - startedAt - pausedTotal
            State.PAUSED, State.STOPPING -> pausedAt.takeIf { it > 0 }?.let { it - startedAt - pausedTotal }
                ?: (SystemClock.elapsedRealtime() - startedAt - pausedTotal)
            else -> 0L
        }.coerceAtLeast(0)

    fun snapshot(extra: Map<String, Any?> = emptyMap()): Map<String, Any?> = mapOf(
        "type" to "state",
        "state" to state.name.lowercase(),
        "elapsedMs" to elapsedMs,
        "countdown" to countdown,
        "micMuted" to micMuted,
        "facecam" to facecamOn,
        "draw" to drawOn,
    ) + extra

    fun setCountdown(value: Int) {
        state = State.COUNTDOWN
        countdown = value
        emit(snapshot())
    }

    fun recordingStarted() {
        startedAt = SystemClock.elapsedRealtime()
        pausedAt = 0; pausedTotal = 0; countdown = 0
        state = State.RECORDING
        emit(snapshot())
    }

    fun paused() {
        if (state != State.RECORDING) return
        pausedAt = SystemClock.elapsedRealtime()
        state = State.PAUSED
        emit(snapshot())
    }

    fun resumed() {
        if (state != State.PAUSED) return
        pausedTotal += SystemClock.elapsedRealtime() - pausedAt
        pausedAt = 0
        state = State.RECORDING
        emit(snapshot())
    }

    fun stopping() {
        if (state == State.RECORDING) pausedAt = SystemClock.elapsedRealtime()
        state = State.STOPPING
        emit(snapshot())
    }

    fun idle() {
        state = State.IDLE
        countdown = 0
        micMuted = false; facecamOn = false; drawOn = false
        emit(snapshot())
    }

    fun emitSaved(path: String, durationMs: Long) =
        emit(mapOf("type" to "saved", "path" to path, "durationMs" to durationMs))

    fun emitError(message: String) = emit(mapOf("type" to "error", "message" to message))

    fun emit(event: Map<String, Any?>) {
        main.post {
            listeners.toList().forEach { it(event) }
            if (event["type"] == "state") appContext?.let { RecordTileService.refresh(it) }
        }
    }
}
