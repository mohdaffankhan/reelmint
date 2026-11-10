package io.github.mohdaffankhan.reelmint

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.File

/** Handles the "Delete" action on the saved-recording notification. */
class NotificationActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_DELETE = "app.reelmint.DELETE_RECORDING"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_DELETE) return
        val path = intent.getStringExtra("path") ?: return
        val f = File(path)
        // Only ever delete inside our own recordings folder.
        if (Storage.owns(context, f) && f.delete()) Storage.scan(context, f.absolutePath)
        context.getSystemService(NotificationManager::class.java).cancel(RecorderService.NOTIF_DONE)
        RecorderBus.emit(mapOf("type" to "deleted", "path" to path))
    }
}
