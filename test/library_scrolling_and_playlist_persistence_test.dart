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
      expect(find.text('Search in Library'), findsOneWidget);
      expect(find.text('Search Global Catalog'), findsOneWidget);
      expect(find.text('Add to Library'), findsOneWidget);
      expect(find.text('Import Playlist'), findsOneWidget);
      expect(find.text('Select Tracks'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('Library Screen Search Feature Tests', () {
    testWidgets('LibraryScreen renders search bar and live-filters tracks', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      final trackA = Track(
        id: 'track_a',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/music/crawl.flac',
        title: 'Crawl Outta Love',
        artist: 'ILLENIUM',
        album: 'Awake',
        durationMs: 242000,
        streamUrl: 'file:///music/crawl.flac',
        codec: 'FLAC',
      );

      final trackB = Track(
        id: 'track_b',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/music/star.flac',
        title: 'Starlight',
        artist: 'Muse',
        album: 'Black Holes',
        durationMs: 240000,
        streamUrl: 'file:///music/star.flac',
        codec: 'FLAC',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [trackA, trackB];
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify SearchBar TextField is present
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      expect(find.text('Crawl Outta Love'), findsOneWidget);
      expect(find.text('Starlight'), findsOneWidget);

      // 2. Type "crawl" into search bar
      await tester.enterText(searchField, 'crawl');
      await tester.pumpAndSettle();

      // "Crawl Outta Love" should be visible, "Starlight" should be filtered out
      expect(find.text('Crawl Outta Love'), findsOneWidget);
      expect(find.text('Starlight'), findsNothing);
      expect(find.textContaining('Found 1 track'), findsOneWidget);

      // 3. Clear search using the clear button
      final clearButton = find.byTooltip('Clear search');
      expect(clearButton, findsOneWidget);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      // Both tracks should be restored
      expect(find.text('Crawl Outta Love'), findsOneWidget);
      expect(find.text('Starlight'), findsOneWidget);

      // 4. Search for nonexistent track -> Empty state
      await tester.enterText(searchField, 'nonexistentquery123');
      await tester.pumpAndSettle();

      expect(find.text('No tracks matching "nonexistentquery123"'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);
      expect(find.text('Search Online'), findsOneWidget);
    });

    testWidgets('LibraryScreen search bar has clipBehavior and no filled sharp corners', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          child: const MaterialApp(
            home: LibraryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final searchTextField = tester.widget<TextField>(find.byType(TextField));
      expect(searchTextField.decoration?.filled, isFalse);
      expect(searchTextField.decoration?.fillColor, Colors.transparent);
      expect(searchTextField.decoration?.border, InputBorder.none);

      // Verify Playlists tab displays app icons for Spotify, Apple Music, and YouTube
      final playlistsTab = find.textContaining('Playlists');
      expect(playlistsTab, findsOneWidget);
      await tester.tap(playlistsTab);
      await tester.pumpAndSettle();

      expect(find.text('Import Playlists & Tracks'), findsOneWidget);
      // Verify app icon tooltips
      expect(find.byTooltip('Spotify'), findsOneWidget);
      expect(find.byTooltip('Apple Music'), findsOneWidget);
      expect(find.byTooltip('YouTube'), findsOneWidget);
    });
  });
}
