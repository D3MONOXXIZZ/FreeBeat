import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/track_details_screen.dart';
import 'package:freebeat/ui/widgets/remove_track_dialog.dart';

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
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') return <String, dynamic>{};
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'disposeAllPlayers') return <dynamic>[];
        return <String, dynamic>{};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async {
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method.startsWith('HapticFeedback.')) return null;
        return null;
      },
    );
  });

  const testTrack1 = Track(
    id: 'track_1',
    accountId: 'acc_1',
    remotePathOrId: 'path/1',
    title: 'Bohemian Rhapsody',
    artist: 'Queen',
    album: 'A Night at the Opera',
    durationMs: 354000,
    streamUrl: 'https://example.com/audio1.flac',
    codec: 'flac',
    bitrateKbps: 1411,
    sampleRateHz: 44100,
    bitDepth: 16,
    providerType: CloudProviderType.googleDrive,
  );

  const testTrack2 = Track(
    id: 'track_2',
    accountId: 'acc_1',
    remotePathOrId: 'path/2',
    title: 'Starboy',
    artist: 'The Weeknd',
    album: 'Starboy',
    durationMs: 230000,
    streamUrl: 'https://example.com/audio2.flac',
    codec: 'flac',
    bitrateKbps: 1411,
    sampleRateHz: 44100,
    bitDepth: 16,
    providerType: CloudProviderType.googleDrive,
  );

  const testTrack3 = Track(
    id: 'track_3',
    accountId: 'acc_1',
    remotePathOrId: 'path/3',
    title: 'Hotel California',
    artist: 'Eagles',
    album: 'Hotel California',
    durationMs: 390000,
    streamUrl: 'https://example.com/audio3.flac',
    codec: 'flac',
    bitrateKbps: 1411,
    sampleRateHz: 44100,
    bitDepth: 16,
    providerType: CloudProviderType.googleDrive,
  );

  group('TracksCatalogNotifier & Database Removal', () {
    test('removeTracks removes track from catalog and database', () async {
      final db = LibraryDatabase();
      final container = ProviderContainer(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
        ],
      );

      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      await catalogNotifier.addIndexedTracks([testTrack1, testTrack2, testTrack3]);

      expect(container.read(tracksCatalogProvider).length, equals(3));

      // Remove testTrack2
      await catalogNotifier.removeTracks([testTrack2.id]);

      final remaining = container.read(tracksCatalogProvider);
      expect(remaining.length, equals(2));
      expect(remaining.any((t) => t.id == testTrack2.id), isFalse);
      expect(remaining.any((t) => t.id == testTrack1.id), isTrue);
      expect(remaining.any((t) => t.id == testTrack3.id), isTrue);

      container.dispose();
    });

    test('removeTrack single helper forwards to removeTracks', () async {
      final container = ProviderContainer();
      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      await catalogNotifier.addIndexedTracks([testTrack1, testTrack2]);

      await catalogNotifier.removeTrack(testTrack1.id);
      expect(container.read(tracksCatalogProvider).length, equals(1));
      expect(container.read(tracksCatalogProvider).first.id, equals(testTrack2.id));

      container.dispose();
    });
  });

  group('Playlists & Playback Synchronization upon Track Removal', () {
    test('Removing track purges it from all custom playlists', () async {
      final db = LibraryDatabase();
      final container = ProviderContainer(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
        ],
      );

      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      final playlistsNotifier = container.read(playlistsProvider.notifier);

      await catalogNotifier.addIndexedTracks([testTrack1, testTrack2, testTrack3]);
      final p1 = await playlistsNotifier.createPlaylist('Rock Classics');
      final p2 = await playlistsNotifier.createPlaylist('Favorites');

      await playlistsNotifier.addTracksToPlaylist(p1.id, [testTrack1.id, testTrack2.id]);
      await playlistsNotifier.addTracksToPlaylist(p2.id, [testTrack2.id, testTrack3.id]);

      expect(container.read(playlistsProvider).firstWhere((p) => p.id == p1.id).trackIds,
          contains(testTrack2.id));
      expect(container.read(playlistsProvider).firstWhere((p) => p.id == p2.id).trackIds,
          contains(testTrack2.id));

      // Remove testTrack2 from library
      await catalogNotifier.removeTracks([testTrack2.id]);

      final updatedP1 = container.read(playlistsProvider).firstWhere((p) => p.id == p1.id);
      final updatedP2 = container.read(playlistsProvider).firstWhere((p) => p.id == p2.id);

      expect(updatedP1.trackIds.contains(testTrack2.id), isFalse);
      expect(updatedP1.trackIds, equals([testTrack1.id]));
      expect(updatedP2.trackIds.contains(testTrack2.id), isFalse);
      expect(updatedP2.trackIds, equals([testTrack3.id]));

      container.dispose();
    });

    test('Playback queue is updated when current track is removed while stopped', () async {
      final container = ProviderContainer();
      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      final playbackNotifier = container.read(playbackProvider.notifier);

      await catalogNotifier.addIndexedTracks([testTrack1, testTrack2, testTrack3]);
      playbackNotifier.setQueue([testTrack1, testTrack2, testTrack3], startTrack: testTrack1);

      expect(container.read(playbackProvider).currentTrack.id, equals(testTrack1.id));
      expect(container.read(playbackProvider).queue.length, equals(3));

      // Remove currently selected testTrack1
      await catalogNotifier.removeTracks([testTrack1.id]);

      final playback = container.read(playbackProvider);
      expect(playback.currentTrack.id, equals(testTrack2.id));
      expect(playback.queue.length, equals(2));
      expect(playback.queue.map((t) => t.id), equals([testTrack2.id, testTrack3.id]));

      container.dispose();
    });

    test('Playback stops cleanly when last remaining track is removed', () async {
      final container = ProviderContainer();
      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      final playbackNotifier = container.read(playbackProvider.notifier);

      await catalogNotifier.addIndexedTracks([testTrack1]);
      playbackNotifier.setQueue([testTrack1], startTrack: testTrack1);

      expect(container.read(playbackProvider).currentTrack.id, equals(testTrack1.id));

      // Remove the only track
      await catalogNotifier.removeTracks([testTrack1.id]);

      final playback = container.read(playbackProvider);
      expect(playback.isPlaying, isFalse);
      expect(playback.currentTrack.id, isEmpty);
      expect(playback.queue, isEmpty);

      container.dispose();
    });
  });

  group('showRemoveTrackConfirmationDialog Widget & UI Interaction', () {
    testWidgets('Renders confirmation dialog and cancelling keeps track intact',
        (tester) async {
      final container = ProviderContainer();
      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      await catalogNotifier.addIndexedTracks([testTrack1]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () => showRemoveTrackConfirmationDialog(
                      context,
                      ref,
                      testTrack1,
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from Library?'), findsOneWidget);
      expect(
        find.textContaining('Are you sure you want to remove "Bohemian Rhapsody"'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Track should still exist in catalog
      expect(container.read(tracksCatalogProvider).length, equals(1));

      container.dispose();
    });

    testWidgets('Confirming dialog removes track and invokes callback',
        (tester) async {
      final container = ProviderContainer();
      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      await catalogNotifier.addIndexedTracks([testTrack1]);

      bool removedCallbackFired = false;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () => showRemoveTrackConfirmationDialog(
                      context,
                      ref,
                      testTrack1,
                      onRemoved: () {
                        removedCallbackFired = true;
                      },
                    ),
                    child: const Text('Open Dialog'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Remove button
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));

      expect(removedCallbackFired, isTrue);
      expect(container.read(tracksCatalogProvider), isEmpty);
      expect(find.text('Removed "Bohemian Rhapsody" from library'), findsOneWidget);

      container.dispose();
    });
  });

  group('TrackDetailsScreen Integration', () {
    testWidgets('TrackDetailsScreen renders delete icon in AppBar and bottom action button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      final catalogNotifier = container.read(tracksCatalogProvider.notifier);
      await catalogNotifier.addIndexedTracks([testTrack1]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: TrackDetailsScreen(track: testTrack1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify app bar delete icon button exists
      final deleteIconButton = find.byTooltip('Remove from Library');
      expect(deleteIconButton, findsOneWidget);

      // Scroll to bottom to verify the text button
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.text('Remove Track from Library'), findsOneWidget);

      // Tap delete in AppBar
      await tester.tap(deleteIconButton);
      await tester.pumpAndSettle();

      expect(find.text('Remove from Library?'), findsOneWidget);

      container.dispose();
    });
  });
}
