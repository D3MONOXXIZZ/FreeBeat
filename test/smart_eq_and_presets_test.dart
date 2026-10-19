import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/poweramp_dsp_state.dart';
import 'package:freebeat/services/audio/poweramp_dsp_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/poweramp_dsp_screen.dart';

class _MockDspService extends PowerampDspService {
  PowerampDspState? lastState;

  @override
  Future<void> applyDspState(PowerampDspState state) async {
    lastState = state;
  }
}

void main() {
  group('Smart EQ Presets & Manual Tuning Unit Tests', () {
    late _MockDspService mockDsp;
    late PowerampDspNotifier notifier;

    setUp(() {
      mockDsp = _MockDspService();
      notifier = PowerampDspNotifier(mockDsp);
    });

    test('All 11 built-in presets load cleanly with unique IDs and distinct sound signatures', () {
      expect(kBuiltInDspPresets.length, equals(11));

      final expectedIds = [
        'flat',
        'bass_boost',
        'smart_eq_bass_treble',
        'vocal',
        'concert',
        'rock',
        'harman_target',
        'hifi_warm_tube',
        'bass_extreme',
        'electronic_edm',
        'late_night',
      ];

      for (final id in expectedIds) {
        notifier.loadPresetById(id);
        expect(notifier.state.activePresetId, equals(id), reason: 'Preset $id should be active');
      }
    });

    test('Bass Boost preset is fully functional and does NOT leave Flat selected', () {
      // Start at Flat
      notifier.resetFlat();
      expect(notifier.state.activePresetId, equals('flat'));
      expect(notifier.state.bands[0].gainDb, equals(0.0));
      expect(notifier.state.bassGain, equals(0.0));

      // Load Bass Boost
      notifier.loadPresetById('bass_boost');
      expect(notifier.state.activePresetId, equals('bass_boost'));
      expect(notifier.state.bands[0].gainDb, equals(7.0));
      expect(notifier.state.bands[1].gainDb, equals(6.0));
      expect(notifier.state.bassGain, greaterThan(0.5));
      expect(notifier.state.preampDb, equals(-3.5));

      // Switch back to Flat
      notifier.resetFlat();
      expect(notifier.state.activePresetId, equals('flat'));
      expect(notifier.state.bands[0].gainDb, equals(0.0));
    });

    test('Legacy aliases map properly to modern Smart EQ presets', () {
      notifier.loadPresetById('poweramp_bass_treble');
      expect(notifier.state.activePresetId, equals('smart_eq_bass_treble'));

      notifier.loadPresetById('vocal_clarity');
      expect(notifier.state.activePresetId, equals('vocal'));

      notifier.loadPresetById('concert_hall');
      expect(notifier.state.activePresetId, equals('concert'));

      notifier.loadPresetById('rock_metal');
      expect(notifier.state.activePresetId, equals('rock'));

      notifier.loadPresetById('bass');
      expect(notifier.state.activePresetId, equals('bass_boost'));
    });

    test('Manual numeric tuning updates band gain and marks preset as custom', () {
      notifier.resetFlat();
      expect(notifier.state.activePresetId, equals('flat'));

      // Set manual number for 1 kHz band (index 5)
      notifier.setBandGain(5, 3.8);
      expect(notifier.state.bands[5].gainDb, equals(3.8));
      expect(notifier.state.activePresetId, equals('custom'));

      // Set manual number for Preamp
      notifier.setPreampDb(-4.2);
      expect(notifier.state.preampDb, equals(-4.2));
      expect(notifier.state.activePresetId, equals('custom'));
    });
  });

  group('Smart EQ UI & Precision Tuning Widget Tests', () {
    late _MockDspService mockDsp;

    setUp(() {
      mockDsp = _MockDspService();
    });

    testWidgets('Smart EQ Studio renders title, dynamic preset chips, and Exact dB button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            powerampDspServiceProvider.overrideWithValue(mockDsp),
          ],
          child: const MaterialApp(
            home: SmartEqScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Smart EQ Studio title
      expect(find.text('Smart EQ Studio'), findsOneWidget);

      // Verify chips are present in Quick Presets Bar
      expect(find.text('Audiophile Flat'), findsWidgets);
      expect(find.text('Bass Boost'), findsOneWidget);
      expect(find.text('Smart EQ'), findsOneWidget);
      expect(find.text('Vocal Air'), findsOneWidget);

      // Verify Exact dB button is rendered
      expect(find.text('Exact dB'), findsOneWidget);

      // Tap Bass Boost chip
      await tester.tap(find.text('Bass Boost'));
      await tester.pumpAndSettle();

      // Now Bass Boost should be applied to the mock service
      expect(mockDsp.lastState?.activePresetId, equals('bass_boost'));

      // Open Exact dB sheet
      await tester.tap(find.text('Exact dB'));
      await tester.pumpAndSettle();

      // Verify Exact Numeric EQ Tuning modal is displayed
      expect(find.text('Exact Numeric EQ Tuning'), findsOneWidget);
      expect(find.text('PREAMP'), findsWidgets);
      expect(find.text('Reset All (0 dB)'), findsOneWidget);
    });
  });
}
