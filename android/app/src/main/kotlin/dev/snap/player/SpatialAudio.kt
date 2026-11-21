package dev.snap.player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.Spatializer
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Reports what the device and the current output actually do with spatial
 * audio. Nothing here processes audio: Android decides whether to spatialize,
 * this only asks it what it is doing so the app can say so honestly.
 */
class SpatialAudio(context: Context, messenger: BinaryMessenger) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S_V2
    private val spatializer: Spatializer? = if (supported) audio.spatializer else null

    private var events: EventChannel.EventSink? = null
    private var stateListener: Spatializer.OnSpatializerStateChangedListener? = null
    private var headTrackingListener: Spatializer.OnHeadTrackerAvailableListener? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status())
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "$CHANNEL/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    events = sink
                    listen()
                    sink?.success(status())
                }

                override fun onCancel(arguments: Any?) {
                    stopListening()
                    events = null
                }
            },
        )
    }

    private fun status(): Map<String, Any> {
        val spatializer = this.spatializer
        if (!supported || spatializer == null) {
            return mapOf(
                "platformSupported" to false,
                "available" to false,
                "enabled" to false,
                "headTracking" to false,
                "multichannel" to false,
            )
        }
        return mapOf(
            // The platform can spatialize at all (Android 12L and up).
            "platformSupported" to true,
            // The device knows how to spatialize for the current output.
            "available" to spatializer.isAvailable,
            // The user or the system has it switched on for this output.
            "enabled" to spatializer.isEnabled,
            "headTracking" to spatializer.isHeadTrackerAvailable,
            // Whether multichannel content (5.1, Atmos in E-AC-3 JOC) would
            // actually be spatialized rather than folded down.
            "multichannel" to canSpatializeMultichannel(spatializer),
            "immersiveLevel" to spatializer.immersiveAudioLevel,
        )
    }

    /** Asks whether a typical 5.1 music stream would be spatialized as it is. */
    private fun canSpatializeMultichannel(spatializer: Spatializer): Boolean {
        return try {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val format = AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(48000)
                .setChannelMask(AudioFormat.CHANNEL_OUT_5POINT1)
                .build()
            spatializer.canBeSpatialized(attributes, format)
        } catch (_: Exception) {
            false
        }
    }

    private fun listen() {
        val spatializer = this.spatializer ?: return
        if (stateListener != null) return
        val executor = { runnable: Runnable -> runnable.run() }
        val state = object : Spatializer.OnSpatializerStateChangedListener {
            override fun onSpatializerEnabledChanged(spatializer: Spatializer, enabled: Boolean) = emit()
            override fun onSpatializerAvailableChanged(spatializer: Spatializer, available: Boolean) = emit()
        }
        val head = Spatializer.OnHeadTrackerAvailableListener { _, _ -> emit() }
        spatializer.addOnSpatializerStateChangedListener(executor, state)
        spatializer.addOnHeadTrackerAvailableListener(executor, head)
        stateListener = state
        headTrackingListener = head
    }

    private fun stopListening() {
        val spatializer = this.spatializer ?: return
        stateListener?.let { spatializer.removeOnSpatializerStateChangedListener(it) }
        headTrackingListener?.let { spatializer.removeOnHeadTrackerAvailableListener(it) }
        stateListener = null
        headTrackingListener = null
    }

    private fun emit() {
        events?.success(status())
    }

    fun dispose() {
        stopListening()
        events = null
    }

    companion object {
        const val CHANNEL = "snap/spatial"
    }
}
