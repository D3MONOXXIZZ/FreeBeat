import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/audio_quality_settings.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/poweramp_dsp_state.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/services/audio/poweramp_dsp_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/now_playing_screen.dart';
import 'package:freebeat/ui/screens/poweramp_dsp_screen.dart';
import 'package:freebeat/ui/widgets/signal_path_sheet.dart';

class MockDspService extends PowerampDspService {
  PowerampDspState? lastAppliedState;

  @override
  Future<void> applyDspState(PowerampDspState state) async {
    lastAppliedState = state;
  }

  @override
  Future<AudioOutputRouteInfo> fetchAudioRouteInfo() async {
    return const AudioOutputRouteInfo(
      deviceName: 'Pixel Buds Pro',
      routeType: 'BLUETOOTH_A2DP',
      isBluetooth: true,
      hardwareSampleRateHz: 96000,
      bluetoothCodecName: 'LDAC Hi-Res 96kHz',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 3: Visualizer Studio & Audiophile DSP Tests', () {
    late MockDspService mockDspService;
    late LibraryDatabase memoryDb;
    late PowerampDspNotifier notifier;

    setUp(() {
      mockDspService = MockDspService();
      memoryDb = LibraryDatabase();
      notifier = PowerampDspNotifier(mockDspService, memoryDb);
    });

    test('PowerampDspState defaults to Spectrum Bars visualizer and BS2B Off', () {
      final state = notifier.state;
      expect(state.visualizerMode, equals(VisualizerMode.spectrumBars));
      expect(state.bs2bCrossfeedMode, equals(Bs2bCrossfeedMode.off));
      expect(state.dvcHeadroomDb, equals(-3.0));
      expect(state.bitPerfectDirectMode, isFalse);
    });

    test('Visualizer modes switch correctly with tactile feedback', () {
      notifier.setVisualizerMode(VisualizerMode.waveformRibbon);
      expect(notifier.state.visualizerMode, equals(VisualizerMode.waveformRibbon));

      notifier.setVisualizerMode(VisualizerMode.vinylPulse);
      expect(notifier.state.visualizerMode, equals(VisualizerMode.vinylPulse));

      notifier.setVisualizerMode(VisualizerMode.spectrumBars);
      expect(notifier.state.visualizerMode, equals(VisualizerMode.spectrumBars));
    });

    test('Bauer BS2B Crossfeed modes update and sync to hardware', () {
      notifier.setBs2bCrossfeedMode(Bs2bCrossfeedMode.subtle);
      expect(notifier.state.bs2bCrossfeedMode, equals(Bs2bCrossfeedMode.subtle));
      expect(mockDspService.lastAppliedState?.bs2bCrossfeedMode, equals(Bs2bCrossfeedMode.subtle));

      notifier.setBs2bCrossfeedMode(Bs2bCrossfeedMode.aggressive);
      expect(notifier.state.bs2bCrossfeedMode, equals(Bs2bCrossfeedMode.aggressive));
      expect(notifier.state.bs2bCrossfeedMode.level, equals(3));
    });

    test('DVC Clean Headroom is clamped between -6.0 dB and 0.0 dB', () {
      notifier.setDvcHeadroomDb(-4.5);
      expect(notifier.state.dvcHeadroomDb, equals(-4.5));

      notifier.setDvcHeadroomDb(-10.0);
      expect(notifier.state.dvcHeadroomDb, equals(-6.0));

      notifier.setDvcHeadroomDb(5.0);
      expect(notifier.state.dvcHeadroomDb, equals(0.0));
    });

    test('Bit-Perfect Direct USB DAC Mode completely bypasses DSP calculation', () {
      // Set strong EQ gains
      notifier.setBandGain(0, 12.0);
      notifier.setBassGain(10.0);
      expect(notifier.state.evaluateResponseAtFrequency(31.0), greaterThan(5.0));

      // Enable Bit-Perfect Direct Mode
      notifier.toggleBitPerfectDirectMode(true);
      expect(notifier.state.bitPerfectDirectMode, isTrue);
      // Under bit-perfect direct mode, response must be strictly 0.0 dB bit-for-bit bypass
      expect(notifier.state.evaluateResponseAtFrequency(31.0), equals(0.0));
      expect(notifier.state.evaluateResponseAtFrequency(1000.0), equals(0.0));
      expect(notifier.state.isClippingRisk, isFalse);

      notifier.toggleBitPerfectDirectMode(false);
      expect(notifier.state.bitPerfectDirectMode, isFalse);
    });

    test('Custom DSP Preset creation, export, and import works seamlessly', () async {
      // 1. Setup specific curve
      notifier.setPreampDb(-2.0);
      notifier.setBandGain(0, 7.5);
      notifier.setBandGain(9, 4.0);
      notifier.setBassGain(6.0);

      // 2. Save Custom Preset
      final saved = await notifier.saveCustomPreset('My Studio Monitor Curve');
      expect(saved.name, equals('My Studio Monitor Curve'));
      expect(saved.isCustom, isTrue);
      expect(notifier.customPresets.length, equals(1));
      expect(notifier.state.activePresetId, equals(saved.id));

      // 3. Export to JSON
      final jsonExport = notifier.exportPresetJson(saved.id);
      expect(jsonExport, contains('My Studio Monitor Curve'));
      expect(jsonExport, contains('"isCustom":true'));

      // 4. Import from JSON
      final imported = await notifier.importPresetFromJson(jsonExport);
      expect(imported, isNotNull);
      expect(imported!.name, equals('My Studio Monitor Curve'));
      expect(notifier.customPresets.length, equals(2));

      // 5. Delete Custom Preset
      await notifier.deleteCustomPreset(saved.id);
      expect(notifier.customPresets.length, equals(1));
    });

    test('Per-Device Hardware Route Auto-Switching loads assigned profiles', () async {
      // Configure profiles
      await notifier.setDeviceProfile('BLUETOOTH', 'harman_target');
      await notifier.setDeviceProfile('USB_DAC', 'flat');
      await notifier.setDeviceProfile('WIRED_HEADPHONES', 'hifi_warm_tube');

      expect(notifier.state.deviceProfiles['BLUETOOTH'], equals('harman_target'));
      expect(notifier.state.deviceProfiles['USB_DAC'], equals('flat'));

      // Switch to Bluetooth route
      notifier.handleAudioRouteChanged(const AudioOutputRouteInfo(
        deviceName: 'Sony WH-1000XM5',
        routeType: 'BLUETOOTH_A2DP',
        isBluetooth: true,
      ));
      expect(notifier.state.activePresetId, equals('harman_target'));

      // Switch to USB-C DAC route
      notifier.handleAudioRouteChanged(const AudioOutputRouteInfo(
        deviceName: 'Fiio Q3 Hi-Res USB DAC',
        routeType: 'USB_DAC_DIRECT',
        isUsbDac: true,
        hardwareSampleRateHz: 192000,
      ));
      expect(notifier.state.activePresetId, equals('flat'));

      // Switch to Wired Headphones
      notifier.handleAudioRouteChanged(const AudioOutputRouteInfo(
        deviceName: 'Sennheiser HD650',
        routeType: 'WIRED_HEADPHONES',
      ));
      expect(notifier.state.activePresetId, equals('hifi_warm_tube'));
    });

    testWidgets('PowerampDspScreen renders multi-mode visualizer switcher and Bit-Perfect badge',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            powerampDspServiceProvider.overrideWithValue(mockDspService),
          ],
          child: const MaterialApp(
            home: PowerampDspScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Screen Title
      expect(find.text('Poweramp DSP Studio'), findsOneWidget);

      // Verify Multi-Mode Visualizer Chips: Bars, Waveform, Vinyl Pulse
      expect(find.text('Bars'), findsOneWidget);
      expect(find.text('Waveform'), findsOneWidget);
      expect(find.text('Vinyl Pulse'), findsOneWidget);

      // Verify Bit-Perfect Chip
      expect(find.text('Bit-Perfect'), findsOneWidget);

      // Tap Waveform visualizer mode
      await tester.tap(find.text('Waveform'));
      await tester.pumpAndSettle();

      // Tap Bit-Perfect Direct toggle
      await tester.tap(find.text('Bit-Perfect'));
      await tester.pumpAndSettle();

      // Verify glowing Bit-Perfect direct banner appears
      expect(
        find.text('BIT-PERFECT DIRECT USB DAC ACTIVE • DSP & TONE BYPASSED • RAW PCM OUT'),
        findsOneWidget,
      );
    });

    testWidgets('SubTab 1 renders BS2B Crossfeed, DVC Clean Headroom, and Signal Path action',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            powerampDspServiceProvider.overrideWithValue(mockDspService),
          ],
          child: const MaterialApp(
            home: PowerampDspScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to SubTab 1 ("Tone Knobs & Stereo X")
      await tester.tap(find.text('Tone Knobs & Stereo X'));
      await tester.pumpAndSettle();

      // Verify BS2B Binaural Crossfeed card
      expect(find.text('Bauer BS2B Binaural Crossfeed'), findsOneWidget);
      expect(find.text('Subtle'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Nearfield'), findsOneWidget);

      // Verify Direct Volume Control (DVC)
      expect(find.text('Direct Volume Control (DVC)'), findsOneWidget);
      expect(find.text('Clean Digital Headroom Guard'), findsOneWidget);

      // Verify Signal Path Action
      expect(find.text('Live Audio Signal Path & Bitrate'), findsOneWidget);
    });

    testWidgets('NowPlayingScreen renders bass-reactive ambient aura stack smoothly',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.reset());

      const testTrack = Track(
        id: 'audiophile_track_1',
        accountId: 'acc_test_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: 'saf_audio_1',
        title: 'Master Audio Experience',
        artist: 'Hi-Fi Ensemble',
        album: 'Lossless Vault',
        durationMs: 240000,
        streamUrl: 'https://example.com/audio.flac',
        codec: 'FLAC',
        bitDepth: 24,
        sampleRateHz: 96000,
        bitrateKbps: 2800,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            powerampDspServiceProvider.overrideWithValue(mockDspService),
            playbackProvider.overrideWith((ref) => PlaybackNotifier(
                  ref,
                  [testTrack],
                )),
          ],
          child: MaterialApp(
            home: NowPlayingScreen(onOpenDspStudio: () {}),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Master Audio Experience'), findsOneWidget);
      expect(find.text('Hi-Fi Ensemble'), findsOneWidget);
      // Verify RepaintBoundary surrounds the hero artwork aura stack
      expect(find.byType(RepaintBoundary), findsWidgets);
    });

    testWidgets('SignalPathSheet displays Bit-Perfect Direct USB DAC Mode telemetry',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.reset());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            powerampDspServiceProvider.overrideWithValue(mockDspService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SignalPathSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Audio Signal Path & Bitrate'), findsOneWidget);
      expect(find.text('Bit-Perfect Direct USB DAC Mode'), findsOneWidget);
      expect(find.text('Switch Live Streaming Bitrate Tier'), findsOneWidget);
    });
  });
}
