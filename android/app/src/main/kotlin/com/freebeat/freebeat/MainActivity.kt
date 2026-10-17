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
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
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
                        params.preferredDisplayModeId = peakMode.modeId
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            params.preferredRefreshRate = peakMode.refreshRate
                        }
                        window.attributes = params
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
                    else -> result.notImplemented()
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
                // Pre-EQ 10-Band enabled, MBC disabled, Post-EQ disabled (prevents uninitialized filter muting), Limiter enabled
                val config = DynamicsProcessing.Config.Builder(
                    DynamicsProcessing.VARIANT_FAVOR_FREQUENCY_RESOLUTION,
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
                dp.enabled = true
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

        // Spatial & Tone Auxiliary Hardware Effects
        try {
            virtualizer = Virtualizer(0, sessionId).apply { enabled = true }
        } catch (_: Throwable) {}
        try {
            bassBoost = BassBoost(0, sessionId).apply { enabled = true }
        } catch (_: Throwable) {}
        try {
            presetReverb = PresetReverb(0, sessionId).apply { enabled = false }
        } catch (_: Throwable) {}
    }

    private fun initFallbackEqualizer(sessionId: Int) {
        try {
            legacyEqualizer = Equalizer(0, sessionId).apply { enabled = true }
            loudnessEnhancer = LoudnessEnhancer(sessionId).apply { enabled = true }
            dspEngineMode = "Android Hardware Equalizer + LoudnessEnhancer (OEM Fallback)"
        } catch (_: Throwable) {
            dspEngineMode = "Software Biquad Float64 DSP"
        }
    }

    private fun applyDspParameters(args: Map<*, *>) {
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && dynamicsProcessing != null) {
            try {
                val dp = dynamicsProcessing!!
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
                }
            } catch (_: Throwable) {}
        }

        // Apply Stereo X Width Expansion & BassBoost
        try {
            virtualizer?.setStrength((stereoExpansion * 1000).roundToInt().toShort().coerceIn(0, 1000))
            bassBoost?.setStrength((bassGain * 1000).roundToInt().toShort().coerceIn(0, 1000))
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

    override fun onDestroy() {
        releaseEffects()
        super.onDestroy()
    }
}
