package com.freebeat.freebeat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.EnvironmentalReverb
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    companion object {
        private const val REQUEST_CODE_PICK_DIRECTORY = 4201
        private const val REQUEST_CODE_PICK_AUDIO_FILES = 4202
    }

    private val channelName = "com.freebeat.app/dsp"
    private var currentSessionId: Int = 0
    private var pendingDirectoryResult: MethodChannel.Result? = null
    private var pendingFilesResult: MethodChannel.Result? = null
    private var batteryReceiver: BroadcastReceiver? = null
    private var powerSaverMethodChannel: MethodChannel? = null

    // Tier 1: Android 9+ (API 28+) Studio-Grade 10-Band DynamicsProcessing
    private var dynamicsProcessing: DynamicsProcessing? = null

    // Tier 2: Universal OEM / Legacy Fallback & Spatial Effects (API 24+)
    private var legacyEqualizer: Equalizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var presetReverb: PresetReverb? = null
    private var environmentalReverb: EnvironmentalReverb? = null
    private var currentReverbEffectId: Int = 0
    private var currentReverbSendLevel: Float = 0f

    private var dspEngineMode: String = "DynamicsProcessing 64-bit Hardware"
    private var isBluetoothOutputActive: Boolean = false

    private val isoBandFrequencies = floatArrayOf(
        31f, 62f, 125f, 250f, 500f, 1000f, 2000f, 4000f, 8000f, 16000f
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableAdaptiveDisplayRefreshRate()
        requestNotificationPermissionIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        enableAdaptiveDisplayRefreshRate()
    }

    override fun onPause() {
        super.onPause()
        clearDisplayRefreshRateOverrides()
    }

    override fun onStop() {
        super.onStop()
        clearDisplayRefreshRateOverrides()
    }

    private fun enableAdaptiveDisplayRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val params = window?.attributes ?: return
                // preferredDisplayModeId = 0 allows Android and LTPO displays to dynamically switch modes
                params.preferredDisplayModeId = 0
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // preferredRefreshRate = 0f allows the system adaptive governor to scale between 1Hz and 120Hz
                    params.preferredRefreshRate = 0f
                }
                window.attributes = params
            } catch (_: Throwable) {
                // Ignore if device OEM restricts custom display mode
            }
        }
    }

    private fun clearDisplayRefreshRateOverrides() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val params = window?.attributes ?: return
                params.preferredDisplayModeId = 0
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    params.preferredRefreshRate = 0f
                }
                window.attributes = params
            } catch (_: Throwable) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.registerAudioDeviceCallback(object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
                updateRouteTelemetry(audioManager)
            }

            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
                updateRouteTelemetry(audioManager)
            }
        }, null)

        val dspChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        powerSaverMethodChannel = dspChannel

        val batteryFilter = IntentFilter().apply {
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                try {
                    dspChannel.invokeMethod("onBatteryStateChanged", getBatteryStatusMap())
                } catch (_: Throwable) {}
            }
        }
        try {
            registerReceiver(batteryReceiver, batteryFilter)
        } catch (_: Throwable) {}

        dspChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "attachSession" -> {
                        val sessionId = call.argument<Int>("audioSessionId") ?: 0
                        attachAudioSession(sessionId)
                        result.success(mapOf("engineMode" to dspEngineMode))
                    }
                    "updateDsp" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            applyDspParameters(args)
                        }
                        result.success(true)
                    }
                    "getAudioRouteInfo" -> {
                        result.success(updateRouteTelemetry(audioManager))
                    }
                    "triggerPixelHaptic" -> {
                        val type = call.argument<String>("type") ?: "tick"
                        val intensity = (call.argument<Double>("intensity") ?: 0.5).toFloat()
                        triggerPixelLraHaptic(type, intensity)
                        result.success(true)
                    }
                    "isAppInstalled" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val isInstalled = try {
                            packageManager.getPackageInfo(packageName, 0)
                            true
                        } catch (e: Exception) {
                            false
                        }
                        result.success(isInstalled)
                    }
                    "launchApp" -> {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            launchIntent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "getDisplayRefreshRate" -> {
                        val rate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            display?.refreshRate ?: 60f
                        } else {
                            @Suppress("DEPRECATION")
                            windowManager.defaultDisplay?.refreshRate ?: 60f
                        }
                        result.success(rate.toDouble())
                    }
                    "setPreferredRefreshRate" -> {
                        val rate = (call.argument<Number>("rate") ?: 60.0).toFloat()
                        setPreferredDisplayRefreshRate(rate)
                        result.success(true)
                    }
                    "getBatteryStatus" -> {
                        result.success(getBatteryStatusMap())
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
                        } else {
                            true
                        }
                        result.success(isIgnoring)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        val success = requestIgnoreBatteryOptimizations()
                        result.success(success)
                    }
                    "setHighRefreshRate" -> {
                        enableAdaptiveDisplayRefreshRate()
                        result.success(true)
                    }
                    "getAppSha1Fingerprint" -> {
                        val sha1 = try {
                            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES)
                            } else {
                                @Suppress("DEPRECATION")
                                packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNATURES)
                            }
                            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                packageInfo.signingInfo?.apkContentsSigners
                            } else {
                                @Suppress("DEPRECATION")
                                packageInfo.signatures
                            }
                            val cert = signatures?.firstOrNull()?.toByteArray()
                            if (cert != null) {
                                val md = java.security.MessageDigest.getInstance("SHA-1")
                                val digest = md.digest(cert)
                                digest.joinToString(":") { "%02X".format(it) }
                            } else {
                                "UNKNOWN"
                            }
                        } catch (e: Exception) {
                            "ERROR: ${e.message}"
                        }
                        result.success(sha1)
                    }
                    "startForegroundPlayback" -> {
                        try {
                            requestNotificationPermissionIfNeeded()
                            val title = call.argument<String>("title") ?: "FreeBeat"
                            val artist = call.argument<String>("artist") ?: "Unknown Artist"
                            val album = call.argument<String>("album") ?: "Library"
                            val artworkPath = call.argument<String>("artworkPath")
                            val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                            val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
                            val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                            val volume = (call.argument<Number>("volume") ?: 0.8).toFloat()
                            val dominantColor = (call.argument<Number>("dominantColor") ?: 0xFF1E293B).toInt()
                            val outputDevice = call.argument<String>("outputDevice") ?: "Phone Speaker"
                            val isShuffle = call.argument<Boolean>("isShuffle") ?: false
                            val repeatMode = (call.argument<Number>("repeatMode") ?: 0).toInt()
                            val isPowerSaver = call.argument<Boolean>("isPowerSaver") ?: false
                            val isCurrentTrackLocal = call.argument<Boolean>("isCurrentTrackLocal") ?: false

                            val serviceIntent = android.content.Intent(this, FreeBeatPlaybackService::class.java).apply {
                                action = FreeBeatPlaybackService.ACTION_UPDATE
                                putExtra("title", title)
                                putExtra("artist", artist)
                                putExtra("album", album)
                                putExtra("artworkPath", artworkPath)
                                putExtra("durationMs", durationMs)
                                putExtra("positionMs", positionMs)
                                putExtra("isPlaying", isPlaying)
                                putExtra("volume", volume)
                                putExtra("dominantColor", dominantColor)
                                putExtra("outputDevice", outputDevice)
                                putExtra("isShuffle", isShuffle)
                                putExtra("repeatMode", repeatMode)
                                putExtra("isPowerSaver", isPowerSaver)
                                putExtra("isCurrentTrackLocal", isCurrentTrackLocal)
                            }
                            if (FreeBeatPlaybackService.isServiceRunning) {
                                startService(serviceIntent)
                            } else {
                                androidx.core.content.ContextCompat.startForegroundService(this, serviceIntent)
                            }
                            result.success(true)
                        } catch (e: Throwable) {
                            android.util.Log.e("MainActivity", "Failed startForegroundPlayback: ${e.message}", e)
                            result.success(false)
                        }
                    }
                    "updatePlaybackNotification" -> {
                        try {
                            val serviceIntent = android.content.Intent(this, FreeBeatPlaybackService::class.java).apply {
                                action = FreeBeatPlaybackService.ACTION_UPDATE
                                call.argument<Number>("positionMs")?.let { putExtra("positionMs", it.toLong()) }
                                call.argument<Number>("durationMs")?.let { putExtra("durationMs", it.toLong()) }
                                call.argument<Boolean>("isPlaying")?.let { putExtra("isPlaying", it) }
                                call.argument<Number>("volume")?.let { putExtra("volume", it.toFloat()) }
                                call.argument<Number>("dominantColor")?.let { putExtra("dominantColor", it.toInt()) }
                                call.argument<String>("title")?.let { putExtra("title", it) }
                                call.argument<String>("artist")?.let { putExtra("artist", it) }
                                call.argument<String>("album")?.let { putExtra("album", it) }
                                call.argument<String>("artworkPath")?.let { putExtra("artworkPath", it) }
                                call.argument<String>("outputDevice")?.let { putExtra("outputDevice", it) }
                                call.argument<Boolean>("isShuffle")?.let { putExtra("isShuffle", it) }
                                call.argument<Number>("repeatMode")?.let { putExtra("repeatMode", it.toInt()) }
                                call.argument<Boolean>("isPowerSaver")?.let { putExtra("isPowerSaver", it) }
                                call.argument<Boolean>("isCurrentTrackLocal")?.let { putExtra("isCurrentTrackLocal", it) }
                            }
                            if (FreeBeatPlaybackService.isServiceRunning) {
                                startService(serviceIntent)
                            } else {
                                androidx.core.content.ContextCompat.startForegroundService(this, serviceIntent)
                            }
                            result.success(true)
                        } catch (e: Throwable) {
                            android.util.Log.e("MainActivity", "Failed updatePlaybackNotification: ${e.message}", e)
                            result.success(false)
                        }
                    }
                    "stopForegroundPlayback" -> {
                        val serviceIntent = android.content.Intent(this, FreeBeatPlaybackService::class.java).apply {
                            action = FreeBeatPlaybackService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    }
                    "takePersistableUriPermission" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString != null && uriString.startsWith("content://")) {
                            try {
                                val uri = android.net.Uri.parse(uriString)
                                val alreadyPersisted = contentResolver.persistedUriPermissions.any {
                                    it.uri == uri && it.isReadPermission
                                }
                                if (alreadyPersisted) {
                                    result.success(true)
                                } else {
                                    contentResolver.takePersistableUriPermission(
                                        uri,
                                        android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                                    )
                                    result.success(true)
                                }
                            } catch (_: Throwable) {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "copyContentUriToFile" -> {
                        val uriString = call.argument<String>("uri")
                        val destPath = call.argument<String>("destPath")
                        if (uriString != null && destPath != null) {
                            try {
                                val uri = android.net.Uri.parse(uriString)
                                val destFile = File(destPath)
                                destFile.parentFile?.mkdirs()
                                val inStream = contentResolver.openInputStream(uri)
                                if (inStream != null) {
                                    inStream.use { input ->
                                        FileOutputStream(destFile).use { output ->
                                            input.copyTo(output)
                                        }
                                    }
                                    result.success(true)
                                } else {
                                    result.success(false)
                                }
                            } catch (e: Throwable) {
                                android.util.Log.e("MainActivity", "Failed to copy content URI: ${e.message}")
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "requestNotificationPermission" -> {
                        requestNotificationPermissionIfNeeded()
                        result.success(true)
                    }
                    "isWifiConnected" -> {
                        val cm = getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
                        val activeNetwork = cm?.activeNetwork
                        val caps = cm?.getNetworkCapabilities(activeNetwork)
                        val isWifi = caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) ?: true
                        result.success(isWifi)
                    }
                    "transcodeAudioIfNeeded" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val lower = path.lowercase()
                        val needsTranscode = lower.endsWith(".wma") || lower.endsWith(".asf") || lower.endsWith(".aiff") || lower.endsWith(".aif")
                        if (!needsTranscode) {
                            result.success(path)
                            return@setMethodCallHandler
                        }
                        val cacheFile = File(cacheDir, "transcoded_${path.hashCode().toUInt().toString(16)}.wav")
                        if (cacheFile.exists() && cacheFile.length() > 44) {
                            result.success(cacheFile.absolutePath)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val decoded = transcodeWmaToWav(path, cacheFile)
                            runOnUiThread {
                                result.success(decoded)
                            }
                        }.start()
                    }
                    "pickDirectory" -> {
                        if (pendingDirectoryResult != null) {
                            result.error("ALREADY_ACTIVE", "A folder picker is already active", null)
                            return@setMethodCallHandler
                        }
                        pendingDirectoryResult = result
                        try {
                            val intent = android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(
                                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    android.content.Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                                )
                            }
                            startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
                        } catch (e: Throwable) {
                            pendingDirectoryResult = null
                            result.error("PICK_DIR_ERROR", e.message, null)
                        }
                    }
                    "pickAudioFiles" -> {
                        if (pendingFilesResult != null) {
                            result.error("ALREADY_ACTIVE", "A file picker is already active", null)
                            return@setMethodCallHandler
                        }
                        pendingFilesResult = result
                        try {
                            val intent = android.content.Intent(android.content.Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(android.content.Intent.CATEGORY_OPENABLE)
                                type = "audio/*"
                                putExtra(android.content.Intent.EXTRA_ALLOW_MULTIPLE, true)
                                putExtra(
                                    android.content.Intent.EXTRA_MIME_TYPES,
                                    arrayOf(
                                        "audio/*",
                                        "application/ogg",
                                        "application/x-flac",
                                        "application/octet-stream"
                                    )
                                )
                                addFlags(
                                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    android.content.Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    android.content.Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                                )
                            }
                            startActivityForResult(intent, REQUEST_CODE_PICK_AUDIO_FILES)
                        } catch (e: Throwable) {
                            pendingFilesResult = null
                            result.error("PICK_FILES_ERROR", e.message, null)
                        }
                    }
                    "getAppCacheSize" -> {
                        Thread {
                            var totalBytes = 0L
                            try {
                                totalBytes += getDirSize(cacheDir)
                                externalCacheDir?.let { totalBytes += getDirSize(it) }
                                codeCacheDir?.let { totalBytes += getDirSize(it) }
                            } catch (_: Throwable) {}
                            runOnUiThread {
                                result.success(totalBytes)
                            }
                        }.start()
                    }
                    "clearAppCache" -> {
                        Thread {
                            var reclaimedBytes = 0L
                            try {
                                reclaimedBytes += clearDir(cacheDir)
                                externalCacheDir?.let { reclaimedBytes += clearDir(it) }
                            } catch (_: Throwable) {}
                            runOnUiThread {
                                result.success(reclaimedBytes)
                            }
                        }.start()
                    }
                    "readContentUriHeaderBytes" -> {
                        val uriString = call.argument<String>("uri")
                        val maxBytes = call.argument<Int>("maxBytes") ?: 131072
                        if (uriString != null) {
                            Thread {
                                try {
                                    val uri = android.net.Uri.parse(uriString)
                                    val inStream = contentResolver.openInputStream(uri)
                                    if (inStream != null) {
                                        inStream.use { input ->
                                            val buffer = ByteArray(maxBytes)
                                            var totalRead = 0
                                            while (totalRead < maxBytes) {
                                                val count = input.read(buffer, totalRead, maxBytes - totalRead)
                                                if (count <= 0) break
                                                totalRead += count
                                            }
                                            val out = if (totalRead == maxBytes) buffer else buffer.copyOf(totalRead)
                                            runOnUiThread { result.success(out) }
                                        }
                                    } else {
                                        runOnUiThread { result.success(null) }
                                    }
                                } catch (_: Throwable) {
                                    runOnUiThread { result.success(null) }
                                }
                            }.start()
                        } else {
                            result.success(null)
                        }
                    }
                    "extractAudioMetadata" -> {
                        val uriOrPath = call.argument<String>("uri") ?: call.argument<String>("path")
                        if (uriOrPath.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            val retriever = MediaMetadataRetriever()
                            try {
                                if (uriOrPath.startsWith("content://")) {
                                    val uri = android.net.Uri.parse(uriOrPath)
                                    retriever.setDataSource(this, uri)
                                } else {
                                    retriever.setDataSource(uriOrPath)
                                }
                                val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                                val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
                                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_AUTHOR)
                                    ?: retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_COMPOSER)
                                val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                                val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                                val durationMs = durationStr?.toLongOrNull() ?: 0L
                                val bitrateStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                                val bitrateKbps = (bitrateStr?.toIntOrNull() ?: 0) / 1000
                                val pictureBytes = retriever.embeddedPicture // Clean raw JPEG/PNG bytes!

                                val map = mutableMapOf<String, Any?>(
                                    "title" to title,
                                    "artist" to artist,
                                    "album" to album,
                                    "durationMs" to durationMs,
                                    "bitrateKbps" to bitrateKbps,
                                    "pictureBytes" to pictureBytes
                                )
                                runOnUiThread { result.success(map) }
                            } catch (_: Throwable) {
                                runOnUiThread { result.success(null) }
                            } finally {
                                try { retriever.release() } catch (_: Throwable) {}
                            }
                        }.start()
                    }
                    "scanDirectory" -> {
                        val pathOrUri = call.argument<String>("uri") ?: call.argument<String>("path")
                        if (pathOrUri.isNullOrEmpty()) {
                            result.success(emptyList<Map<String, Any>>())
                            return@setMethodCallHandler
                        }
                        Thread {
                            val items = scanPathOrUri(pathOrUri)
                            runOnUiThread {
                                result.success(items)
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        FreeBeatPlaybackService.playerActionListener = { action, extras ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    val engine = flutterEngine
                    if (engine != null) {
                        MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
                            .invokeMethod("onNotificationAction", mapOf("action" to action, "extras" to extras))
                    }
                } catch (e: Throwable) {
                    android.util.Log.w("MainActivity", "Failed to dispatch onNotificationAction: ${e.message}")
                }
            }
        }

        val autoPlay = intent?.getBooleanExtra("auto_play", false) ?: false
        val initialAction = intent?.getStringExtra("action")
        if (autoPlay || !initialAction.isNullOrEmpty()) {
            intent?.removeExtra("auto_play")
            intent?.removeExtra("action")
            window.decorView.postDelayed({
                val actionToDispatch = if (!initialAction.isNullOrEmpty()) initialAction else "onPlayPause"
                FreeBeatPlaybackService.playerActionListener?.invoke(actionToDispatch, mapOf("isPlaying" to true))
            }, 1200)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val autoPlay = intent.getBooleanExtra("auto_play", false)
        val action = intent.getStringExtra("action")
        if (autoPlay || !action.isNullOrEmpty()) {
            intent.removeExtra("auto_play")
            intent.removeExtra("action")
            val actionToDispatch = if (!action.isNullOrEmpty()) action else "onPlayPause"
            FreeBeatPlaybackService.playerActionListener?.invoke(actionToDispatch, mapOf("isPlaying" to true))
        }
    }

    private fun applyReverbAuxEffectToExoPlayer(effectId: Int, sendLevel: Float) {
        try {
            val engine = flutterEngine ?: return
            val pluginClass = Class.forName("com.ryanheise.just_audio.JustAudioPlugin")
            @Suppress("UNCHECKED_CAST")
            val plugin = engine.plugins.get(pluginClass as Class<out io.flutter.embedding.engine.plugins.FlutterPlugin>) ?: return
            val handlerField = plugin.javaClass.getDeclaredField("methodCallHandler").apply { isAccessible = true }
            val handler = handlerField.get(plugin) ?: return
            val playersField = handler.javaClass.getDeclaredField("players").apply { isAccessible = true }
            val playersMap = playersField.get(handler) as? Map<*, *> ?: return

            val auxClass = try {
                Class.forName("androidx.media3.common.AuxEffectInfo")
            } catch (_: Throwable) {
                try {
                    Class.forName("com.google.android.exoplayer2.audio.AuxEffectInfo")
                } catch (_: Throwable) {
                    null
                }
            }

            for (audioPlayer in playersMap.values) {
                if (audioPlayer == null) continue
                try {
                    val playerField = audioPlayer.javaClass.getDeclaredField("player").apply { isAccessible = true }
                    val exoPlayer = playerField.get(audioPlayer) ?: continue

                    if (effectId > 0 && sendLevel > 0.001f && auxClass != null) {
                        val auxConstructor = auxClass.getConstructor(Int::class.javaPrimitiveType, Float::class.javaPrimitiveType)
                        val auxInstance = auxConstructor.newInstance(effectId, sendLevel.coerceIn(0f, 1f))
                        val setAuxMethod = exoPlayer.javaClass.getMethod("setAuxEffectInfo", auxClass)
                        setAuxMethod.invoke(exoPlayer, auxInstance)
                    } else {
                        val clearAuxMethod = exoPlayer.javaClass.getMethod("clearAuxEffectInfo")
                        clearAuxMethod.invoke(exoPlayer)
                    }
                } catch (e: Throwable) {
                    android.util.Log.w("MainActivity", "Failed applying aux effect to player instance: ${e.message}")
                }
            }
        } catch (e: Throwable) {
            android.util.Log.w("MainActivity", "Failed applying reverb aux effect: ${e.message}")
        }
    }

    private fun attachAudioSession(sessionId: Int) {
        if (sessionId <= 0 || sessionId == currentSessionId) return
        releaseEffects()
        currentSessionId = sessionId

        // Attempt Tier 1: Hardware 10-Band DynamicsProcessing (API 28+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                // Use VARIANT_FAVOR_TIME_RESOLUTION for ultra-low latency without buffer underruns
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_TIME_RESOLUTION,
                    2, // Stereo channels
                    true, // Pre-EQ enabled
                    10, // 10 Pre-EQ bands
                    false, // MBC disabled
                    0,
                    false, // Post-EQ disabled (fixes speaker audio muting)
                    0,
                    true // Hardware Limiter enabled
                ).build()

                val dp = DynamicsProcessing(1000, sessionId, config)
                // Initialize default flat 0dB pass-through bands immediately upon session attachment
                for (i in 0 until 10) {
                    val cutoff = if (i < 9) (isoBandFrequencies[i] + isoBandFrequencies[i + 1]) / 2f else 20000f
                    dp.setPreEqBandAllChannelsTo(i, DynamicsProcessing.EqBand(true, cutoff, 0.0f))
                }
                dp.setInputGainAllChannelsTo(0.0f)
                val limiter = DynamicsProcessing.Limiter(true, true, 0, 1.0f, 60.0f, 10.0f, -0.1f, 0.0f)
                dp.setLimiterAllChannelsTo(limiter)
                dp.enabled = false // Keep bypassed until non-flat parameters or limiter are requested
                dynamicsProcessing = dp
                dspEngineMode = "DynamicsProcessing 64-bit Hardware (10-Band)"

                try {
                    virtualizer = Virtualizer(1000, sessionId).apply {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            val mode = if (isBluetoothOutputActive) {
                                Virtualizer.VIRTUALIZATION_MODE_BINAURAL
                            } else {
                                Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL
                            }
                            try { forceVirtualizationMode(mode) } catch (_: Throwable) {}
                        }
                        enabled = false
                    }
                } catch (_: Throwable) {}
            } catch (e: Throwable) {
                // Rule B1: OEM firmware fallback if DynamicsProcessing is restricted
                dynamicsProcessing = null
                initFallbackEqualizer(sessionId)
            }
        } else {
            initFallbackEqualizer(sessionId)
        }
        if (currentReverbEffectId > 0 && currentReverbSendLevel > 0.001f) {
            applyReverbAuxEffectToExoPlayer(currentReverbEffectId, currentReverbSendLevel)
        }
    }

    private fun initFallbackEqualizer(sessionId: Int) {
        try {
            legacyEqualizer = Equalizer(1000, sessionId).apply { enabled = false }
            loudnessEnhancer = LoudnessEnhancer(sessionId).apply { enabled = false }
            try {
                virtualizer = Virtualizer(1000, sessionId).apply {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val mode = if (isBluetoothOutputActive) {
                            Virtualizer.VIRTUALIZATION_MODE_BINAURAL
                        } else {
                            Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL
                        }
                        try { forceVirtualizationMode(mode) } catch (_: Throwable) {}
                    }
                    enabled = false
                }
            } catch (_: Throwable) {}
            dspEngineMode = "Android Hardware Equalizer + LoudnessEnhancer (OEM Fallback)"
        } catch (_: Throwable) {
            dspEngineMode = "Software Biquad Float64 DSP"
        }
    }

    private fun applyDspParameters(args: Map<*, *>) {
        val bitPerfectDirect = args["bitPerfectDirectMode"] as? Boolean ?: false
        val eqEnabled = args["eqEnabled"] as? Boolean ?: true
        val limiterEnabled = args["limiterEnabled"] as? Boolean ?: true
        val preampDb = (args["preampDb"] as? Number)?.toFloat() ?: 0f
        val bassGain = (args["bassGain"] as? Number)?.toFloat() ?: 0f
        val trebleGain = (args["trebleGain"] as? Number)?.toFloat() ?: 0f
        val stereoExpansion = (args["stereoExpansion"] as? Number)?.toFloat() ?: 0f
        val balance = (args["balance"] as? Number)?.toFloat() ?: 0f
        val monoMix = args["monoMix"] as? Boolean ?: false
        val reverbPresetId = (args["reverbPresetId"] as? Number)?.toInt() ?: 0
        val reverbMix = (args["reverbMix"] as? Number)?.toFloat() ?: 0.50f
        val bandGainsRaw = args["bandGainsDb"] as? List<*>
        val bandFreqsRaw = args["bandFreqsHz"] as? List<*>

        val bandGains = FloatArray(10) { i ->
            (bandGainsRaw?.getOrNull(i) as? Number)?.toFloat() ?: 0f
        }
        val bandFreqs = FloatArray(10) { i ->
            (bandFreqsRaw?.getOrNull(i) as? Number)?.toFloat() ?: isoBandFrequencies[i]
        }

        // If Bit-Perfect Direct USB DAC Mode is active, bypass ALL hardware DSP nodes immediately
        if (bitPerfectDirect) {
            try { dynamicsProcessing?.enabled = false } catch (_: Throwable) {}
            try { legacyEqualizer?.enabled = false } catch (_: Throwable) {}
            try { loudnessEnhancer?.enabled = false } catch (_: Throwable) {}
            try { virtualizer?.enabled = false } catch (_: Throwable) {}
            try { bassBoost?.enabled = false } catch (_: Throwable) {}
            try { presetReverb?.enabled = false } catch (_: Throwable) {}
            try { environmentalReverb?.enabled = false } catch (_: Throwable) {}
            currentReverbEffectId = 0
            currentReverbSendLevel = 0f
            applyReverbAuxEffectToExoPlayer(0, 0f)
            return
        }

        val effectiveStereoExpansion = if (monoMix) 0f else stereoExpansion.coerceIn(0f, 1f)

        val isDspFlat = Math.abs(preampDb) < 0.01f &&
            Math.abs(bassGain) < 0.01f &&
            Math.abs(trebleGain) < 0.01f &&
            Math.abs(balance) < 0.01f &&
            effectiveStereoExpansion < 0.01f &&
            reverbPresetId == 0 &&
            bandGains.all { Math.abs(it) < 0.01f }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && dynamicsProcessing != null) {
            try {
                val dp = dynamicsProcessing!!
                val shouldEnableDp = eqEnabled && (!isDspFlat || limiterEnabled)

                if (shouldEnableDp) {
                    val basePreamp = if (eqEnabled) preampDb else 0f
                    val leftAtten = if (balance > 0f) -balance * 36f else 0f
                    val rightAtten = if (balance < 0f) balance * 36f else 0f
                    dp.setInputGainbyChannel(0, basePreamp + leftAtten)
                    dp.setInputGainbyChannel(1, basePreamp + rightAtten)

                    for (i in 0 until 10) {
                        val lowShelfBonus = if (i <= 2) bassGain * 8f * (1f - i * 0.28f) else 0f
                        val highShelfBonus = if (i >= 7) trebleGain * 8f * ((i - 6) * 0.3f) else 0f
                        val baseBandGain = if (eqEnabled) (bandGains[i] + lowShelfBonus + highShelfBonus) else 0f

                        var leftSpatialBonus = 0f
                        var rightSpatialBonus = 0f
                        if (effectiveStereoExpansion > 0.005f) {
                            when (i) {
                                6 -> { leftSpatialBonus = effectiveStereoExpansion * 1.8f; rightSpatialBonus = -effectiveStereoExpansion * 1.0f }
                                7 -> { leftSpatialBonus = -effectiveStereoExpansion * 1.0f; rightSpatialBonus = effectiveStereoExpansion * 2.2f }
                                8 -> { leftSpatialBonus = effectiveStereoExpansion * 2.5f; rightSpatialBonus = -effectiveStereoExpansion * 0.8f }
                                9 -> { leftSpatialBonus = -effectiveStereoExpansion * 0.8f; rightSpatialBonus = effectiveStereoExpansion * 2.8f }
                            }
                        }

                        val cutoffFreq = if (i < 9) (bandFreqs[i] + bandFreqs[i + 1]) / 2f else 20000f
                        val leftEqBand = DynamicsProcessing.EqBand(eqEnabled, cutoffFreq, baseBandGain + leftSpatialBonus)
                        val rightEqBand = DynamicsProcessing.EqBand(eqEnabled, cutoffFreq, baseBandGain + rightSpatialBonus)
                        dp.setPreEqBandByChannelIndex(0, i, leftEqBand)
                        dp.setPreEqBandByChannelIndex(1, i, rightEqBand)
                    }

                    // Rule B2: Bluetooth Inter-Sample Peak (-0.5 dBFS) vs Wired (-0.1 dBFS) Hardware Limiter
                    val ceilingDb = if (isBluetoothOutputActive) -0.5f else -0.1f
                    val limiter = DynamicsProcessing.Limiter(
                        true,
                        limiterEnabled,
                        0,
                        1.0f, // 1ms fast attack
                        60.0f, // 60ms release
                        10.0f, // 10:1 brickwall ratio
                        ceilingDb,
                        0.0f
                    )
                    dp.setLimiterAllChannelsTo(limiter)
                    dp.enabled = true
                } else {
                    dp.enabled = false
                }
            } catch (_: Throwable) {}
        } else {
            // Apply to Tier 2 Fallback Equalizer + LoudnessEnhancer
            try {
                loudnessEnhancer?.setTargetGain((preampDb * 100).roundToInt())
                val eq = legacyEqualizer
                if (eq != null) {
                    val numBands = eq.numberOfBands.toInt()
                    for (b in 0 until numBands) {
                        val mappedIdx = ((b.toFloat() / numBands) * 9).roundToInt().coerceIn(0, 9)
                        val targetMillibel = (bandGains[mappedIdx] * 100).roundToInt().toShort()
                        eq.setBandLevel(b.toShort(), if (eqEnabled) targetMillibel else 0)
                    }
                    eq.enabled = eqEnabled && !isDspFlat
                }
            } catch (_: Throwable) {}
        }

        // Apply Stereo X Width Expansion, BassBoost (fallback only), and Reverb
        try {
            if (effectiveStereoExpansion > 0.001f) {
                if (virtualizer == null && currentSessionId > 0) {
                    try { virtualizer = Virtualizer(1000, currentSessionId) } catch (_: Throwable) {}
                }
                virtualizer?.let { v ->
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            val mode = if (isBluetoothOutputActive) {
                                Virtualizer.VIRTUALIZATION_MODE_BINAURAL
                            } else {
                                Virtualizer.VIRTUALIZATION_MODE_TRANSAURAL
                            }
                            v.forceVirtualizationMode(mode)
                        }
                    } catch (_: Throwable) {}
                    try {
                        v.enabled = true
                        v.setStrength((effectiveStereoExpansion * 1000).roundToInt().toShort().coerceIn(0, 1000))
                    } catch (_: Throwable) {}
                }
            } else {
                virtualizer?.enabled = false
            }

            if (dynamicsProcessing == null) {
                if (bassGain > 0.001f) {
                    if (bassBoost == null && currentSessionId > 0) {
                        try { bassBoost = BassBoost(1000, currentSessionId) } catch (_: Throwable) {}
                    }
                    bassBoost?.enabled = true
                    bassBoost?.setStrength((bassGain * 1000).roundToInt().toShort().coerceIn(0, 1000))
                } else {
                    bassBoost?.enabled = false
                }
            } else {
                bassBoost?.enabled = false
            }

            if (reverbPresetId > 0 && reverbMix > 0.001f) {
                if (presetReverb == null && environmentalReverb == null) {
                    try {
                        presetReverb = PresetReverb(1000, 0)
                    } catch (e1: Throwable) {
                        if (currentSessionId > 0) {
                            try {
                                presetReverb = PresetReverb(1000, currentSessionId)
                            } catch (e2: Throwable) {
                                try {
                                    environmentalReverb = EnvironmentalReverb(1000, 0)
                                } catch (_: Throwable) {
                                    try {
                                        environmentalReverb = EnvironmentalReverb(1000, currentSessionId)
                                    } catch (_: Throwable) {}
                                }
                            }
                        }
                    }
                }

                var activeEffectId = 0
                presetReverb?.let { pr ->
                    try {
                        pr.preset = reverbPresetId.toShort()
                        pr.enabled = true
                        activeEffectId = pr.id
                    } catch (_: Throwable) {}
                }

                if (activeEffectId == 0) {
                    environmentalReverb?.let { er ->
                        try {
                            er.enabled = true
                            when (reverbPresetId) {
                                1 -> { er.roomLevel = -1200; er.decayTime = 600 } // Small Room
                                2 -> { er.roomLevel = -900; er.decayTime = 1200 } // Medium Room
                                3 -> { er.roomLevel = -600; er.decayTime = 2200 } // Large Room
                                4 -> { er.roomLevel = -500; er.decayTime = 3200 } // Medium Hall
                                5 -> { er.roomLevel = -300; er.decayTime = 4800 } // Large Hall
                                6 -> { er.roomLevel = -200; er.decayTime = 3800; er.diffusion = 1000 } // Studio Plate
                                else -> { er.roomLevel = -800; er.decayTime = 1500 }
                            }
                            activeEffectId = er.id
                        } catch (_: Throwable) {}
                    }
                }

                currentReverbEffectId = activeEffectId
                currentReverbSendLevel = reverbMix
                applyReverbAuxEffectToExoPlayer(activeEffectId, reverbMix)
            } else {
                try { presetReverb?.enabled = false } catch (_: Throwable) {}
                try { environmentalReverb?.enabled = false } catch (_: Throwable) {}
                currentReverbEffectId = 0
                currentReverbSendLevel = 0f
                applyReverbAuxEffectToExoPlayer(0, 0f)
            }
        } catch (_: Throwable) {}
    }

    private fun updateRouteTelemetry(audioManager: AudioManager): Map<String, Any> {
        val sampleRateStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
        val bufferFramesStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)
        var hwSampleRate = sampleRateStr?.toIntOrNull() ?: 48000
        val hwBufferFrames = bufferFramesStr?.toIntOrNull() ?: 256
        var hwBitDepth = 24
        var deviceName = "Pixel Built-in Stereo Speakers"
        var routeType = "BUILTIN_SPEAKER"
        var btCodec = "Direct 24-bit PCM"
        var isBt = false
        var isUsb = false

        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        for (dev in devices) {
            when (dev.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER -> {
                    isBt = true
                    deviceName = dev.productName?.toString()?.takeIf { it.isNotBlank() } ?: "Bluetooth Audio"
                    routeType = if (dev.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP) "BLUETOOTH_A2DP" else "BLE_AUDIO_LC3"
                    val maxRate = dev.sampleRates.maxOrNull() ?: hwSampleRate
                    hwSampleRate = maxRate
                    btCodec = when {
                        dev.type != AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BLE Audio LC3"
                        maxRate >= 96000 -> "LDAC / LHDC Hi-Res 96kHz"
                        maxRate >= 48000 -> "aptX Adaptive / aptX HD / AAC"
                        else -> "Bluetooth A2DP (AAC / SBC)"
                    }
                }
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_ACCESSORY -> {
                    isUsb = true
                    deviceName = dev.productName?.toString()?.takeIf { it.isNotBlank() } ?: "USB-C Hi-Res DAC"
                    routeType = "USB_DAC_DIRECT"
                    hwSampleRate = dev.sampleRates.maxOrNull() ?: 96000
                    hwBitDepth = 32
                    btCodec = "USB-C Bit-Perfect PCM"
                }
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_WIRED_HEADSET -> {
                    if (!isBt && !isUsb) {
                        deviceName = "Wired Studio Headphones"
                        routeType = "WIRED_HEADSET"
                        btCodec = "Analog Direct Out"
                    }
                }
            }
        }

        isBluetoothOutputActive = isBt

        return mapOf(
            "deviceName" to deviceName,
            "routeType" to routeType,
            "bluetoothCodecName" to btCodec,
            "hardwareSampleRateHz" to hwSampleRate,
            "hardwareBitDepth" to hwBitDepth,
            "hardwareBufferFrames" to hwBufferFrames,
            "isBluetooth" to isBt,
            "isUsbDac" to isUsb,
            "dspEngineMode" to dspEngineMode
        )
    }

    /**
     * Section 12.1: Google Pixel Custom X-Axis LRA Haptic Composition Engine.
     * Uses VibrationEffect.Composition primitives on Pixel / Android 11+ (API 30/31+)
     * and gracefully falls back on legacy Android devices.
     */
    private fun triggerPixelLraHaptic(type: String, intensity: Float) {
        val vibrator: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

        if (!vibrator.hasVibrator()) return
        val scale = intensity.coerceIn(0.15f, 1.0f)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val composition = VibrationEffect.startComposition()
                var usedComposition = false

                when (type) {
                    "low_tick" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_LOW_TICK)
                        ) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_LOW_TICK, scale * 0.55f)
                            usedComposition = true
                        } else if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK)) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, scale * 0.45f)
                            usedComposition = true
                        }
                    }
                    "tick" -> {
                        if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK)) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, scale * 0.75f)
                            usedComposition = true
                        }
                    }
                    "detent_snap" -> {
                        if (vibrator.areAllPrimitivesSupported(
                                VibrationEffect.Composition.PRIMITIVE_CLICK,
                                VibrationEffect.Composition.PRIMITIVE_TICK
                            )
                        ) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.90f)
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, 0.55f, 16)
                            usedComposition = true
                        }
                    }
                    "rail_thud" -> {
                        if ( Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_THUD)
                        ) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_THUD, 0.85f)
                            usedComposition = true
                        }
                    }
                    "play_toggle" -> {
                        if (vibrator.areAllPrimitivesSupported(
                                VibrationEffect.Composition.PRIMITIVE_CLICK,
                                VibrationEffect.Composition.PRIMITIVE_QUICK_RISE
                            )
                        ) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.80f)
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_QUICK_RISE, 0.50f, 12)
                            usedComposition = true
                        }
                    }
                    "sheet_expand" -> {
                        if (vibrator.areAllPrimitivesSupported(
                                VibrationEffect.Composition.PRIMITIVE_QUICK_RISE,
                                VibrationEffect.Composition.PRIMITIVE_TICK
                            )
                        ) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_QUICK_RISE, 0.60f)
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, 0.75f, 22)
                            usedComposition = true
                        }
                    }
                    "hifi_confirm" -> {
                        if (vibrator.areAllPrimitivesSupported(
                                VibrationEffect.Composition.PRIMITIVE_SLOW_RISE,
                                VibrationEffect.Composition.PRIMITIVE_CLICK
                            )
                        ) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_SLOW_RISE, 0.55f)
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 0.95f, 35)
                            usedComposition = true
                        }
                    }
                    "swipe_click" -> {
                        if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, (scale * 1.0f).coerceIn(0.75f, 1.0f))
                            usedComposition = true
                        } else if (vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_TICK)) {
                            composition.addPrimitive(VibrationEffect.Composition.PRIMITIVE_TICK, scale * 0.95f)
                            usedComposition = true
                        }
                    }
                }

                if (usedComposition) {
                    vibrator.vibrate(composition.compose())
                    return
                }
            } catch (_: Throwable) {}
        }

        // Universal Android 7-10 / Non-Pixel Fallback
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val durationMs = when (type) {
                "low_tick" -> 5L
                "tick" -> 8L
                "swipe_click" -> 10L
                "detent_snap" -> 14L
                "rail_thud" -> 22L
                else -> 12L
            }
            val amp = when (type) {
                "swipe_click" -> (scale * 230).roundToInt().coerceIn(40, 255)
                else -> (scale * 180).roundToInt().coerceIn(25, 255)
            }
            vibrator.vibrate(VibrationEffect.createOneShot(durationMs, amp))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(10L)
        }
    }

    private fun transcodeWmaToWav(sourcePath: String, outputFile: File): String? {
        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var fos: FileOutputStream? = null
        val tempPcmFile = File(outputFile.absolutePath + ".pcm")
        try {
            extractor = MediaExtractor()
            if (sourcePath.startsWith("content://")) {
                extractor.setDataSource(this, Uri.parse(sourcePath), null)
            } else {
                extractor.setDataSource(sourcePath)
            }

            var audioTrackIndex = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val trackFormat = extractor.getTrackFormat(i)
                val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    format = trackFormat
                    break
                }
            }

            if (audioTrackIndex < 0 || format == null) return null
            extractor.selectTrack(audioTrackIndex)

            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()

            val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) format.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
            val channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 2

            fos = FileOutputStream(tempPcmFile)

            val bufferInfo = MediaCodec.BufferInfo()
            var sawInputEOS = false
            var sawOutputEOS = false
            val timeoutUs = 5000L

            while (!sawOutputEOS) {
                if (!sawInputEOS) {
                    val inputIndex = decoder.dequeueInputBuffer(timeoutUs)
                    if (inputIndex >= 0) {
                        val inputBuffer = decoder.getInputBuffer(inputIndex)
                        if (inputBuffer != null) {
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(inputIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                sawInputEOS = true
                            } else {
                                val sampleTime = extractor.sampleTime
                                decoder.queueInputBuffer(inputIndex, 0, sampleSize, sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                val outputIndex = decoder.dequeueOutputBuffer(bufferInfo, timeoutUs)
                if (outputIndex >= 0) {
                    val outputBuffer = decoder.getOutputBuffer(outputIndex)
                    if (outputBuffer != null && bufferInfo.size > 0) {
                        val chunk = ByteArray(bufferInfo.size)
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.get(chunk)
                        fos.write(chunk)
                    }
                    decoder.releaseOutputBuffer(outputIndex, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        sawOutputEOS = true
                    }
                }
            }

            fos.flush()
            fos.close()
            fos = null

            writeWavFile(tempPcmFile, outputFile, sampleRate, channelCount, 16)
            tempPcmFile.delete()

            if (outputFile.exists() && outputFile.length() > 44) {
                return outputFile.absolutePath
            }
        } catch (e: Throwable) {
            android.util.Log.w("MainActivity", "WMA transcoding: ${e.message}")
        } finally {
            try { fos?.close() } catch (_: Throwable) {}
            try { tempPcmFile.delete() } catch (_: Throwable) {}
            try { decoder?.stop(); decoder?.release() } catch (_: Throwable) {}
            try { extractor?.release() } catch (_: Throwable) {}
        }
        return null
    }

    private fun writeWavFile(pcmFile: File, wavFile: File, sampleRate: Int, channels: Int, bitDepth: Int) {
        val pcmLength = pcmFile.length()
        val totalDataLen = pcmLength + 36
        val byteRate = (sampleRate * channels * bitDepth / 8).toLong()
        val blockAlign = channels * bitDepth / 8

        val header = ByteArray(44)
        header[0] = 'R'.code.toByte(); header[1] = 'I'.code.toByte(); header[2] = 'F'.code.toByte(); header[3] = 'F'.code.toByte()
        header[4] = (totalDataLen and 0xff).toByte()
        header[5] = ((totalDataLen shr 8) and 0xff).toByte()
        header[6] = ((totalDataLen shr 16) and 0xff).toByte()
        header[7] = ((totalDataLen shr 24) and 0xff).toByte()
        header[8] = 'W'.code.toByte(); header[9] = 'A'.code.toByte(); header[10] = 'V'.code.toByte(); header[11] = 'E'.code.toByte()
        header[12] = 'f'.code.toByte(); header[13] = 'm'.code.toByte(); header[14] = 't'.code.toByte(); header[15] = ' '.code.toByte()
        header[16] = 16; header[17] = 0; header[18] = 0; header[19] = 0
        header[20] = 1; header[21] = 0
        header[22] = channels.toByte(); header[23] = 0
        header[24] = (sampleRate and 0xff).toByte()
        header[25] = ((sampleRate shr 8) and 0xff).toByte()
        header[26] = ((sampleRate shr 16) and 0xff).toByte()
        header[27] = ((sampleRate shr 24) and 0xff).toByte()
        header[28] = (byteRate and 0xff).toByte()
        header[29] = ((byteRate shr 8) and 0xff).toByte()
        header[30] = ((byteRate shr 16) and 0xff).toByte()
        header[31] = ((byteRate shr 24) and 0xff).toByte()
        header[32] = blockAlign.toByte(); header[33] = 0
        header[34] = bitDepth.toByte(); header[35] = 0
        header[36] = 'd'.code.toByte(); header[37] = 'a'.code.toByte(); header[38] = 't'.code.toByte(); header[39] = 'a'.code.toByte()
        header[40] = (pcmLength and 0xff).toByte()
        header[41] = ((pcmLength shr 8) and 0xff).toByte()
        header[42] = ((pcmLength shr 16) and 0xff).toByte()
        header[43] = ((pcmLength shr 24) and 0xff).toByte()

        FileOutputStream(wavFile).use { out ->
            out.write(header)
            FileInputStream(pcmFile).use { inStream ->
                inStream.copyTo(out)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_DIRECTORY) {
            val pending = pendingDirectoryResult
            pendingDirectoryResult = null
            if (resultCode == android.app.Activity.RESULT_OK && data?.data != null) {
                val treeUri = data.data!!
                try {
                    contentResolver.takePersistableUriPermission(
                        treeUri,
                        android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                    )
                } catch (_: Throwable) {}
                val folderName = getTreeDisplayName(treeUri) ?: "Music Folder"
                pending?.success(
                    mapOf(
                        "uri" to treeUri.toString(),
                        "name" to folderName
                    )
                )
            } else {
                pending?.success(null)
            }
        } else if (requestCode == REQUEST_CODE_PICK_AUDIO_FILES) {
            val pending = pendingFilesResult
            pendingFilesResult = null
            if (resultCode == android.app.Activity.RESULT_OK && data != null) {
                val uris = mutableListOf<android.net.Uri>()
                val clip = data.clipData
                if (clip != null) {
                    for (i in 0 until clip.itemCount) {
                        val u = clip.getItemAt(i).uri
                        if (u != null) uris.add(u)
                    }
                } else if (data.data != null) {
                    uris.add(data.data!!)
                }

                Thread {
                    val list = mutableListOf<Map<String, Any?>>()
                    for (uri in uris) {
                        try {
                            contentResolver.takePersistableUriPermission(
                                uri,
                                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                            )
                        } catch (_: Throwable) {}

                        var displayName = "Audio Track"
                        var sizeBytes = 0L

                        try {
                            contentResolver.query(
                                uri,
                                arrayOf(
                                    android.provider.OpenableColumns.DISPLAY_NAME,
                                    android.provider.OpenableColumns.SIZE
                                ),
                                null,
                                null,
                                null
                            )?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val nameIdx = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                                    if (nameIdx >= 0) displayName = cursor.getString(nameIdx) ?: displayName
                                    val sizeIdx = cursor.getColumnIndex(android.provider.OpenableColumns.SIZE)
                                    if (sizeIdx >= 0) sizeBytes = cursor.getLong(sizeIdx)
                                }
                            }
                        } catch (_: Throwable) {}

                        list.add(
                            mapOf(
                                "uri" to uri.toString(),
                                "name" to displayName,
                                "size" to sizeBytes
                            )
                        )
                    }

                    runOnUiThread {
                        pending?.success(list)
                    }
                }.start()
            } else {
                pending?.success(emptyList<Map<String, Any?>>())
            }
        }
    }

    private fun getTreeDisplayName(treeUri: android.net.Uri): String? {
        try {
            val docId = android.provider.DocumentsContract.getTreeDocumentId(treeUri)
            val docUri = android.provider.DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            contentResolver.query(
                docUri,
                arrayOf(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrEmpty()) return name
                }
            }
        } catch (_: Throwable) {}
        val last = treeUri.lastPathSegment
        return if (!last.isNullOrEmpty()) {
            last.substringAfterLast(':').substringAfterLast('/')
        } else {
            "Music Folder"
        }
    }

    private fun scanPathOrUri(pathOrUri: String): List<Map<String, Any>> {
        val trimmed = pathOrUri.trim().trimEnd('/')
        // Safety: If the path is empty or root directory, NEVER scan the entire device!
        if (trimmed.isEmpty() || trimmed == "/" || trimmed == "/storage" || trimmed == "/storage/emulated" || trimmed == "/storage/emulated/0") {
            return emptyList()
        }

        if (trimmed.startsWith("content://")) {
            return scanDirectoryTree(trimmed)
        }

        val dir = File(trimmed)
        if (dir.exists() && dir.isDirectory) {
            val results = mutableListOf<Map<String, Any>>()
            val supportedExtensions = setOf(
                "mp3", "flac", "m4a", "wav", "aac", "ogg", "opus", "alac",
                "aiff", "aif", "wma", "asf", "ape", "dsd", "dsf", "dff", "mka"
            )
            try {
                dir.walkTopDown().filter { it.isFile }.forEach { file ->
                    val ext = file.extension.lowercase()
                    if (supportedExtensions.contains(ext)) {
                        results.add(
                            mapOf(
                                "path" to file.absolutePath,
                                "name" to file.name,
                                "size" to file.length()
                            )
                        )
                    }
                }
            } catch (_: Throwable) {
            }
            if (results.isNotEmpty()) {
                return results
            }
        }
        return scanMediaStoreForFolder(trimmed)
    }

    private fun scanDirectoryTree(treeUriString: String): List<Map<String, Any>> {
        val treeUri = android.net.Uri.parse(treeUriString)
        try {
            contentResolver.takePersistableUriPermission(
                treeUri,
                android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: Throwable) {
        }

        val results = mutableListOf<Map<String, Any>>()
        val supportedExtensions = setOf(
            "mp3", "flac", "m4a", "wav", "aac", "ogg", "opus", "alac",
            "aiff", "aif", "wma", "asf", "ape", "dsd", "dsf", "dff", "mka"
        )

        fun scanSubtree(parentDocId: String) {
            val childrenUri = try {
                android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
            } catch (_: Throwable) {
                return
            }

            val projection = arrayOf(
                android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE,
                android.provider.DocumentsContract.Document.COLUMN_SIZE
            )

            try {
                contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                    val idCol = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                    val nameCol = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                    val mimeCol = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE)
                    val sizeCol = cursor.getColumnIndex(android.provider.DocumentsContract.Document.COLUMN_SIZE)

                    while (cursor.moveToNext()) {
                        val childId = cursor.getString(idCol) ?: continue
                        val displayName = cursor.getString(nameCol) ?: "Unknown"
                        val mimeType = cursor.getString(mimeCol) ?: ""
                        val size = if (sizeCol != -1 && !cursor.isNull(sizeCol)) cursor.getLong(sizeCol) else 0L

                        if (mimeType == android.provider.DocumentsContract.Document.MIME_TYPE_DIR) {
                            scanSubtree(childId)
                        } else {
                            val ext = displayName.substringAfterLast('.', "").lowercase()
                            if (supportedExtensions.contains(ext) || mimeType.startsWith("audio/")) {
                                val fileDocUri = android.provider.DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                                results.add(
                                    mapOf(
                                        "uri" to fileDocUri.toString(),
                                        "name" to displayName,
                                        "size" to size
                                    )
                                )
                            }
                        }
                    }
                }
            } catch (_: Throwable) {
            }
        }

        try {
            val rootDocId = android.provider.DocumentsContract.getTreeDocumentId(treeUri)
            scanSubtree(rootDocId)
        } catch (_: Throwable) {
            try {
                val docId = android.provider.DocumentsContract.getDocumentId(treeUri)
                scanSubtree(docId)
            } catch (_: Throwable) {
            }
        }

        return results
    }

    private fun scanMediaStoreForFolder(folderPath: String): List<Map<String, Any>> {
        val trimmed = folderPath.trim().trimEnd('/')
        // Strictly guard against empty, root or device-level paths
        if (trimmed.isEmpty() || trimmed == "/" || trimmed == "/storage" || trimmed == "/storage/emulated" || trimmed == "/storage/emulated/0") {
            return emptyList()
        }

        val results = mutableListOf<Map<String, Any>>()
        try {
            val uri = android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                android.provider.MediaStore.Audio.Media._ID,
                android.provider.MediaStore.Audio.Media.DISPLAY_NAME,
                android.provider.MediaStore.Audio.Media.DATA,
                android.provider.MediaStore.Audio.Media.SIZE,
                android.provider.MediaStore.Audio.Media.DURATION,
                android.provider.MediaStore.Audio.Media.TITLE,
                android.provider.MediaStore.Audio.Media.ARTIST,
                android.provider.MediaStore.Audio.Media.ALBUM,
                android.provider.MediaStore.Audio.Media.ALBUM_ID
            )
            val normalizedPath = "$trimmed/%"
            val relativeFilter = if (trimmed.contains("/storage/emulated/0/")) {
                trimmed.substringAfter("/storage/emulated/0/").trimStart('/') + "/%"
            } else {
                trimmed.trimStart('/') + "/%"
            }

            // Exclude non-music audio, short notification chirps (<15s), and filter by path
            val selection = "${android.provider.MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${android.provider.MediaStore.Audio.Media.DURATION} >= 15000 AND (${android.provider.MediaStore.Audio.Media.DATA} LIKE ? OR ${android.provider.MediaStore.Audio.Media.RELATIVE_PATH} LIKE ?)"
            val selectionArgs = arrayOf(normalizedPath, relativeFilter)

            contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
                val idCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media._ID)
                val nameCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.DISPLAY_NAME)
                val dataCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.DATA)
                val sizeCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.SIZE)
                val durCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.DURATION)
                val titleCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.TITLE)
                val artistCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.ARTIST)
                val albumCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.ALBUM)
                val albumIdCol = cursor.getColumnIndex(android.provider.MediaStore.Audio.Media.ALBUM_ID)

                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val name = cursor.getString(nameCol) ?: "Audio Track"
                    val path = cursor.getString(dataCol) ?: ""
                    val size = cursor.getLong(sizeCol)
                    val duration = if (durCol != -1) cursor.getLong(durCol) else 0L
                    val rawTitle = if (titleCol != -1) cursor.getString(titleCol) else null
                    val rawArtist = if (artistCol != -1) cursor.getString(artistCol) else null
                    val rawAlbum = if (albumCol != -1) cursor.getString(albumCol) else null
                    val albumId = if (albumIdCol != -1) cursor.getLong(albumIdCol) else 0L

                    // Skip noisy app folders
                    val lowerPath = path.lowercase()
                    if (lowerPath.contains("/whatsapp/") ||
                        lowerPath.contains("/telegram/") ||
                        lowerPath.contains("/notifications/") ||
                        lowerPath.contains("/ringtones/") ||
                        lowerPath.contains("/alarms/") ||
                        lowerPath.contains("/recordings/") ||
                        lowerPath.contains("/android/data/")) {
                        continue
                    }

                    val contentUri = android.content.ContentUris.withAppendedId(
                        android.provider.MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                        id
                    )
                    val item = mutableMapOf<String, Any>(
                        "uri" to contentUri.toString(),
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "durationMs" to duration
                    )
                    if (!rawTitle.isNullOrEmpty() && rawTitle != "<unknown>") item["title"] = rawTitle
                    if (!rawArtist.isNullOrEmpty() && rawArtist != "<unknown>") item["artist"] = rawArtist
                    if (!rawAlbum.isNullOrEmpty() && rawAlbum != "<unknown>") item["album"] = rawAlbum
                    if (albumId > 0) {
                        item["albumArtUri"] = "content://media/external/audio/albumart/$albumId"
                    }
                    results.add(item)
                }
            }
        } catch (_: Throwable) {
        }
        return results
    }

    private fun releaseEffects() {
        try { dynamicsProcessing?.release() } catch (_: Throwable) {}
        try { legacyEqualizer?.release() } catch (_: Throwable) {}
        try { loudnessEnhancer?.release() } catch (_: Throwable) {}
        try { virtualizer?.release() } catch (_: Throwable) {}
        try { bassBoost?.release() } catch (_: Throwable) {}
        try { presetReverb?.release() } catch (_: Throwable) {}
        try { environmentalReverb?.release() } catch (_: Throwable) {}
        dynamicsProcessing = null
        legacyEqualizer = null
        loudnessEnhancer = null
        virtualizer = null
        bassBoost = null
        presetReverb = null
        environmentalReverb = null
        currentReverbEffectId = 0
        currentReverbSendLevel = 0f
        applyReverbAuxEffectToExoPlayer(0, 0f)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    private fun getDirSize(dir: File): Long {
        var size = 0L
        if (!dir.exists()) return 0L
        val children = dir.listFiles() ?: return 0L
        for (child in children) {
            size += if (child.isDirectory) getDirSize(child) else child.length()
        }
        return size
    }

    private fun clearDir(dir: File): Long {
        var reclaimed = 0L
        if (!dir.exists()) return 0L
        val children = dir.listFiles() ?: return 0L
        for (child in children) {
            if (child.isDirectory) {
                reclaimed += clearDir(child)
                try { child.delete() } catch (_: Throwable) {}
            } else {
                val len = child.length()
                if (child.delete()) {
                    reclaimed += len
                }
            }
        }
        return reclaimed
    }

    private fun getBatteryStatusMap(): Map<String, Any> {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isPowerSaveMode = powerManager?.isPowerSaveMode ?: false

        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPct = if (level >= 0 && scale > 0) (level * 100 / scale) else 100

        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL

        return mapOf(
            "batteryLevel" to batteryPct,
            "isCharging" to isCharging,
            "isPowerSaveMode" to isPowerSaveMode
        )
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (powerManager?.isIgnoringBatteryOptimizations(packageName) == false) {
                return try {
                    val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = android.net.Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    true
                } catch (_: Throwable) {
                    try {
                        val fallbackIntent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(fallbackIntent)
                        true
                    } catch (_: Throwable) {
                        false
                    }
                }
            }
        }
        return true
    }

    private fun setPreferredDisplayRefreshRate(rate: Float) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val params = window?.attributes ?: return
                params.preferredRefreshRate = rate
                window.attributes = params
            } catch (_: Throwable) {}
        }
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onDestroy() {
        batteryReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Throwable) {}
            batteryReceiver = null
        }
        if (!FreeBeatPlaybackService.isServiceRunning) {
            FreeBeatPlaybackService.playerActionListener = null
        }
        clearDisplayRefreshRateOverrides()
        releaseEffects()
        super.onDestroy()
    }
}
