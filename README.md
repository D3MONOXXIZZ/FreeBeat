# FreeBeat 🎵

**Pixel-Native Android Cloud Music Streaming App with Hi-Fi Lossless & Smart EQ 10-Band DSP (Built with Flutter)**

FreeBeat is a 100% client-side, serverless Android cloud music player that unifies user-owned music across **consumer clouds**, **self-hosted media servers**, **open protocols**, and **local NAS/SAF storage** inside an authentic **Google Pixel Material 3 Expressive (Material You)** interface.

---

## ✨ Key Capabilities

- **12 Unified Cloud & Media Server Integrations**:
  - **Consumer Clouds (OAuth2 PKCE)**: Google Drive, Microsoft OneDrive, Dropbox, Box
  - **Media Servers**: Jellyfin, Subsonic / Navidrome / OpenSubsonic
  - **Open Protocols**: WebDAV (Nextcloud / ownCloud / Synology), S3-Compatible (AWS S3, Cloudflare R2, Backblaze B2, MinIO via AWS SigV4)
  - **Network & Device**: SFTP / SSH NAS, SMB LAN Shares, Android Native Storage Access Framework (SAF), and a built-in **Pixel Demo Cloud Showcase**
- **User-Configurable Bitrate Tiers & Hi-Fi Lossless**:
  - Independent quality settings for **Wi-Fi**, **Mobile Data**, and **Offline Downloads**:
    - `Data Saver (96 kbps Opus)` • `Normal (128 kbps)` • `High (192 kbps)` • `Extreme (320 kbps)` • **`Hi-Fi Master / Lossless (Bit-Perfect up to 24-bit / 192 kHz FLAC, ALAC, WAV)`**
  - **Live Audio Signal Path Inspector**: Inspect the active chain (`Cloud Source → Codec/Bitrate → 64-bit DSP Engine → Android Hi-Res Output`) and switch streaming bitrates on the fly.
- **Smart EQ 10-Band EQ & Native Android DSP Studio**:
  - Powered by Android's hardware `DynamicsProcessing` API (`com.freebeat.app/dsp`):
  - **Preamp Fader (`-15 dB` to `+15 dB`)** + **10-Band ISO Graphic & Parametric Equalizer (`31Hz`–`16kHz`)** with an interactive frequency response spline curve.
  - **Tactile Rotary Knobs** for **Bass**, **Treble**, and **Stereo X (Mid/Side Width Expansion)**.
  - **Exact Numeric Tuning** for preamp and individual/all frequency bands (-15.0 to +15.0 dB).
  - **DVC (Direct Volume Control)**, **Hardware Auto-Limiter**, **L/R Channel Balance & Mono Mix**, **Tempo/Pitch Shifter**, **Crossfade (`0–12s`)**, **Room Reverb**, and **Audiophile Preset Hub** (11 built-in presets + custom curve import/export).
- **Smart Bandwidth & Synced Lyrics**:
  - Zero-download **HTTP Range (`bytes=0-65535`) ID3v2 & FLAC tag parser** + iTunes/MusicBrainz cover art enrichment.
  - Millisecond-accurate **Time-Synced Lyrics** via cloud `.lrc` sidecars, Jellyfin/Subsonic lyrics APIs, and **LRCLIB**.
- **Google Pixel Material 3 Expressive UI**:
  - **Wallpaper Monet (`dynamic_color`)** + **Album Art Dynamic Palette** theming.
  - Signature Android 13–15 animated **Squiggly Seekbar**, scalloped/cookie expressive badges, and morphing pill navigation.

---

## 📚 Project Documentation

- **[EXECUTION_DOCUMENTATION.md](./EXECUTION_DOCUMENTATION.md)** — Complete system architecture, cloud connector specifications, Hi-Fi & Smart EQ DSP pipeline, and the **6-Phase Execution Blueprint**.
- **[SETUP_AND_RULES.md](./SETUP_AND_RULES.md)** — Development environment setup, OAuth2 PKCE configuration, security policies, audio/DSP standards, and Pixel UI design rules.
- **[.agent/rules/freebeat-rules.md](./.agent/rules/freebeat-rules.md)** — Automated workspace rules for AI-assisted development.
