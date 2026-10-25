import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/track.dart';
import '../../core/storage/library_database.dart';
import 'cloud_audio_cache_service.dart';

enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  paused,
}

class DownloadQueueItem {
  const DownloadQueueItem({
    required this.track,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  final Track track;
  final DownloadStatus status;
  final double progress;
  final int bytesDownloaded;
  final int totalBytes;
  final String? errorMessage;

  DownloadQueueItem copyWith({
    Track? track,
    DownloadStatus? status,
    double? progress,
    int? bytesDownloaded,
    int? totalBytes,
    String? errorMessage,
  }) {
    return DownloadQueueItem(
      track: track ?? this.track,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Advanced Background Download Queue Manager with concurrency control,
/// Wi-Fi-only enforcement, retry logic, and playlist/album batch syncing.
class DownloadQueueManager extends ChangeNotifier {
  DownloadQueueManager({
    required this.cacheService,
    this.database,
    this.onTrackPinned,
  }) {
    _loadPreferences();
  }

  final CloudAudioCacheService cacheService;
  final LibraryDatabase? database;
  final void Function(Track updatedTrack)? onTrackPinned;

  static const MethodChannel _channel = MethodChannel('com.freebeat.freebeat/dsp');

  final List<DownloadQueueItem> _queue = [];
  bool _isPaused = false;
  bool _wifiOnly = true;
  int _maxCacheSizeMb = 2048; // 2 GB default
  static const int _maxConcurrent = 2;
  int _activeCount = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  List<DownloadQueueItem> get queue => List.unmodifiable(_queue);
  bool get isPaused => _isPaused;
  bool get wifiOnly => _wifiOnly;
  int get maxCacheSizeMb => _maxCacheSizeMb;
  int get activeCount => _activeCount;

  int get totalCount => _queue.length;
  int get completedCount => _queue.where((i) => i.status == DownloadStatus.completed).length;

  /// High-efficiency O(N) lookup for single track status without copying full queue list
  bool isTrackInQueue(String trackId) {
    for (int i = 0; i < _queue.length; i++) {
      final q = _queue[i];
      if (q.track.id == trackId &&
          (q.status == DownloadStatus.downloading ||
              q.status == DownloadStatus.queued)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wifiOnly = prefs.getBool('download_wifi_only') ?? true;
      _maxCacheSizeMb = prefs.getInt('max_cache_size_mb') ?? 2048;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setWifiOnly(bool val) async {
    _wifiOnly = val;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('download_wifi_only', val);
    } catch (_) {}
    if (!val) {
      _processNext();
    }
  }

  Future<void> setMaxCacheSizeMb(int mb, List<Track> allTracks) async {
    _maxCacheSizeMb = mb;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('max_cache_size_mb', mb);
      await cacheService.autoPurgeCacheIfNeeded(allTracks, mb);
    } catch (_) {}
  }

  /// Adds a single track to the download queue.
  void enqueue(Track track) {
    if (track.id.isEmpty) return;
    final existingIndex = _queue.indexWhere((i) => i.track.id == track.id);
    if (existingIndex != -1) {
      final item = _queue[existingIndex];
      if (item.status == DownloadStatus.failed || item.status == DownloadStatus.paused) {
        _queue[existingIndex] = item.copyWith(status: DownloadStatus.queued, errorMessage: null);
        notifyListeners();
        _processNext();
      }
      return;
    }

    _queue.add(DownloadQueueItem(track: track));
    notifyListeners();
    _processNext();
  }

  /// Adds multiple tracks (e.g. from a playlist or album) to the download queue.
  void enqueueAll(List<Track> tracks) {
    bool addedAny = false;
    for (final track in tracks) {
      if (track.id.isEmpty) continue;
      final existingIndex = _queue.indexWhere((i) => i.track.id == track.id);
      if (existingIndex == -1) {
        _queue.add(DownloadQueueItem(track: track));
        addedAny = true;
      } else {
        final item = _queue[existingIndex];
        if (item.status == DownloadStatus.failed || item.status == DownloadStatus.paused) {
          _queue[existingIndex] = item.copyWith(status: DownloadStatus.queued, errorMessage: null);
          addedAny = true;
        }
      }
    }
    if (addedAny) {
      notifyListeners();
      _processNext();
    }
  }

  /// Pauses the entire download queue.
  void pauseQueue() {
    _isPaused = true;
    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].status == DownloadStatus.queued) {
        _queue[i] = _queue[i].copyWith(status: DownloadStatus.paused);
      }
    }
    notifyListeners();
  }

  /// Resumes the download queue.
  void resumeQueue() {
    _isPaused = false;
    for (int i = 0; i < _queue.length; i++) {
      if (_queue[i].status == DownloadStatus.paused) {
        _queue[i] = _queue[i].copyWith(status: DownloadStatus.queued);
      }
    }
    notifyListeners();
    _processNext();
  }

  /// Cancels a track from the queue.
  void cancel(String trackId) {
    _queue.removeWhere((i) => i.track.id == trackId);
    notifyListeners();
    _processNext();
  }

  /// Cancels all pending and queued downloads.
  void cancelAll() {
    _queue.removeWhere((i) => i.status == DownloadStatus.queued || i.status == DownloadStatus.paused);
    notifyListeners();
  }

  /// Clears completed downloads from the queue list.
  void clearCompleted() {
    _queue.removeWhere((i) => i.status == DownloadStatus.completed);
    notifyListeners();
  }

  /// Retries a failed track.
  void retry(String trackId) {
    final idx = _queue.indexWhere((i) => i.track.id == trackId);
    if (idx != -1) {
      _queue[idx] = _queue[idx].copyWith(
        status: DownloadStatus.queued,
        progress: 0.0,
        errorMessage: null,
      );
      notifyListeners();
      _processNext();
    }
  }

  Future<bool> _checkWifiAllowed() async {
    if (!_wifiOnly) return true;
    try {
      final isWifi = await _channel.invokeMethod<bool>('isWifiConnected');
      return isWifi ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _processNext() async {
    if (_disposed) return;
    if (_isPaused) return;
    if (_activeCount >= _maxConcurrent) return;

    final allowed = await _checkWifiAllowed();
    if (!allowed) {
      debugPrint('[DownloadQueue] Paused: Waiting for unmetered Wi-Fi connection.');
      return;
    }

    final nextIndex = _queue.indexWhere((i) => i.status == DownloadStatus.queued);
    if (nextIndex == -1) return;

    final item = _queue[nextIndex];
    _queue[nextIndex] = item.copyWith(status: DownloadStatus.downloading, progress: 0.05);
    _activeCount++;
    notifyListeners();

    _downloadItem(item.track);
  }

  Future<void> _downloadItem(Track track) async {
    try {
      final downloadedPath = await cacheService.cacheTrack(
        track,
        markPinnedOffline: true,
        onComplete: (updated) {
          if (database != null) {
            database!.upsertTracks([updated]);
          }
          onTrackPinned?.call(updated);
        },
      );

      final idx = _queue.indexWhere((i) => i.track.id == track.id);
      if (idx != -1) {
        if (downloadedPath != null && downloadedPath.isNotEmpty) {
          _queue[idx] = _queue[idx].copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
          );
        } else {
          final err = cacheService.getProgress(track.id).errorMessage ?? 'Download failed';
          _queue[idx] = _queue[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: err,
          );
        }
      }
    } catch (e) {
      final idx = _queue.indexWhere((i) => i.track.id == track.id);
      if (idx != -1) {
        _queue[idx] = _queue[idx].copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
        );
      }
    } finally {
      _activeCount = (_activeCount - 1).clamp(0, _maxConcurrent);
      if (!_disposed) {
        notifyListeners();
        _processNext();
      }
    }
  }
}
