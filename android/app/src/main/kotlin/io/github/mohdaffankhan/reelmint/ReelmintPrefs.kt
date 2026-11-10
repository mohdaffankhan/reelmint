package io.github.mohdaffankhan.reelmint

import android.content.Context

/**
 * Reads the user's settings straight from Flutter's shared_preferences store, so
 * recordings started outside the app (Quick Settings tile, launcher shortcut)
 * use exactly the same options as the in-app record button.
 *
 * Keys and defaults must match lib/services/settings.dart.
 */
object ReelmintPrefs {
    private fun sp(ctx: Context) = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun options(ctx: Context): HashMap<String, Any?> {
        val all = sp(ctx).all
        fun int(k: String, d: Int) = (all["flutter.$k"] as? Number)?.toInt() ?: d
        fun bool(k: String, d: Boolean) = all["flutter.$k"] as? Boolean ?: d
        fun str(k: String, d: String) = all["flutter.$k"] as? String ?: d
        return hashMapOf(
            "resolution" to int("resolution", 1080),
            "fps" to int("fps", 60),
            "bitrate" to int("bitrateMbps", 0) * 1_000_000,
            "audio" to str("audio", "internal"),
            "audioBitrate" to int("audioKbps", 192) * 1000,
            "orientation" to str("orientation", "auto"),
            "countdown" to int("countdown", 3),
            "floatingControls" to bool("floatingControls", false),
            "stopOnScreenOff" to bool("stopOnScreenOff", true),
            "facecam" to bool("facecam", false),
            "facecamSize" to str("facecamSize", "m"),
            "timeLimitSec" to int("timeLimitMin", 0) * 60,
            "shakeToStop" to bool("shakeToStop", false),
        )
    }
}
