package io.github.mohdaffankhan.reelmint

import android.content.ContentValues
import android.os.StatFs
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.provider.MediaStore
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

object MediaTools {

    fun thumbnail(path: String, atMs: Long, maxWidth: Int): ByteArray? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            val w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: maxWidth
            val h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: maxWidth
            val scale = (maxWidth.toFloat() / w).coerceAtMost(1f)
            val bmp = r.getScaledFrameAtTime(
                atMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                (w * scale).toInt().coerceAtLeast(1), (h * scale).toInt().coerceAtLeast(1),
            ) ?: return null
            ByteArrayOutputStream().use { out ->
                bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                bmp.recycle()
                out.toByteArray()
            }
        } catch (_: Exception) {
            null
        } finally {
            runCatching { r.release() }
        }
    }

    fun info(path: String): Map<String, Any?> {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            fun key(k: Int) = r.extractMetadata(k)
            val rotation = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            var w = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) { val t = w; w = h; h = t }
            mapOf(
                "durationMs" to (key(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L),
                "width" to w,
                "height" to h,
                "bitrate" to (key(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0),
                "hasAudio" to (key(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"),
                "frameCount" to (key(MediaMetadataRetriever.METADATA_KEY_VIDEO_FRAME_COUNT)?.toIntOrNull() ?: 0),
            )
        } catch (_: Exception) {
            mapOf("durationMs" to 0L, "width" to 0, "height" to 0, "bitrate" to 0, "hasAudio" to false)
        } finally {
            runCatching { r.release() }
        }
    }

    /** Lossless trim (cuts start at the nearest preceding keyframe). */
    fun trim(src: String, dst: String, startMs: Long, endMs: Long) {
        val ex = MediaExtractor()
        val muxer = MediaMuxer(dst, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            ex.setDataSource(src)
            val trackMap = HashMap<Int, Int>()
            var maxSize = 1 shl 20
            var videoTrack = -1
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                ex.selectTrack(i)
                trackMap[i] = muxer.addTrack(f)
                if (mime.startsWith("video/")) videoTrack = i
                if (f.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) maxSize = maxOf(maxSize, f.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
            }
            require(trackMap.isNotEmpty()) { "No media tracks" }
            muxer.start()

            val startUs = startMs * 1000
            val endUs = endMs * 1000
            ex.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            // The cut point is the keyframe we landed on so audio stays aligned with video.
            var cutUs = -1L
            val buf = ByteBuffer.allocate(maxSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val track = ex.sampleTrackIndex
                if (track < 0) break
                val t = ex.sampleTime
                if (t > endUs) break
                if (cutUs < 0) {
                    if (videoTrack >= 0 && track != videoTrack) { ex.advance(); continue }
                    cutUs = t
                }
                if (t < cutUs) { ex.advance(); continue }
                val size = ex.readSampleData(buf, 0)
                if (size < 0) break
                val flags = if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                info.set(0, size, t - cutUs, flags)
                muxer.writeSampleData(trackMap[track]!!, buf, info)
                ex.advance()
            }
            muxer.stop()
        } catch (e: Exception) {
            File(dst).delete()
            throw e
        } finally {
            runCatching { muxer.release() }
            ex.release()
        }
    }

    /** URIs of Reelmint's gallery copies with the given display name. */
    fun galleryFind(ctx: Context, name: String): List<android.net.Uri> {
        val out = mutableListOf<android.net.Uri>()
        ctx.contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Video.Media._ID),
            "${MediaStore.Video.Media.DISPLAY_NAME}=? AND ${MediaStore.Video.Media.RELATIVE_PATH} LIKE ?",
            arrayOf(name, "Movies/Reelmint%"),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                out += android.content.ContentUris.withAppendedId(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, c.getLong(0))
            }
        }
        return out
    }

    // ---------------------------------------------------------------- lossless remux tools

    /**
     * Copies [src] to [dst] keeping only the selected track kinds, optionally adding
     * [rotateBy] degrees to the display rotation. No re-encoding: instant and lossless.
     */
    fun remux(src: String, dst: String, keepVideo: Boolean = true, keepAudio: Boolean = true, rotateBy: Int = 0) {
        val ex = MediaExtractor()
        val muxer = MediaMuxer(dst, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            ex.setDataSource(src)
            val map = HashMap<Int, Int>()
            var maxSize = 1 shl 20
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                val isVideo = mime.startsWith("video/"); val isAudio = mime.startsWith("audio/")
                if ((isVideo && keepVideo) || (isAudio && keepAudio)) {
                    ex.selectTrack(i)
                    map[i] = muxer.addTrack(f)
                    if (f.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) maxSize = maxOf(maxSize, f.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
            }
            require(map.isNotEmpty()) { if (keepAudio && !keepVideo) "This recording has no audio" else "No media tracks" }
            if (rotateBy != 0) {
                val r = MediaMetadataRetriever()
                val current = try { r.setDataSource(src); r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0 } finally { r.release() }
                muxer.setOrientationHint(((current + rotateBy) % 360 + 360) % 360)
            }
            muxer.start()
            val buf = ByteBuffer.allocate(maxSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val track = ex.sampleTrackIndex
                if (track < 0) break
                val size = ex.readSampleData(buf, 0)
                if (size < 0) break
                val flags = if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                info.set(0, size, ex.sampleTime, flags)
                muxer.writeSampleData(map[track]!!, buf, info)
                ex.advance()
            }
            muxer.stop()
        } catch (e: Exception) {
            File(dst).delete()
            throw e
        } finally {
            runCatching { muxer.release() }
            ex.release()
        }
    }

    /** Saves the frame at [atMs] at full resolution to Pictures/Reelmint. Returns the content URI. */
    fun saveFrame(ctx: Context, path: String, atMs: Long, name: String): String {
        val r = MediaMetadataRetriever()
        val bmp = try {
            r.setDataSource(path)
            r.getFrameAtTime(atMs * 1000, MediaMetadataRetriever.OPTION_CLOSEST) ?: error("Couldn't read that frame")
        } finally { runCatching { r.release() } }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Reelmint")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = ctx.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("Gallery insert failed")
        resolver.openOutputStream(uri)!!.use { bmp.compress(Bitmap.CompressFormat.JPEG, 95, it) }
        bmp.recycle()
        values.clear(); values.put(MediaStore.Images.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    /** Copies an audio file into Music/Reelmint. Returns the content URI. */
    fun saveAudioToMusic(ctx: Context, file: File): String {
        val resolver = ctx.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, file.name)
            put(MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
            put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/Reelmint")
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values) ?: error("Music insert failed")
        resolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
        values.clear(); values.put(MediaStore.Audio.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }

    /** Removes our own copies (images/audio/video) with [name] from shared storage. */
    fun deleteShared(ctx: Context, collection: android.net.Uri, name: String): Int =
        ctx.contentResolver.delete(collection, "${MediaStore.MediaColumns.DISPLAY_NAME}=?", arrayOf(name))

    fun storage(dir: File): Map<String, Long> {
        val st = StatFs(dir.absolutePath)
        return mapOf("free" to st.availableBytes, "total" to st.totalBytes)
    }

    fun formatBytes(b: Long): String = when {
        b >= 1L shl 30 -> "%.1f GB".format(b / (1L shl 30).toDouble())
        b >= 1L shl 20 -> "%.1f MB".format(b / (1L shl 20).toDouble())
        else -> "%d KB".format(b / 1024)
    }
}
