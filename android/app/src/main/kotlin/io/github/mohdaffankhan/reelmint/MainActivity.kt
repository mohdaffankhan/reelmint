package io.github.mohdaffankhan.reelmint

import android.Manifest
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val REQ_CAPTURE = 7001
        private const val REQ_AUDIO = 7002
        private const val REQ_NOTIFY = 7003
        private const val REQ_CAMERA = 7004
    }

    private val io = Executors.newFixedThreadPool(3)
    private val main = Handler(Looper.getMainLooper())
    private var pendingStart: MethodChannel.Result? = null
    private var pendingOptions: HashMap<String, Any?> = hashMapOf()
    private var pendingMicResult: MethodChannel.Result? = null
    private var pendingCameraResult: MethodChannel.Result? = null
    private var eventSink: EventChannel.EventSink? = null
    private val busListener: (Map<String, Any?>) -> Unit = { eventSink?.success(it) }
    private var launchRecording: String? = null
    private var launchTab: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        RecorderBus.appContext = applicationContext
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        launchRecording = intent?.getStringExtra("openRecording")
        launchTab = intent?.getStringExtra("openTab")

        MethodChannel(messenger, "reelmint/recorder").setMethodCallHandler(::onCall)
        EventChannel(messenger, "reelmint/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                RecorderBus.addListener(busListener)
            }
            override fun onCancel(arguments: Any?) {
                RecorderBus.removeListener(busListener)
                eventSink = null
            }
        })
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        preferHighRefreshRate()
    }

    /**
     * Ask for the panel's fastest mode (e.g. 120 Hz) at the current resolution. Without this
     * vote many OEMs (Samsung especially) keep Flutter apps at 60 Hz, which feels sluggish.
     */
    private fun preferHighRefreshRate() {
        runCatching {
            @Suppress("DEPRECATION")
            val display = if (Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay
            display ?: return
            val current = display.mode
            val best = display.supportedModes
                .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
                .maxByOrNull { it.refreshRate } ?: return
            if (best.modeId != current.modeId || best.refreshRate > current.refreshRate) {
                window.attributes = window.attributes.also { it.preferredDisplayModeId = best.modeId }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra("openRecording")?.let { eventSink?.success(mapOf("type" to "open", "path" to it)) }
        intent.getStringExtra("openTab")?.let { eventSink?.success(mapOf("type" to "tab", "tab" to it)) }
    }

    override fun onDestroy() {
        RecorderBus.removeListener(busListener)
        io.shutdown()
        super.onDestroy()
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        fun str(k: String) = call.argument<String>(k)!!
        fun long(k: String, d: Long = 0) = (call.argument<Number>(k) ?: d).toLong()
        when (call.method) {
            "getCapabilities" -> result.success(
                mapOf(
                    "platform" to "android",
                    "sdk" to Build.VERSION.SDK_INT,
                    "internalAudio" to true,
                    "pause" to true,
                    "floatingControls" to true,
                    "maxFps" to maxRefreshRate(),
                    "quickTile" to (Build.VERSION.SDK_INT >= 33),
                    "hasCamera" to packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
                )
            )
            "getRecordingsDir" -> result.success(RecorderService.recordingsDir(this).absolutePath)
            "bubbleGeometry" -> result.success(FloatingControls.current?.geometry())
            "scan" -> {
                Storage.scan(this, *call.argument<List<String>>("paths")!!.toTypedArray())
                result.success(true)
            }
            "getState" -> result.success(RecorderBus.snapshot())
            "consumeLaunchRecording" -> { result.success(launchRecording); launchRecording = null }
            "consumeLaunchTab" -> { result.success(launchTab); launchTab = null }

            // ---- recording
            "start" -> {
                @Suppress("UNCHECKED_CAST")
                startFlow(call.arguments as? HashMap<String, Any?> ?: hashMapOf(), result)
            }
            "pause" -> command(RecorderService.ACTION_PAUSE, result)
            "resume" -> command(RecorderService.ACTION_RESUME, result)
            "stop" -> command(RecorderService.ACTION_STOP, result)
            "toggleMic" -> command(RecorderService.ACTION_TOGGLE_MIC, result)
            "toggleFacecam" -> command(RecorderService.ACTION_TOGGLE_FACECAM, result)
            "toggleDraw" -> command(RecorderService.ACTION_TOGGLE_DRAW, result)
            "getOverlays" -> result.success(RecorderBus.overlays())
            "moveToBackground" -> { moveTaskToBack(true); result.success(null) }

            // ---- permissions
            "micPermission" -> result.success(has(Manifest.permission.RECORD_AUDIO))
            "requestMicPermission" -> {
                if (has(Manifest.permission.RECORD_AUDIO)) result.success(true)
                else { pendingMicResult = result; requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO, *Storage.extraPermissions), REQ_AUDIO) }
            }
            "cameraPermission" -> result.success(has(Manifest.permission.CAMERA))
            "requestCameraPermission" -> {
                if (has(Manifest.permission.CAMERA)) result.success(true)
                else { pendingCameraResult = result; requestPermissions(arrayOf(Manifest.permission.CAMERA), REQ_CAMERA) }
            }
            "overlayPermission" -> result.success(Settings.canDrawOverlays(this))
            "requestOverlayPermission" -> {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                result.success(null)
            }
            "notificationPermission" -> result.success(notificationsAllowed())
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= 33 && !notificationsAllowed()) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFY)
                }
                result.success(null)
            }

            // ---- security & system
            "canAuthenticate" -> result.success(
                BiometricManager.from(this).canAuthenticate(authenticators()) == BiometricManager.BIOMETRIC_SUCCESS
            )
            "authenticate" -> authenticate(call.argument<String>("reason") ?: "Unlock Reelmint", result)
            "requestAddTile" -> requestAddTile(result)
            "storage" -> background(result) { MediaTools.storage(RecorderService.recordingsDir(this)) }

            // ---- media tools
            "thumbnail" -> background(result) {
                MediaTools.thumbnail(str("path"), long("atMs"), call.argument<Int>("maxWidth") ?: 360)
            }
            "info" -> background(result) { MediaTools.info(str("path")) }
            "trim" -> background(result) {
                val src = File(str("path"))
                val dst = derived(src, "trim")
                MediaTools.trim(src.absolutePath, dst.absolutePath, long("startMs"), long("endMs", Long.MAX_VALUE / 1000))
                dst.absolutePath.also { Storage.scan(this, it) }
            }
            "rotate" -> background(result) {
                val src = File(str("path")); val dst = derived(src, "rot")
                MediaTools.remux(src.absolutePath, dst.absolutePath, rotateBy = call.argument<Int>("degrees") ?: 90)
                dst.absolutePath.also { Storage.scan(this, it) }
            }
            "removeAudio" -> background(result) {
                val src = File(str("path")); val dst = derived(src, "silent")
                MediaTools.remux(src.absolutePath, dst.absolutePath, keepAudio = false)
                dst.absolutePath.also { Storage.scan(this, it) }
            }
            "extractAudio" -> background(result) {
                val src = File(str("path"))
                val out = File(File(cacheDir, "audio").apply { mkdirs() }, "${src.nameWithoutExtension}.m4a")
                MediaTools.remux(src.absolutePath, out.absolutePath, keepVideo = false)
                mapOf("path" to out.absolutePath, "uri" to MediaTools.saveAudioToMusic(this, out))
            }
            "saveFrame" -> background(result) {
                val src = File(str("path"))
                MediaTools.saveFrame(this, src.absolutePath, long("atMs"), "${src.nameWithoutExtension}_${long("atMs")}.jpg")
            }
            "transform" -> transform(call, result)
            "cancelJob" -> result.success(Editor.cancel(str("id")))
            "galleryHas" -> background(result) { MediaTools.galleryFind(this, str("name")).isNotEmpty() }
            "galleryDelete" -> background(result) {
                MediaTools.galleryFind(this, str("name")).sumOf { contentResolver.delete(it, null, null) }
            }
            "deleteShared" -> background(result) {
                val collection = when (str("kind")) {
                    "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                    else -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                }
                MediaTools.deleteShared(this, collection, str("name"))
            }
            else -> result.notImplemented()
        }
    }

    private fun command(action: String, result: MethodChannel.Result) {
        RecorderService.command(this, action)
        result.success(null)
    }

    /** "<name>_<suffix>.mp4", "<name>_<suffix>1.mp4", … next to [src]; strips earlier edit suffixes. */
    private fun derived(src: File, suffix: String): File {
        val base = src.nameWithoutExtension.replace(Regex("_(trim|rot|silent|merged|export|\\d+p|[\\d.]+x)\\d*$"), "")
        var n = 0
        while (true) {
            val f = File(src.parentFile, "${base}_$suffix${if (n == 0) "" else n.toString()}.mp4")
            if (!f.exists()) return f
            n++
        }
    }

    /**
     * A compress must never grow the file: when the source already uses less than the
     * requested bitrate (static screens encode tiny), aim for the source's own rate
     * scaled by the pixel reduction instead.
     */
    private fun cappedBitrate(paths: List<String>, shortSide: Int, requested: Int): Int {
        if (requested <= 0 || paths.size != 1) return requested
        val info = MediaTools.info(paths.first())
        val srcRate = (info["bitrate"] as? Int) ?: 0
        val w = (info["width"] as? Int) ?: 0
        val h = (info["height"] as? Int) ?: 0
        if (srcRate <= 0 || w <= 0 || h <= 0) return requested
        val srcShort = minOf(w, h).toDouble()
        val scale = if (shortSide in 1 until srcShort.toInt()) (shortSide / srcShort).let { it * it } else 1.0
        val audio = if (info["hasAudio"] == true) 192_000 else 0
        val target = ((srcRate - audio).coerceAtLeast(srcRate / 2) * scale * 0.85).toInt()
        return minOf(requested, maxOf(target, 200_000))
    }

    private fun transform(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths")!!
        val id = call.argument<String>("id") ?: "job"
        val shortSide = call.argument<Int>("shortSide") ?: 0
        val speed = (call.argument<Number>("speed") ?: 1.0).toFloat()
        val suffix = when {
            paths.size > 1 -> "merged"
            speed != 1f -> "${speed.toString().removeSuffix(".0")}x"
            shortSide > 0 -> "${shortSide}p"
            else -> "export"
        }
        val out = derived(File(paths.first()), suffix)
        try {
            Editor.run(
                this,
                Editor.Job(
                    id = id,
                    inputs = paths,
                    output = out.absolutePath,
                    shortSide = shortSide,
                    bitrate = cappedBitrate(paths, shortSide, call.argument<Int>("bitrate") ?: 0),
                    speed = speed,
                    removeAudio = call.argument<Boolean>("removeAudio") ?: false,
                ),
            ) { r ->
                main.post {
                    // Compress must never hand back a bigger file. Near-static screen recordings are
                    // already tiny, and Android's encoder quality floor can push a re-encode above them.
                    val src = File(paths.first())
                    if (r.isSuccess && suffix == "${shortSide}p" && out.length() >= src.length()) {
                        out.delete()
                        result.error("compact", "Already as compact as it gets — kept the original", null)
                        return@post
                    }
                    r.fold(
                        { Storage.scan(this, it); result.success(it) },
                        { result.error("failed", it.message ?: "Export failed", null) },
                    )
                }
            }
        } catch (e: Exception) {
            result.error("failed", e.message ?: "Export failed", null)
        }
    }

    // ------------------------------------------------------------------ biometrics

    private fun authenticators() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BIOMETRIC_WEAK or DEVICE_CREDENTIAL else BIOMETRIC_WEAK

    private fun authenticate(reason: String, result: MethodChannel.Result) {
        var replied = false
        fun reply(ok: Boolean) { if (!replied) { replied = true; result.success(ok) } }
        val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) = reply(true)
            override fun onAuthenticationError(code: Int, msg: CharSequence) = reply(false)
        })
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Reelmint is locked")
            .setSubtitle(reason)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setAllowedAuthenticators(authenticators())
                else setNegativeButtonText("Cancel")
            }
            .build()
        prompt.authenticate(info)
    }

    private fun requestAddTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33) { result.success(-1); return }
        val sbm = getSystemService(StatusBarManager::class.java)
        sbm.requestAddTileService(
            ComponentName(this, RecordTileService::class.java),
            "Reelmint record",
            Icon.createWithResource(this, R.drawable.ic_stat_record),
            ContextCompat.getMainExecutor(this),
        ) { code -> result.success(code) }
    }

    // ------------------------------------------------------------------ start flow

    private fun startFlow(options: HashMap<String, Any?>, result: MethodChannel.Result) {
        if (RecorderBus.state != RecorderBus.State.IDLE) {
            result.error("busy", "A recording is already in progress", null); return
        }
        if (pendingStart != null) { result.error("busy", "Already waiting for permission", null); return }
        pendingStart = result
        pendingOptions = options
        if (Build.VERSION.SDK_INT >= 33 && !notificationsAllowed()) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFY)
            return
        }
        afterNotificationPermission()
    }

    private fun afterNotificationPermission() {
        val audio = AudioMode.parse(pendingOptions["audio"] as? String)
        if (audio != AudioMode.NONE && !has(Manifest.permission.RECORD_AUDIO)) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO, *Storage.extraPermissions), REQ_AUDIO)
            return
        }
        requestCapture()
    }

    private fun requestCapture() {
        val mpm = getSystemService(MediaProjectionManager::class.java)
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CAPTURE) return
        val result = pendingStart ?: return
        pendingStart = null
        if (resultCode != RESULT_OK || data == null) {
            result.success(false); return
        }
        ContextCompat.startForegroundService(
            this,
            Intent(this, RecorderService::class.java)
                .setAction(RecorderService.ACTION_START)
                .putExtra(RecorderService.EXTRA_RESULT_CODE, resultCode)
                .putExtra(RecorderService.EXTRA_RESULT_DATA, data)
                .putExtra(RecorderService.EXTRA_OPTIONS, pendingOptions),
        )
        result.success(true)
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        @Suppress("DEPRECATION")
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        when (requestCode) {
            REQ_NOTIFY -> if (pendingStart != null) afterNotificationPermission()
            REQ_CAMERA -> { pendingCameraResult?.success(granted); pendingCameraResult = null }
            REQ_AUDIO -> {
                pendingMicResult?.let { it.success(granted); pendingMicResult = null }
                if (pendingStart != null) {
                    if (!granted) {
                        pendingOptions["audio"] = "none"
                        eventSink?.success(mapOf("type" to "warning", "message" to "Microphone access denied — recording without audio."))
                    }
                    requestCapture()
                }
            }
        }
    }

    // ------------------------------------------------------------------ helpers

    private fun has(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun notificationsAllowed() = Build.VERSION.SDK_INT < 33 || has(Manifest.permission.POST_NOTIFICATIONS)

    private fun maxRefreshRate(): Int {
        val d = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else null
        @Suppress("DEPRECATION")
        val modes = (d ?: windowManager.defaultDisplay).supportedModes
        return (modes.maxOfOrNull { it.refreshRate } ?: 60f).toInt()
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val v = work()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }
}
