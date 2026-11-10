package io.github.mohdaffankhan.reelmint

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile: one tap to start (with the user's settings) or stop recording. */
class RecordTileService : TileService() {

    companion object {
        fun refresh(ctx: Context) {
            runCatching { requestListeningState(ctx, ComponentName(ctx, RecordTileService::class.java)) }
        }
    }

    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    override fun onClick() {
        super.onClick()
        if (RecorderBus.state == RecorderBus.State.IDLE) {
            val intent = Intent(this, CaptureActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
                )
            } else {
                @Suppress("DEPRECATION") startActivityAndCollapse(intent)
            }
        } else {
            RecorderService.command(this, RecorderService.ACTION_STOP)
        }
    }

    private fun render() {
        val tile = qsTile ?: return
        val active = RecorderBus.state != RecorderBus.State.IDLE
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (active) "Stop" else "Record"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when (RecorderBus.state) {
                RecorderBus.State.RECORDING -> "Recording"
                RecorderBus.State.PAUSED -> "Paused"
                RecorderBus.State.COUNTDOWN -> "Starting…"
                else -> "Reelmint"
            }
        }
        tile.updateTile()
    }
}
