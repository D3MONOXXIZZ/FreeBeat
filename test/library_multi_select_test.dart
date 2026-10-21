import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/library_screen.dart';
import 'package:freebeat/ui/widgets/add_to_playlist_modal.dart';
import 'package:freebeat/ui/widgets/remove_track_dialog.dart';

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

  const track1 = Track(
    id: 'track_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/storage/emulated/0/Music/Track1.flac',
    title: 'Track One',
    artist: 'Artist A',
    album: 'Album A',
    durationMs: 180000,
    streamUrl: 'https://example.com/1.flac',
    bitDepth: 24,
    sampleRateHz: 96000,
    codec: 'FLAC',
  );

  const track2 = Track(
    id: 'track_2',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/storage/emulated/0/Music/Track2.flac',
    title: 'Track Two',
    artist: 'Artist B',
    album: 'Album B',
    durationMs: 200000,
    streamUrl: 'https://example.com/2.flac',
    bitDepth: 16,
    sampleRateHz: 44100,
    codec: 'FLAC',
  );

  const track3 = Track(
    id: 'track_3',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/storage/emulated/0/Music/Track3.flac',
    title: 'Track Three',
    artist: 'Artist C',
    album: 'Album C',
    durationMs: 220000,
    streamUrl: 'https://example.com/3.flac',
    bitDepth: 24,
    sampleRateHz: 192000,
    codec: 'FLAC',
  );

  group('PlaybackNotifier Multi-Track Batch Operations', () {
    test('playNextMultiple inserts tracks directly after current track without duplicates', () {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.state = notifier.state.copyWith(
        currentTrack: track1,
        queue: [track1],
      );

      notifier.playNextMultiple([track2, track3]);

      final updatedQueue = container.read(playbackProvider).queue;
      expect(updatedQueue.length, 3);
      expect(updatedQueue[0].id, 'track_1');
      expect(updatedQueue[1].id, 'track_2');
      expect(updatedQueue[2].id, 'track_3');
    });

    test('addToQueueMultiple appends tracks to the end of Up Next queue', () {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playbackProvider.notifier);
      notifier.state = notifier.state.copyWith(
        currentTrack: track1,
        queue: [track1],
      );

      notifier.addToQueueMultiple([track2, track3]);

      final updatedQueue = container.read(playbackProvider).queue;
      expect(updatedQueue.length, 3);
      expect(updatedQueue.map((t) => t.id).toList(), ['track_1', 'track_2', 'track_3']);
    });
  });

  group('PlaylistsNotifier Multi-Track Batch Operations', () {
    test('addTracksToPlaylist and removeTracksFromPlaylist update playlist state correctly', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(playlistsProvider.notifier);
      final pl = await notifier.createPlaylist('Favorites Test');

      await notifier.addTracksToPlaylist(pl.id, ['track_1', 'track_2', 'track_3']);
      var state = container.read(playlistsProvider);
      expect(state.firstWhere((p) => p.id == pl.id).trackIds, ['track_1', 'track_2', 'track_3']);

      // Removing multiple tracks in batch
      await notifier.removeTracksFromPlaylist(pl.id, ['track_1', 'track_3']);
      state = container.read(playlistsProvider);
      expect(state.firstWhere((p) => p.id == pl.id).trackIds, ['track_2']);
    });
  });

  group('showRemoveTracksConfirmationDialog Widget Test', () {
    testWidgets('Renders batch remove confirmation dialog and executes deletion on confirm', (tester) async {
      bool removedCallbackFired = false;
      final catalog = TracksCatalogNotifier(null, null);
      catalog.state = [track1, track2, track3];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
            tracksCatalogProvider.overrideWith((ref) => catalog),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  return ElevatedButton(
                    onPressed: () {
                      showRemoveTracksConfirmationDialog(
                        context,
                        ref,
                        [track1, track2],
                        onRemoved: () {
                          removedCallbackFired = true;
                        },
                      );
                    },
                    child: const Text('Remove Batch'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Remove Batch'));
      await tester.pumpAndSettle();

      // Check dialog title & message for multiple tracks
      expect(find.text('Remove 2 Tracks?'), findsOneWidget);
      expect(find.textContaining('Are you sure you want to remove 2 selected tracks'), findsOneWidget);

      // Tap Confirm Remove
      await tester.tap(find.widgetWithText(FilledButton, 'Remove 2 Tracks'));
      await tester.pumpAndSettle();

      expect(removedCallbackFired, isTrue);
      expect(catalog.state.length, 1);
      expect(catalog.state.first.id, 'track_3');
    });
  });

  group('showAddToPlaylistModal Multi-Track Tests', () {
    testWidgets('Modal displays header with count and allows adding multiple tracks to playlist', (tester) async {
      final playlistsNotifier = PlaylistsNotifier(null);
      playlistsNotifier.state = [
        Playlist(
          id: 'test_pl_1',
          title: 'Morning Chill',
          trackIds: [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
            playlistsProvider.overrideWith((ref) => playlistsNotifier),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showAddToPlaylistModal(context, null, [track1, track2]);
                    },
                    child: const Text('Open Add Modal'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Add Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Add 2 Tracks to Playlist'), findsOneWidget);
      expect(find.text('Morning Chill'), findsOneWidget);

      // Tap playlist tile to add tracks
      await tester.tap(find.text('Morning Chill'));
      await tester.pumpAndSettle();

      expect(playlistsNotifier.state.first.trackIds, ['track_1', 'track_2']);
    });
  });

  group('LibraryScreen Multi-Select & Select All Integration Tests', () {
    testWidgets('Multi-select mode, Select All, Deselect All, and Batch Options sheet function seamlessly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final catalog = TracksCatalogNotifier(null, null);
      catalog.state = [track1, track2, track3];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
            tracksCatalogProvider.overrideWith((ref) => catalog),
          ],
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state: shows 3 tracks and "Select" button
      expect(find.text('3 tracks'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
      expect(find.byIcon(Icons.checklist_rounded), findsWidgets);

      // Enter selection mode via the "Select" button
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      // Now in multi-select mode: 0 of 3 selected, "Select All" button visible
      expect(find.text('0 of 3 selected'), findsOneWidget);
      expect(find.text('Select All'), findsOneWidget);

      // Tap on Track One to select it
      await tester.tap(find.text('Track One'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 3 selected'), findsOneWidget);
      expect(find.text('1 Selected'), findsOneWidget);

      // Verify floating batch actions bar is rendered
      expect(find.byTooltip('Play Next'), findsOneWidget);
      expect(find.byTooltip('Add to Queue'), findsOneWidget);
      expect(find.byTooltip('Add to Playlist'), findsOneWidget);
      expect(find.byTooltip('Download / Offline'), findsOneWidget);
      expect(find.byTooltip('Remove from Library'), findsOneWidget);

      // Tap "Select All" button
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      expect(find.text('3 of 3 selected'), findsOneWidget);
      expect(find.text('3 Selected'), findsOneWidget);
      expect(find.text('Deselect All'), findsOneWidget);

      // Tap batch options overflow button (either in AppBar or floating bar)
      final optionsBtn = find.byTooltip('Batch Options');
      expect(optionsBtn, findsOneWidget);
      await tester.tap(optionsBtn);
      await tester.pumpAndSettle();

      // Bottom sheet with all long-press track options should appear
      expect(find.text('3 Selected Tracks'), findsOneWidget);
      expect(find.text('Play Next'), findsOneWidget);
      expect(find.text('Add to Queue'), findsOneWidget);
      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.textContaining('Download / Cache Offline'), findsOneWidget);
      expect(find.text('Remove from Library'), findsOneWidget);

      // Close the bottom sheet by tapping the top drag handle or popping
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // Tap "Deselect All" button
      await tester.tap(find.text('Deselect All'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 3 selected'), findsOneWidget);
      expect(find.text('Select Tracks'), findsOneWidget);

      // Exit multi-select mode via close button
      await tester.tap(find.byTooltip('Exit Selection'));
      await tester.pumpAndSettle();

      // Returns to standard library mode
      expect(find.text('Your Library'), findsOneWidget);
      expect(find.text('Select'), findsOneWidget);
    });
  });
}
