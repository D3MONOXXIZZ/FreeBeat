import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/playlist_details_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testTrack = Track(
    id: 'track_test_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/music/song.flac',
    title: 'City to City',
    artist: 'JANI',
    album: 'Know Me',
    durationMs: 215000,
    streamUrl: 'file:///music/song.flac',
    codec: 'FLAC',
  );

  final testPlaylist = Playlist(
    id: 'playlist_know_me',
    title: 'KNOW ME',
    description: 'Z41N Playlist',
    trackIds: ['track_test_1'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    syncSourceUrl: 'https://open.spotify.com/playlist/test',
    lastSyncedAt: DateTime.now(),
  );

  group('PlaylistDetailsScreen Header Hamburger Menu and Action Pills Tests', () {
    testWidgets('Header renders hamburger menu and opens options popup', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            smartPlaylistsProvider.overrideWith((ref) => [testPlaylist]),
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [testTrack];
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: PlaylistDetailsScreen(playlist: testPlaylist),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify header has back button and single hamburger menu icon
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      final hamburgerFinder = find.byIcon(Icons.menu_rounded);
      expect(hamburgerFinder, findsOneWidget);

      // Verify the 6 old cluttered action buttons are NOT directly in SliverAppBar.actions
      expect(find.byIcon(Icons.qr_code_2_rounded), findsNothing);
      expect(find.byIcon(Icons.file_download_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

      // 2. Tap hamburger menu to open popup
      await tester.tap(hamburgerFinder);
      await tester.pumpAndSettle();

      // 3. Verify all options are present in the popup menu
      expect(find.textContaining('Sync (Spotify)'), findsOneWidget);
      expect(find.text('Import Songs'), findsOneWidget);
      expect(find.text('Edit Playlist'), findsOneWidget);
      expect(find.text('Share & QR Code'), findsOneWidget);
      expect(find.text('Export .M3U8'), findsOneWidget);
      expect(find.text('Delete Playlist'), findsOneWidget);
    });

    testWidgets('Renders 3 equal-size action pills (Download, Import, Sync) under Play and Shuffle', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            smartPlaylistsProvider.overrideWith((ref) => [testPlaylist]),
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [testTrack];
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: PlaylistDetailsScreen(playlist: testPlaylist),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify Play All and Shuffle buttons exist
      expect(find.text('Play All'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);

      // 2. Verify all 3 small action pills exist
      final downloadPillText = find.text('Download');
      final importPillText = find.text('Import');
      final syncPillText = find.text('Sync');

      expect(downloadPillText, findsOneWidget);
      expect(importPillText, findsOneWidget);
      expect(syncPillText, findsOneWidget);

      // 3. Verify their bounding boxes to ensure equal size and distance
      final downloadRect = tester.getRect(downloadPillText);
      final importRect = tester.getRect(importPillText);
      final syncRect = tester.getRect(syncPillText);

      // The pills are all in the same vertical row
      expect((downloadRect.center.dy - importRect.center.dy).abs() < 5, isTrue);
      expect((importRect.center.dy - syncRect.center.dy).abs() < 5, isTrue);

      // Pills are ordered left to right: Download -> Import -> Sync
      expect(downloadRect.center.dx < importRect.center.dx, isTrue);
      expect(importRect.center.dx < syncRect.center.dx, isTrue);

      // Distance between Download and Import centers is equal to distance between Import and Sync centers
      final dist1 = importRect.center.dx - downloadRect.center.dx;
      final dist2 = syncRect.center.dx - importRect.center.dx;
      expect((dist1 - dist2).abs() < 25, isTrue);
    });
  });
}
