import 'dart:convert';
import 'dart:math' as math;

/// Standard ISO 10-band center frequencies used in Poweramp Graphic/Parametric EQ.
const List<double> kPoweramp10BandFrequencies = [
  31.0,
  62.0,
  125.0,
  250.0,
  500.0,
  1000.0,
  2000.0,
  4000.0,
  8000.0,
  16000.0,
];

class EqBandConfig {
  const EqBandConfig({
    required this.index,
    required this.frequencyHz,
    this.gainDb = 0.0,
    this.qFactor = 1.41,
  });

  final int index;
  final double frequencyHz;
  final double gainDb; // -15.0 dB to +15.0 dB
  final double qFactor; // 0.3 to 10.0

  String get frequencyLabel {
    if (frequencyHz >= 1000) {
      final k = frequencyHz / 1000.0;
      return k == k.roundToDouble() ? '${k.toInt()}k' : '${k.toStringAsFixed(1)}k';
    }
    return '${frequencyHz.toInt()}';
  }

  String get label => frequencyLabel;

  EqBandConfig copyWith({
    int? index,
    double? frequencyHz,
    double? gainDb,
    double? qFactor,
  }) {
    return EqBandConfig(
      index: index ?? this.index,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      gainDb: (gainDb ?? this.gainDb).clamp(-15.0, 15.0),
      qFactor: (qFactor ?? this.qFactor).clamp(0.3, 10.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'index': index,
        'frequencyHz': frequencyHz,
        'gainDb': gainDb,
        'qFactor': qFactor,
      };

  factory EqBandConfig.fromMap(Map<String, dynamic> map) => EqBandConfig(
        index: map['index'] as int? ?? 0,
        frequencyHz: (map['frequencyHz'] as num?)?.toDouble() ?? 1000.0,
        gainDb: (map['gainDb'] as num?)?.toDouble() ?? 0.0,
        qFactor: (map['qFactor'] as num?)?.toDouble() ?? 1.41,
      );
}

enum ReverbPresetType {
  none('Off', 0),
  smallRoom('Small Room', 1),
  mediumRoom('Medium Room', 2),
  largeRoom('Large Room', 3),
  mediumHall('Medium Hall', 4),
  largeHall('Large Hall', 5),
  plate('Studio Plate', 6);

  const ReverbPresetType(this.label, this.androidPresetId);
  final String label;
  final int androidPresetId;
}

enum VisualizerMode {
  spectrumBars('Spectrum Bars', 'Retro multi-band rainbow equalizer'),
  waveformRibbon('Waveform Ribbon', 'Fluid oscilloscope dynamic ribbon'),
  vinylPulse('Vinyl Pulse', 'Acoustic concentric soundwave ripples');

  const VisualizerMode(this.label, this.description);
  final String label;
  final String description;
}

enum Bs2bCrossfeedMode {
  off('Off', 'Stereo separation unaltered', 0),
  subtle('Subtle', 'Chu Moy 700 Hz / 4.5 dB crossfeed', 1),
  defaultMode('Default', 'Bauer BS2B 700 Hz / 6.0 dB standard', 2),
  aggressive('Nearfield', 'Studio Nearfield 650 Hz / 9.5 dB', 3);

  const Bs2bCrossfeedMode(this.label, this.description, this.level);
  final String label;
  final String description;
  final int level;
}

class DspPreset {
  const DspPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.preampDb,
    required this.bandGainsDb,
    this.bassTone = 0.0,
    this.trebleTone = 0.0,
    this.stereoExpansion = 0.0,
    this.isCustom = false,
    this.qFactors,
  });

  final String id;
  final String name;
  final String category;
  final double preampDb;
  final List<double> bandGainsDb; // 10 values (-15 to +15)
  final double bassTone;
  final double trebleTone;
  final double stereoExpansion;
  final bool isCustom;
  final List<double>? qFactors; // 10 Q factors (0.3 to 10.0)

  List<double> get effectiveQFactors =>
      qFactors ?? List<double>.filled(10, 1.41);

  String get shortName {
    if (id == 'flat') return 'Audiophile Flat';
    if (id == 'bass_boost') return 'Bass Boost';
    if (id == 'smart_eq_bass_treble' || id == 'poweramp_bass_treble') return 'Smart EQ';
    if (id == 'vocal' || id == 'vocal_clarity') return 'Vocal Air';
    if (id == 'concert' || id == 'concert_hall') return 'Concert Hall';
    if (id == 'rock' || id == 'rock_metal') return 'Rock & Metal';
    if (id == 'harman_target') return 'Harman Target';
    if (id == 'hifi_warm_tube') return 'Warm Tube';
    if (id == 'bass_extreme') return 'Sub-Bass Extreme';
    if (id == 'electronic_edm') return 'Club EDM';
    if (id == 'late_night') return 'Late Night';
    if (name.contains('/')) return name.split('/').first.trim();
    if (name.contains('(')) return name.split('(').first.trim();
    return name;
  }

  String get description =>
      '$category Preset • Preamp: ${preampDb >= 0 ? "+" : ""}${preampDb.toStringAsFixed(1)} dB';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'preampDb': preampDb,
        'bandGainsDb': bandGainsDb,
        'bassTone': bassTone,
        'trebleTone': trebleTone,
        'stereoExpansion': stereoExpansion,
        'isCustom': isCustom,
        'qFactors': effectiveQFactors,
      };

  factory DspPreset.fromMap(Map<String, dynamic> map) {
    final rawGains = (map['bandGainsDb'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    final rawQs = (map['qFactors'] as List<dynamic>?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    return DspPreset(
      id: map['id'] as String? ?? 'custom',
      name: map['name'] as String? ?? 'Custom Preset',
      category: map['category'] as String? ?? 'Custom',
      preampDb: (map['preampDb'] as num?)?.toDouble() ?? 0.0,
      bandGainsDb: rawGains.length == 10
          ? rawGains
          : List<double>.filled(10, 0.0),
      bassTone: (map['bassTone'] as num?)?.toDouble() ?? 0.0,
      trebleTone: (map['trebleTone'] as num?)?.toDouble() ?? 0.0,
      stereoExpansion: (map['stereoExpansion'] as num?)?.toDouble() ?? 0.0,
      isCustom: map['isCustom'] as bool? ?? true,
      qFactors: rawQs != null && rawQs.length == 10 ? rawQs : null,
    );
  }
}

/// Built-in audiophile & Smart EQ presets.
const List<DspPreset> kBuiltInDspPresets = [
  DspPreset(
    id: 'flat',
    name: 'Audiophile Flat / Bit-Perfect Reference',
    category: 'Audiophile',
    preampDb: 0.0,
    bandGainsDb: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
  ),
  DspPreset(
    id: 'bass_boost',
    name: 'Bass Boost (Punchy Low-End)',
    category: 'Bass',
    preampDb: -3.5,
    bandGainsDb: [7.0, 6.0, 4.0, 1.5, 0.0, 0.0, 0.0, 1.0, 2.0, 2.5],
    bassTone: 0.55,
    trebleTone: 0.15,
    stereoExpansion: 0.10,
  ),
  DspPreset(
    id: 'smart_eq_bass_treble',
    name: 'Smart EQ Bass & Treble',
    category: 'Signature',
    preampDb: -2.5,
    bandGainsDb: [6.5, 5.5, 3.0, 0.5, -1.0, -0.5, 1.5, 3.5, 5.0, 6.0],
    bassTone: 0.35,
    trebleTone: 0.28,
    stereoExpansion: 0.22,
  ),
  DspPreset(
    id: 'vocal',
    name: 'Vocal Air & Presence',
    category: 'Vocal',
    preampDb: -1.5,
    bandGainsDb: [-2.0, -1.0, 0.5, 2.5, 4.2, 4.8, 3.5, 2.0, 1.0, 0.5],
    trebleTone: 0.25,
  ),
  DspPreset(
    id: 'concert',
    name: 'Concert Hall / Spatial Reverb',
    category: 'Spatial',
    preampDb: -2.0,
    bandGainsDb: [2.0, 1.0, -0.5, -1.0, 0.0, 1.5, 3.0, 4.5, 5.0, 4.5],
    stereoExpansion: 0.45,
    trebleTone: 0.20,
  ),
  DspPreset(
    id: 'rock',
    name: 'Rock & Metal Studio',
    category: 'Genre',
    preampDb: -2.5,
    bandGainsDb: [5.0, 4.0, 2.5, -1.0, -1.5, 1.0, 3.5, 4.8, 5.0, 4.5],
    bassTone: 0.30,
    trebleTone: 0.35,
    stereoExpansion: 0.25,
  ),
  DspPreset(
    id: 'harman_target',
    name: 'Harman Target Curve 2026',
    category: 'Audiophile',
    preampDb: -3.0,
    bandGainsDb: [5.5, 4.8, 2.2, -0.5, -1.2, 0.0, 2.5, 3.8, 2.0, 1.0],
    bassTone: 0.20,
    trebleTone: 0.15,
  ),
  DspPreset(
    id: 'hifi_warm_tube',
    name: 'Hi-Fi Warm Tube Class-A',
    category: 'Audiophile',
    preampDb: -1.5,
    bandGainsDb: [2.5, 3.2, 2.8, 1.5, 0.5, -0.5, -1.2, 0.5, 1.8, 1.2],
    bassTone: 0.25,
    stereoExpansion: 0.30,
  ),
  DspPreset(
    id: 'bass_extreme',
    name: 'Sub-Bass Extreme + Limiter',
    category: 'Bass',
    preampDb: -4.5,
    bandGainsDb: [9.5, 8.0, 5.0, 1.5, -1.0, -1.0, 0.5, 2.0, 3.0, 3.5],
    bassTone: 0.65,
    trebleTone: 0.20,
  ),
  DspPreset(
    id: 'electronic_edm',
    name: 'Electronic / Festival Club',
    category: 'Genre',
    preampDb: -3.0,
    bandGainsDb: [7.0, 6.0, 2.5, -1.5, -2.0, 0.0, 2.0, 4.5, 5.5, 6.5],
    bassTone: 0.45,
    trebleTone: 0.35,
    stereoExpansion: 0.40,
  ),
  DspPreset(
    id: 'late_night',
    name: 'Late Night Loudness Contour',
    category: 'Utility',
    preampDb: -2.0,
    bandGainsDb: [4.8, 3.5, 1.0, -0.5, -1.0, 0.5, 2.0, 3.5, 4.5, 5.0],
    bassTone: 0.30,
    trebleTone: 0.25,
  ),
];

class PowerampDspState {
  const PowerampDspState({
    this.eqEnabled = true,
    this.toneEnabled = true,
    this.limiterEnabled = true,
    this.dvcEnabled = true,
    this.isParametricMode = false,
    this.preampDb = 0.0,
    required this.bands,
    this.bassGain = 0.0,
    this.bassFreqHz = 85.0,
    this.trebleGain = 0.0,
    this.trebleFreqHz = 10000.0,
    this.stereoExpansion = 0.0,
    this.balance = 0.0,
    this.monoMix = false,
    this.tempo = 1.0,
    this.pitchSemitones = 0.0,
    this.reverbPreset = ReverbPresetType.none,
    this.reverbMix = 0.0,
    this.activePresetId = 'flat',
    this.visualizerMode = VisualizerMode.spectrumBars,
    this.bs2bCrossfeedMode = Bs2bCrossfeedMode.off,
    this.dvcHeadroomDb = -3.0,
    this.bitPerfectDirectMode = false,
    this.deviceProfiles = const {
      'BLUETOOTH': 'harman_target',
      'USB_DAC': 'flat',
      'WIRED_HEADPHONES': 'hifi_warm_tube',
      'BUILTIN_SPEAKER': 'vocal',
    },
  });

  final bool eqEnabled;
  final bool toneEnabled;
  final bool limiterEnabled;
  final bool dvcEnabled;
  final bool isParametricMode;
  final double preampDb; // -15.0 to +15.0 dB
  final List<EqBandConfig> bands; // 10 bands
  final double bassGain; // 0.0 to 1.0 (maps to 0 to +12 dB low shelf)
  final double bassFreqHz; // 40 to 150 Hz
  final double trebleGain; // 0.0 to 1.0 (maps to 0 to +12 dB high shelf)
  final double trebleFreqHz; // 6000 to 16000 Hz
  final double stereoExpansion; // 0.0 to 1.0 (Stereo X)
  final double balance; // -1.0 (L) to +1.0 (R)
  final bool monoMix;
  final double tempo; // 0.5x to 2.0x
  final double pitchSemitones; // -12.0 to +12.0
  final ReverbPresetType reverbPreset;
  final double reverbMix; // 0.0 to 1.0
  final String activePresetId;
  final VisualizerMode visualizerMode;
  final Bs2bCrossfeedMode bs2bCrossfeedMode;
  final double dvcHeadroomDb; // -6.0 to 0.0 dB
  final bool bitPerfectDirectMode;
  final Map<String, String> deviceProfiles;

  double get toneFrequencyHz => bassFreqHz;
  double get bassGainDb => (bassGain * 20.0) - 10.0;
  double get trebleGainDb => (trebleGain * 20.0) - 10.0;
  double get stereoXAmount => stereoExpansion;

  factory PowerampDspState.initial() {
    final preset = kBuiltInDspPresets[0]; // Flat / Bit-Perfect Reference
    return PowerampDspState(
      preampDb: preset.preampDb,
      bands: List.generate(
        kPoweramp10BandFrequencies.length,
        (i) => EqBandConfig(
          index: i,
          frequencyHz: kPoweramp10BandFrequencies[i],
          gainDb: preset.bandGainsDb[i],
        ),
      ),
      bassGain: preset.bassTone,
      trebleGain: preset.trebleTone,
      stereoExpansion: preset.stereoExpansion,
      activePresetId: preset.id,
      visualizerMode: VisualizerMode.spectrumBars,
      bs2bCrossfeedMode: Bs2bCrossfeedMode.off,
      dvcHeadroomDb: -3.0,
      bitPerfectDirectMode: false,
    );
  }

  /// Calculates the combined frequency response in dB at any frequency `freqHz` (20Hz - 20kHz)
  /// combining Preamp + 10 Parametric/Graphic Biquad Bell filters + Bass/Treble Shelves.
  double evaluateResponseAtFrequency(double freqHz) {
    if (bitPerfectDirectMode) return 0.0;
    double totalDb = eqEnabled ? preampDb : 0.0;
    final logF = math.log(freqHz) / math.ln10;

    if (eqEnabled) {
      for (final band in bands) {
        if (band.gainDb.abs() < 0.01) continue;
        final logCenter = math.log(band.frequencyHz) / math.ln10;
        final octaveDistance = (logF - logCenter) / 0.30103; // log10(2)
        final bandwidth = 1.0 / (band.qFactor * 0.65);
        final influence =
            math.exp(-(octaveDistance * octaveDistance) / (2 * bandwidth * bandwidth));
        totalDb += band.gainDb * influence;
      }
    }

    if (toneEnabled) {
      // Low-shelf Bass contribution
      if (bassGain > 0.005) {
        final bassMaxDb = bassGain * 12.0;
        final ratio = freqHz / bassFreqHz;
        final shelf = 1.0 / (1.0 + math.pow(ratio, 2.2));
        totalDb += bassMaxDb * shelf;
      }
      // High-shelf Treble contribution
      if (trebleGain > 0.005) {
        final trebleMaxDb = trebleGain * 12.0;
        final ratio = trebleFreqHz / freqHz;
        final shelf = 1.0 / (1.0 + math.pow(ratio, 2.2));
        totalDb += trebleMaxDb * shelf;
      }
    }

    return totalDb.clamp(-24.0, 24.0);
  }

  /// Peak gain across the spectrum to detect potential clipping if Limiter/DVC is off.
  double get maxPeakDb {
    if (bitPerfectDirectMode) return 0.0;
    double peak = -24.0;
    for (final f in kPoweramp10BandFrequencies) {
      final val = evaluateResponseAtFrequency(f);
      if (val > peak) peak = val;
    }
    return peak;
  }

  bool get isClippingRisk => !bitPerfectDirectMode && !limiterEnabled && maxPeakDb > 0.5;

  PowerampDspState copyWith({
    bool? eqEnabled,
    bool? toneEnabled,
    bool? limiterEnabled,
    bool? dvcEnabled,
    bool? isParametricMode,
    double? preampDb,
    List<EqBandConfig>? bands,
    double? bassGain,
    double? bassFreqHz,
    double? trebleGain,
    double? trebleFreqHz,
    double? stereoExpansion,
    double? balance,
    bool? monoMix,
    double? tempo,
    double? pitchSemitones,
    ReverbPresetType? reverbPreset,
    double? reverbMix,
    String? activePresetId,
    VisualizerMode? visualizerMode,
    Bs2bCrossfeedMode? bs2bCrossfeedMode,
    double? dvcHeadroomDb,
    bool? bitPerfectDirectMode,
    Map<String, String>? deviceProfiles,
  }) {
    return PowerampDspState(
      eqEnabled: eqEnabled ?? this.eqEnabled,
      toneEnabled: toneEnabled ?? this.toneEnabled,
      limiterEnabled: limiterEnabled ?? this.limiterEnabled,
      dvcEnabled: dvcEnabled ?? this.dvcEnabled,
      isParametricMode: isParametricMode ?? this.isParametricMode,
      preampDb: (preampDb ?? this.preampDb).clamp(-15.0, 15.0),
      bands: bands ?? this.bands,
      bassGain: (bassGain ?? this.bassGain).clamp(0.0, 1.0),
      bassFreqHz: (bassFreqHz ?? this.bassFreqHz).clamp(40.0, 150.0),
      trebleGain: (trebleGain ?? this.trebleGain).clamp(0.0, 1.0),
      trebleFreqHz: (trebleFreqHz ?? this.trebleFreqHz).clamp(6000.0, 16000.0),
      stereoExpansion: (stereoExpansion ?? this.stereoExpansion).clamp(0.0, 1.0),
      balance: (balance ?? this.balance).clamp(-1.0, 1.0),
      monoMix: monoMix ?? this.monoMix,
      tempo: (tempo ?? this.tempo).clamp(0.5, 2.0),
      pitchSemitones: (pitchSemitones ?? this.pitchSemitones).clamp(-12.0, 12.0),
      reverbPreset: reverbPreset ?? this.reverbPreset,
      reverbMix: (reverbMix ?? this.reverbMix).clamp(0.0, 1.0),
      activePresetId: activePresetId ?? this.activePresetId,
      visualizerMode: visualizerMode ?? this.visualizerMode,
      bs2bCrossfeedMode: bs2bCrossfeedMode ?? this.bs2bCrossfeedMode,
      dvcHeadroomDb: (dvcHeadroomDb ?? this.dvcHeadroomDb).clamp(-6.0, 0.0),
      bitPerfectDirectMode: bitPerfectDirectMode ?? this.bitPerfectDirectMode,
      deviceProfiles: deviceProfiles ?? this.deviceProfiles,
    );
  }

  Map<String, dynamic> toMap() => {
        'eqEnabled': eqEnabled,
        'toneEnabled': toneEnabled,
        'limiterEnabled': limiterEnabled,
        'dvcEnabled': dvcEnabled,
        'isParametricMode': isParametricMode,
        'preampDb': preampDb,
        'bands': bands.map((b) => b.toMap()).toList(),
        'bassGain': bassGain,
        'bassFreqHz': bassFreqHz,
        'trebleGain': trebleGain,
        'trebleFreqHz': trebleFreqHz,
        'stereoExpansion': stereoExpansion,
        'balance': balance,
        'monoMix': monoMix,
        'tempo': tempo,
        'pitchSemitones': pitchSemitones,
        'reverbPreset': reverbPreset.name,
        'reverbMix': reverbMix,
        'activePresetId': activePresetId,
        'visualizerMode': visualizerMode.name,
        'bs2bCrossfeedMode': bs2bCrossfeedMode.name,
        'dvcHeadroomDb': dvcHeadroomDb,
        'bitPerfectDirectMode': bitPerfectDirectMode,
        'deviceProfiles': deviceProfiles,
      };

  String toJsonString() => jsonEncode(toMap());

  factory PowerampDspState.fromMap(Map<String, dynamic> map) {
    final rawBands = (map['bands'] as List<dynamic>? ?? [])
        .map((e) => EqBandConfig.fromMap(e as Map<String, dynamic>))
        .toList();
    final rawProfiles = (map['deviceProfiles'] as Map<String, dynamic>?)?.map(
          (k, v) {
            String val = v.toString();
            if (val == 'vocal_clarity') val = 'vocal';
            if (val == 'poweramp_bass_treble') val = 'smart_eq_bass_treble';
            if (val == 'concert_hall') val = 'concert';
            if (val == 'rock_metal') val = 'rock';
            if (val == 'bass') val = 'bass_boost';
            if (val == 'audiophile_warmth') val = 'warm';
            return MapEntry(k, val);
          },
        ) ??
        const {
          'BLUETOOTH': 'harman_target',
          'USB_DAC': 'flat',
          'WIRED_HEADPHONES': 'hifi_warm_tube',
          'BUILTIN_SPEAKER': 'vocal',
        };

    String activePreset = map['activePresetId'] as String? ?? 'custom';
    if (activePreset == 'vocal_clarity') activePreset = 'vocal';
    if (activePreset == 'poweramp_bass_treble') activePreset = 'smart_eq_bass_treble';
    if (activePreset == 'concert_hall') activePreset = 'concert';
    if (activePreset == 'rock_metal') activePreset = 'rock';
    if (activePreset == 'bass') activePreset = 'bass_boost';
    if (activePreset == 'audiophile_warmth') activePreset = 'warm';

    return PowerampDspState(
      eqEnabled: map['eqEnabled'] as bool? ?? true,
      toneEnabled: map['toneEnabled'] as bool? ?? true,
      limiterEnabled: map['limiterEnabled'] as bool? ?? true,
      dvcEnabled: map['dvcEnabled'] as bool? ?? true,
      isParametricMode: map['isParametricMode'] as bool? ?? false,
      preampDb: (map['preampDb'] as num?)?.toDouble() ?? 0.0,
      bands: rawBands.length == 10
          ? rawBands
          : PowerampDspState.initial().bands,
      bassGain: (map['bassGain'] as num?)?.toDouble() ?? 0.0,
      bassFreqHz: (map['bassFreqHz'] as num?)?.toDouble() ?? 85.0,
      trebleGain: (map['trebleGain'] as num?)?.toDouble() ?? 0.0,
      trebleFreqHz: (map['trebleFreqHz'] as num?)?.toDouble() ?? 10000.0,
      stereoExpansion: (map['stereoExpansion'] as num?)?.toDouble() ?? 0.0,
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      monoMix: map['monoMix'] as bool? ?? false,
      tempo: (map['tempo'] as num?)?.toDouble() ?? 1.0,
      pitchSemitones: (map['pitchSemitones'] as num?)?.toDouble() ?? 0.0,
      reverbPreset: ReverbPresetType.values.firstWhere(
        (r) => r.name == map['reverbPreset'],
        orElse: () => ReverbPresetType.none,
      ),
      reverbMix: (map['reverbMix'] as num?)?.toDouble() ?? 0.0,
      activePresetId: activePreset,
      visualizerMode: VisualizerMode.values.firstWhere(
        (v) => v.name == map['visualizerMode'],
        orElse: () => VisualizerMode.spectrumBars,
      ),
      bs2bCrossfeedMode: Bs2bCrossfeedMode.values.firstWhere(
        (v) => v.name == map['bs2bCrossfeedMode'],
        orElse: () => Bs2bCrossfeedMode.off,
      ),
      dvcHeadroomDb: (map['dvcHeadroomDb'] as num?)?.toDouble() ?? -3.0,
      bitPerfectDirectMode: map['bitPerfectDirectMode'] as bool? ?? false,
      deviceProfiles: rawProfiles,
    );
  }

  factory PowerampDspState.fromJsonString(String jsonStr) {
    return PowerampDspState.fromMap(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }
}

/// Smart EQ Type Aliases & Frequency Constants
const List<double> kSmartEq10BandFrequencies = kPoweramp10BandFrequencies;
typedef SmartEqState = PowerampDspState;
typedef SmartEqBandConfig = EqBandConfig;

