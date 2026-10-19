---
description: Core architectural, security, Smart EQ DSP, Hi-Fi audio, and Google Pixel Material 3 Expressive UI rules for FreeBeat.
---

# FreeBeat Workspace Engineering Rules

1. **100% Client-Side Serverless**: Never introduce a mandatory middleman backend server. All OAuth2 PKCE flows, cloud API requests, and stream proxies run directly on the Android device.
2. **Android Keystore Credential Security**: Store all OAuth tokens, refresh tokens, passwords, and S3 secret keys exclusively via `SecureCredentialStore` (`flutter_secure_storage`). Never write secrets to SQLite or plaintext preferences.
3. **Loopback Stream Proxy (`127.0.0.1`)**: Route cloud and NAS streams through `CloudStreamProxy` bound strictly to `InternetAddress.loopbackIPv4` with HTTP `206 Partial Content` byte-range support and offline caching.
4. **Bandwidth-Safe Indexing**: Use `Range: bytes=0-65535` (64 KB) partial HTTP requests when parsing ID3v2 / FLAC tags from raw cloud files.
5. **Configurable Bitrate & Hi-Fi Lossless**: Respect `AudioQualityConfig` (`96 kbps Opus`, `128 kbps`, `192 kbps`, `320 kbps`, and `Hi-Fi Lossless 24-bit/192kHz`) across Wi-Fi, Cellular, and Offline Downloads, and expose the full audio chain in the Signal Path Sheet.
6. **Smart EQ 10-Band EQ & Native DSP**: Maintain the Kotlin `DynamicsProcessing` bridge (`com.freebeat.app/dsp`) supporting Preamp (`-15` to `+15 dB`), 10 ISO Graphic/Parametric bands (`31Hz`–`16kHz`), Exact Numeric Band Tuning, Rotary Bass/Treble/Stereo X knobs, DVC, Hardware Limiter, L/R Balance, Mono Mix, Tempo/Pitch, and Reverb.
7. **Google Pixel Material 3 Expressive UI**: Always use `Theme.of(context).colorScheme` tokens powered by `DynamicColorBuilder` (Wallpaper Monet) and Album Art palette extraction, alongside the animated `SquigglySlider` seekbar and expressive scalloped/morphing shapes.
8. **Universal Android Compatibility (`minSdkVersion = 24`) & Dual-Tier DSP Fallback**: Use `DynamicsProcessing` on API 28+ as Tier 1 and automatically fall back to `Equalizer` + `LoudnessEnhancer` + `BassBoost` + `Virtualizer` on API 24–27 or restricted OEM ROMs so the 10-band EQ + Preamp never crashes on any device.
9. **Universal Bluetooth Codec & Output Route Engine**: Use `AudioDeviceCallback` to detect active output routes (Bluetooth A2DP/BLE LC3/LDAC/aptX/AAC/SBC, USB-C DAC, Wired, Speaker), enforce `-0.5 dBFS` inter-sample peak limiting over Bluetooth, protect against Bluetooth Absolute Volume + DVC conflicts, and support Per-Output EQ presets.
10. **Two-Pass Throttled Cloud Indexing**: Perform instant bulk catalog listing first, followed by a max-3-concurrent token-bucket worker with HTTP 429 exponential backoff for 64 KB `Range` tag extraction.
11. **Pixel Custom LRA Haptics (`VibrationEffect.Composition`) & 120Hz Physics Animations**: Route all touch interactions (Rotary Knobs, 10-Band EQ Faders, `0.0 dB` detents, Squiggly Seekbar scrubbing, Morphing Play/Pause, MiniPlayer expansion, Lyric seek) through `PixelHaptics` backed by native Android `VibrationEffect.Composition` primitives (`PRIMITIVE_LOW_TICK`, `PRIMITIVE_TICK`, `PRIMITIVE_CLICK`, `PRIMITIVE_QUICK_RISE`, `PRIMITIVE_THUD`) with spring-physics UI animations.
