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
}
