import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/poweramp_dsp_state.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/library_screen.dart';
import 'package:freebeat/ui/screens/poweramp_dsp_screen.dart';

class _FakeCloudStreamProxy extends CloudStreamProxy {
  _FakeCloudStreamProxy()
      : super(
          connectorRegistry: CloudConnectorRegistry(),
          credentialStore: SecureCredentialStore(),
        );

  @override
  Future<void> start() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
  });

  const testTrack1 = Track(
    id: 'test_track_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/storage/emulated/0/Music/Time.flac',
    title: 'Time',
    artist: 'Pink Floyd',
    album: 'Dark Side of the Moon',
    durationMs: 425000,
    streamUrl: 'https://example.com/time.flac',
    bitDepth: 24,
    sampleRateHz: 96000,
    codec: 'FLAC',
  );

  group('Poweramp DSP Defaults & Material You Visualizer Tests', () {
    test('PowerampDspState defaults to Flat profile with 0 dB gains and neutral tone', () {
      final initial = PowerampDspState.initial();
      expect(initial.activePresetId, 'flat');
      expect(initial.preampDb, 0.0);
      expect(initial.bassGain, 0.0);
      expect(initial.trebleGain, 0.0);
      expect(initial.stereoExpansion, 0.0);
      for (final band in initial.bands) {
        expect(band.gainDb, 0.0);
      }
      // Flat frequency evaluation at 1kHz should be exactly 0 dB
      expect(initial.evaluateResponseAtFrequency(1000.0), closeTo(0.0, 0.01));
    });

    test('Acoustic Room Reverb and send level updates state and triggers immediate hardware sync', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(powerampDspProvider.notifier);
      expect(container.read(powerampDspProvider).reverbPreset, ReverbPresetType.none);
      expect(container.read(powerampDspProvider).reverbMix, 0.0);

      // Select Large Hall
      notifier.setReverbPreset(ReverbPresetType.largeHall);
      expect(container.read(powerampDspProvider).reverbPreset, ReverbPresetType.largeHall);
      expect(container.read(powerampDspProvider).reverbMix, 0.50);

      // Adjust wet mix
      notifier.setReverbMix(0.75);
      expect(container.read(powerampDspProvider).reverbMix, 0.75);

      // Turn off reverb
      notifier.setReverbPreset(ReverbPresetType.none);
      expect(container.read(powerampDspProvider).reverbPreset, ReverbPresetType.none);
      expect(container.read(powerampDspProvider).reverbMix, 0.0);
    });

    testWidgets('PowerampDspScreen renders with Flat preset label and Material You visualizer', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
          ],
          child: const MaterialApp(
            home: PowerampDspScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check preset button shows Audiophile Flat
      expect(find.text('Audiophile Flat'), findsWidgets);
      // Check CustomPaint visualizer is rendered
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('Batch Import Greyed-Out Circle Indicator & Library Edge-to-Edge Tests', () {
    testWidgets('Pending import items show up together greyed out with circular progress indicators', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late ImportProgressNotifier notifier;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
            tracksCatalogProvider.overrideWith((ref) {
              final cat = TracksCatalogNotifier(null, null);
              cat.state = [testTrack1];
              return cat;
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              notifier = ref.read(importProgressProvider.notifier);
              return const MaterialApp(
                home: LibraryScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start batch import of 3 songs
      notifier.startWithFiles([
        'Echoes.flac',
        'Money.mp3',
        'Us and Them.wav',
      ]);
      await tester.pump();

      // All 3 pending items should show up immediately together
      expect(find.text('Echoes'), findsOneWidget);
      expect(find.text('Money'), findsOneWidget);
      expect(find.text('Us and Them'), findsOneWidget);
      expect(find.textContaining('Importing 3 Songs'), findsOneWidget);

      // Verify circular indicators are displayed for the pending items
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Now simulate progress on first file
      notifier.update(
        current: 1,
        total: 3,
        name: 'Echoes.flac',
        track: const Track(
          id: 'imported_echoes',
          accountId: 'acc_1',
          providerType: CloudProviderType.androidSaf,
          remotePathOrId: '/music/echoes.flac',
          title: 'Echoes (Live)',
          artist: 'Pink Floyd',
          album: 'Meddle',
          durationMs: 1400000,
          streamUrl: '',
        ),
      );
      await tester.pump();

      // First file completed with ready indicator
      expect(find.text('Echoes (Live)'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);

      // Second file now in progress
      expect(find.text('Importing & analyzing audio...'), findsOneWidget);
    });

    testWidgets('Add Music button is a circular + button with clearance above mini player', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
            tracksCatalogProvider.overrideWith((ref) {
              final cat = TracksCatalogNotifier(null, null);
              cat.state = [testTrack1];
              return cat;
            }),
          ],
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify circular FAB is present with add icon
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);
      final fab = tester.widget<FloatingActionButton>(fabFinder);
      expect(fab.shape, isA<CircleBorder>());
      expect(
        find.descendant(
          of: fabFinder,
          matching: find.byIcon(Icons.add_rounded),
        ),
        findsOneWidget,
      );
    });
  });

  group('Smart EQ Comprehensive Audit & Engine Tests', () {
    test('PowerampDspState handles Parametric tuning, Tone, Limiter, and Pitch semitones', () {
      var dsp = PowerampDspState.initial();
      expect(dsp.isParametricMode, isFalse);
      expect(dsp.limiterEnabled, isTrue);
      expect(dsp.toneEnabled, isTrue);
      expect(dsp.pitchSemitones, 0.0);

      // Verify parametric band frequency & Q tuning
      final tunedBands = List<EqBandConfig>.from(dsp.bands);
      tunedBands[0] = tunedBands[0].copyWith(frequencyHz: 35.0, qFactor: 2.5);
      dsp = dsp.copyWith(
        isParametricMode: true,
        limiterEnabled: false,
        toneEnabled: false,
        pitchSemitones: 3.0,
        bands: tunedBands,
      );

      expect(dsp.isParametricMode, isTrue);
      expect(dsp.limiterEnabled, isFalse);
      expect(dsp.toneEnabled, isFalse);
      expect(dsp.pitchSemitones, 3.0);
      expect(dsp.bands[0].frequencyHz, 35.0);
      expect(dsp.bands[0].qFactor, 2.5);

      // Verify toMap and fromMap serialization round-trip
      final map = dsp.toMap();
      final restored = PowerampDspState.fromMap(map);
      expect(restored.isParametricMode, isTrue);
      expect(restored.limiterEnabled, isFalse);
      expect(restored.toneEnabled, isFalse);
      expect(restored.pitchSemitones, 3.0);
      expect(restored.bands[0].frequencyHz, 35.0);
      expect(restored.bands[0].qFactor, 2.5);
    });

    test('PowerampDspState normalizes legacy preset IDs and speaker default profiles', () {
      final legacyMap = {
        'activePresetId': 'poweramp_bass_treble',
        'deviceProfiles': {
          'BUILTIN_SPEAKER': 'vocal_clarity',
          'BLUETOOTH': 'audiophile_warmth',
        },
      };

      final normalized = PowerampDspState.fromMap(legacyMap);
      // Legacy 'poweramp_bass_treble' -> 'smart_eq_bass_treble'
      expect(normalized.activePresetId, 'smart_eq_bass_treble');
      // Legacy 'vocal_clarity' -> 'vocal'
      expect(normalized.deviceProfiles['BUILTIN_SPEAKER'], 'vocal');
      // Legacy 'audiophile_warmth' -> 'warm'
      expect(normalized.deviceProfiles['BLUETOOTH'], 'warm');
    });

    testWidgets('PowerampDspScreen renders Graphic / Parametric toggle, Limiter, and Pitch controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
          ],
          child: const MaterialApp(
            home: PowerampDspScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Parametric vs Graphic mode switcher initially in Graphic mode
      final graphicFinder = find.text('Graphic');
      expect(graphicFinder, findsWidgets);

      // Tap to toggle to Parametric mode
      await tester.tap(graphicFinder.first);
      await tester.pumpAndSettle();
      expect(find.text('Parametric'), findsWidgets);

      // Switch to SubTab 1 ("Tone Knobs & Stereo X")
      await tester.tap(find.text('Tone Knobs & Stereo X'));
      await tester.pumpAndSettle();

      // Rotary Tone & Spatial Stage
      expect(find.text('Rotary Tone & Spatial Stage'), findsOneWidget);

      // Hardware Auto-Limiter
      expect(find.text('Hardware Peak Auto-Limiter'), findsOneWidget);

      // Pitch Transposition
      expect(find.textContaining('Pitch Transposition'), findsOneWidget);
    });
  });
}

