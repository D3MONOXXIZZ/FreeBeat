import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/fullscreen_lyrics_screen.dart';
import 'package:freebeat/ui/screens/library_screen.dart';
import 'package:freebeat/ui/screens/playlist_details_screen.dart';
import 'package:freebeat/ui/widgets/material_you_album_cover.dart';
import 'package:freebeat/ui/widgets/mini_player_dock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testTrack = Track(
    id: 'track_test_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/music/song.flac',
    title: 'Crawl Outta Love',
    artist: 'ILLENIUM',
    album: 'Awake',
    durationMs: 242000,
    streamUrl: 'file:///music/song.flac',
    artworkUrl: null,
    codec: 'FLAC',
    dominantColorValue: 0xFF5B45BA,
  );

  final testPlaylist = Playlist(
    id: 'playlist_awake_1',
    title: 'Awake',
    description: 'ILLENIUM 2017 Album',
    trackIds: ['track_test_1'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    customArtworkUrl: 'https://example.com/cover.jpg',
    syncSourceUrl: 'https://open.spotify.com/album/7A9I9BrNylVCqXzgN3Y6qi',
    lastSyncedAt: DateTime.now(),
  );

  group('LibraryDatabase Playlist Persistence Tests', () {
    test('LibraryDatabase retains playlists without dropping them', () async {
      final db = LibraryDatabase();
      await db.init();

      // Upsert playlist
      await db.upsertPlaylist(testPlaylist);

      // Load playlists
      final loaded = await db.loadPlaylists();
      expect(loaded.any((p) => p.id == testPlaylist.id), isTrue);

      final fetched = loaded.firstWhere((p) => p.id == testPlaylist.id);
      expect(fetched.title, 'Awake');
      expect(fetched.syncSourceUrl, 'https://open.spotify.com/album/7A9I9BrNylVCqXzgN3Y6qi');
      expect(fetched.customArtworkUrl, 'https://example.com/cover.jpg');

      // Delete playlist
      await db.deletePlaylist(testPlaylist.id);
      final afterDelete = await db.loadPlaylists();
      expect(afterDelete.any((p) => p.id == testPlaylist.id), isFalse);
    });
  });

  group('Lyrics Screen Mini Player Artwork Tests', () {
    testWidgets('FullscreenLyricsScreen renders MaterialYouAlbumCover thumbnail on mini dock', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackProvider.overrideWith((ref) {
              final notifier = PlaybackNotifier(ref, [testTrack]);
              notifier.updateCurrentTrack(testTrack);
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: FullscreenLyricsScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify MaterialYouAlbumCover thumbnail is present
      expect(find.byType(MaterialYouAlbumCover), findsOneWidget);
      expect(find.text('Crawl Outta Love'), findsWidgets);
    });
  });

  group('Playlist Details Screen Mini Player Dock Tests', () {
    testWidgets('PlaylistDetailsScreen renders MiniPlayerDock when track is active', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [testTrack];
              return notifier;
            }),
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = [testPlaylist];
              return notifier;
            }),
            playbackProvider.overrideWith((ref) {
              final notifier = PlaybackNotifier(ref, [testTrack]);
              notifier.updateCurrentTrack(testTrack);
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: PlaylistDetailsScreen(playlist: testPlaylist),
          ),
        ),
      );

      await tester.pump();

      // Verify MiniPlayerDock is present and visible
      expect(find.byType(MiniPlayerDock), findsOneWidget);
      expect(find.text('Crawl Outta Love'), findsWidgets);
    });
  });

  group('Library Screen Hamburger Menu Tests', () {
    testWidgets('LibraryScreen renders hamburger menu icon button in header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [testTrack];
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the hamburger menu icon is rendered
      final menuButton = find.byIcon(Icons.menu_rounded);
      expect(menuButton, findsOneWidget);

      // Tap hamburger menu to open popup menu
      await tester.tap(menuButton);
      await tester.pumpAndSettle();

      // Verify all items are present in the hamburger menu
      expect(find.text('Search Library'), findsOneWidget);
      expect(find.text('Add to Library'), findsOneWidget);
      expect(find.text('Import Playlist'), findsOneWidget);
      expect(find.text('Select Tracks'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
