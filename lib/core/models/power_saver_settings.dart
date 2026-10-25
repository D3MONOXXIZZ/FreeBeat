import 'dart:convert';

/// User-configurable power saver options to reduce battery consumption
/// during background audio playback and foreground UI usage.
class PowerSaverSettings {
  const PowerSaverSettings({
    this.isEnabled = false,
    this.autoOnSystemSaver = true,
    this.autoBelowBatteryPercent = 20,
    this.amoledPitchBlack = true,
    this.disableBlurAndAura = true,
    this.pauseVisualizers = true,
    this.capRefreshRate60Hz = true,
    this.smartWifiLock = true,
    this.reducePreloadCount = true,
    this.disableHaptics = true,
    this.throttleBackgroundTicks = true,
  });

  /// Master manual toggle to force Power Saver mode on or off.
  final bool isEnabled;

  /// Automatically activate Power Saver mode whenever Android's system battery saver is on.
  final bool autoOnSystemSaver;

  /// Automatically activate when battery drops below this percentage (0 = disabled).
  final int autoBelowBatteryPercent;

  /// Use pure #000000 pitch-black surfaces in dark theme to turn off OLED/AMOLED pixels.
  final bool amoledPitchBlack;

  /// Disable 38-sigma Gaussian blur shader and dynamic aura animations on Now Playing screen.
  final bool disableBlurAndAura;

  /// Pause 60/120fps animated spectrum waves on Equalizer screen (retains static EQ curve).
  final bool pauseVisualizers;

  /// Cap screen refresh rate to 60Hz via Android window attributes (saves ~30% display power).
  final bool capRefreshRate60Hz;

  /// Drop Wi-Fi lock completely when playing locally cached/offline tracks.
  final bool smartWifiLock;

  /// Preload only 1 track instead of 5 in background queue (saves 80% radio/network power).
  final bool reducePreloadCount;

  /// Suppress continuous haptic micro-ticks on sliders and knobs to prevent current spikes.
  final bool disableHaptics;

  /// Throttle Riverpod playback position stream updates to 1000ms.
  final bool throttleBackgroundTicks;

  PowerSaverSettings copyWith({
    bool? isEnabled,
    bool? autoOnSystemSaver,
    int? autoBelowBatteryPercent,
    bool? amoledPitchBlack,
    bool? disableBlurAndAura,
    bool? pauseVisualizers,
    bool? capRefreshRate60Hz,
    bool? smartWifiLock,
    bool? reducePreloadCount,
    bool? disableHaptics,
    bool? throttleBackgroundTicks,
  }) {
    return PowerSaverSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      autoOnSystemSaver: autoOnSystemSaver ?? this.autoOnSystemSaver,
      autoBelowBatteryPercent:
          autoBelowBatteryPercent ?? this.autoBelowBatteryPercent,
      amoledPitchBlack: amoledPitchBlack ?? this.amoledPitchBlack,
      disableBlurAndAura: disableBlurAndAura ?? this.disableBlurAndAura,
      pauseVisualizers: pauseVisualizers ?? this.pauseVisualizers,
      capRefreshRate60Hz: capRefreshRate60Hz ?? this.capRefreshRate60Hz,
      smartWifiLock: smartWifiLock ?? this.smartWifiLock,
      reducePreloadCount: reducePreloadCount ?? this.reducePreloadCount,
      disableHaptics: disableHaptics ?? this.disableHaptics,
      throttleBackgroundTicks:
          throttleBackgroundTicks ?? this.throttleBackgroundTicks,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isEnabled': isEnabled,
      'autoOnSystemSaver': autoOnSystemSaver,
      'autoBelowBatteryPercent': autoBelowBatteryPercent,
      'amoledPitchBlack': amoledPitchBlack,
      'disableBlurAndAura': disableBlurAndAura,
      'pauseVisualizers': pauseVisualizers,
      'capRefreshRate60Hz': capRefreshRate60Hz,
      'smartWifiLock': smartWifiLock,
      'reducePreloadCount': reducePreloadCount,
      'disableHaptics': disableHaptics,
      'throttleBackgroundTicks': throttleBackgroundTicks,
    };
  }

  factory PowerSaverSettings.fromMap(Map<String, dynamic> map) {
    return PowerSaverSettings(
      isEnabled: map['isEnabled'] as bool? ?? false,
      autoOnSystemSaver: map['autoOnSystemSaver'] as bool? ?? true,
      autoBelowBatteryPercent: map['autoBelowBatteryPercent'] as int? ?? 20,
      amoledPitchBlack: map['amoledPitchBlack'] as bool? ?? true,
      disableBlurAndAura: map['disableBlurAndAura'] as bool? ?? true,
      pauseVisualizers: map['pauseVisualizers'] as bool? ?? true,
      capRefreshRate60Hz: map['capRefreshRate60Hz'] as bool? ?? true,
      smartWifiLock: map['smartWifiLock'] as bool? ?? true,
      reducePreloadCount: map['reducePreloadCount'] as bool? ?? true,
      disableHaptics: map['disableHaptics'] as bool? ?? true,
      throttleBackgroundTicks: map['throttleBackgroundTicks'] as bool? ?? true,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PowerSaverSettings.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return PowerSaverSettings.fromMap(decoded);
      }
    } catch (_) {}
    return const PowerSaverSettings();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PowerSaverSettings &&
        other.isEnabled == isEnabled &&
        other.autoOnSystemSaver == autoOnSystemSaver &&
        other.autoBelowBatteryPercent == autoBelowBatteryPercent &&
        other.amoledPitchBlack == amoledPitchBlack &&
        other.disableBlurAndAura == disableBlurAndAura &&
        other.pauseVisualizers == pauseVisualizers &&
        other.capRefreshRate60Hz == capRefreshRate60Hz &&
        other.smartWifiLock == smartWifiLock &&
        other.reducePreloadCount == reducePreloadCount &&
        other.disableHaptics == disableHaptics &&
        other.throttleBackgroundTicks == throttleBackgroundTicks;
  }

  @override
  int get hashCode => Object.hash(
        isEnabled,
        autoOnSystemSaver,
        autoBelowBatteryPercent,
        amoledPitchBlack,
        disableBlurAndAura,
        pauseVisualizers,
        capRefreshRate60Hz,
        smartWifiLock,
        reducePreloadCount,
        disableHaptics,
        throttleBackgroundTicks,
      );
}

/// Snapshot of the host device's battery and system power-saver state.
class DeviceBatteryStatus {
  const DeviceBatteryStatus({
    this.batteryLevel = 100,
    this.isCharging = false,
    this.isPowerSaveMode = false,
    this.isIgnoringBatteryOptimizations = true,
  });

  final int batteryLevel; // 0 to 100
  final bool isCharging;
  final bool isPowerSaveMode;
  final bool isIgnoringBatteryOptimizations;

  DeviceBatteryStatus copyWith({
    int? batteryLevel,
    bool? isCharging,
    bool? isPowerSaveMode,
    bool? isIgnoringBatteryOptimizations,
  }) {
    return DeviceBatteryStatus(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      isPowerSaveMode: isPowerSaveMode ?? this.isPowerSaveMode,
      isIgnoringBatteryOptimizations:
          isIgnoringBatteryOptimizations ?? this.isIgnoringBatteryOptimizations,
    );
  }
}
