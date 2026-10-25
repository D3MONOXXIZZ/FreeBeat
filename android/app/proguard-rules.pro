# Flutter Core & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Play Core (deferred components not used in standalone app)
-dontwarn com.google.android.play.core.**

# FreeBeat Native Classes
-keep class com.freebeat.freebeat.** { *; }
-keep class com.freebeat.freebeat.FreeBeatPlaybackService { *; }
-keep class com.freebeat.freebeat.MainActivity { *; }

# Android Media & Architecture Components
-keep class androidx.media.** { *; }
-keep class androidx.media.session.** { *; }
-keep class androidx.core.app.NotificationCompat** { *; }
-dontwarn androidx.media.**
-dontwarn androidx.core.**
-keep class android.media.audiofx.** { *; }

# ExoPlayer & JustAudio
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-keep class com.ryanheise.just_audio.** { *; }
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**

# FFmpegKit Audio Engine
-keep class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**

# Google Sign-In & Auth
-keep class com.google.android.gms.auth.api.signin.** { *; }
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Flutter Secure Storage & Crypto
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn javax.crypto.**

# File Picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Keep native JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}
