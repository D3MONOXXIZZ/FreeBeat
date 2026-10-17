import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/settings/playback_settings_screen.dart';
import 'package:freebeat/ui/widgets/ab_loop_modal.dart';
import 'package:freebeat/ui/widgets/playback_speed_modal.dart';
import 'package:freebeat/ui/widgets/queue_bottom_sheet.dart';
import 'package:freebeat/ui/widgets/sleep_timer_modal.dart';

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

  // Mock path_provider and method channels for headless test environment
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

  const track1 = Track(
    id: 'track_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'file_1',
    title: 'Time',
    artist: 'Pink Floyd',
    album: 'Dark Side of the Moon',
    durationMs: 425000,
    streamUrl: 'https://example.com/time.flac',
  );

  const track2 = Track(
    id: 'track_2',
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'file_2',
    title: 'Money',
    artist: 'Pink Floyd',
    album: 'Dark Side of the Moon',
    durationMs: 382000,
    streamUrl: 'https://example.com/money.flac',
  );

  const track3 = Track(
    id: 'track_3',
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'file_3',
    title: 'Us and Them',
    artist: 'Pink Floyd',
    album: 'Dark Side of the Moon',
    durationMs: 469000,
    streamUrl: 'https://example.com/us_and_them.flac',
  );

  const track4 = Track(
    id: 'track_4',
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'file_4',
    title: 'Echoes',
    artist: 'Pink Floyd',
    album: 'Meddle',
    durationMs: 1410000,
    streamUrl: 'https://example.com/echoes.flac',
  );

  group('PlaybackViewState Phase 1 Features', () {
    test('upNextQueue correctly returns tracks following currently playing index', () {
      final state = PlaybackViewState(
        currentTrack: track2,
        queue: [track1, track2, track3, track4],
        isPlaying: true,
      );

      expect(state.upNextQueue.length, 2);
      expect(state.upNextQueue[0].id, 'track_3');
      expect(state.upNextQueue[1].id, 'track_4');
    });

    test('isSleepTimerActive and formattedSleepTimerRemaining helper formats correctly', () {
      const activeState = PlaybackViewState(
        currentTrack: track1,
        queue: [track1],
        sleepTimerDuration: Duration(minutes: 30),
        sleepTimerRemaining: Duration(minutes: 14, seconds: 45),
      );

      expect(activeState.isSleepTimerActive, isTrue);
      expect(activeState.formattedSleepTimerRemaining, '14:45');

      const expiredState = PlaybackViewState(
        currentTrack: track1,
        queue: [track1],
        sleepTimerDuration: Duration(minutes: 30),
        sleepTimerRemaining: Duration.zero,
      );
      expect(expiredState.isSleepTimerActive, isFalse);
    });

    test('Loop points state and isLoopActive calculations', () {
      const inactive = PlaybackViewState(
        currentTrack: track1,
        queue: [track1],
        loopPointA: 5000,
        loopPointB: null,
        isLoopActive: false,
      );
      expect(inactive.isLoopActive, isFalse);

      const active = PlaybackViewState(
        currentTrack: track1,
        queue: [track1],
        loopPointA: 5000,
        loopPointB: 25000,
        isLoopActive: true,
      );
      expect(active.isLoopActive, isTrue);
      expect(active.loopPointA, 5000);
      expect(active.loopPointB, 25000);
    });
  });

  group('PlaybackNotifier Queue Operations', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith(
            (ref) => TracksCatalogNotifier()..state = [track1, track2, track3, track4],
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('playNext inserts track immediately after current playing track', () {
      final notifier = container.read(playbackProvider.notifier);
      notifier.state = PlaybackViewState(
        currentTrack: track1,
        queue: [track1, track3],
        isPlaying: true,
      );

      notifier.playNext(track2);

      final state = container.read(playbackProvider);
      expect(state.queue.length, 3);
      expect(state.queue[0].id, 'track_1');
      expect(state.queue[1].id, 'track_2'); // inserted next
      expect(state.queue[2].id, 'track_3');
    });

    test('addToQueue appends track to the end of queue', () {
      final notifier = container.read(playbackProvider.notifier);
      notifier.state = PlaybackViewState(
        currentTrack: track1,
        queue: [track1, track2],
        isPlaying: true,
      );

      notifier.addToQueue(track4);

      final state = container.read(playbackProvider);
      expect(state.queue.length, 3);
      expect(state.queue.last.id, 'track_4');
    });

    test('reorderUpNext changes relative order of future items without disturbing current track', () {
      final notifier = container.read(playbackProvider.notifier);
      notifier.state = PlaybackViewState(
        currentTrack: track1,
        queue: [track1, track2, track3, track4],
        isPlaying: true,
      );

      // Reorder track 4 (index 2 in upNext) to front (index 0 in upNext)
      notifier.reorderUpNext(2, 0);

      final state = container.read(playbackProvider);
      expect(state.currentTrack.id, 'track_1');
      expect(state.upNextQueue[0].id, 'track_4');
      expect(state.upNextQueue[1].id, 'track_2');
      expect(state.upNextQueue[2].id, 'track_3');
    });

    test('removeFromQueue removes targeted track', () {
      final notifier = container.read(playbackProvider.notifier);
      notifier.state = PlaybackViewState(
        currentTrack: track1,
        queue: [track1, track2, track3],
        isPlaying: true,
      );

      notifier.removeFromQueue('track_2');

      final state = container.read(playbackProvider);
      expect(state.queue.length, 2);
      expect(state.queue.any((t) => t.id == 'track_2'), isFalse);
    });

    test('clearUpNext retains only currently playing track', () {
      final notifier = container.read(playbackProvider.notifier);
      notifier.state = PlaybackViewState(
        currentTrack: track2,
        queue: [track1, track2, track3, track4],
        isPlaying: true,
      );

      notifier.clearUpNext();

      final state = container.read(playbackProvider);
      expect(state.queue.length, 1);
      expect(state.currentTrack.id, 'track_2');
      expect(state.upNextQueue, isEmpty);
    });

    test('toggleAutoplay and crossfade settings update state correctly', () {
      final notifier = container.read(playbackProvider.notifier);
      expect(container.read(playbackProvider).isAutoplay, isTrue);

      notifier.toggleAutoplay();
      expect(container.read(playbackProvider).isAutoplay, isFalse);

      notifier.setCrossfadeSeconds(6);
      expect(container.read(playbackProvider).crossfadeSeconds, 6);
    });

    test('Variable Speed and Pitch Shifting updates state', () async {
      final notifier = container.read(playbackProvider.notifier);

      await notifier.setPlaybackSpeed(1.25);
      expect(container.read(playbackProvider).playbackSpeed, 1.25);

      await notifier.setPitch(1.12);
      expect(container.read(playbackProvider).pitch, closeTo(1.12, 0.01));
    });

    test('A-B Loop point setting, activation, and clearing', () {
      final notifier = container.read(playbackProvider.notifier);
      notifier.state = PlaybackViewState(
        currentTrack: track1,
        queue: const [track1],
        positionMs: 10000,
      );

      notifier.setLoopPointA(10000);
      expect(container.read(playbackProvider).loopPointA, 10000);
      expect(container.read(playbackProvider).isLoopActive, isFalse);

      notifier.setLoopPointB(45000);
      expect(container.read(playbackProvider).loopPointB, 45000);
      expect(container.read(playbackProvider).isLoopActive, isTrue);

      notifier.clearLoop();
      expect(container.read(playbackProvider).loopPointA, isNull);
      expect(container.read(playbackProvider).loopPointB, isNull);
      expect(container.read(playbackProvider).isLoopActive, isFalse);
    });
  });

  group('Phase 1 UI Modals & Sheets Widget Tests', () {
    testWidgets('QueueBottomSheet renders hero track, up next items, and tabs', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
          playbackProvider.overrideWith((ref) {
            final n = PlaybackNotifier(ref);
            n.state = const PlaybackViewState(
              currentTrack: track1,
              queue: [track1, track2, track3],
              isPlaying: true,
              positionMs: 65000,
            );
            return n;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: QueueBottomSheet()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Up Next Queue'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget); // Hero track
      expect(find.text('Money'), findsOneWidget); // Up Next track
      expect(find.text('Us and Them'), findsOneWidget);
      expect(find.text('Smart Autoplay'), findsOneWidget);
    });

    testWidgets('SleepTimerModal displays preset chips and allows selection', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SleepTimerModal()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Sleep Timer'), findsOneWidget);
      expect(find.text('15 Minutes'), findsOneWidget);
      expect(find.text('30 Minutes'), findsOneWidget);
      expect(find.text('End of Current Track'), findsOneWidget);
      expect(find.text('Set Timer for 30 Minutes'), findsOneWidget);
    });

    testWidgets('PlaybackSpeedModal displays speed chips and sliders', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: PlaybackSpeedModal()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Speed & Pitch'), findsOneWidget);
      expect(find.text('PLAYBACK SPEED'), findsOneWidget);
      expect(find.text('PITCH SHIFT'), findsOneWidget);
      expect(find.text('Nightcore'), findsOneWidget);
      expect(find.text('Slowed'), findsOneWidget);
    });

    testWidgets('ABLoopModal displays loop controls and point setters', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
          playbackProvider.overrideWith((ref) {
            final n = PlaybackNotifier(ref);
            n.state = const PlaybackViewState(
              currentTrack: track1,
              queue: [track1],
              positionMs: 35000,
            );
            return n;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ABLoopModal()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('A-B Loop Repeater'), findsOneWidget);
      expect(find.text('Start Point [A]'), findsOneWidget);
      expect(find.text('End Point [B]'), findsOneWidget);
      expect(find.text('Set at Current'), findsNWidgets(2));
    });

    testWidgets('PlaybackSettingsScreen renders crossfade and autoplay options', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: PlaybackSettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Playback & Transitions'), findsOneWidget);
      expect(find.text('Crossfade'), findsOneWidget);
      expect(find.text('Smart Autoplay'), findsOneWidget);
      expect(find.text('Speed & Pitch Shifter'), findsOneWidget);
      expect(find.text('Sleep Timer'), findsOneWidget);
    });
  });
}
