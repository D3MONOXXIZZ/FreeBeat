/// User-configurable audio streaming and download bitrate tiers, including Hi-Fi Lossless.
enum AudioQualityTier {
  dataSaver96(
    id: 'data_saver_96',
    label: 'Data Saver',
    subtitle: '96 kbps Opus • Ultra-low cellular data usage (~43 MB/hr)',
    kbps: 96,
    codec: 'OPUS',
    bitDepth: 16,
    sampleRateHz: 48000,
    isLossless: false,
  ),
  standard128(
    id: 'standard_128',
    label: 'Normal',
    subtitle: '128 kbps AAC/MP3 • Fast start on weak connections (~57 MB/hr)',
    kbps: 128,
    codec: 'AAC',
    bitDepth: 16,
    sampleRateHz: 44100,
    isLossless: false,
  ),
  high192(
    id: 'high_192',
    label: 'High',
    subtitle: '192 kbps AAC • Balanced clarity and bandwidth (~86 MB/hr)',
    kbps: 192,
    codec: 'AAC',
    bitDepth: 16,
    sampleRateHz: 48000,
    isLossless: false,
  ),
  extreme320(
    id: 'extreme_320',
    label: 'Extreme (320 kbps)',
    subtitle: '320 kbps MP3/AAC • Transparent mastering quality (~144 MB/hr)',
    kbps: 320,
    codec: 'MP3',
    bitDepth: 16,
    sampleRateHz: 48000,
    isLossless: false,
  ),
  hifiLossless(
    id: 'hifi_lossless',
    label: 'Hi-Fi Master / Lossless',
    subtitle: 'Bit-Perfect Direct Stream • Up to 24-bit / 192 kHz FLAC, ALAC & WAV',
    kbps: 0, // 0 indicates uncompressed/original source bitrate
    codec: 'FLAC',
    bitDepth: 24,
    sampleRateHz: 96000,
    isLossless: true,
  );

  const AudioQualityTier({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.kbps,
    required this.codec,
    required this.bitDepth,
    required this.sampleRateHz,
    required this.isLossless,
  });

  final String id;
  final String label;
  final String subtitle;
  final int kbps;
  final String codec;
  final int bitDepth;
  final int sampleRateHz;
  final bool isLossless;

  String get shortBadge =>
      isLossless ? 'HI-FI LOSSLESS' : '$kbps kbps $codec';

  static AudioQualityTier fromId(String id) {
    return AudioQualityTier.values.firstWhere(
      (e) => e.id == id,
      orElse: () => AudioQualityTier.hifiLossless,
    );
  }
}

/// Active audio output route & Bluetooth codec telemetry reported by Android AudioManager.
class AudioOutputRouteInfo {
  const AudioOutputRouteInfo({
    this.deviceName = 'Pixel Built-in Stereo Speakers',
    this.routeType = 'BUILTIN_SPEAKER',
    this.bluetoothCodecName = 'Direct PCM',
    this.hardwareSampleRateHz = 48000,
    this.hardwareBitDepth = 24,
    this.hardwareBufferFrames = 256,
    this.isBluetooth = false,
    this.isUsbDac = false,
    this.dspEngineMode = 'DynamicsProcessing 64-bit Hardware',
  });

  final String deviceName;
  final String routeType;
  final String bluetoothCodecName; // e.g., LDAC, aptX HD, aptX Adaptive, AAC, SBC, LC3, SSC
  final int hardwareSampleRateHz;
  final int hardwareBitDepth;
  final int hardwareBufferFrames;
  final bool isBluetooth;
  final bool isUsbDac;
  final String dspEngineMode;

  String get formattedSampleRate =>
      '${(hardwareSampleRateHz / 1000.0).toStringAsFixed(1)} kHz';

  factory AudioOutputRouteInfo.fromMap(Map<dynamic, dynamic> map) {
    return AudioOutputRouteInfo(
      deviceName: map['deviceName'] as String? ?? 'Android Audio Output',
      routeType: map['routeType'] as String? ?? 'SPEAKER',
      bluetoothCodecName: map['bluetoothCodecName'] as String? ?? 'PCM',
      hardwareSampleRateHz: map['hardwareSampleRateHz'] as int? ?? 48000,
      hardwareBitDepth: map['hardwareBitDepth'] as int? ?? 24,
      hardwareBufferFrames: map['hardwareBufferFrames'] as int? ?? 256,
      isBluetooth: map['isBluetooth'] as bool? ?? false,
      isUsbDac: map['isUsbDac'] as bool? ?? false,
      dspEngineMode:
          map['dspEngineMode'] as String? ?? 'DynamicsProcessing Hardware DSP',
    );
  }
}

class AudioQualityConfig {
  const AudioQualityConfig({
    this.wifiTier = AudioQualityTier.hifiLossless,
    this.cellularTier = AudioQualityTier.extreme320,
    this.offlineDownloadTier = AudioQualityTier.hifiLossless,
    this.activeOverrideTier,
    this.isOnCellularSimulated = false,
    this.enableHiResDirectOutput = true,
    this.enableGaplessPlayback = true,
    this.crossfadeDurationMs = 0,
    this.streamBufferSizeMb = 64,
    this.maxOfflineCacheGb = 10,
    this.bluetoothIspProtection = true,
    this.disableDvcOnBluetoothAbsoluteVolume = true,
  });

  final AudioQualityTier wifiTier;
  final AudioQualityTier cellularTier;
  final AudioQualityTier offlineDownloadTier;
  final AudioQualityTier? activeOverrideTier;
  final bool isOnCellularSimulated;
  final bool enableHiResDirectOutput;
  final bool enableGaplessPlayback;
  final int crossfadeDurationMs;
  final int streamBufferSizeMb;
  final int maxOfflineCacheGb;
  final bool bluetoothIspProtection;
  final bool disableDvcOnBluetoothAbsoluteVolume;

  AudioQualityTier get effectiveStreamingTier {
    if (activeOverrideTier != null) return activeOverrideTier!;
    return isOnCellularSimulated ? cellularTier : wifiTier;
  }

  AudioQualityConfig copyWith({
    AudioQualityTier? wifiTier,
    AudioQualityTier? cellularTier,
    AudioQualityTier? offlineDownloadTier,
    AudioQualityTier? activeOverrideTier,
    bool clearOverride = false,
    bool? isOnCellularSimulated,
    bool? enableHiResDirectOutput,
    bool? enableGaplessPlayback,
    int? crossfadeDurationMs,
    int? streamBufferSizeMb,
    int? maxOfflineCacheGb,
    bool? bluetoothIspProtection,
    bool? disableDvcOnBluetoothAbsoluteVolume,
  }) {
    return AudioQualityConfig(
      wifiTier: wifiTier ?? this.wifiTier,
      cellularTier: cellularTier ?? this.cellularTier,
      offlineDownloadTier: offlineDownloadTier ?? this.offlineDownloadTier,
      activeOverrideTier:
          clearOverride ? null : (activeOverrideTier ?? this.activeOverrideTier),
      isOnCellularSimulated:
          isOnCellularSimulated ?? this.isOnCellularSimulated,
      enableHiResDirectOutput:
          enableHiResDirectOutput ?? this.enableHiResDirectOutput,
      enableGaplessPlayback:
          enableGaplessPlayback ?? this.enableGaplessPlayback,
      crossfadeDurationMs: crossfadeDurationMs ?? this.crossfadeDurationMs,
      streamBufferSizeMb: streamBufferSizeMb ?? this.streamBufferSizeMb,
      maxOfflineCacheGb: maxOfflineCacheGb ?? this.maxOfflineCacheGb,
      bluetoothIspProtection:
          bluetoothIspProtection ?? this.bluetoothIspProtection,
      disableDvcOnBluetoothAbsoluteVolume:
          disableDvcOnBluetoothAbsoluteVolume ??
              this.disableDvcOnBluetoothAbsoluteVolume,
    );
  }
}
