import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../state/app_providers.dart';
import '../audio/missing_track_audio_resolver.dart';
import '../audio/track_audio_tagger_service.dart';
import '../cloud/universal_cloud_upload_service.dart';
import '../engine/track_resolution_gateway.dart';
import '../haptics/pixel_haptics.dart';

/// Representation of an unresolved missing track entry.
class MissingTrackItem {
  const MissingTrackItem({
    required this.title,
    required this.artist,
    this.expectedDurationMs,
    this.preferredArtworkUrl,
    this.previewAudioUrl,
    this.album,
    this.sourceUrl,
  });

  final String title;
  final String artist;
  final int? expectedDurationMs;
  final String? preferredArtworkUrl;
  final String? previewAudioUrl;
  final String? album;
  final String? sourceUrl;

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

enum CloudAuthDecision {
  saveToLocalStorage,
  retryWithFreshAuth,
  cancel,
}

class CloudAuthPromptRequest {
  const CloudAuthPromptRequest({
    required this.account,
    required this.playlistTitle,
    required this.playlistId,
    required this.errorMessage,
  });

  final CloudAccount account;
  final String playlistTitle;
  final String playlistId;
  final String errorMessage;
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
    this.pendingAuthPrompt,
    this.fallbackToLocalStorageApproved = false,
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
  final CloudAuthPromptRequest? pendingAuthPrompt;
  final bool fallbackToLocalStorageApproved;

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
    CloudAuthPromptRequest? Function()? pendingAuthPrompt,
    bool? fallbackToLocalStorageApproved,
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
      pendingAuthPrompt: pendingAuthPrompt != null ? pendingAuthPrompt() : this.pendingAuthPrompt,
      fallbackToLocalStorageApproved: fallbackToLocalStorageApproved ?? this.fallbackToLocalStorageApproved,
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
    TrackResolutionGateway? resolutionGateway,
  })  : _ref = ref,
        _resolver = resolver ?? MissingTrackAudioResolver(),
        _tagger = tagger ?? TrackAudioTaggerService(),
        _uploader = uploader ?? UniversalCloudUploadService(),
        _resolutionGateway = resolutionGateway ??
            TrackResolutionGateway(
              resolver: resolver,
            ),
        super(const PlaylistMissingTracksSyncState());

  final Ref _ref;
  final MissingTrackAudioResolver _resolver;
  final TrackAudioTaggerService _tagger;
  final UniversalCloudUploadService _uploader;
  final TrackResolutionGateway _resolutionGateway;

  bool _isCancelled = false;
  Completer<CloudAuthDecision>? _authDecisionCompleter;
  Future<void>? _resolveChain;

  void cancelSync() {
    _isCancelled = true;
    if (!mounted) return;
    state = state.copyWith(
      isSyncing: false,
      pendingAuthPrompt: () => null,
      currentStatusText: 'Sync cancelled by user',
    );
    if (_authDecisionCompleter != null && !_authDecisionCompleter!.isCompleted) {
      _authDecisionCompleter!.complete(CloudAuthDecision.cancel);
    }
  }

  Future<CloudAuthDecision> _requestAuthDecision({
    required CloudAccount account,
    required String playlistTitle,
    required String playlistId,
    required String errorMessage,
  }) async {
    if (!mounted) return CloudAuthDecision.cancel;
    if (state.fallbackToLocalStorageApproved) {
      return CloudAuthDecision.saveToLocalStorage;
    }
    if (_isCancelled) {
      return CloudAuthDecision.cancel;
    }

    _authDecisionCompleter = Completer<CloudAuthDecision>();
    state = state.copyWith(
      pendingAuthPrompt: () => CloudAuthPromptRequest(
        account: account,
        playlistTitle: playlistTitle,
        playlistId: playlistId,
        errorMessage: errorMessage,
      ),
      currentStatusText: 'Cloud auth error on ${account.displayName}. Prompting user...',
    );

    return await _authDecisionCompleter!.future;
  }

  void confirmAuthFallbackToLocalStorage() {
    if (!mounted) return;
    state = state.copyWith(
      pendingAuthPrompt: () => null,
      fallbackToLocalStorageApproved: true,
      currentStatusText: 'Switched to Device Storage. Saving tracks...',
    );
    if (_authDecisionCompleter != null && !_authDecisionCompleter!.isCompleted) {
      _authDecisionCompleter!.complete(CloudAuthDecision.saveToLocalStorage);
    }
  }

  void retryAuthWithFreshToken(String newToken) {
    if (!mounted) return;
    state = state.copyWith(
      pendingAuthPrompt: () => null,
      currentStatusText: 'Cloud credentials updated. Retrying upload...',
    );
    if (_authDecisionCompleter != null && !_authDecisionCompleter!.isCompleted) {
      _authDecisionCompleter!.complete(CloudAuthDecision.retryWithFreshAuth);
    }
  }

  void cancelAuthPromptAndSync() {
    cancelSync();
  }

  /// Initiates concurrent resolution, audio tagging, and cloud upload for
  /// all missing tracks in an imported playlist.
  Future<void> startSync({
    required List<MissingTrackItem> missingTracks,
    required String playlistId,
    required String playlistTitle,
    required CloudAccount account,
    bool fallbackToLocalStorageApproved = false,
  }) async {
    if (missingTracks.isEmpty) return;

    _isCancelled = false;
    _resolveChain = null;
    final credStore = _ref.read(credentialStoreProvider);
    var secrets = await credStore.readSecrets(account.id);

    if (account.providerType == CloudProviderType.googleDrive) {
      final token = secrets['accessToken'];
      if (token == null || token.isEmpty) {
        try {
          final authService = _ref.read(nativeCloudAuthServiceProvider);
          final freshToken = await authService.getFreshGoogleAccessToken();
          if (freshToken != null && freshToken.isNotEmpty) {
            secrets = {'accessToken': freshToken};
            await credStore.saveSecrets(account.id, secrets);
          }
        } catch (_) {}
      }
    }

    final isRemote = account.providerType != CloudProviderType.androidSaf &&
        account.providerType != CloudProviderType.demoCloud;
    final hasCredentials = (secrets['accessToken'] ?? '').isNotEmpty ||
        (secrets['password'] ?? '').isNotEmpty ||
        (secrets['accessKeyId'] ?? '').isNotEmpty ||
        (secrets['username'] ?? '').isNotEmpty;

    if (isRemote && !hasCredentials && !fallbackToLocalStorageApproved) {
      final decision = await _requestAuthDecision(
        account: account,
        playlistTitle: playlistTitle,
        playlistId: playlistId,
        errorMessage: 'Missing login credentials for ${account.displayName}',
      );
      if (decision == CloudAuthDecision.cancel) {
        cancelSync();
        return;
      } else if (decision == CloudAuthDecision.saveToLocalStorage) {
        fallbackToLocalStorageApproved = true;
      }
    }

    final initialProgresses = missingTracks
        .map((item) => SyncTrackProgress(item: item))
        .toList();

    if (!mounted) return;
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
      fallbackToLocalStorageApproved: fallbackToLocalStorageApproved,
    );

    await PixelHaptics.tick();

    // Continuous sliding-window worker pool (concurrency: 3)
    // Eliminates blocking batch barriers and stalls while keeping upstream bandwidth smooth.
    const maxConcurrency = 3;
    var nextTrackIndex = 0;
    final activeFutures = <Future<void>>{};

    while ((nextTrackIndex < missingTracks.length || activeFutures.isNotEmpty) &&
        !_isCancelled &&
        mounted) {
      while (activeFutures.length < maxConcurrency &&
          nextTrackIndex < missingTracks.length &&
          !_isCancelled &&
          mounted) {
        final idx = nextTrackIndex++;
        final trackItem = missingTracks[idx];

        if (mounted) {
          state = state.copyWith(
            currentStatusText:
                'Processing track ${idx + 1} of ${missingTracks.length}: "${trackItem.displayName}"...',
          );
        }

        late Future<void> workerFuture;
        workerFuture = (() async {
          try {
            await _processSingleTrack(
              index: idx,
              item: trackItem,
              playlistId: playlistId,
              playlistName: playlistTitle,
              account: account,
              secrets: secrets,
            ).timeout(const Duration(seconds: 90));
          } catch (e) {
            debugPrint('Worker timeout or error on track $idx: $e');
            _updateTrackProgress(
              idx,
              (p) => p.copyWith(
                status: SyncTrackStatus.failed,
                error: e.toString(),
              ),
            );
            if (mounted) {
              state = state.copyWith(
                failedCount: state.failedCount + 1,
              );
            }
          } finally {
            activeFutures.remove(workerFuture);
          }
        })();

        activeFutures.add(workerFuture);
      }

      if (activeFutures.isNotEmpty) {
        await Future.any(activeFutures);
      }
    }

    if (mounted) {
      state = state.copyWith(
        isSyncing: false,
        currentStatusText: _isCancelled
            ? 'Sync cancelled'
            : 'Sync complete (${state.completedCount} uploaded, ${state.failedCount} failed)',
      );
    }

    if (!_isCancelled && state.completedCount > 0) {
      await PixelHaptics.hifiConfirm();
    }
  }

  Future<Track?> _processSingleTrack({
    required int index,
    required MissingTrackItem item,
    required String playlistId,
    required String playlistName,
    required CloudAccount account,
    required Map<String, String> secrets,
  }) async {
    if (_isCancelled) return null;

    // STEP 0: Check if this track already exists in the cloud folder or local storage
    // (e.g. if the user deleted and re-imported the playlist, or if it was previously synced).
    // Reusing the existing cloud track completely bypasses YouTube stream resolution,
    // audio download, and uploading, saving bandwidth and preventing duplicate files in Drive!
    try {
      final existingTrack = await _uploader.findExistingCloudTrack(
        account: account,
        secrets: secrets,
        playlistName: playlistName,
        title: item.title,
        artist: item.artist,
        expectedDurationMs: item.expectedDurationMs,
        preferredArtworkUrl: item.preferredArtworkUrl,
        preferredAlbum: item.album,
      );

      if (existingTrack != null) {
        // Register in tracks catalog and add to playlist
        await _ref.read(tracksCatalogProvider.notifier).addIndexedTracks([existingTrack]);
        await _ref.read(playlistsProvider.notifier).addTracksToPlaylist(
              playlistId,
              [existingTrack.id],
            );
        if (existingTrack.artworkUrl != null && existingTrack.artworkUrl!.isNotEmpty) {
          unawaited(_ref.read(playlistsProvider.notifier).updatePlaylistArtwork(playlistId, existingTrack.artworkUrl!));
        }

        _updateTrackProgress(
          index,
          (p) => p.copyWith(
            status: SyncTrackStatus.completed,
            completedTrack: existingTrack,
            progressFraction: 1.0,
          ),
        );

        state = state.copyWith(
          completedCount: state.completedCount + 1,
          uploadedTracks: [...state.uploadedTracks, existingTrack],
        );

        await PixelHaptics.tick();
        return existingTrack;
      }
    } catch (e) {
      debugPrint('Cloud deduplication check error for "${item.displayName}": $e');
    }

    _updateTrackProgress(index, (p) => p.copyWith(status: SyncTrackStatus.resolving));
    state = state.copyWith(
      currentTrackTitle: item.displayName,
      currentStatusText: 'Resolving stream for "${item.displayName}"...',
    );

    try {
      // Pacing gate: FIFO asynchronous lock ensures stream resolution queries are paced sequentially
      // to eliminate burst rate-limiting while allowing audio downloads and uploads to remain fully concurrent.
      final prevGate = _resolveChain;
      final currentGate = Completer<void>();
      _resolveChain = currentGate.future;
      if (prevGate != null) {
        await prevGate;
      }

      ResolvedAudioBundle? bundle;
      try {
        // 1. Resolve Audio Stream via Quality-Max Gateway (320kbps Studio Masters or YouTube Music)
        bundle = await _resolutionGateway.resolveAudioBundle(
          title: item.title,
          artist: item.artist,
          expectedDurationMs: item.expectedDurationMs,
          spotifyUrlOrUri: item.sourceUrl,
          preferredArtworkUrl: item.preferredArtworkUrl,
          preferredAlbum: item.album,
        );
      } finally {
        await Future.delayed(const Duration(milliseconds: 150));
        if (!currentGate.isCompleted) currentGate.complete();
      }

      if (bundle == null) {
        throw Exception('No stream candidate found for "${item.displayName}"');
      }

      if (_isCancelled) return null;

      final candidate = bundle.candidate;

      // 2. Download and Tag Audio
      _updateTrackProgress(index, (p) => p.copyWith(status: SyncTrackStatus.downloading));
      state = state.copyWith(
        currentStatusText: 'Downloading "${item.displayName}" (0%)...',
      );

      final preparedAudio = await _tagger.downloadAndPrepareAudio(
        candidate: candidate,
        targetTitle: bundle.title,
        targetArtist: bundle.artist,
        targetAlbum: bundle.album,
        preferredArtworkUrl: bundle.artworkUrl ?? item.preferredArtworkUrl,
        sourceUrl: item.sourceUrl,
        onProgress: (frac) {
          final pct = (frac * 100).toInt();
          _updateTrackProgress(index, (p) => p.copyWith(progressFraction: frac * 0.5));
          state = state.copyWith(
            currentStatusText: 'Downloading "${item.displayName}" ($pct%)...',
          );
        },
      );

      if (_isCancelled) {
        await preparedAudio.purge();
        return null;
      }

      // 3. Upload to Cloud (with Graceful Local Music Fallback)
      _updateTrackProgress(index, (p) => p.copyWith(status: SyncTrackStatus.uploading));
      state = state.copyWith(
        currentStatusText: 'Uploading "${item.displayName}" to ${account.displayName}...',
      );

      Track uploadedTrack;
      try {
        uploadedTrack = await _uploader.uploadPreparedTrack(
          preparedAudio: preparedAudio,
          account: account,
          secrets: secrets,
          playlistName: playlistName,
          onProgress: (frac) {
            final pct = (frac * 100).toInt();
            _updateTrackProgress(index, (p) => p.copyWith(progressFraction: 0.5 + (frac * 0.5)));
            state = state.copyWith(
              currentStatusText: 'Uploading "${item.displayName}" ($pct%)...',
            );
          },
          onTokenExpired: () async {
            try {
              final authService = _ref.read(nativeCloudAuthServiceProvider);
              final freshToken = await authService.getFreshGoogleAccessToken();
              if (freshToken != null && freshToken.isNotEmpty) {
                secrets['accessToken'] = freshToken;
                final credStore = _ref.read(credentialStoreProvider);
                await credStore.saveSecrets(account.id, secrets);
                return freshToken;
              }
            } catch (_) {}
            return null;
          },
        );
      } catch (cloudErr) {
        final isAuthErr = cloudErr is CloudUploadException &&
            (cloudErr.statusCode == 401 ||
                cloudErr.statusCode == 403 ||
                cloudErr.message.toLowerCase().contains('token') ||
                cloudErr.message.toLowerCase().contains('auth') ||
                cloudErr.message.toLowerCase().contains('credential'));

        if (isAuthErr && !state.fallbackToLocalStorageApproved) {
          final decision = await _requestAuthDecision(
            account: account,
            playlistTitle: playlistName,
            playlistId: playlistId,
            errorMessage: cloudErr.toString(),
          );

          if (decision == CloudAuthDecision.cancel) {
            _isCancelled = true;
            await preparedAudio.purge();
            throw Exception('Sync cancelled by user upon cloud auth prompt');
          } else if (decision == CloudAuthDecision.retryWithFreshAuth) {
            final freshSecrets = await _ref.read(credentialStoreProvider).readSecrets(account.id);
            secrets.addAll(freshSecrets);
            return await _processSingleTrack(
              index: index,
              item: item,
              playlistId: playlistId,
              playlistName: playlistName,
              account: account,
              secrets: secrets,
            );
          }
        }

        debugPrint(
          'Cloud upload failed for "${item.displayName}" ($cloudErr). '
          'Gracefully saving to on-device Music folder for playlist "$playlistName"',
        );
        state = state.copyWith(
          currentStatusText: 'Saving "${item.displayName}" to Music folder...',
        );
        uploadedTrack = await _uploader.uploadToLocalStorage(
          preparedAudio: preparedAudio,
          account: account,
          playlistName: playlistName,
          onProgress: (frac) {
            _updateTrackProgress(index, (p) => p.copyWith(progressFraction: 1.0));
          },
        );
      }

      // LIVE PLAYLIST AND CATALOG INJECTION:
      // Immediately index track and append to playlist so it appears on screen without delay!
      await _ref.read(tracksCatalogProvider.notifier).addIndexedTracks([uploadedTrack]);
      await _ref.read(playlistsProvider.notifier).addTracksToPlaylist(
            playlistId,
            [uploadedTrack.id],
          );
      if (uploadedTrack.artworkUrl != null && uploadedTrack.artworkUrl!.isNotEmpty) {
        unawaited(_ref.read(playlistsProvider.notifier).updatePlaylistArtwork(playlistId, uploadedTrack.artworkUrl!));
      }

      // 4. Update Track State
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
      return uploadedTrack;
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
      return null;
    }
  }

  void _updateTrackProgress(
    int index,
    SyncTrackProgress Function(SyncTrackProgress prev) updater,
  ) {
    if (!mounted) return;
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
