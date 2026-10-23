import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../core/storage/secure_credential_store.dart';
import '../metadata/artwork_extractor.dart';

enum CacheState {
  notCached,
  caching,
  cached,
  failed,
}

class CacheProgress {
  const CacheProgress({
    required this.state,
    this.progress = 0.0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorMessage,
    this.localPath,
  });

  final CacheState state;
  final double progress;
  final int bytesDownloaded;
  final int totalBytes;
  final String? errorMessage;
  final String? localPath;
}

class StorageUsageInfo {
  const StorageUsageInfo({
    required this.pinnedBytes,
    required this.streamCacheBytes,
    required this.transcodedBytes,
    required this.totalAppCacheBytes,
    required this.freeDiskBytes,
    this.nativeCacheBytes = 0,
  });

  final int pinnedBytes;
  final int streamCacheBytes;
  final int transcodedBytes;
  final int totalAppCacheBytes;
  final int freeDiskBytes;
  final int nativeCacheBytes;

  String get pinnedFormatted => _formatBytes(pinnedBytes);
  String get streamCacheFormatted => _formatBytes(streamCacheBytes);
  String get transcodedFormatted => _formatBytes(transcodedBytes);
  String get totalFormatted => _formatBytes(totalAppCacheBytes);
  String get freeFormatted => _formatBytes(freeDiskBytes);
  String get nativeCacheFormatted => _formatBytes(nativeCacheBytes);

  static String formatBytes(int bytes) => _formatBytes(bytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Service that manages streaming directly from Google Drive / Cloud providers
/// and caching full audio tracks permanently in the app's offline storage.
class CloudAudioCacheService extends ChangeNotifier {
  CloudAudioCacheService({
    required this.credentialStore,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final SecureCredentialStore credentialStore;
  final http.Client _client;

  Directory? _cacheDir;
  final Map<String, CacheProgress> _progressMap = {};

  CacheProgress getProgress(String trackId) {
    return _progressMap[trackId] ?? const CacheProgress(state: CacheState.notCached);
  }

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) {
      return _cacheDir!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'cached_music'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Determines whether [track] is explicitly pinned offline or downloaded by user.
  bool isTrackCached(Track track) {
    if (track.isPinnedOffline) return true;
    if (track.localCachePath != null && track.localCachePath!.isNotEmpty) {
      if (File(track.localCachePath!).existsSync() && track.isPinnedOffline) {
        return true;
      }
    }
    return false;
  }

  /// Resolves the local file path if cached, or returns null.
  Future<String?> getCachedFilePath(Track track) async {
    if (track.localCachePath != null && track.localCachePath!.isNotEmpty) {
      if (File(track.localCachePath!).existsSync()) {
        return track.localCachePath!;
      }
    }
    final dir = await _getCacheDirectory();
    final sanitizedId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ext = _getExtensionForTrack(track);
    final file = File(p.join(dir.path, '$sanitizedId.$ext'));
    if (file.existsSync() && file.lengthSync() > 1024) {
      return file.path;
    }
    return null;
  }

  /// Caches [track] to local storage in the background, downloading it from Google Drive or stream URL.
  Future<String?> cacheTrack(
    Track track, {
    void Function(Track updatedTrack)? onComplete,
    bool markPinnedOffline = true,
  }) async {
    // If already cached, notify immediately
    final existingPath = await getCachedFilePath(track);
    if (existingPath != null) {
      _progressMap[track.id] = CacheProgress(
        state: CacheState.cached,
        progress: 1.0,
        localPath: existingPath,
      );
      notifyListeners();
      return existingPath;
    }

    if (_progressMap[track.id]?.state == CacheState.caching) {
      return null; // Already in progress
    }

    _progressMap[track.id] = const CacheProgress(
      state: CacheState.caching,
      progress: 0.05,
    );
    notifyListeners();

    try {
      final dir = await _getCacheDirectory();
      final sanitizedId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final ext = _getExtensionForTrack(track);
      final finalFile = File(p.join(dir.path, '$sanitizedId.$ext'));
      final tempFile = File(p.join(dir.path, '$sanitizedId.part'));

      // If source is a local file already (e.g. from device storage picker)
      if (File(track.streamUrl).existsSync()) {
        _progressMap[track.id] = CacheProgress(
          state: CacheState.cached,
          progress: 1.0,
          localPath: track.streamUrl,
        );
        notifyListeners();

        final updated = track.copyWith(
          isPinnedOffline: markPinnedOffline ? true : track.isPinnedOffline,
          localCachePath: track.streamUrl,
        );
        onComplete?.call(updated);
        return track.streamUrl;
      }

      // Build authenticated download request
      final uri = Uri.parse(track.streamUrl);
      final headers = <String, String>{};

      if (track.providerType == CloudProviderType.googleDrive) {
        final secrets = await credentialStore.readSecrets(track.accountId);
        final token = secrets['accessToken'] ?? '';
        if (token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      }

      final request = http.Request('GET', uri)..headers.addAll(headers);
      final streamedResponse = await _client.send(request);

      if (streamedResponse.statusCode != 200 &&
          streamedResponse.statusCode != 206) {
        _progressMap[track.id] = CacheProgress(
          state: CacheState.failed,
          errorMessage: 'Server returned HTTP ${streamedResponse.statusCode}',
        );
        notifyListeners();
        return null;
      }

      final totalBytes = streamedResponse.contentLength ?? track.sizeBytes;
      int downloaded = 0;
      final sink = tempFile.openWrite();
      DateTime lastNotifyTime = DateTime.now();
      int lastNotifyBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloaded += chunk.length;

        final now = DateTime.now();
        final bytesDelta = downloaded - lastNotifyBytes;
        final timeDelta = now.difference(lastNotifyTime);

        if (timeDelta.inMilliseconds >= 500 || bytesDelta >= 512 * 1024) {
          lastNotifyTime = now;
          lastNotifyBytes = downloaded;
          final progress = totalBytes > 0
              ? (downloaded / totalBytes).clamp(0.0, 0.99)
              : 0.0;
          _progressMap[track.id] = CacheProgress(
            state: CacheState.caching,
            progress: progress,
            bytesDownloaded: downloaded,
            totalBytes: totalBytes,
          );
          notifyListeners();
        }
      }

      await sink.flush();
      await sink.close();

      if (finalFile.existsSync()) {
        try {
          finalFile.deleteSync();
        } catch (_) {}
      }
      await tempFile.rename(finalFile.path);

      // Extract embedded artwork from downloaded file if missing
      String? artUrl = track.artworkUrl;
      if (artUrl == null || artUrl.isEmpty) {
        artUrl = await ArtworkExtractor.extractEmbeddedArtwork(finalFile, track.id);
      }

      _progressMap[track.id] = CacheProgress(
        state: CacheState.cached,
        progress: 1.0,
        bytesDownloaded: downloaded,
        totalBytes: downloaded,
        localPath: finalFile.path,
      );
      notifyListeners();

      final updated = track.copyWith(
        isPinnedOffline: markPinnedOffline ? true : track.isPinnedOffline,
        localCachePath: finalFile.path,
        artworkUrl: artUrl ?? track.artworkUrl,
        sizeBytes: downloaded > 0 ? downloaded : track.sizeBytes,
      );
      onComplete?.call(updated);
      return finalFile.path;
    } catch (e) {
      _progressMap[track.id] = CacheProgress(
        state: CacheState.failed,
        errorMessage: e.toString(),
      );
      notifyListeners();
      return null;
    }
  }

  final Set<String> _preloadingTrackIds = {};

  /// Preloads up to [preloadCount] (at least 5) upcoming tracks in the queue into local stream cache.
  Future<void> preloadQueueTracks(
    List<Track> queue, {
    required String currentTrackId,
    int preloadCount = 5,
    void Function(Track updatedTrack)? onTrackCached,
  }) async {
    if (queue.isEmpty || currentTrackId.isEmpty) return;
    final currIdx = queue.indexWhere((t) => t.id == currentTrackId);
    if (currIdx == -1) return;

    final upcoming = <Track>[];
    for (int i = 1; i <= preloadCount && i < queue.length; i++) {
      final targetIdx = (currIdx + i) % queue.length;
      upcoming.add(queue[targetIdx]);
    }
    if (upcoming.isEmpty) return;

    for (final track in upcoming) {
      if (_preloadingTrackIds.contains(track.id)) continue;
      // If already a local file or already cached on disk, skip
      if (!track.streamUrl.startsWith('http://') &&
          !track.streamUrl.startsWith('https://') &&
          File(track.streamUrl).existsSync()) {
        continue;
      }
      if (track.localCachePath != null && File(track.localCachePath!).existsSync()) {
        continue;
      }
      final existing = await getCachedFilePath(track);
      if (existing != null && File(existing).existsSync()) {
        continue;
      }

      _preloadingTrackIds.add(track.id);
      try {
        await cacheTrack(
          track,
          markPinnedOffline: false,
          onComplete: (updated) {
            onTrackCached?.call(updated);
          },
        );
      } catch (_) {
      } finally {
        _preloadingTrackIds.remove(track.id);
      }
    }
  }

  /// Removes cached file from disk.
  Future<void> removeCachedTrack(Track track) async {
    try {
      final path = await getCachedFilePath(track);
      if (path != null) {
        final f = File(path);
        if (f.existsSync()) {
          f.deleteSync();
        }
      }
      _progressMap[track.id] = const CacheProgress(state: CacheState.notCached);
      notifyListeners();
    } catch (_) {}
  }

  /// Computes storage usage breakdown across pinned offline tracks, unpinned stream cache,
  /// transcoded audio files, and native Android cache.
  Future<StorageUsageInfo> getStorageUsage(List<Track> catalogTracks) async {
    int pinnedBytes = 0;
    int streamCacheBytes = 0;
    int transcodedBytes = 0;
    int nativeCacheBytes = 0;

    try {
      final cacheDir = await _getCacheDirectory();
      final pinnedPaths = catalogTracks
          .where((t) => t.isPinnedOffline && t.localCachePath != null)
          .map((t) => t.localCachePath!)
          .toSet();

      final pinnedIds = catalogTracks
          .where((t) => t.isPinnedOffline)
          .map((t) => t.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'))
          .toSet();

      if (cacheDir.existsSync()) {
        for (final entity in cacheDir.listSync()) {
          if (entity is File) {
            final len = entity.lengthSync();
            final baseName = p.basenameWithoutExtension(entity.path);
            final isPinned = pinnedPaths.contains(entity.path) || pinnedIds.contains(baseName);
            if (isPinned) {
              pinnedBytes += len;
            } else {
              streamCacheBytes += len;
            }
          }
        }
      }

      // Check temporary transcoded WAV cache directory and inputs
      final tempDir = await getTemporaryDirectory();
      final transcodeDir = Directory(p.join(tempDir.path, 'transcoded_audio'));
      if (transcodeDir.existsSync()) {
        for (final entity in transcodeDir.listSync()) {
          if (entity is File) {
            transcodedBytes += entity.lengthSync();
          }
        }
      }

      final transcodeInDir = Directory(p.join(tempDir.path, 'transcode_in'));
      if (transcodeInDir.existsSync()) {
        for (final entity in transcodeInDir.listSync()) {
          if (entity is File) {
            transcodedBytes += entity.lengthSync();
          }
        }
      }

      // Query native Android cache size (file_picker, cacheDir, externalCacheDir)
      if (Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.freebeat.freebeat/native_cloud_auth');
          final result = await channel.invokeMethod<int>('getAppCacheSize');
          if (result != null && result > 0) {
            nativeCacheBytes = result;
          }
        } catch (_) {}
      }
    } catch (_) {}

    final totalStreamAndNative = streamCacheBytes + nativeCacheBytes;
    final totalAppCacheBytes = pinnedBytes + totalStreamAndNative + transcodedBytes;
    return StorageUsageInfo(
      pinnedBytes: pinnedBytes,
      streamCacheBytes: totalStreamAndNative,
      transcodedBytes: transcodedBytes,
      totalAppCacheBytes: totalAppCacheBytes,
      nativeCacheBytes: nativeCacheBytes,
      freeDiskBytes: 15 * 1024 * 1024 * 1024,
    );
  }

  /// Clears only unpinned streaming cache, temporary transcoded audio files,
  /// and any native file_picker / temporary caches.
  /// Strictly preserves all user-pinned offline downloads.
  Future<int> clearStreamCache(List<Track> catalogTracks) async {
    int reclaimedBytes = 0;
    try {
      final cacheDir = await _getCacheDirectory();
      final pinnedPaths = catalogTracks
          .where((t) => t.isPinnedOffline && t.localCachePath != null)
          .map((t) => t.localCachePath!)
          .toSet();

      final pinnedIds = catalogTracks
          .where((t) => t.isPinnedOffline)
          .map((t) => t.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'))
          .toSet();

      if (cacheDir.existsSync()) {
        for (final entity in cacheDir.listSync()) {
          if (entity is File) {
            final baseName = p.basenameWithoutExtension(entity.path);
            final isPinned = pinnedPaths.contains(entity.path) || pinnedIds.contains(baseName);
            if (!isPinned) {
              final len = entity.lengthSync();
              try {
                entity.deleteSync();
                reclaimedBytes += len;
              } catch (_) {}
            }
          }
        }
      }

      // Also clean temporary transcoded files and staging copies
      final tempDir = await getTemporaryDirectory();
      final transcodeDir = Directory(p.join(tempDir.path, 'transcoded_audio'));
      if (transcodeDir.existsSync()) {
        for (final entity in transcodeDir.listSync()) {
          if (entity is File) {
            final len = entity.lengthSync();
            try {
              entity.deleteSync();
              reclaimedBytes += len;
            } catch (_) {}
          }
        }
      }

      final transcodeInDir = Directory(p.join(tempDir.path, 'transcode_in'));
      if (transcodeInDir.existsSync()) {
        for (final entity in transcodeInDir.listSync()) {
          if (entity is File) {
            final len = entity.lengthSync();
            try {
              entity.deleteSync();
              reclaimedBytes += len;
            } catch (_) {}
          }
        }
      }

      // Clear Flutter file_picker plugin temporary files
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      // Clear Android native cache directory (e.g. file_picker copies, transcoded WAVs)
      if (Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.freebeat.freebeat/native_cloud_auth');
          final nativeReclaimed = await channel.invokeMethod<int>('clearAppCache');
          if (nativeReclaimed != null && nativeReclaimed > 0) {
            reclaimedBytes += nativeReclaimed;
          }
        } catch (_) {}
      }

      notifyListeners();
    } catch (_) {}
    return reclaimedBytes;
  }

  /// Proactively cleans orphaned cache on startup (e.g. leftover file_picker copies,
  /// orphaned transcode input files, stale temporary files).
  /// Strictly preserves user-pinned offline downloads.
  Future<void> autoPurgeOrphanedCache() async {
    try {
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      final tempDir = await getTemporaryDirectory();
      final transcodeInDir = Directory(p.join(tempDir.path, 'transcode_in'));
      if (transcodeInDir.existsSync()) {
        for (final entity in transcodeInDir.listSync()) {
          if (entity is File) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      }

      if (Platform.isAndroid) {
        try {
          const channel = MethodChannel('com.freebeat.freebeat/native_cloud_auth');
          await channel.invokeMethod<int>('clearAppCache');
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Automatically purges oldest unpinned files if stream cache exceeds [maxCacheSizeMb].
  /// Never deletes user-pinned offline downloads.
  Future<int> autoPurgeCacheIfNeeded(List<Track> catalogTracks, int maxCacheSizeMb) async {
    if (maxCacheSizeMb <= 0) return 0; // Unlimited
    final maxBytes = maxCacheSizeMb * 1024 * 1024;
    int purgedBytes = 0;

    try {
      final cacheDir = await _getCacheDirectory();
      if (!cacheDir.existsSync()) return 0;

      final pinnedPaths = catalogTracks
          .where((t) => t.isPinnedOffline && t.localCachePath != null)
          .map((t) => t.localCachePath!)
          .toSet();

      final pinnedIds = catalogTracks
          .where((t) => t.isPinnedOffline)
          .map((t) => t.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_'))
          .toSet();

      final unpinnedFiles = <File>[];
      int currentStreamBytes = 0;

      for (final entity in cacheDir.listSync()) {
        if (entity is File) {
          final baseName = p.basenameWithoutExtension(entity.path);
          final isPinned = pinnedPaths.contains(entity.path) || pinnedIds.contains(baseName);
          if (!isPinned) {
            unpinnedFiles.add(entity);
            currentStreamBytes += entity.lengthSync();
          }
        }
      }

      if (currentStreamBytes > maxBytes) {
        unpinnedFiles.sort((a, b) {
          final aTime = a.statSync().modified;
          final bTime = b.statSync().modified;
          return aTime.compareTo(bTime);
        });

        for (final f in unpinnedFiles) {
          if (currentStreamBytes <= maxBytes) break;
          final len = f.lengthSync();
          try {
            f.deleteSync();
            currentStreamBytes -= len;
            purgedBytes += len;
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (purgedBytes > 0) notifyListeners();
    return purgedBytes;
  }

  String _getExtensionForTrack(Track track) {
    final rawExt = p.extension(track.streamUrl).toLowerCase().replaceFirst('.', '');
    if (rawExt.isNotEmpty) return rawExt;
    final c = track.codec.toLowerCase();
    if (c == 'flac') return 'flac';
    if (c == 'mp3') return 'mp3';
    if (c == 'm4a' || c == 'aac' || c == 'alac') return 'm4a';
    if (c == 'wav') return 'wav';
    if (c == 'ogg') return 'ogg';
    if (c == 'opus') return 'opus';
    if (c == 'wma' || c == 'asf') return 'wma';
    if (c == 'aiff' || c == 'aif') return 'aiff';
    if (c == 'ape') return 'ape';
    if (c == 'dsd' || c == 'dsf' || c == 'dff') return 'dsf';
    return 'mp3';
  }
}
