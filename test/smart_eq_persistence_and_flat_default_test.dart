import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/audio_quality_settings.dart';
import 'package:freebeat/core/models/poweramp_dsp_state.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/services/audio/poweramp_dsp_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockDspService extends PowerampDspService {
  PowerampDspState? lastAppliedState;

  @override
  Future<void> applyDspState(PowerampDspState state) async {
    lastAppliedState = state;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Smart EQ Flat Default & Tuned Slider Persistence Tests', () {
    late MockDspService mockDspService;
    late LibraryDatabase memoryDb;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockDspService = MockDspService();
      memoryDb = LibraryDatabase();
    });

    test('New user opening the app gets Audiophile Flat with all sliders at zero', () {
      final notifier = PowerampDspNotifier(mockDspService, memoryDb);
      final state = notifier.state;

      expect(state.activePresetId, equals('flat'));
      expect(state.preampDb, equals(0.0));
      expect(state.bassGain, equals(0.0));
      expect(state.trebleGain, equals(0.0));
      expect(state.stereoExpansion, equals(0.0));
      expect(state.balance, equals(0.0));
      expect(state.monoMix, isFalse);

      for (int i = 0; i < state.bands.length; i++) {
        expect(state.bands[i].gainDb, equals(0.0));
      }
    });

    test('Route detection on startup does NOT apply any weird preset like vocal or harman_target', () {
      final notifier = PowerampDspNotifier(mockDspService, memoryDb);

      // Simulate initial speaker route detection
      notifier.handleAudioRouteChanged(const AudioOutputRouteInfo(
        deviceName: 'Pixel Built-in Stereo Speakers',
        routeType: 'BUILTIN_SPEAKER',
      ));
      expect(notifier.state.activePresetId, equals('flat'));

      // Simulate initial bluetooth connection detection
      notifier.handleAudioRouteChanged(const AudioOutputRouteInfo(
        deviceName: 'Pixel Buds Pro',
        routeType: 'BLUETOOTH_A2DP',
        isBluetooth: true,
      ));
      expect(notifier.state.activePresetId, equals('flat'));
    });

    test('Tuned EQ slider positions are saved and restored on app reopen without being overridden', () async {
      final notifier1 = PowerampDspNotifier(mockDspService, memoryDb);

      // User tunes EQ sliders
      notifier1.setBandGain(0, 6.5);
      notifier1.setBandGain(1, -3.2);
      notifier1.setBandGain(5, 4.0);
      notifier1.setPreampDb(2.5);
      notifier1.setBassTone(0.60);
      notifier1.setTrebleTone(0.35);
      notifier1.setStereoExpansion(0.25);

      expect(notifier1.state.activePresetId, equals('custom'));
      expect(notifier1.state.bands[0].gainDb, equals(6.5));
      expect(notifier1.state.bands[1].gainDb, equals(-3.2));
      expect(notifier1.state.bands[5].gainDb, equals(4.0));
      expect(notifier1.state.preampDb, equals(2.5));
      expect(notifier1.state.bassGain, equals(0.60));
      expect(notifier1.state.trebleGain, equals(0.35));
      expect(notifier1.state.stereoExpansion, equals(0.25));

      // Wait for throttled save to complete
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Simulate reopening the app (creating a new notifier instance)
      final notifier2 = PowerampDspNotifier(mockDspService, memoryDb);
      // Wait for asynchronous load from SharedPreferences
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Verify all tuned slider positions and active preset are restored exactly
      expect(notifier2.state.activePresetId, equals('custom'));
      expect(notifier2.state.bands[0].gainDb, equals(6.5));
      expect(notifier2.state.bands[1].gainDb, equals(-3.2));
      expect(notifier2.state.bands[5].gainDb, equals(4.0));
      expect(notifier2.state.preampDb, equals(2.5));
      expect(notifier2.state.bassGain, equals(0.60));
      expect(notifier2.state.trebleGain, equals(0.35));
      expect(notifier2.state.stereoExpansion, equals(0.25));

      // Simulate route change on reopen
      notifier2.handleAudioRouteChanged(const AudioOutputRouteInfo(
        deviceName: 'Pixel Built-in Stereo Speakers',
        routeType: 'BUILTIN_SPEAKER',
      ));

      // Tuned positions must still be intact
      expect(notifier2.state.activePresetId, equals('custom'));
      expect(notifier2.state.bands[0].gainDb, equals(6.5));
      expect(notifier2.state.bands[1].gainDb, equals(-3.2));
    });
  });
}
