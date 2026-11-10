package io.github.mohdaffankhan.reelmint

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import java.io.File

/**
 * Where recordings live: the public **Movies/Reelmint** folder, so they show up in Gallery,
 * Google Photos and every file manager. Files are written through the normal file API
 * (allowed for media in Movies/ on Android 11+, and on Android 10 via legacy storage with
 * WRITE_EXTERNAL_STORAGE). If that isn't possible we fall back to the app's own folder.
 */
object Storage {
    val publicDir: File
        get() = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "Reelmint")

    fun privateDir(ctx: Context): File =
        File(ctx.getExternalFilesDir(Environment.DIRECTORY_MOVIES) ?: ctx.filesDir, "recordings")

    /** Permissions to request alongside others (only Android 10 needs one). */
    val extraPermissions: Array<String>
        get() = if (Build.VERSION.SDK_INT == 29) arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE) else emptyArray()

    private fun canUsePublic(ctx: Context): Boolean = when {
        Build.VERSION.SDK_INT >= 30 -> true
        else -> Environment.isExternalStorageLegacy() &&
            ctx.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }

    fun dir(ctx: Context): File {
        if (canUsePublic(ctx)) {
            val d = publicDir
            if ((d.isDirectory || d.mkdirs()) && d.canWrite()) return d
        }
        return privateDir(ctx).apply { mkdirs() }
    }

    /** True when [f] is one of our recordings (public or fallback folder). */
    fun owns(ctx: Context, f: File): Boolean {
        val parent = f.parentFile?.canonicalPath ?: return false
        return parent == publicDir.canonicalPath || parent == privateDir(ctx).canonicalPath
    }

    /** Tell the media index a file appeared, changed or was deleted, so Gallery stays in sync. */
    fun scan(ctx: Context, vararg paths: String) {
        if (paths.isEmpty()) return
        MediaScannerConnection.scanFile(ctx.applicationContext, paths, null, null)
    }
}
