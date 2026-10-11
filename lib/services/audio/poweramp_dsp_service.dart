import 'package:flutter/services.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/poweramp_dsp_state.dart';

/// Communicates with the native Kotlin `DynamicsProcessing` + `Virtualizer` + `BassBoost`
/// hardware bridge (`com.freebeat.app/dsp`) in `MainActivity.kt`.
class PowerampDspService {
  static const MethodChannel _channel = MethodChannel('com.freebeat.app/dsp');

  Future<String> attachAudioSession(int audioSessionId) async {
    if (audioSessionId <= 0) return 'DynamicsProcessing 64-bit Hardware';
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'attachSession',
        {'audioSessionId': audioSessionId},
      );
      return res?['engineMode'] as String? ??
          'DynamicsProcessing 64-bit Hardware';
    } catch (_) {
      return 'DynamicsProcessing 64-bit Hardware';
    }
  }

  Future<void> applyDspState(PowerampDspState state) async {
    try {
      await _channel.invokeMethod('updateDsp', {
        'eqEnabled': state.eqEnabled,
        'toneEnabled': state.toneEnabled,
        'limiterEnabled': state.limiterEnabled,
        'dvcEnabled': state.dvcEnabled,
        'preampDb': state.preampDb,
        'bassGain': state.toneEnabled ? state.bassGain : 0.0,
        'bassFreqHz': state.bassFreqHz,
        'trebleGain': state.toneEnabled ? state.trebleGain : 0.0,
        'trebleFreqHz': state.trebleFreqHz,
        'stereoExpansion': state.stereoExpansion,
        'balance': state.balance,
        'monoMix': state.monoMix,
        'reverbPresetId': state.reverbPreset.androidPresetId,
        'reverbMix': state.reverbMix,
        'bandGainsDb': state.bands.map((b) => b.gainDb).toList(),
        'bandFreqsHz': state.bands.map((b) => b.frequencyHz).toList(),
        'bandQs': state.bands.map((b) => b.qFactor).toList(),
      });
    } catch (_) {
      // Runs cleanly in widget tests or desktop preview without platform channel
    }
  }

  Future<AudioOutputRouteInfo> fetchAudioRouteInfo() async {
    try {
      final map = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getAudioRouteInfo');
      if (map != null) {
        return AudioOutputRouteInfo.fromMap(map);
      }
    } catch (_) {}
    return const AudioOutputRouteInfo();
  }
}
