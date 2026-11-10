package io.github.mohdaffankhan.reelmint

import android.annotation.SuppressLint
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Bundle
import android.util.Log
import java.io.File
import java.nio.ByteOrder
import kotlin.math.max
import kotlin.math.min

enum class AudioMode { NONE, MIC, INTERNAL, BOTH;
    val usesMic get() = this == MIC || this == BOTH
    val usesInternal get() = this == INTERNAL || this == BOTH

    companion object {
        fun parse(s: String?) = entries.firstOrNull { it.name.equals(s, true) } ?: NONE
    }
}

data class RecordConfig(
    val width: Int,
    val height: Int,
    val dpi: Int,
    val fps: Int,
    val videoBitrate: Int,
    val audioMode: AudioMode,
    val audioBitrate: Int,
    val output: File,
)

/**
 * Hardware screen encoder: VirtualDisplay -> H.264 surface encoder, AudioRecord (mic and/or
 * system playback capture, mixed) -> AAC, both muxed to MP4. Supports pause/resume with
 * gap-free timestamps.
 */
class ScreenEncoder(
    private val projection: MediaProjection,
    private val cfg: RecordConfig,
    private val onFatal: (Throwable) -> Unit,
) {
    companion object {
        private const val TAG = "ReelmintEncoder"
        private const val SAMPLE_RATE = 44_100
        private const val CHANNELS = 2
        private const val FRAMES_PER_CHUNK = 1024
    }

    private lateinit var videoCodec: MediaCodec
    private var audioCodec: MediaCodec? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var micRecord: AudioRecord? = null
    private var internalRecord: AudioRecord? = null
    private val muxer = MediaMuxer(cfg.output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

    private val lock = Object()
    private var videoTrack = -1
    private var audioTrack = -1
    private var muxerStarted = false
    private var baseUs = 0L
    private var pauseStartUs = 0L
    private var pauseOffsetUs = 0L
    private var lastVideoPts = -1L
    private var lastAudioPts = -1L
    private var samplesWritten = 0

    @Volatile private var running = false
    @Volatile var paused = false
        private set
    @Volatile var micMuted = false
    @Volatile private var needKeyframe = true

    private var videoThread: Thread? = null
    private var audioThread: Thread? = null

    private val hasAudio get() = cfg.audioMode != AudioMode.NONE

    fun start() {
        try {
            prepareVideo()
            if (hasAudio) prepareAudio()
        } catch (e: Exception) {
            releasePartial()
            throw e
        }
        running = true

        virtualDisplay = projection.createVirtualDisplay(
            "Reelmint", cfg.width, cfg.height, cfg.dpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            videoCodec.createInputSurface().also { videoSurface = it }, null, null,
        )
        videoCodec.start()
        audioCodec?.start()
        micRecord?.startRecording()
        internalRecord?.startRecording()

        videoThread = Thread({ guard { drainVideoLoop() } }, "reelmint-video").apply { start() }
        if (hasAudio) audioThread = Thread({ guard { audioLoop() } }, "reelmint-audio").apply { start() }
    }

    private var videoSurface: android.view.Surface? = null

    private fun prepareVideo() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, cfg.width, cfg.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, cfg.videoBitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, cfg.fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 1_000_000L / cfg.fps)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setFloat(MediaFormat.KEY_MAX_FPS_TO_ENCODER, cfg.fps.toFloat())
            }
        }
        videoCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        videoCodec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
    }

    @SuppressLint("MissingPermission") // RECORD_AUDIO is requested before recording starts.
    private fun prepareAudio() {
        val channelMask = AudioFormat.CHANNEL_IN_STEREO
        val pcm = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(channelMask)
            .build()
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, channelMask, AudioFormat.ENCODING_PCM_16BIT)
        val bufSize = max(minBuf, FRAMES_PER_CHUNK * CHANNELS * 2) * 4

        if (cfg.audioMode.usesInternal && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val capture = AudioPlaybackCaptureConfiguration.Builder(projection)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()
            internalRecord = AudioRecord.Builder()
                .setAudioFormat(pcm)
                .setBufferSizeInBytes(bufSize)
                .setAudioPlaybackCaptureConfig(capture)
                .build()
        }
        if (cfg.audioMode.usesMic || internalRecord == null) {
            micRecord = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.MIC)
                .setAudioFormat(pcm)
                .setBufferSizeInBytes(bufSize)
                .build()
        }

        listOfNotNull(internalRecord, micRecord).forEach {
            check(it.state == AudioRecord.STATE_INITIALIZED) { "Audio capture unavailable on this device" }
        }

        val aac = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, CHANNELS).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, cfg.audioBitrate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, FRAMES_PER_CHUNK * CHANNELS * 2 * 2)
        }
        audioCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
            configure(aac, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
    }

    /** Frees whatever was created before [start] failed. */
    private fun releasePartial() {
        listOfNotNull(micRecord, internalRecord).forEach { runCatching { it.release() } }
        audioCodec?.let { runCatching { it.release() } }
        if (::videoCodec.isInitialized) runCatching { videoCodec.release() }
        runCatching { muxer.release() }
        cfg.output.delete()
    }

    // ---------------------------------------------------------------- controls

    fun pause() = synchronized(lock) {
        if (paused) return
        paused = true
        pauseStartUs = nowUs()
    }

    fun resume() = synchronized(lock) {
        if (!paused) return
        pauseOffsetUs += nowUs() - pauseStartUs
        paused = false
        needKeyframe = true
        requestKeyframe()
    }

    /** Stops and finalises the file. Returns true if a playable file was written. */
    fun stop(): Boolean {
        if (!running) return false
        running = false
        try { videoCodec.signalEndOfInputStream() } catch (e: Exception) { Log.w(TAG, "EOS", e) }
        audioThread?.join(3000)
        videoThread?.join(3000)

        virtualDisplay?.release()
        videoSurface?.release()
        listOfNotNull(micRecord, internalRecord).forEach { r ->
            runCatching { r.stop() }; r.release()
        }
        runCatching { videoCodec.stop() }; videoCodec.release()
        audioCodec?.let { runCatching { it.stop() }; it.release() }

        val ok = synchronized(lock) {
            if (muxerStarted && samplesWritten > 0) runCatching { muxer.stop() }.isSuccess else false
        }
        runCatching { muxer.release() }
        if (!ok) cfg.output.delete()
        return ok
    }

    // ---------------------------------------------------------------- video

    private fun drainVideoLoop() {
        val info = MediaCodec.BufferInfo()
        var eosWaits = 0
        while (true) {
            val idx = videoCodec.dequeueOutputBuffer(info, 10_000)
            when {
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> synchronized(lock) {
                    videoTrack = muxer.addTrack(videoCodec.outputFormat)
                    maybeStartMuxer()
                }
                idx >= 0 -> {
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    val key = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                    if (!config && info.size > 0) {
                        val buf = videoCodec.getOutputBuffer(idx)!!
                        synchronized(lock) {
                            if (muxerStarted && !paused) {
                                if (needKeyframe && key) needKeyframe = false
                                if (!needKeyframe) {
                                    var pts = info.presentationTimeUs - baseUs - pauseOffsetUs
                                    if (pts < 0) pts = 0
                                    if (pts <= lastVideoPts) pts = lastVideoPts + 1
                                    lastVideoPts = pts
                                    info.presentationTimeUs = pts
                                    muxer.writeSampleData(videoTrack, buf, info)
                                    samplesWritten++
                                }
                            }
                        }
                    }
                    videoCodec.releaseOutputBuffer(idx, false)
                    if (eos) return
                }
                idx == MediaCodec.INFO_TRY_AGAIN_LATER && !running -> {
                    // EOS was signalled; give the encoder ~2s to flush, then bail out.
                    if (++eosWaits > 200) return
                }
            }
        }
    }

    private fun requestKeyframe() {
        runCatching {
            videoCodec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        }
    }

    // ---------------------------------------------------------------- audio

    private fun audioLoop() {
        val codec = audioCodec ?: return
        val samples = FRAMES_PER_CHUNK * CHANNELS
        val primary = ShortArray(samples)
        val secondary = ShortArray(samples)
        val chunkUs = FRAMES_PER_CHUNK * 1_000_000L / SAMPLE_RATE
        val info = MediaCodec.BufferInfo()
        val src = internalRecord ?: micRecord!!
        val mix = if (internalRecord != null) micRecord else null
        val primaryIsMic = src === micRecord

        while (running) {
            val n = src.read(primary, 0, samples)
            if (n <= 0) {
                if (n < 0) Thread.sleep(5) // driver error: back off instead of spinning
                continue
            }
            if (mix != null) {
                val m = mix.read(secondary, 0, n)
                if (!micMuted && m > 0) {
                    for (i in 0 until min(n, m)) {
                        primary[i] = (primary[i] + secondary[i]).coerceIn(-32768, 32767).toShort()
                    }
                }
            } else if (primaryIsMic && micMuted) {
                primary.fill(0, 0, n)
            }
            if (!paused) {
                val inIdx = codec.dequeueInputBuffer(10_000)
                if (inIdx >= 0) {
                    val buf = codec.getInputBuffer(inIdx)!!
                    buf.clear()
                    buf.order(ByteOrder.nativeOrder()).asShortBuffer().put(primary, 0, n)
                    codec.queueInputBuffer(inIdx, 0, n * 2, nowUs() - chunkUs, 0)
                }
            }
            drainAudio(codec, info, 0)
        }

        // End of stream
        val inIdx = codec.dequeueInputBuffer(50_000)
        if (inIdx >= 0) codec.queueInputBuffer(inIdx, 0, 0, nowUs(), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drainAudio(codec, info, 10_000, untilEos = true)
    }

    private fun drainAudio(codec: MediaCodec, info: MediaCodec.BufferInfo, timeoutUs: Long, untilEos: Boolean = false) {
        var tries = 0
        while (true) {
            val idx = codec.dequeueOutputBuffer(info, timeoutUs)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!untilEos || ++tries > 50) return
                }
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> synchronized(lock) {
                    audioTrack = muxer.addTrack(codec.outputFormat)
                    maybeStartMuxer()
                }
                idx >= 0 -> {
                    val eos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (!config && info.size > 0) {
                        val buf = codec.getOutputBuffer(idx)!!
                        synchronized(lock) {
                            if (muxerStarted) {
                                var pts = info.presentationTimeUs - baseUs - pauseOffsetUs
                                if (pts >= 0) {
                                    if (pts <= lastAudioPts) pts = lastAudioPts + 1
                                    lastAudioPts = pts
                                    info.presentationTimeUs = pts
                                    muxer.writeSampleData(audioTrack, buf, info)
                                    samplesWritten++
                                }
                            }
                        }
                    }
                    codec.releaseOutputBuffer(idx, false)
                    if (eos) return
                }
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    private fun maybeStartMuxer() {
        if (muxerStarted || videoTrack < 0 || (hasAudio && audioTrack < 0)) return
        muxer.start()
        baseUs = nowUs()
        muxerStarted = true
        needKeyframe = true
        requestKeyframe()
    }

    private fun nowUs() = System.nanoTime() / 1000

    private inline fun guard(block: () -> Unit) {
        try { block() } catch (t: Throwable) {
            Log.e(TAG, "encoder failure", t)
            if (running) onFatal(t)
        }
    }
}
