import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

  /// Determines whether [track] is already cached on local storage.
  bool isTrackCached(Track track) {
    if (track.localCachePath != null && track.localCachePath!.isNotEmpty) {
      if (File(track.localCachePath!).existsSync()) {
        return true;
      }
    }
    if (_cacheDir != null) {
      final sanitizedId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final ext = _getExtensionForTrack(track);
      final file = File(p.join(_cacheDir!.path, '$sanitizedId.$ext'));
      return file.existsSync() && file.lengthSync() > 1024;
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
        await File(track.streamUrl).copy(finalFile.path);
        _progressMap[track.id] = CacheProgress(
          state: CacheState.cached,
          progress: 1.0,
          localPath: finalFile.path,
        );
        notifyListeners();

        final updated = track.copyWith(
          isPinnedOffline: true,
          localCachePath: finalFile.path,
        );
        onComplete?.call(updated);
        return finalFile.path;
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

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (totalBytes > 0) {
          final progress = (downloaded / totalBytes).clamp(0.0, 0.99);
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
        isPinnedOffline: true,
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

  String _getExtensionForTrack(Track track) {
    final c = track.codec.toLowerCase();
    if (c == 'flac') return 'flac';
    if (c == 'mp3') return 'mp3';
    if (c == 'm4a' || c == 'aac' || c == 'alac') return 'm4a';
    if (c == 'wav') return 'wav';
    if (c == 'ogg') return 'ogg';
    if (c == 'opus') return 'opus';
    return 'flac';
  }
}
