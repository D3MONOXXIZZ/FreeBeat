import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/widgets/material_you_download_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('freebeat_shuffle_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => testDir.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/pixel_haptics'),
      (MethodCall methodCall) async => null,
    );
  });

  tearDown(() {
    try {
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  final List<Track> testTracks = List.generate(
    10,
    (i) => Track(
      id: 'track_$i',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/track_$i.mp3',
      streamUrl: '/music/track_$i.mp3',
      title: 'Track $i',
      artist: 'Artist $i',
      album: 'Album 1',
      durationMs: 180000,
    ),
  );

  group('Shuffle Functionality & Queue Preservation Tests', () {
    test('Turning shuffle ON randomizes remaining queue and turning OFF restores original order', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueue(testTracks, startTrack: testTracks[2]);

      final initial = container.read(playbackProvider);
      expect(initial.currentTrack.id, 'track_2');
      expect(initial.isShuffle, false);
      expect(initial.queue.map((t) => t.id).toList(), testTracks.map((t) => t.id).toList());

      // Toggle Shuffle ON
      notifier.toggleShuffle();
      final shuffledState = container.read(playbackProvider);
      expect(shuffledState.isShuffle, true);
      // Current track must remain first
      expect(shuffledState.currentTrack.id, 'track_2');
      expect(shuffledState.queue.first.id, 'track_2');
      expect(shuffledState.queue.length, testTracks.length);

      // Verify that all tracks exist in shuffled queue
      final shuffledIds = shuffledState.queue.map((t) => t.id).toSet();
      expect(shuffledIds, testTracks.map((t) => t.id).toSet());

      // Toggle Shuffle OFF -> original queue must be restored
      notifier.toggleShuffle();
      final restoredState = container.read(playbackProvider);
      expect(restoredState.isShuffle, false);
      expect(restoredState.currentTrack.id, 'track_2');
      expect(restoredState.queue.map((t) => t.id).toList(), testTracks.map((t) => t.id).toList());
    });

    test('Queue removal and addition persist cleanly in shuffled and restored states', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueue(testTracks, startTrack: testTracks.first);

      notifier.toggleShuffle();
      expect(container.read(playbackProvider).isShuffle, true);

      // Remove track_5 from queue
      notifier.removeFromQueue('track_5');
      expect(container.read(playbackProvider).queue.any((t) => t.id == 'track_5'), false);

      // Add a new track
      const newTrack = Track(
        id: 'track_new',
        accountId: 'local',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/music/new.mp3',
        streamUrl: '/music/new.mp3',
        title: 'New Track',
        artist: 'New Artist',
        album: 'Album 1',
        durationMs: 200000,
      );
      notifier.addToQueue(newTrack);
      expect(container.read(playbackProvider).queue.any((t) => t.id == 'track_new'), true);

      // Turn shuffle OFF
      notifier.toggleShuffle();
      final restored = container.read(playbackProvider);
      expect(restored.isShuffle, false);
      expect(restored.queue.any((t) => t.id == 'track_5'), false);
      expect(restored.queue.any((t) => t.id == 'track_new'), true);
    });

    test('playTrack with isShuffle: true updates shuffle state and preserves queue', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      await notifier.playTrack(
        testTracks[3],
        newQueue: testTracks,
        isShuffle: true,
      );

      final state = container.read(playbackProvider);
      expect(state.currentTrack.id, 'track_3');
      expect(state.isShuffle, true);
    });

    test('Toggling shuffle and cycling repeat maintains track duration and metadata', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueue(testTracks, startTrack: testTracks[1]);

      expect(container.read(playbackProvider).currentTrack.durationMs, 180000);

      // Trigger shuffle toggle
      notifier.toggleShuffle();
      expect(container.read(playbackProvider).isShuffle, true);
      expect(container.read(playbackProvider).currentTrack.durationMs, 180000);
      expect(container.read(playbackProvider).currentTrack.title, 'Track 1');

      // Trigger repeat cycling
      notifier.cycleRepeatMode(); // 1: all
      expect(container.read(playbackProvider).repeatMode, 1);
      expect(container.read(playbackProvider).currentTrack.durationMs, 180000);

      notifier.cycleRepeatMode(); // 2: one
      expect(container.read(playbackProvider).repeatMode, 2);
      expect(container.read(playbackProvider).currentTrack.durationMs, 180000);
    });
  });

  group('Pause and Track Desync Resilience Tests', () {
    test('resyncWithActivePlayer does not overwrite currentTrack when paused', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueue(testTracks, startTrack: testTracks[4]);

      // Manually set paused state with track_4
      expect(container.read(playbackProvider).currentTrack.id, 'track_4');
      expect(container.read(playbackProvider).isPlaying, false);

      // Execute resyncWithActivePlayer()
      await notifier.resyncWithActivePlayer();

      final stateAfter = container.read(playbackProvider);
      expect(stateAfter.currentTrack.id, 'track_4');
      expect(stateAfter.isPlaying, false);
    });

    test('syncWithLoadedCatalog preserves in-memory paused track over stale saved ids', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueue(testTracks, startTrack: testTracks[7]);

      expect(container.read(playbackProvider).currentTrack.id, 'track_7');
      expect(container.read(playbackProvider).isPlaying, false);

      // Simulate catalog reload
      await notifier.syncWithLoadedCatalog(testTracks);

      final stateAfter = container.read(playbackProvider);
      expect(stateAfter.currentTrack.id, 'track_7');
      expect(stateAfter.queue.length, testTracks.length);
    });
  });

  group('Download Button Offline Pinning vs Stream Cache Tests', () {
    testWidgets('Download tick icon strictly renders only when isPinnedOffline is true', (tester) async {
      const normalTrack = Track(
        id: 'stream_cached_track',
        accountId: 'local',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/music/sample.mp3',
        streamUrl: '/music/sample.mp3',
        title: 'Sample Stream',
        artist: 'Artist',
        album: 'Album',
        durationMs: 120000,
        localCachePath: '/storage/cache/sample.mp3', // Stream cached, but NOT pinned offline
        isPinnedOffline: false,
      );

      const pinnedTrack = Track(
        id: 'pinned_offline_track',
        accountId: 'local',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/music/pinned.mp3',
        streamUrl: '/music/pinned.mp3',
        title: 'Pinned Stream',
        artist: 'Artist',
        album: 'Album',
        durationMs: 120000,
        localCachePath: '/storage/cache/pinned.mp3',
        isPinnedOffline: true, // Explicitly downloaded offline
      );

      // Render normalTrack (stream cached, but not pinned)
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MaterialYouDownloadButton(track: normalTrack),
            ),
          ),
        ),
      );

      // Must NOT show download_done_rounded tick!
      expect(find.byIcon(Icons.download_done_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_circle_down_rounded), findsOneWidget);

      // Render pinnedTrack (explicitly downloaded offline)
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MaterialYouDownloadButton(track: pinnedTrack),
            ),
          ),
        ),
      );

      // Must show download_done_rounded tick!
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_circle_down_rounded), findsNothing);
    });
  });
}
