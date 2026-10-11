import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/audio_quality_settings.dart';
import 'package:freebeat/core/models/poweramp_dsp_state.dart';
import 'package:freebeat/providers/implementations/media_server_connectors.dart';

void main() {
  group('Poweramp 10-Band EQ, Preamp & Rotary Tone DSP Math', () {
    test('Initial state has 10 ISO octave bands (31Hz to 16kHz)', () {
      final state = PowerampDspState.initial();
      expect(state.bands.length, 10);
      expect(state.bands.first.frequencyHz, 31.0);
      expect(state.bands.last.frequencyHz, 16000.0);
    });

    test('Preamp and 10-band gain accurately shift frequency response spline', () {
      final flat = PowerampDspState.initial().copyWith(
        preampDb: 0.0,
        bassGain: 0.0,
        trebleGain: 0.0,
        bands: List.generate(
          10,
          (i) => EqBandConfig(
            index: i,
            frequencyHz: kPoweramp10BandFrequencies[i],
            gainDb: 0.0,
          ),
        ),
      );
      expect(flat.evaluateResponseAtFrequency(1000.0), closeTo(0.0, 0.01));

      // Apply +6.0 dB Preamp and +8.0 dB at 1kHz (band index 5)
      final boostedBands = List<EqBandConfig>.from(flat.bands);
      boostedBands[5] = boostedBands[5].copyWith(gainDb: 8.0);
      final boosted = flat.copyWith(preampDb: 6.0, bands: boostedBands);

      expect(boosted.evaluateResponseAtFrequency(1000.0), greaterThan(13.5));
      expect(
        boosted.copyWith(limiterEnabled: false).isClippingRisk,
        isTrue,
      );
    });

    test('PowerampDspState serializes and deserializes cleanly', () {
      final initial = PowerampDspState.initial().copyWith(
        preampDb: -3.5,
        stereoExpansion: 0.42,
      );
      final jsonStr = initial.toJsonString();
      final restored = PowerampDspState.fromJsonString(jsonStr);
      expect(restored.preampDb, closeTo(-3.5, 0.001));
      expect(restored.stereoExpansion, closeTo(0.42, 0.001));
      expect(restored.bands.length, 10);
    });
  });

  group('Configurable Audio Bitrate & Hi-Fi Lossless Stream Resolution', () {
    test('Jellyfin builds static direct-play URL for Hi-Fi Lossless tier', () {
      final url = JellyfinConnector.buildStreamingUrl(
        baseUrl: 'https://jellyfin.example.com',
        itemId: 'track99',
        apiKey: 'secret_key',
        targetQuality: AudioQualityTier.hifiLossless,
      );
      expect(url, contains('static=true'));
      expect(url, isNot(contains('MaxStreamingBitrate')));
    });

    test('Jellyfin builds bitrate-capped URL for Data Saver 96kbps Opus tier', () {
      final url = JellyfinConnector.buildStreamingUrl(
        baseUrl: 'https://jellyfin.example.com',
        itemId: 'track99',
        apiKey: 'secret_key',
        targetQuality: AudioQualityTier.dataSaver96,
      );
      expect(url, contains('MaxStreamingBitrate=96000'));
      expect(url, contains('AudioCodec=opus'));
    });

    test('Subsonic / Navidrome generates salted MD5 token & honors quality tier', () {
      final hiFiUri = SubsonicConnector.buildStreamUri(
        baseServerUrl: 'https://navidrome.example.com',
        songId: 'song_42',
        username: 'audiophile',
        password: 'supersecret',
        targetQuality: AudioQualityTier.hifiLossless,
        fixedSalt: 'abc12345',
      );
      expect(hiFiUri.queryParameters['format'], 'raw');
      expect(hiFiUri.queryParameters['maxBitRate'], '0');
      expect(hiFiUri.queryParameters['s'], 'abc12345');
      expect(hiFiUri.queryParameters['t'], isNotEmpty);

      final extreme320Uri = SubsonicConnector.buildStreamUri(
        baseServerUrl: 'https://navidrome.example.com',
        songId: 'song_42',
        username: 'audiophile',
        password: 'supersecret',
        targetQuality: AudioQualityTier.extreme320,
        fixedSalt: 'abc12345',
      );
      expect(extreme320Uri.queryParameters['maxBitRate'], '320');
      expect(extreme320Uri.queryParameters['format'], 'mp3');
    });
  });
}
