import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';
import 'package:freebeat/services/playlist/playlist_missing_tracks_sync_service.dart';
import 'package:freebeat/services/playlist/playlist_sync_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  group('Spotify 121-track Playlist Pagination & Sync Re-matching Tests', () {
    const targetPlaylistUrl =
        'https://open.spotify.com/playlist/6SL7RnFAkFrRKKdjFRiAtg';

    test('Live Spotify import parses all 121 tracks beyond 100 limit',
        () async {
      final importService = const PlaylistImportService();
      final result = await importService.importFromUrl(targetPlaylistUrl, []);

      expect(result.sourceType, 'spotify');
      expect(result.totalParsed, greaterThanOrEqualTo(121));

      // Verify tracks beyond track 100 are present
      final hasTrackBeyond100 = result.missingTracks.any((t) =>
          t.title.toLowerCase().contains('two of us') ||
          t.title.toLowerCase().contains('maikhana') ||
          t.title.toLowerCase().contains('head over heels'));
      expect(hasTrackBeyond100, isTrue);
    });

    test(
        'PlaylistSyncService reconciles manually imported library tracks into playlist',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final playlistsNotifier = container.read(playlistsProvider.notifier);
      final missingTracksNotifier =
          container.read(playlistMissingTracksSyncProvider.notifier);

      // Create playlist initially with 90 dummy tracks
      final initialTrackIds = List.generate(90, (i) => 'dummy_track_$i');
      await playlistsNotifier.createPlaylist('JANI 👑');
      final created = container.read(playlistsProvider).first;
      await playlistsNotifier.addTracksToPlaylist(created.id, initialTrackIds);

      // Now simulate user having manually imported track #101 "Two of Us" by Jokhay & JANI into their library
      const missingTrackInLibrary = Track(
        id: 'library_two_of_us_id',
        accountId: 'acc1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'remote/path/101',
        title: 'Two of Us',
        artist: 'Jokhay, JANI, Shareh',
        album: 'Emotional Baggage',
        durationMs: 214588,
        streamUrl: 'https://example.com/two_of_us.mp3',
      );

      final allLibraryTracks = [missingTrackInLibrary];

      final syncService = PlaylistSyncService();
      final outcome = await syncService.syncPlaylist(
        playlist: container
            .read(playlistsProvider)
            .firstWhere((p) => p.id == created.id),
        sourceUrl: targetPlaylistUrl,
        allLibraryTracks: allLibraryTracks,
        playlistsNotifier: playlistsNotifier,
        missingTracksNotifier: missingTracksNotifier,
        cloudAccounts: const [
          CloudAccount(
            id: 'test_drive',
            providerType: CloudProviderType.googleDrive,
            displayName: 'Google Drive',
            endpointOrFolder: 'FreeBeat',
          ),
        ],
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.newMatchedTracksCount, greaterThanOrEqualTo(1));

      final updatedPlaylist = container
          .read(playlistsProvider)
          .firstWhere((p) => p.id == created.id);

      // Verify the missing track was successfully appended to the playlist's trackIds!
      expect(
          updatedPlaylist.trackIds.contains('library_two_of_us_id'), isTrue);

      missingTracksNotifier.cancelSync();
    });

    test('findBestMatch matches tracks with reordered artist names', () {
      const libraryTrack = Track(
        id: 't1',
        accountId: 'a1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'p1',
        title: 'Two of Us',
        artist: 'JANI & Jokhay',
        album: 'Emotional Baggage',
        durationMs: 200000,
        streamUrl: 'http://example.com/1',
      );

      // Query from Spotify has different artist ordering and formatting
      final match = PlaylistImportService.findBestMatch(
        'Two of Us',
        'Jokhay, JANI, Shareh',
        [libraryTrack],
      );

      expect(match, isNotNull);
      expect(match!.id, 't1');
    });
  });
}

