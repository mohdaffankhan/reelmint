package io.github.mohdaffankhan.reelmint

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.core.content.ContextCompat

/**
 * Invisible activity that starts a recording from outside the app (Quick Settings
 * tile, launcher shortcut): asks for mic access if needed, shows the system capture
 * prompt, then hands off to [RecorderService] with the user's saved settings.
 */
class CaptureActivity : Activity() {
    companion object {
        private const val REQ_CAPTURE = 8101
        private const val REQ_AUDIO = 8102
    }

    private lateinit var options: HashMap<String, Any?>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (RecorderBus.state != RecorderBus.State.IDLE) {
            RecorderService.command(this, RecorderService.ACTION_STOP)
            finish(); return
        }
        options = ReelmintPrefs.options(this)
        val needsMic = AudioMode.parse(options["audio"] as? String) != AudioMode.NONE
        if (needsMic && !granted(Manifest.permission.RECORD_AUDIO)) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO, *Storage.extraPermissions), REQ_AUDIO)
        } else {
            requestCapture()
        }
    }

    private fun granted(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    private fun requestCapture() {
        val mpm = getSystemService(MediaProjectionManager::class.java)
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CAPTURE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_AUDIO) {
            if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED) options["audio"] = "none"
            requestCapture()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_CAPTURE && resultCode == RESULT_OK && data != null) {
            ContextCompat.startForegroundService(
                this,
                Intent(this, RecorderService::class.java)
                    .setAction(RecorderService.ACTION_START)
                    .putExtra(RecorderService.EXTRA_RESULT_CODE, resultCode)
                    .putExtra(RecorderService.EXTRA_RESULT_DATA, data)
                    .putExtra(RecorderService.EXTRA_OPTIONS, options),
            )
        }
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
