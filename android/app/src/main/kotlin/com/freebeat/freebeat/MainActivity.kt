package com.freebeat.freebeat

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.audiofx.BassBoost
import android.media.audiofx.DynamicsProcessing
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.media.audiofx.Virtualizer
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Bundle
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
    private val channelName = "com.freebeat.app/dsp"
    private var currentSessionId: Int = 0

    // Tier 1: Android 9+ (API 28+) Studio-Grade 10-Band DynamicsProcessing
    private var dynamicsProcessing: DynamicsProcessing? = null

    // Tier 2: Universal OEM / Legacy Fallback & Spatial Effects (API 24+)
    private var legacyEqualizer: Equalizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var presetReverb: PresetReverb? = null

    private var dspEngineMode: String = "DynamicsProcessing 64-bit Hardware"
    private var isBluetoothOutputActive: Boolean = false

    private val isoBandFrequencies = floatArrayOf(
        31f, 62f, 125f, 250f, 500f, 1000f, 2000f, 4000f, 8000f, 16000f
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enablePeakDisplayRefreshRate()
        requestNotificationPermissionIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        enablePeakDisplayRefreshRate()
    }

    private fun enablePeakDisplayRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    windowManager.defaultDisplay
                }

                val supportedModes = currentDisplay?.supportedModes ?: emptyArray()
                if (supportedModes.isNotEmpty()) {
                    // Pick the mode with the highest refresh rate (e.g. 90Hz, 120Hz, 144Hz)
                    val peakMode = supportedModes.maxWithOrNull(
                        compareBy<android.view.Display.Mode> { it.refreshRate }
                            .thenBy { it.physicalWidth * it.physicalHeight }
                    )

                    if (peakMode != null && peakMode.refreshRate > 60f) {
                        val params = window.attributes
                        if (params.preferredDisplayModeId != peakMode.modeId) {
                            params.preferredDisplayModeId = peakMode.modeId
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                params.preferredRefreshRate = peakMode.refreshRate
                            }
                            window.attributes = params
                        }
                    }
                }
            } catch (_: Throwable) {
                // Ignore if device OEM restricts custom display mode
            }
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
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
                    "setHighRefreshRate" -> {
                        enablePeakDisplayRefreshRate()
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
                            }
                            androidx.core.content.ContextCompat.startForegroundService(this, serviceIntent)
                            result.success(true)
                        } catch (e: Throwable) {
                            android.util.Log.e("MainActivity", "Failed startForegroundPlayback: ${e.message}", e)
                            result.success(false)
                        }
                    }
                    "updatePlaybackNotification" -> {
                        try {
                            val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
                            val durationMs = (call.argument<Number>("durationMs") ?: 0).toLong()
                            val isPlaying = call.argument<Boolean>("isPlaying") ?: true
                            val volume = (call.argument<Number>("volume") ?: 0.8).toFloat()
                            val dominantColor = (call.argument<Number>("dominantColor") ?: 0xFF1E293B).toInt()
                            val title = call.argument<String>("title")
                            val artist = call.argument<String>("artist")
                            val artworkPath = call.argument<String>("artworkPath")
                            val outputDevice = call.argument<String>("outputDevice")
                            val isShuffle = call.argument<Boolean>("isShuffle")
                            val repeatMode = call.argument<Number>("repeatMode")?.toInt()

                            val serviceIntent = android.content.Intent(this, FreeBeatPlaybackService::class.java).apply {
                                action = FreeBeatPlaybackService.ACTION_UPDATE
                                putExtra("positionMs", positionMs)
                                putExtra("durationMs", durationMs)
                                putExtra("isPlaying", isPlaying)
                                putExtra("volume", volume)
                                putExtra("dominantColor", dominantColor)
                                title?.let { putExtra("title", it) }
                                artist?.let { putExtra("artist", it) }
                                artworkPath?.let { putExtra("artworkPath", it) }
                                outputDevice?.let { putExtra("outputDevice", it) }
                                isShuffle?.let { putExtra("isShuffle", it) }
                                repeatMode?.let { putExtra("repeatMode", it) }
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
                                contentResolver.takePersistableUriPermission(
                                    uri,
                                    android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION
                                )
                                result.success(true)
                            } catch (_: Throwable) {
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
                                result.success(decoded ?: path)
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }

        FreeBeatPlaybackService.playerActionListener = { action, extras ->
            runOnUiThread {
                MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
                    .invokeMethod("onNotificationAction", mapOf("action" to action, "extras" to extras))
            }
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

                val dp = DynamicsProcessing(0, sessionId, config)
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
            } catch (e: Throwable) {
                // Rule B1: OEM firmware fallback if DynamicsProcessing is restricted
                dynamicsProcessing = null
                initFallbackEqualizer(sessionId)
            }
        } else {
            initFallbackEqualizer(sessionId)
        }
    }

    private fun initFallbackEqualizer(sessionId: Int) {
        try {
            legacyEqualizer = Equalizer(0, sessionId).apply { enabled = false }
            loudnessEnhancer = LoudnessEnhancer(sessionId).apply { enabled = false }
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
            return
        }

        val isDspFlat = Math.abs(preampDb) < 0.01f &&
            Math.abs(bassGain) < 0.01f &&
            Math.abs(trebleGain) < 0.01f &&
            bandGains.all { Math.abs(it) < 0.01f }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && dynamicsProcessing != null) {
            try {
                val dp = dynamicsProcessing!!
                val shouldEnableDp = eqEnabled && (!isDspFlat || limiterEnabled)

                if (shouldEnableDp) {
                    dp.setInputGainAllChannelsTo(if (eqEnabled) preampDb else 0f)

                    for (i in 0 until 10) {
                        val lowShelfBonus = if (i <= 2) bassGain * 8f * (1f - i * 0.28f) else 0f
                        val highShelfBonus = if (i >= 7) trebleGain * 8f * ((i - 6) * 0.3f) else 0f
                        val totalBandGain = if (eqEnabled) (bandGains[i] + lowShelfBonus + highShelfBonus) else 0f

                        val cutoffFreq = if (i < 9) (bandFreqs[i] + bandFreqs[i + 1]) / 2f else 20000f
                        val eqBand = DynamicsProcessing.EqBand(eqEnabled, cutoffFreq, totalBandGain)
                        dp.setPreEqBandAllChannelsTo(i, eqBand)
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

        // Apply Stereo X Width Expansion & BassBoost only when activated
        try {
            if (stereoExpansion > 0.001f) {
                if (virtualizer == null && currentSessionId > 0) {
                    try { virtualizer = Virtualizer(0, currentSessionId) } catch (_: Throwable) {}
                }
                virtualizer?.enabled = true
                virtualizer?.setStrength((stereoExpansion * 1000).roundToInt().toShort().coerceIn(0, 1000))
            } else {
                virtualizer?.enabled = false
            }

            if (bassGain > 0.001f) {
                if (bassBoost == null && currentSessionId > 0) {
                    try { bassBoost = BassBoost(0, currentSessionId) } catch (_: Throwable) {}
                }
                bassBoost?.enabled = true
                bassBoost?.setStrength((bassGain * 1000).roundToInt().toShort().coerceIn(0, 1000))
            } else {
                bassBoost?.enabled = false
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
                "detent_snap" -> 14L
                "rail_thud" -> 22L
                else -> 12L
            }
            val amp = (scale * 180).roundToInt().coerceIn(25, 255)
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

    private fun releaseEffects() {
        try { dynamicsProcessing?.release() } catch (_: Throwable) {}
        try { legacyEqualizer?.release() } catch (_: Throwable) {}
        try { loudnessEnhancer?.release() } catch (_: Throwable) {}
        try { virtualizer?.release() } catch (_: Throwable) {}
        try { bassBoost?.release() } catch (_: Throwable) {}
        try { presetReverb?.release() } catch (_: Throwable) {}
        dynamicsProcessing = null
        legacyEqualizer = null
        loudnessEnhancer = null
        virtualizer = null
        bassBoost = null
        presetReverb = null
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
