import 'package:flutter/services.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/poweramp_dsp_state.dart';

/// Communicates with the native Kotlin `DynamicsProcessing` + `Virtualizer` + `BassBoost`
/// hardware bridge (`com.freebeat.app/dsp`) in `MainActivity.kt` for Smart EQ & DSP.
class PowerampDspService {
  static const MethodChannel _channel = MethodChannel('com.freebeat.app/dsp');

  Future<String> attachAudioSession(int audioSessionId) async {
    if (audioSessionId <= 0) return 'Smart EQ DynamicsProcessing 64-bit Hardware';
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'attachSession',
        {'audioSessionId': audioSessionId},
      );
      return res?['engineMode'] as String? ??
          'Smart EQ DynamicsProcessing 64-bit Hardware';
    } catch (_) {
      return 'Smart EQ DynamicsProcessing 64-bit Hardware';
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
        'bs2bCrossfeedLevel': state.bs2bCrossfeedMode.level,
        'dvcHeadroomDb': state.dvcHeadroomDb,
        'bitPerfectDirectMode': state.bitPerfectDirectMode,
        'bandGainsDb': state.bands.map((b) => b.gainDb).toList(),
        'bandFreqsHz': state.bands.map((b) => b.frequencyHz).toList(),
        'bandQs': state.bands.map((b) => b.qFactor).toList(),
        'tempo': state.tempo,
        'pitchSemitones': state.pitchSemitones,
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

  Future<void> startForegroundPlayback({
    required String title,
    required String artist,
    required String album,
    String? artworkPath,
    String? audioPath,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
    required double volume,
    required int dominantColor,
    String outputDevice = 'Phone Speaker',
    bool isShuffle = false,
    int repeatMode = 0,
    bool isPowerSaver = false,
    bool isCurrentTrackLocal = false,
    String? trackId,
    String? codec,
    int? bitDepth,
    int? sampleRateHz,
  }) async {
    try {
      await _channel.invokeMethod('startForegroundPlayback', {
        'title': title,
        'artist': artist,
        'album': album,
        'artworkPath': artworkPath,
        if (audioPath != null) 'audioPath': audioPath,
        'durationMs': durationMs,
        'positionMs': positionMs,
        'isPlaying': isPlaying,
        'volume': volume,
        'dominantColor': dominantColor,
        'outputDevice': outputDevice,
        'isShuffle': isShuffle,
        'repeatMode': repeatMode,
        'isPowerSaver': isPowerSaver,
        'isCurrentTrackLocal': isCurrentTrackLocal,
        if (trackId != null) 'trackId': trackId,
        if (codec != null) 'codec': codec,
        if (bitDepth != null) 'bitDepth': bitDepth,
        if (sampleRateHz != null) 'sampleRateHz': sampleRateHz,
      });
    } catch (_) {}
  }

  Future<void> updatePlaybackNotification({
    int? positionMs,
    int? durationMs,
    bool? isPlaying,
    double? volume,
    int? dominantColor,
    String? title,
    String? artist,
    String? artworkPath,
    String? audioPath,
    String? outputDevice,
    bool? isShuffle,
    int? repeatMode,
    bool? isPowerSaver,
    bool? isCurrentTrackLocal,
    String? trackId,
    String? codec,
    int? bitDepth,
    int? sampleRateHz,
  }) async {
    try {
      await _channel.invokeMethod('updatePlaybackNotification', {
        if (positionMs != null) 'positionMs': positionMs,
        if (durationMs != null) 'durationMs': durationMs,
        if (isPlaying != null) 'isPlaying': isPlaying,
        if (volume != null) 'volume': volume,
        if (dominantColor != null) 'dominantColor': dominantColor,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (artworkPath != null) 'artworkPath': artworkPath,
        if (audioPath != null) 'audioPath': audioPath,
        if (outputDevice != null) 'outputDevice': outputDevice,
        if (isShuffle != null) 'isShuffle': isShuffle,
        if (repeatMode != null) 'repeatMode': repeatMode,
        if (isPowerSaver != null) 'isPowerSaver': isPowerSaver,
        if (isCurrentTrackLocal != null) 'isCurrentTrackLocal': isCurrentTrackLocal,
        if (trackId != null) 'trackId': trackId,
        if (codec != null) 'codec': codec,
        if (bitDepth != null) 'bitDepth': bitDepth,
        if (sampleRateHz != null) 'sampleRateHz': sampleRateHz,
      });
    } catch (_) {}
  }

  Future<void> preloadArtwork(String? artworkUrl) async {
    if (artworkUrl == null || artworkUrl.isEmpty) return;
    if (!artworkUrl.startsWith('http://') && !artworkUrl.startsWith('https://')) return;
    try {
      await _channel.invokeMethod('preloadArtwork', {'artworkUrl': artworkUrl});
    } catch (_) {}
  }

  Future<void> stopForegroundPlayback() async {
    try {
      await _channel.invokeMethod('stopForegroundPlayback');
    } catch (_) {}
  }

  Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  Future<String?> transcodeAudioIfNeeded(String path) async {
    try {
      final res = await _channel.invokeMethod<String>('transcodeAudioIfNeeded', {'path': path});
      return res;
    } catch (_) {
      return null;
    }
  }

  void Function(String action, Map<String, dynamic> extras)? _notificationListener;
  void Function(Map<String, dynamic> batteryMap)? _batteryListener;

  void setNotificationActionListener(
      void Function(String action, Map<String, dynamic> extras) listener) {
    _notificationListener = listener;
    _ensureMethodCallHandler();
  }

  void setBatteryStateListener(
      void Function(Map<String, dynamic> batteryMap) listener) {
    _batteryListener = listener;
    _ensureMethodCallHandler();
  }

  void _ensureMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationAction') {
        final args = call.arguments as Map<dynamic, dynamic>? ?? {};
        final action = args['action'] as String? ?? '';
        final extras = (args['extras'] as Map<dynamic, dynamic>? ?? {})
            .map((k, v) => MapEntry(k.toString(), v));
        _notificationListener?.call(action, extras);
      } else if (call.method == 'onBatteryStateChanged') {
        final args = call.arguments;
        if (args is Map) {
          _batteryListener?.call(Map<String, dynamic>.from(args));
        }
      }
    });
  }
}

/// Smart EQ Service Alias
typedef SmartEqService = PowerampDspService;

