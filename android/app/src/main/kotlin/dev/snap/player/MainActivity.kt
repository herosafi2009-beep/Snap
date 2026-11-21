package dev.snap.player

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Extends AudioServiceActivity so background playback and the media
 * notification keep working. Adds a channel to delete music files through
 * MediaStore, which shows the system consent dialog on Android 10+.
 */
class MainActivity : AudioServiceActivity() {
    private var pendingDelete: MethodChannel.Result? = null
    private var pendingDeletePath: String? = null
    private var spatialAudio: SpatialAudio? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyBootColors()
        useHighestRefreshRate()
    }

    /**
     * Ask for the fastest display mode at the resolution the device is
     * already using. Phones with 90/120Hz panels often hand apps 60Hz unless
     * they ask, which is the difference between smooth and merely fine.
     */
    private fun useHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay
        val current = display?.mode ?: return
        val fastest = display.supportedModes
            ?.filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            ?.maxByOrNull { it.refreshRate }
            ?: return
        if (fastest.modeId == current.modeId) return
        window.attributes = window.attributes.apply { preferredDisplayModeId = fastest.modeId }
    }

    /**
     * Start-up colors follow the app theme / album art of the last session:
     * the window behind Flutter's first frame uses the exact saved color, and
     * on Android 13+ the system splash of the next launch uses the closest
     * precompiled splash theme.
     */
    private fun applyBootColors() {
        val prefs = getSharedPreferences(BOOT_PREFS, MODE_PRIVATE)
        if (!prefs.contains("bucket")) return
        val mode = prefs.getInt("mode", 0)
        val systemDark = (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val dark = mode == 2 || (mode == 0 && systemDark)
        window.setBackgroundDrawable(ColorDrawable(prefs.getInt(if (dark) "dark" else "light", 0)))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val index = prefs.getInt("bucket", 0) * 3 + mode
            BootThemes.styles.getOrNull(index)?.let { splashScreen.setSplashScreenTheme(it) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        spatialAudio = SpatialAudio(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snap/boot").setMethodCallHandler { call, result ->
            if (call.method != "update") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val light = (call.argument<Number>("light") ?: 0).toInt()
            val dark = (call.argument<Number>("dark") ?: 0).toInt()
            val bucket = call.argument<Int>("bucket") ?: 0
            val mode = call.argument<Int>("mode") ?: 0
            getSharedPreferences(BOOT_PREFS, MODE_PRIVATE).edit()
                .putInt("light", light)
                .putInt("dark", dark)
                .putInt("bucket", bucket)
                .putInt("mode", mode)
                .apply()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                BootThemes.styles.getOrNull(bucket * 3 + mode)?.let { splashScreen.setSplashScreenTheme(it) }
            }
            result.success(null)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "snap/files").setMethodCallHandler { call, result ->
            when (call.method) {
                "deleteMedia" -> {
                    val path = call.argument<String>("path")
                    if (path == null) result.error("args", "Missing path", null) else deleteMedia(path, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun deleteMedia(path: String, result: MethodChannel.Result) {
        if (pendingDelete != null) {
            result.error("busy", "Another delete is in progress", null)
            return
        }
        val uri = findMediaUri(path)
        if (uri == null) {
            // Not indexed by MediaStore; fall back to a plain file delete.
            result.success(if (File(path).delete()) "deleted" else "failed")
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val request = MediaStore.createDeleteRequest(contentResolver, listOf(uri))
                pendingDelete = result
                pendingDeletePath = path
                startIntentSenderForResult(request.intentSender, DELETE_REQUEST, null, 0, 0, 0)
            } else {
                val rows = contentResolver.delete(uri, null, null)
                if (rows > 0 || !File(path).exists()) {
                    result.success("deleted")
                } else {
                    result.success(if (File(path).delete()) "deleted" else "failed")
                }
            }
        } catch (e: RecoverableSecurityException) {
            // Android 10: ask the user for permission, then retry.
            pendingDelete = result
            pendingDeletePath = path
            startIntentSenderForResult(e.userAction.actionIntent.intentSender, RECOVER_REQUEST, null, 0, 0, 0)
        } catch (e: Exception) {
            pendingDelete = null
            pendingDeletePath = null
            result.success("failed")
        }
    }

    private fun findMediaUri(path: String): Uri? {
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        @Suppress("DEPRECATION")
        val projection = arrayOf(MediaStore.Audio.Media._ID)
        @Suppress("DEPRECATION")
        val selection = "${MediaStore.Audio.Media.DATA} = ?"
        return try {
            contentResolver.query(collection, projection, selection, arrayOf(path), null)?.use { cursor ->
                if (cursor.moveToFirst()) ContentUris.withAppendedId(collection, cursor.getLong(0)) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun onDestroy() {
        spatialAudio?.dispose()
        spatialAudio = null
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != DELETE_REQUEST && requestCode != RECOVER_REQUEST) return
        val result = pendingDelete ?: return
        val path = pendingDeletePath
        pendingDelete = null
        pendingDeletePath = null
        if (resultCode != Activity.RESULT_OK) {
            result.success("cancelled")
            return
        }
        if (requestCode == RECOVER_REQUEST && path != null) {
            deleteMedia(path, result)
            return
        }
        result.success("deleted")
    }

    companion object {
        private const val BOOT_PREFS = "snap_boot"
        private const val DELETE_REQUEST = 4101
        private const val RECOVER_REQUEST = 4102
    }
}
