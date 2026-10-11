# FreeBeat — Environment Setup Guide & Engineering Rules

This document defines the mandatory setup instructions, architectural constraints, security policies, audio/DSP engineering standards, and Google Pixel Material 3 Expressive UI rules for **FreeBeat**.

---

## 1. Development Environment & Toolchain Setup

### 1.1 Required SDKs & Versions
- **Flutter SDK**: `>= 3.24.0` (Stable channel, Dart `>= 3.5.0`)
- **Android SDK**:
  - `compileSdkVersion`: `35` (Android 15)
  - `targetSdkVersion`: `35`
  - `minSdkVersion`: `28` (Android 9 Pie — required for native hardware `android.media.audiofx.DynamicsProcessing` 10-Band EQ, Preamp, MBC, and Limiter APIs)
- **JDK / Kotlin**: Java `17`, Kotlin `>= 1.9.22`

### 1.2 Initial Project Setup Commands
```powershell
# Verify Flutter & Android toolchain
flutter doctor -v

# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Execute unit & widget tests
flutter test

# Run on connected Pixel / Android device or emulator
flutter run
```

---

## 2. Cloud Provider & OAuth2 Setup Rules

### 2.1 Custom Redirect URI Scheme
All OAuth2 PKCE consumer cloud flows MUST use the unified Android custom scheme registered in `AndroidManifest.xml`:
```text
com.freebeat.app://oauth2redirect
```

### 2.2 Per-Provider Scope & Endpoint Rules
1. **Google Drive (OAuth2 PKCE)**:
   - Scope: `https://www.googleapis.com/auth/drive.readonly`
   - Supports user-supplied Custom Client ID or direct Bearer Token in the Add Account sheet for zero-backend self-hosting.
2. **Microsoft OneDrive (MS Graph OAuth2 PKCE)**:
   - Scope: `Files.Read offline_access User.Read`
3. **Dropbox (OAuth2 PKCE)**:
   - Scope: `files.metadata.read files.content.read`
4. **Box (OAuth2 PKCE)**:
   - Scope: `root_readwrite` (or read-only file access)
5. **Jellyfin Media Server**:
   - Auth Header: `X-Emby-Authorization: MediaBrowser Client="FreeBeat", Device="Android", DeviceId="<uuid>", Version="1.0.0"`
   - Must support both **Direct Play (`static=true`)** for Hi-Fi Lossless and **Universal Transcoding (`maxStreamingBitrate`)** for cellular bitrate caps.
6. **Subsonic / Navidrome / OpenSubsonic**:
   - Must authenticate using salted MD5 tokens (`t = md5(password + salt)`, `s = salt`, `v = 1.16.1`, `c = FreeBeat`, `f = json`) — never send plaintext passwords in query strings.
7. **WebDAV (Nextcloud / ownCloud / Synology)**:
   - Use App Passwords with HTTPS Basic Auth and `Depth: 1` iterative `PROPFIND` requests to avoid server timeouts on large music libraries.
8. **S3-Compatible Storage (AWS S3 / Cloudflare R2 / Backblaze B2 / MinIO)**:
   - Must sign all object listing and streaming URLs locally using **AWS Signature Version 4 (HMAC-SHA256)** in pure Dart.

---

## 3. Core Architectural & Security Rules

### Rule A1 — 100% Client-Side Serverless Mandate
- FreeBeat MUST NOT depend on any proprietary backend server to proxy user credentials, index files, or transcode audio.
- All cloud communication occurs directly between the user's Android device and their chosen cloud provider or self-hosted server.

### Rule A2 — Zero Plaintext Credentials
- OAuth access tokens, refresh tokens, WebDAV passwords, S3 secret keys, SFTP private keys, and Subsonic salts MUST ONLY be stored in `SecureCredentialStore` (`flutter_secure_storage` backed by Android Hardware Keystore `EncryptedSharedPreferences`).
- SQLite (`LibraryDatabase`) may store non-sensitive `CloudAccount` metadata (display name, provider type, endpoint URL, username) but **NEVER** passwords or tokens.

### Rule A3 — Loopback Proxy Streaming (`127.0.0.1`)
- All cloud and NAS playback requests MUST route through `CloudStreamProxy` (`http://127.0.0.1:<port>/stream/<trackId>`) before reaching `just_audio` (`ExoPlayer`).
- `CloudStreamProxy` MUST bind strictly to `InternetAddress.loopbackIPv4` (`127.0.0.1`) so no other device on the LAN can access the local stream endpoint.
- `CloudStreamProxy` MUST forward `Range` headers and return `206 Partial Content` with accurate `Content-Range` and `Accept-Ranges: bytes` headers so scrubbing/seeking is instantaneous.

### Rule A4 — Bandwidth-Safe Metadata Indexing
- When indexing raw cloud storage (Google Drive, OneDrive, Dropbox, Box, WebDAV, S3, SFTP, SMB), the indexer MUST NOT download entire audio files.
- `RangeTagParser` MUST cap tag inspection requests to `Range: bytes=0-65535` (first 64 KB) to extract ID3v2 / FLAC `STREAMINFO` & `VORBIS_COMMENT` headers.

---

## 4. Audio Quality, Hi-Fi & Poweramp DSP Rules

### Rule D1 — Bitrate Tier Enforcement
- Playback and download resolution MUST always honor `AudioQualityConfig`:
  - `wifiTier` when on Wi-Fi / Ethernet.
  - `cellularTier` when on Mobile Data.
  - `offlineDownloadTier` when pinning tracks to local storage.
- Switching the bitrate tier inside the **Signal Path Sheet** during playback MUST seamlessly reload the stream at the current playback position (`player.position`) without losing queue state.

### Rule D2 — Native `DynamicsProcessing` 10-Band EQ & Preamp Integrity
- The native Kotlin DSP bridge (`MainActivity.kt`) MUST attach `DynamicsProcessing` to the active ExoPlayer `audioSessionId` as soon as a valid session ID (`> 0`) is emitted.
- **Preamp + 10-Band EQ + Rotary Tone Coexistence**:
  - Band center frequencies are fixed at ISO octaves by default (`31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz`), overridable in Parametric mode.
  - When `DVC (Direct Volume Control)` is active, negative headroom attenuation is applied automatically if peak band boost exceeds `0.0 dBFS`.
  - When `Limiter` is enabled, the hardware output limiter MUST engage at `-0.2 dB` threshold with a `1 ms` attack to guarantee zero digital clipping even at `+15 dB` Preamp/Bass settings.

### Rule D3 — Zero-Stutter Real-Time Fader & Knob Updates
- Dragging the Preamp slider, any of the 10 EQ faders, or the Rotary Bass/Treble/Stereo X knobs MUST update both the UI spline curve at 60/120fps and the native `MethodChannel` without re-initializing the `DynamicsProcessing` instance or interrupting audio playback.

---

## 5. Google Pixel Material 3 Expressive UI Rules

### Rule U1 — Dynamic Color Token Enforcement
- **NEVER** hardcode static hex background or accent colors for screens, cards, or navigation bars.
- Always derive colors from `Theme.of(context).colorScheme` (`surface`, `surfaceContainerLow`, `surfaceContainerHigh`, `primary`, `secondaryContainer`, `tertiaryContainer`), which automatically adapts to:
  1. The user's **Google Pixel Wallpaper Monet Palette** (`DynamicColorBuilder`).
  2. The **Active Track's Album Art Palette** on the Now Playing screen, MiniPlayer, and Poweramp DSP Studio.

### Rule U2 — Signature Pixel Components
- **Squiggly Seekbar (`SquigglySlider`)**: Must be used on the Now Playing screen. Wave amplitude must animate smoothly between playing (`4.5 dp`) and paused/scrubbing (`0.0 dp`).
- **Expressive Shapes**: Featured cards and badges must use Pixel Material 3 Expressive radii (`24dp`–`32dp`), scalloped/cookie clippers, and morphing pill buttons.
- **Haptic Feedback**: Every rotary knob tick, EQ fader center-detent (`0.0 dB`) snap, and play/pause toggle must trigger subtle native Android haptics (`HapticFeedback.selectionClick()` or `lightImpact()`).

---

## 6. Phase Execution & Git Workflow Rules

1. **Sequential Phase Execution**: Execute Phases 1 through 6 in order as documented in [EXECUTION_DOCUMENTATION.md](file:///f:/FreeBeat/EXECUTION_DOCUMENTATION.md).
2. **Continuous Verification**: Run `flutter analyze` after completing each phase to catch type or lint issues immediately.
3. **Commit Convention**: Use clean Conventional Commits (`docs:`, `feat(core):`, `feat(providers):`, `feat(dsp):`, `feat(ui):`, `test:`) and push completed milestones to the private GitHub repository.


---

## 7. Universal Android Compatibility, Bluetooth Codec & Bottleneck Rules

### Rule B1 — Universal Android Coverage (`minSdkVersion = 24`) & Dual-Tier DSP Fallback
- `minSdkVersion` MUST be set to **`24` (Android 7.0)** (`compileSdk = 35`, `targetSdk = 35`) to support 99.6%+ of Android devices.
- `MainActivity.kt` MUST implement a **Dual-Tier Hardware DSP Engine**:
  1. **Primary (API 28+ `DynamicsProcessing`)**: Hardware 10-band Pre-EQ, Post-EQ, Preamp, MBC, and Limiter.
  2. **Fallback (API 24–27 or OEM firmware restriction)**: Automatic catch-and-fallback to Android `Equalizer` + `LoudnessEnhancer` + `BassBoost` + `Virtualizer`, interpolating the 10-band spline gains onto the available hardware bands so DSP never crashes on any Samsung, Xiaomi, OnePlus, Sony, or Motorola device.

### Rule B2 — Universal Bluetooth Codec & Per-Output Route Handling
- Must support all Bluetooth audio codecs transparently (**SBC, AAC, aptX, aptX HD, aptX Adaptive, aptX Lossless, LDAC, LHDC/LLAC, Samsung SSC, and BLE Audio LC3**).
- Register `AudioDeviceCallback` in `MainActivity.kt` to detect active output device (`Bluetooth A2DP`, `BLE Audio`, `USB-C DAC`, `Wired Headphones`, `Speaker`), device name, hardware sample rates, and bit-depth encodings.
- **Bluetooth Inter-Sample Peak Protection**: Automatically clamp the hardware limiter ceiling to **`-0.5 dBFS`** when streaming over Bluetooth to prevent resampler/encoder clipping on 24-bit/192kHz tracks.
- **Per-Output DSP Profiles & Absolute Volume Protection**: Support automatic EQ preset switching per audio output type and provide a **"Disable DVC on Bluetooth Absolute Volume"** toggle.

### Rule B3 — Cloud API Rate-Limit & Hi-Fi Seek Bottleneck Prevention
- **Two-Pass Indexing**: Never fire unbounded parallel `Range` requests during library scans. Use bulk directory listing first, followed by a max-3-concurrent token-bucket queue with HTTP `429` exponential backoff for `bytes=0-65535` tag inspection.
- **Mid-Stream Token Refresh**: `CloudStreamProxy` must transparently refresh expired OAuth2 tokens or re-sign S3 SigV4 URLs on incoming `Range` requests so paused streams never fail after 1 hour.
