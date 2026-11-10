package io.github.mohdaffankhan.reelmint

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.MediaCodecList
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

class RecorderService : Service() {

    companion object {
        const val ACTION_START = "app.reelmint.START"
        const val ACTION_PAUSE = "app.reelmint.PAUSE"
        const val ACTION_RESUME = "app.reelmint.RESUME"
        const val ACTION_STOP = "app.reelmint.STOP"
        const val ACTION_TOGGLE_MIC = "app.reelmint.TOGGLE_MIC"
        const val ACTION_TOGGLE_FACECAM = "app.reelmint.TOGGLE_FACECAM"
        const val ACTION_TOGGLE_DRAW = "app.reelmint.TOGGLE_DRAW"

        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_OPTIONS = "options"

        private const val CHANNEL_REC = "reelmint_recording"
        const val CHANNEL_DONE = "reelmint_saved"
        private const val NOTIF_REC = 41
        const val NOTIF_DONE = 42
        private const val TAG = "ReelmintService"

        fun recordingsDir(ctx: Context): File = Storage.dir(ctx)

        fun command(ctx: Context, action: String) {
            ctx.startService(Intent(ctx, RecorderService::class.java).setAction(action))
        }

        fun fileUri(ctx: Context, file: File) = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
    }

    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var encoder: ScreenEncoder? = null
    private var options: HashMap<String, Any?> = hashMapOf()
    private var floating: FloatingControls? = null
    private var facecam: FacecamOverlay? = null
    private var draw: DrawOverlay? = null
    private var screenOffReceiver: BroadcastReceiver? = null
    private var shake: SensorEventListener? = null
    private var outputFile: File? = null
    private var usesMic = false
    private var cameraAllowed = false
    private var stopReason: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        RecorderBus.appContext = applicationContext
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> handleStart(intent)
            ACTION_PAUSE -> pause()
            ACTION_RESUME -> resume()
            ACTION_STOP -> stopRecording()
            ACTION_TOGGLE_MIC -> toggleMic()
            ACTION_TOGGLE_FACECAM -> toggleFacecam()
            ACTION_TOGGLE_DRAW -> toggleDraw()
        }
        return START_NOT_STICKY
    }

    private fun granted(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED
    private val canOverlay get() = Settings.canDrawOverlays(this)

    // ------------------------------------------------------------------ start

    @Suppress("UNCHECKED_CAST", "DEPRECATION")
    private fun handleStart(intent: Intent) {
        if (RecorderBus.state != RecorderBus.State.IDLE) return
        createChannels()
        options = (intent.getSerializableExtra(EXTRA_OPTIONS) as? HashMap<String, Any?>) ?: ReelmintPrefs.options(this)
        val audioMode = AudioMode.parse(options["audio"] as? String)
        usesMic = audioMode != AudioMode.NONE && granted(Manifest.permission.RECORD_AUDIO)
        cameraAllowed = granted(Manifest.permission.CAMERA)

        // Must be in the foreground with the mediaProjection type before obtaining the projection.
        // Camera/mic types are declared up front so facecam can be toggled on mid-recording.
        var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        if (usesMic) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        if (cameraAllowed) type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        try {
            startForeground(NOTIF_REC, buildRecordingNotification(), type)
        } catch (e: Exception) {
            fail("Could not start the recording service: ${e.message}")
            return
        }

        val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
        val data: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else intent.getParcelableExtra(EXTRA_RESULT_DATA)
        val mpm = getSystemService(MediaProjectionManager::class.java)
        val proj = data?.let { runCatching { mpm.getMediaProjection(resultCode, it) }.getOrNull() }
        if (proj == null) {
            fail("Screen capture permission was not granted")
            return
        }
        projection = proj
        proj.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                main.post { if (RecorderBus.state != RecorderBus.State.IDLE) stopRecording() }
            }
        }, main)

        runCountdown((options["countdown"] as? Number)?.toInt() ?: 3)
    }

    private fun runCountdown(seconds: Int) {
        if (seconds <= 0) { begin(); return }
        RecorderBus.setCountdown(seconds)
        updateNotification()
        main.postDelayed({
            if (RecorderBus.state == RecorderBus.State.COUNTDOWN) runCountdown(seconds - 1)
        }, 1000)
    }

    private fun begin() {
        val proj = projection ?: return
        val audioMode = if (usesMic) AudioMode.parse(options["audio"] as? String) else AudioMode.NONE
        val (w, h, dpi) = computeSize()
        val fps = ((options["fps"] as? Number)?.toInt() ?: 60).coerceIn(15, 120)
        val requestedBitrate = (options["bitrate"] as? Number)?.toInt() ?: 0
        val bitrate = if (requestedBitrate > 0) requestedBitrate else
            (w.toLong() * h * fps * 0.11).toInt().coerceIn(2_000_000, 40_000_000)
        val audioBitrate = (options["audioBitrate"] as? Number)?.toInt() ?: 192_000

        val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val file = File(recordingsDir(this), "Reelmint_$stamp.mp4")
        outputFile = file
        stopReason = null

        val onFatal: (Throwable) -> Unit = { t ->
            main.post {
                RecorderBus.emitError("Recording failed: ${t.message ?: t.javaClass.simpleName}")
                stopRecording()
            }
        }
        val cfg = RecordConfig(w, h, dpi, fps, bitrate, audioMode, audioBitrate, file)
        try {
            encoder = try {
                ScreenEncoder(proj, cfg, onFatal).also { it.start() }
            } catch (e: Exception) {
                if (audioMode == AudioMode.NONE) throw e
                // Audio capture can fail (e.g. another app holds the mic) — keep recording video.
                Log.w(TAG, "audio unavailable, retrying video-only", e)
                usesMic = false
                RecorderBus.emit(mapOf("type" to "warning", "message" to "Audio unavailable — recording video only."))
                ScreenEncoder(proj, cfg.copy(audioMode = AudioMode.NONE), onFatal).also { it.start() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "start failed", e)
            encoder = null
            fail("This device's encoder rejected ${w}x$h @ ${fps}fps. Try a lower quality. (${e.message})")
            return
        }

        RecorderBus.recordingStarted()
        updateNotification()
        if (options["floatingControls"] == true && canOverlay) {
            floating = FloatingControls(this, usesMic && audioMode.usesMic).also { it.show() }
        }
        if (options["facecam"] == true) setFacecam(true)
        if (options["stopOnScreenOff"] == true) registerScreenOff()
        if (options["shakeToStop"] == true) registerShake()
        val limit = (options["timeLimitSec"] as? Number)?.toLong() ?: 0L
        if (limit > 0) watchTimeLimit(limit * 1000)
    }

    /** Returns (width, height, dpi) — even, encoder-supported, scaled to the requested short side. */
    private fun computeSize(): Triple<Int, Int, Int> {
        val wm = getSystemService(WindowManager::class.java)
        val b = wm.maximumWindowMetrics.bounds
        val dpi = resources.displayMetrics.densityDpi
        var w = b.width(); var h = b.height()
        when (options["orientation"] as? String) {
            "portrait" -> if (w > h) { val t = w; w = h; h = t }
            "landscape" -> if (h > w) { val t = w; w = h; h = t }
        }
        val target = (options["resolution"] as? Number)?.toInt() ?: 0
        val short = min(w, h)
        if (target in 1 until short) {
            val scale = target.toDouble() / short
            w = (w * scale).roundToInt(); h = (h * scale).roundToInt()
        }
        return fitEncoder(w, h).let { Triple(it.first, it.second, dpi) }
    }

    private fun fitEncoder(width: Int, height: Int): Pair<Int, Int> {
        var w = width and 1.inv(); var h = height and 1.inv()
        val caps = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .firstOrNull { it.isEncoder && it.supportedTypes.any { t -> t.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) } }
            ?.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)?.videoCapabilities
            ?: return w to h
        var guard = 0
        while (!caps.isSizeSupported(w, h) && guard++ < 20) {
            val maxW = caps.supportedWidths.upper; val maxH = caps.supportedHeights.upper
            val scale = min(min(maxW.toDouble() / w, maxH.toDouble() / h), 0.95).coerceAtMost(1.0)
            w = max(((w * scale).toInt() / 16) * 16, 16)
            h = max(((h * scale).toInt() / 16) * 16, 16)
        }
        return w to h
    }

    // ------------------------------------------------------------------ controls

    private fun pause() {
        if (RecorderBus.state != RecorderBus.State.RECORDING) return
        encoder?.pause()
        RecorderBus.paused()
        updateNotification()
    }

    private fun resume() {
        if (RecorderBus.state != RecorderBus.State.PAUSED) return
        encoder?.resume()
        RecorderBus.resumed()
        updateNotification()
    }

    private fun toggleMic() {
        val enc = encoder ?: return
        enc.micMuted = !enc.micMuted
        RecorderBus.micMuted = enc.micMuted
        RecorderBus.emit(mapOf("type" to "mic", "muted" to enc.micMuted))
        RecorderBus.emitOverlays()
        updateNotification()
    }

    private fun toggleFacecam() = setFacecam(!RecorderBus.facecamOn)

    private fun setFacecam(on: Boolean) {
        if (encoder == null) return
        if (on) {
            when {
                !cameraAllowed -> { RecorderBus.emitError("Allow camera access to use the facecam."); return }
                !canOverlay -> { RecorderBus.emitError("Allow “Display over other apps” to use the facecam."); return }
            }
            facecam = (facecam ?: FacecamOverlay(this, options["facecamSize"] as? String ?: "m")).also { it.show() }
        } else {
            facecam?.hide()
        }
        RecorderBus.facecamOn = facecam?.isShown == true
        RecorderBus.emitOverlays()
    }

    private fun toggleDraw() {
        if (encoder == null) return
        if (RecorderBus.drawOn) {
            draw?.hide()
        } else {
            if (!canOverlay) { RecorderBus.emitError("Allow “Display over other apps” to draw on screen."); return }
            draw = DrawOverlay(this) { RecorderBus.drawOn = false; RecorderBus.emitOverlays() }.also { it.show() }
        }
        RecorderBus.drawOn = draw?.isShown == true
        RecorderBus.emitOverlays()
    }

    private fun watchTimeLimit(limitMs: Long) {
        val check = object : Runnable {
            override fun run() {
                if (RecorderBus.state != RecorderBus.State.RECORDING && RecorderBus.state != RecorderBus.State.PAUSED) return
                if (RecorderBus.elapsedMs >= limitMs) {
                    stopReason = "Time limit reached — recording stopped."
                    stopRecording()
                } else main.postDelayed(this, 250)
            }
        }
        main.postDelayed(check, 250)
    }

    private fun stopRecording() {
        when (RecorderBus.state) {
            RecorderBus.State.IDLE, RecorderBus.State.STOPPING -> return
            RecorderBus.State.COUNTDOWN -> { cleanup(); RecorderBus.idle(); return }
            else -> Unit
        }
        val duration = RecorderBus.elapsedMs
        RecorderBus.stopping()
        removeOverlays()
        unregisterScreenOff()
        unregisterShake()
        val enc = encoder
        encoder = null
        val reason = stopReason
        Thread {
            val ok = enc?.stop() ?: false
            val file = outputFile
            main.post {
                if (ok && file != null && file.exists()) {
                    Storage.scan(this, file.absolutePath)
                    reason?.let { RecorderBus.emit(mapOf("type" to "warning", "message" to it)) }
                    RecorderBus.emitSaved(file.absolutePath, duration)
                    postSavedNotification(file, duration)
                } else {
                    RecorderBus.emitError("The recording was too short or could not be saved.")
                }
                cleanup()
                RecorderBus.idle()
            }
        }.start()
    }

    private fun removeOverlays() {
        floating?.hide(); floating = null
        facecam?.hide(); facecam = null
        draw?.hide(); draw = null
    }

    private fun fail(message: String) {
        RecorderBus.emitError(message)
        cleanup()
        RecorderBus.idle()
    }

    private fun cleanup() {
        main.removeCallbacksAndMessages(null)
        removeOverlays()
        unregisterScreenOff()
        unregisterShake()
        runCatching { projection?.stop() }
        projection = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (RecorderBus.state == RecorderBus.State.RECORDING || RecorderBus.state == RecorderBus.State.PAUSED) {
            removeOverlays()
            encoder?.stop()
            RecorderBus.idle()
        }
        super.onDestroy()
    }

    // ------------------------------------------------------------------ screen off / shake

    private fun registerScreenOff() {
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) {
                stopReason = "Screen locked — recording stopped."
                stopRecording()
            }
        }
        ContextCompat.registerReceiver(this, r, IntentFilter(Intent.ACTION_SCREEN_OFF), ContextCompat.RECEIVER_NOT_EXPORTED)
        screenOffReceiver = r
    }

    private fun unregisterScreenOff() {
        screenOffReceiver?.let { runCatching { unregisterReceiver(it) } }
        screenOffReceiver = null
    }

    private fun registerShake() {
        val sm = getSystemService(SensorManager::class.java)
        val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        var lastPeak = 0L
        var peaks = 0
        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val g = sqrt(e.values[0] * e.values[0] + e.values[1] * e.values[1] + e.values[2] * e.values[2]) /
                    SensorManager.GRAVITY_EARTH
                if (g < 2.5f) return
                val now = SystemClock.elapsedRealtime()
                if (now - lastPeak < 120) return // same jolt
                peaks = if (now - lastPeak < 700) peaks + 1 else 1
                lastPeak = now
                if (peaks >= 2) {
                    stopReason = "Shake detected — recording stopped."
                    main.post { stopRecording() }
                }
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        sm.registerListener(l, accel, SensorManager.SENSOR_DELAY_GAME)
        shake = l
    }

    private fun unregisterShake() {
        shake?.let { getSystemService(SensorManager::class.java).unregisterListener(it) }
        shake = null
    }

    // ------------------------------------------------------------------ notifications

    private fun createChannels() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_REC, "Recording controls", NotificationManager.IMPORTANCE_LOW).apply {
                setShowBadge(false)
                description = "Shown while Reelmint is recording your screen"
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_DONE, "Saved recordings", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Tells you when a recording has been saved"
            }
        )
    }

    private fun servicePending(action: String, code: Int): PendingIntent =
        PendingIntent.getService(
            this, code, Intent(this, RecorderService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun openAppPending(path: String? = null): PendingIntent =
        PendingIntent.getActivity(
            this, if (path == null) 0 else 1,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                path?.let { putExtra("openRecording", it) }
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    private fun buildRecordingNotification(): Notification {
        val b = NotificationCompat.Builder(this, CHANNEL_REC)
            .setSmallIcon(R.drawable.ic_stat_record)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setColor(0xFFFF4D6D.toInt())
            .setContentIntent(openAppPending())
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        when (RecorderBus.state) {
            RecorderBus.State.COUNTDOWN -> b.setContentTitle("Starting in ${RecorderBus.countdown}…")
                .setContentText("Get ready")
                .addAction(0, "Cancel", servicePending(ACTION_STOP, 3))
            RecorderBus.State.PAUSED -> b.setContentTitle("Recording paused")
                .setContentText(formatDuration(RecorderBus.elapsedMs))
                .addAction(0, "Resume", servicePending(ACTION_RESUME, 2))
                .addAction(0, "Stop", servicePending(ACTION_STOP, 3))
            RecorderBus.State.RECORDING -> {
                b.setContentTitle("Recording screen")
                    .setUsesChronometer(true)
                    .setShowWhen(true)
                    .setWhen(System.currentTimeMillis() - RecorderBus.elapsedMs)
                    .addAction(0, "Pause", servicePending(ACTION_PAUSE, 1))
                    .addAction(0, "Stop", servicePending(ACTION_STOP, 3))
                if (usesMic && AudioMode.parse(options["audio"] as? String).usesMic) {
                    b.addAction(0, if (RecorderBus.micMuted) "Unmute" else "Mute", servicePending(ACTION_TOGGLE_MIC, 4))
                }
            }
            else -> b.setContentTitle("Preparing recorder…")
        }
        return b.build()
    }

    private fun updateNotification() {
        getSystemService(NotificationManager::class.java).notify(NOTIF_REC, buildRecordingNotification())
    }

    /** "Recording saved" with a preview frame and Share / Delete actions. */
    private fun postSavedNotification(file: File, durationMs: Long) {
        val thumb = MediaTools.thumbnail(file.absolutePath, durationMs / 2, 720)
            ?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        val uri = fileUri(this, file)
        val share = Intent.createChooser(
            Intent(Intent.ACTION_SEND).setType("video/mp4").putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            "Share recording",
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val sharePi = PendingIntent.getActivity(this, 5, share, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val deletePi = PendingIntent.getBroadcast(
            this, 6,
            Intent(this, NotificationActionReceiver::class.java)
                .setAction(NotificationActionReceiver.ACTION_DELETE)
                .putExtra("path", file.absolutePath),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = NotificationCompat.Builder(this, CHANNEL_DONE)
            .setSmallIcon(R.drawable.ic_stat_record)
            .setColor(0xFF7C5CFF.toInt())
            .setContentTitle("Recording saved")
            .setContentText("${formatDuration(durationMs)} · ${MediaTools.formatBytes(file.length())} · tap to watch")
            .setAutoCancel(true)
            .setContentIntent(openAppPending(file.absolutePath))
            .addAction(R.drawable.ic_share, "Share", sharePi)
            .addAction(R.drawable.ic_delete, "Delete", deletePi)
        if (thumb != null) {
            b.setLargeIcon(thumb)
            b.setStyle(NotificationCompat.BigPictureStyle().bigPicture(thumb).bigLargeIcon(null as android.graphics.Bitmap?))
        }
        runCatching { getSystemService(NotificationManager::class.java).notify(NOTIF_DONE, b.build()) }
    }

    private fun formatDuration(ms: Long): String {
        val s = ms / 1000
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, (s / 60) % 60, s % 60)
        else "%02d:%02d".format(s / 60, s % 60)
    }
}
