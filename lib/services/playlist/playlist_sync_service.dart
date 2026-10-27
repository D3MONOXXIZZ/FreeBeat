import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../state/app_providers.dart';
import 'playlist_import_service.dart';
import 'playlist_missing_tracks_sync_service.dart';

/// Outcome of a remote playlist sync operation.
class PlaylistSyncOutcome {
  const PlaylistSyncOutcome({
    required this.isSuccess,
    this.totalFoundInSource = 0,
    this.newMatchedTracksCount = 0,
    this.newMissingTracksCount = 0,
    required this.message,
    this.error,
  });

  final bool isSuccess;
  final int totalFoundInSource;
  final int newMatchedTracksCount;
  final int newMissingTracksCount;
  final String message;
  final String? error;

  int get totalNewTracksCount => newMatchedTracksCount + newMissingTracksCount;
}

/// Service that coordinates syncing an existing FreeBeat playlist with its
/// upstream source (Spotify, Apple Music, or YouTube playlist).
class PlaylistSyncService {
  PlaylistSyncService({PlaylistImportService? importService})
      : _importService = importService ?? const PlaylistImportService();

  final PlaylistImportService _importService;

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Syncs an existing playlist against its remote source (Spotify / Apple Music / YouTube).
  ///
  /// Extracts all tracks from the remote source playlist, diffs them against
  /// existing tracks currently in [playlist], appends matched library tracks immediately,
  /// and queues missing tracks for cloud resolution and upload via [missingTracksNotifier].
  Future<PlaylistSyncOutcome> syncPlaylist({
    required Playlist playlist,
    required String sourceUrl,
    required List<Track> allLibraryTracks,
    required PlaylistsNotifier playlistsNotifier,
    required PlaylistMissingTracksSyncNotifier missingTracksNotifier,
    required List<CloudAccount> cloudAccounts,
  }) async {
    final cleanUrl = sourceUrl.trim();
    if (cleanUrl.isEmpty) {
      return const PlaylistSyncOutcome(
        isSuccess: false,
        message: 'No source URL provided.',
        error: 'Missing URL',
      );
    }

    try {
      // 1. Fetch fresh playlist from source URL
      final importResult =
          await _importService.importFromUrl(cleanUrl, allLibraryTracks);

      if (importResult.totalParsed == 0) {
        return const PlaylistSyncOutcome(
          isSuccess: false,
          message:
              'No tracks found in remote playlist. Please ensure the link is public.',
          error: 'Empty remote playlist',
        );
      }

      // 2. Build identity lookup of tracks already inside the current playlist
      final currentTrackMap = {for (final t in allLibraryTracks) t.id: t};
      final existingPlaylistTracks = playlist.trackIds
          .map((id) => currentTrackMap[id])
          .whereType<Track>()
          .toList();

      final existingTrackIds = playlist.trackIds.toSet();
      final existingKeys = <String>{};
      for (final t in existingPlaylistTracks) {
        final key = '${_normalize(t.title)}:::${_normalize(t.artist)}';
        existingKeys.add(key);
      }

      // 3. Find truly NEW matched tracks not already in the playlist
      final newMatched = <Track>[];
      for (final t in importResult.matchedTracks) {
        final key = '${_normalize(t.title)}:::${_normalize(t.artist)}';
        if (!existingTrackIds.contains(t.id) && !existingKeys.contains(key)) {
          newMatched.add(t);
          existingTrackIds.add(t.id);
          existingKeys.add(key);
        }
      }

      // 4. Find truly NEW missing tracks not already in the playlist or matched.
      // Defensively check against allLibraryTracks in case an item was already imported into the library.
      final newMissing = <MissingTrackItem>[];
      for (final item in importResult.missingTracks) {
        final libraryMatch = PlaylistImportService.findBestMatch(
          item.title,
          item.artist,
          allLibraryTracks,
        );
        if (libraryMatch != null) {
          final libKey = '${_normalize(libraryMatch.title)}:::${_normalize(libraryMatch.artist)}';
          if (!existingTrackIds.contains(libraryMatch.id) && !existingKeys.contains(libKey)) {
            newMatched.add(libraryMatch);
            existingTrackIds.add(libraryMatch.id);
            existingKeys.add(libKey);
          }
          continue;
        }

        final key = '${_normalize(item.title)}:::${_normalize(item.artist)}';
        if (!existingKeys.contains(key)) {
          newMissing.add(item);
          existingKeys.add(key);
        }
      }

      // 5. Append new matched tracks immediately to the playlist
      if (newMatched.isNotEmpty) {
        await playlistsNotifier.addTracksToPlaylist(
          playlist.id,
          newMatched.map((t) => t.id).toList(),
        );
      }

      // 6. Update sync metadata on playlist
      await playlistsNotifier.updatePlaylistSyncSource(playlist.id, cleanUrl);
      await playlistsNotifier.updatePlaylistLastSynced(
          playlist.id, DateTime.now());

      // 7. Queue missing tracks for cloud resolution and upload if any
      if (newMissing.isNotEmpty) {
        final remoteAccounts = cloudAccounts
            .where((a) =>
                a.providerType != CloudProviderType.androidSaf &&
                a.providerType != CloudProviderType.demoCloud)
            .toList();

        final targetAccount = remoteAccounts.isNotEmpty
            ? remoteAccounts.first
            : (cloudAccounts.isNotEmpty
                ? cloudAccounts.first
                : const CloudAccount(
                    id: 'device_storage_import',
                    providerType: CloudProviderType.androidSaf,
                    displayName: 'Device Storage',
                    endpointOrFolder: '/FreeBeat Music/',
                  ));

        unawaited(
          missingTracksNotifier.startSync(
            missingTracks: newMissing,
            playlistId: playlist.id,
            playlistTitle: playlist.title,
            account: targetAccount,
          ),
        );
      }

      final totalNew = newMatched.length + newMissing.length;
      final sourceName = cleanUrl.contains('spotify')
          ? 'Spotify'
          : (cleanUrl.contains('apple')
              ? 'Apple Music'
              : (cleanUrl.contains('youtube') || cleanUrl.contains('youtu.be')
                  ? 'YouTube'
                  : 'source'));

      if (totalNew == 0) {
        final totalInSource = importResult.totalParsed;
        final currentCount = playlist.trackIds.length;
        final duplicateDifference = totalInSource > currentCount
            ? totalInSource - currentCount
            : 0;

        final countDetails = duplicateDifference > 0
            ? '$totalInSource tracks checked: $currentCount unique, $duplicateDifference duplicate source entries'
            : '$totalInSource tracks checked';

        return PlaylistSyncOutcome(
          isSuccess: true,
          totalFoundInSource: importResult.totalParsed,
          newMatchedTracksCount: 0,
          newMissingTracksCount: 0,
          message:
              'Playlist is already up to date with $sourceName ($countDetails). Note: Newly added songs on $sourceName may take 1-2 minutes to propagate across their CDN.',
        );
      }

      return PlaylistSyncOutcome(
        isSuccess: true,
        totalFoundInSource: importResult.totalParsed,
        newMatchedTracksCount: newMatched.length,
        newMissingTracksCount: newMissing.length,
        message: newMissing.isNotEmpty
            ? 'Added ${newMatched.length} tracks from library and syncing ${newMissing.length} new songs to cloud from $sourceName!'
            : 'Added $totalNew new tracks from $sourceName!',
      );
    } catch (e) {
      return PlaylistSyncOutcome(
        isSuccess: false,
        message: 'Sync failed: ${e.toString().replaceFirst('Exception: ', '')}',
        error: e.toString(),
      );
    }
  }
}

/// Provider for the PlaylistSyncService.
final playlistSyncServiceProvider = Provider<PlaylistSyncService>((ref) {
  return PlaylistSyncService();
});

