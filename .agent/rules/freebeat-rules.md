---
description: Core architectural, security, Poweramp DSP, Hi-Fi audio, and Google Pixel Material 3 Expressive UI rules for FreeBeat.
---

# FreeBeat Workspace Engineering Rules

1. **100% Client-Side Serverless**: Never introduce a mandatory middleman backend server. All OAuth2 PKCE flows, cloud API requests, and stream proxies run directly on the Android device.
2. **Android Keystore Credential Security**: Store all OAuth tokens, refresh tokens, passwords, and S3 secret keys exclusively via `SecureCredentialStore` (`flutter_secure_storage`). Never write secrets to SQLite or plaintext preferences.
3. **Loopback Stream Proxy (`127.0.0.1`)**: Route cloud and NAS streams through `CloudStreamProxy` bound strictly to `InternetAddress.loopbackIPv4` with HTTP `206 Partial Content` byte-range support and offline caching.
4. **Bandwidth-Safe Indexing**: Use `Range: bytes=0-65535` (64 KB) partial HTTP requests when parsing ID3v2 / FLAC tags from raw cloud files.
5. **Configurable Bitrate & Hi-Fi Lossless**: Respect `AudioQualityConfig` (`96 kbps Opus`, `128 kbps`, `192 kbps`, `320 kbps`, and `Hi-Fi Lossless 24-bit/192kHz`) across Wi-Fi, Cellular, and Offline Downloads, and expose the full audio chain in the Signal Path Sheet.
6. **Poweramp-Style 10-Band EQ & Native DSP**: Maintain the Kotlin `DynamicsProcessing` bridge (`com.freebeat.app/dsp`) supporting Preamp (`-15` to `+15 dB`), 10 ISO Graphic/Parametric bands (`31Hz`–`16kHz`), Rotary Bass/Treble/Stereo X knobs, DVC, Hardware Limiter, L/R Balance, Mono Mix, Tempo/Pitch, and Reverb.
7. **Google Pixel Material 3 Expressive UI**: Always use `Theme.of(context).colorScheme` tokens powered by `DynamicColorBuilder` (Wallpaper Monet) and Album Art palette extraction, alongside the animated `SquigglySlider` seekbar and expressive scalloped/morphing shapes.
