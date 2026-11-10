package io.github.mohdaffankhan.reelmint

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.C
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

/**
 * Re-encoding edits powered by Media3 Transformer: compress / resize,
 * playback-speed change, and merging several clips into one.
 * Jobs report progress through [RecorderBus] ("progress" events).
 */
object Editor {
    private val main = Handler(Looper.getMainLooper())
    private class Running(val transformer: Transformer, val output: String, val done: (Result<String>) -> Unit)
    private val running = mutableMapOf<String, Running>()

    data class Job(
        val id: String,
        val inputs: List<String>,
        val output: String,
        val shortSide: Int = 0,      // 0 = keep
        val bitrate: Int = 0,        // 0 = encoder default
        val speed: Float = 1f,
        val removeAudio: Boolean = false,
    )

    private class ConstantSpeed(private val speed: Float) : SpeedProvider {
        override fun getSpeed(timeUs: Long) = speed
        override fun getNextSpeedChangeTimeUs(timeUs: Long) = C.TIME_UNSET
    }

    /** Must be called on the main thread. [done] receives the output path or an error. */
    fun run(ctx: Context, job: Job, done: (Result<String>) -> Unit) {
        File(job.output).parentFile?.mkdirs()
        // For merges, normalise every clip to the first clip's size so mixed orientations letterbox cleanly.
        val first = MediaTools.info(job.inputs.first())
        val baseW = (first["width"] as? Int) ?: 0
        val baseH = (first["height"] as? Int) ?: 0

        val items = job.inputs.map { path ->
            val videoEffects = buildList {
                when {
                    job.shortSide > 0 -> add(Presentation.createForShortSide(job.shortSide))
                    job.inputs.size > 1 && baseW > 0 ->
                        add(Presentation.createForWidthAndHeight(baseW, baseH, Presentation.LAYOUT_SCALE_TO_FIT))
                }
            }
            EditedMediaItem.Builder(MediaItem.fromUri(File(path).toURI().toString()))
                .setRemoveAudio(job.removeAudio)
                .setEffects(Effects(emptyList(), videoEffects))
                .apply { if (job.speed != 1f) setSpeed(ConstantSpeed(job.speed)) }
                .build()
        }
        val sequence = EditedMediaItemSequence.Builder(items)
            .apply { if (!job.removeAudio && job.inputs.size > 1) experimentalSetForceAudioTrack(true) }
            .build()
        val composition = Composition.Builder(sequence).build()

        val encoders = DefaultEncoderFactory.Builder(ctx.applicationContext)
            .apply {
                if (job.bitrate > 0) {
                    setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(job.bitrate).build())
                }
            }
            .setEnableFallback(true)
            .build()

        lateinit var transformer: Transformer
        val progress = ProgressHolder()
        val poll = object : Runnable {
            override fun run() {
                if (!running.containsKey(job.id)) return
                if (transformer.getProgress(progress) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    RecorderBus.emit(mapOf("type" to "progress", "job" to job.id, "progress" to progress.progress))
                }
                main.postDelayed(this, 200)
            }
        }
        transformer = Transformer.Builder(ctx.applicationContext)
            .setEncoderFactory(encoders)
            .setVideoMimeType("video/avc")
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (running.remove(job.id) == null) return // cancelled meanwhile
                    RecorderBus.emit(mapOf("type" to "progress", "job" to job.id, "progress" to 100))
                    done(Result.success(job.output))
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    if (running.remove(job.id) == null) return
                    File(job.output).delete()
                    done(Result.failure(exportException))
                }
            })
            .build()
        running[job.id] = Running(transformer, job.output, done)
        transformer.start(composition, job.output)
        main.post(poll)
    }

    fun cancel(id: String): Boolean {
        val r = running.remove(id) ?: return false
        r.transformer.cancel()
        File(r.output).delete() // never leave a broken partial video in the Gallery
        r.done(Result.failure(java.util.concurrent.CancellationException("Export cancelled")))
        return true
    }
}
