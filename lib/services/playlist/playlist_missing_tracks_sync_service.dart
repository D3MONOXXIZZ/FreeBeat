import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../state/app_providers.dart';
import '../audio/missing_track_audio_resolver.dart';
import '../audio/track_audio_tagger_service.dart';
import '../cloud/universal_cloud_upload_service.dart';
import '../haptics/pixel_haptics.dart';

/// Representation of an unresolved missing track entry.
class MissingTrackItem {
  const MissingTrackItem({
    required this.title,
    required this.artist,
    this.expectedDurationMs,
    this.preferredArtworkUrl,
  });

  final String title;
  final String artist;
  final int? expectedDurationMs;
  final String? preferredArtworkUrl;

  String get displayName =>
      artist.isNotEmpty ? '$artist - $title' : title;

  /// Parses a display string like "Artist - Title" or "Title" into a [MissingTrackItem].
  factory MissingTrackItem.fromString(String raw) {
    final trimmed = raw.trim();
    final parts = trimmed.split(' - ');
    if (parts.length >= 2) {
      return MissingTrackItem(
        artist: parts[0].trim(),
        title: parts.sublist(1).join(' - ').trim(),
      );
    }
    return MissingTrackItem(
      artist: '',
      title: trimmed,
    );
  }
}

enum SyncTrackStatus {
  pending,
  resolving,
  downloading,
  uploading,
  completed,
  failed,
}

class SyncTrackProgress {
  const SyncTrackProgress({
    required this.item,
    this.status = SyncTrackStatus.pending,
    this.error,
    this.completedTrack,
    this.progressFraction = 0.0,
  });

  final MissingTrackItem item;
  final SyncTrackStatus status;
  final String? error;
  final Track? completedTrack;
  final double progressFraction;

  SyncTrackProgress copyWith({
    SyncTrackStatus? status,
    String? error,
    Track? completedTrack,
    double? progressFraction,
  }) {
    return SyncTrackProgress(
      item: item,
      status: status ?? this.status,
      error: error ?? this.error,
      completedTrack: completedTrack ?? this.completedTrack,
      progressFraction: progressFraction ?? this.progressFraction,
    );
  }
}

class PlaylistMissingTracksSyncState {
  const PlaylistMissingTracksSyncState({
    this.isSyncing = false,
    this.activePlaylistId,
    this.activePlaylistTitle,
    this.activeCloudAccount,
    this.totalCount = 0,
    this.completedCount = 0,
    this.failedCount = 0,
    this.currentTrackTitle = '',
    this.currentStatusText = '',
    this.trackProgresses = const [],
    this.uploadedTracks = const [],
  });

  final bool isSyncing;
  final String? activePlaylistId;
  final String? activePlaylistTitle;
  final CloudAccount? activeCloudAccount;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final String currentTrackTitle;
  final String currentStatusText;
  final List<SyncTrackProgress> trackProgresses;
  final List<Track> uploadedTracks;

  double get overallProgress =>
      totalCount > 0 ? (completedCount + failedCount) / totalCount : 0.0;

  PlaylistMissingTracksSyncState copyWith({
    bool? isSyncing,
    String? activePlaylistId,
    String? activePlaylistTitle,
    CloudAccount? activeCloudAccount,
    int? totalCount,
    int? completedCount,
    int? failedCount,
    String? currentTrackTitle,
    String? currentStatusText,
    List<SyncTrackProgress>? trackProgresses,
    List<Track>? uploadedTracks,
  }) {
    return PlaylistMissingTracksSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      activePlaylistId: activePlaylistId ?? this.activePlaylistId,
      activePlaylistTitle: activePlaylistTitle ?? this.activePlaylistTitle,
      activeCloudAccount: activeCloudAccount ?? this.activeCloudAccount,
      totalCount: totalCount ?? this.totalCount,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
      currentStatusText: currentStatusText ?? this.currentStatusText,
      trackProgresses: trackProgresses ?? this.trackProgresses,
      uploadedTracks: uploadedTracks ?? this.uploadedTracks,
    );
  }
}

class PlaylistMissingTracksSyncNotifier
    extends StateNotifier<PlaylistMissingTracksSyncState> {
  PlaylistMissingTracksSyncNotifier({
    required Ref ref,
    MissingTrackAudioResolver? resolver,
    TrackAudioTaggerService? tagger,
    UniversalCloudUploadService? uploader,
  })  : _ref = ref,
        _resolver = resolver ?? MissingTrackAudioResolver(),
        _tagger = tagger ?? TrackAudioTaggerService(),
        _uploader = uploader ?? UniversalCloudUploadService(),
        super(const PlaylistMissingTracksSyncState());

  final Ref _ref;
  final MissingTrackAudioResolver _resolver;
  final TrackAudioTaggerService _tagger;
  final UniversalCloudUploadService _uploader;

  bool _isCancelled = false;

  void cancelSync() {
    _isCancelled = true;
    state = state.copyWith(
      isSyncing: false,
      currentStatusText: 'Sync cancelled by user',
    );
  }

  /// Initiates concurrent resolution, audio tagging, and cloud upload for
  /// all missing tracks in an imported playlist.
  Future<void> startSync({
    required List<MissingTrackItem> missingTracks,
    required String playlistId,
    required String playlistTitle,
    required CloudAccount account,
  }) async {
    if (missingTracks.isEmpty) return;

    _isCancelled = false;
    final credStore = _ref.read(credentialStoreProvider);
    final secrets = await credStore.readSecrets(account.id);

    final initialProgresses = missingTracks
        .map((item) => SyncTrackProgress(item: item))
        .toList();

    state = PlaylistMissingTracksSyncState(
      isSyncing: true,
      activePlaylistId: playlistId,
      activePlaylistTitle: playlistTitle,
      activeCloudAccount: account,
      totalCount: missingTracks.length,
      completedCount: 0,
      failedCount: 0,
      currentTrackTitle: missingTracks.first.displayName,
      currentStatusText: 'Starting cloud sync to ${account.displayName}...',
      trackProgresses: initialProgresses,
      uploadedTracks: [],
    );

    await PixelHaptics.tick();

    // Process queue with concurrency of 2 to balance throughput and network bandwidth
    const concurrency = 2;
    for (var i = 0; i < missingTracks.length && !_isCancelled; i += concurrency) {
      final batch = <Future<void>>[];
      for (var c = 0; c < concurrency && (i + c) < missingTracks.length && !_isCancelled; c++) {
        final idx = i + c;
        batch.add(_processSingleTrack(
          index: idx,
          item: missingTracks[idx],
          playlistId: playlistId,
          playlistName: playlistTitle,
          account: account,
          secrets: secrets,
        ));
      }
      if (batch.isNotEmpty) {
        await Future.wait(batch);
      }
    }

    state = state.copyWith(
      isSyncing: false,
      currentStatusText: _isCancelled
          ? 'Sync cancelled'
          : 'Sync complete (${state.completedCount} uploaded, ${state.failedCount} failed)',
    );

    if (!_isCancelled && state.completedCount > 0) {
      await PixelHaptics.hifiConfirm();
    }
  }

  Future<void> _processSingleTrack({
    required int index,
    required MissingTrackItem item,
    required String playlistId,
    required String playlistName,
    required CloudAccount account,
    required Map<String, String> secrets,
  }) async {
    if (_isCancelled) return;

    _updateTrackProgress(index, (p) => p.copyWith(status: SyncTrackStatus.resolving));
    state = state.copyWith(
      currentTrackTitle: item.displayName,
      currentStatusText: 'Resolving stream for "${item.displayName}"...',
    );

    try {
      // 1. Resolve Audio Stream
      final candidate = await _resolver.resolveTrackAudio(
        title: item.title,
        artist: item.artist,
        expectedDurationMs: item.expectedDurationMs,
      );

      if (candidate == null) {
        throw Exception('No stream candidate found for "${item.displayName}"');
      }

      if (_isCancelled) return;

      // 2. Download and Tag Audio
      _updateTrackProgress(index, (p) => p.copyWith(status: SyncTrackStatus.downloading));
      state = state.copyWith(
        currentStatusText: 'Downloading and preparing "${item.displayName}"...',
      );

      final preparedAudio = await _tagger.downloadAndPrepareAudio(
        candidate: candidate,
        targetTitle: item.title,
        targetArtist: item.artist,
        targetAlbum: playlistName,
        preferredArtworkUrl: item.preferredArtworkUrl,
        onProgress: (frac) {
          _updateTrackProgress(index, (p) => p.copyWith(progressFraction: frac * 0.5));
        },
      );

      if (_isCancelled) {
        await preparedAudio.purge();
        return;
      }

      // 3. Upload to Cloud
      _updateTrackProgress(index, (p) => p.copyWith(status: SyncTrackStatus.uploading));
      state = state.copyWith(
        currentStatusText: 'Uploading "${item.displayName}" to ${account.displayName}...',
      );

      final uploadedTrack = await _uploader.uploadPreparedTrack(
        preparedAudio: preparedAudio,
        account: account,
        secrets: secrets,
        playlistName: playlistName,
        onProgress: (frac) {
          _updateTrackProgress(index, (p) => p.copyWith(progressFraction: 0.5 + (frac * 0.5)));
        },
      );

      // 4. Register in Track Catalog and SQLite Database
      await _ref.read(tracksCatalogProvider.notifier).addIndexedTracks([uploadedTrack]);

      // 5. Append to Playlist
      await _ref.read(playlistsProvider.notifier).addTrackToPlaylist(playlistId, uploadedTrack.id);

      // 6. Update State
      _updateTrackProgress(
        index,
        (p) => p.copyWith(
          status: SyncTrackStatus.completed,
          completedTrack: uploadedTrack,
          progressFraction: 1.0,
        ),
      );

      state = state.copyWith(
        completedCount: state.completedCount + 1,
        uploadedTracks: [...state.uploadedTracks, uploadedTrack],
      );

      await PixelHaptics.tick();
    } catch (e) {
      debugPrint('Sync failed for ${item.displayName}: $e');
      _updateTrackProgress(
        index,
        (p) => p.copyWith(
          status: SyncTrackStatus.failed,
          error: e.toString(),
        ),
      );
      state = state.copyWith(
        failedCount: state.failedCount + 1,
      );
    }
  }

  void _updateTrackProgress(
    int index,
    SyncTrackProgress Function(SyncTrackProgress prev) updater,
  ) {
    final list = List<SyncTrackProgress>.from(state.trackProgresses);
    if (index >= 0 && index < list.length) {
      list[index] = updater(list[index]);
      state = state.copyWith(trackProgresses: list);
    }
  }

  @override
  void dispose() {
    _isCancelled = true;
    _resolver.close();
    super.dispose();
  }
}

/// Global provider for monitoring and managing missing track cloud synchronization.
final playlistMissingTracksSyncProvider = StateNotifierProvider<
    PlaylistMissingTracksSyncNotifier, PlaylistMissingTracksSyncState>((ref) {
  return PlaylistMissingTracksSyncNotifier(ref: ref);
});
