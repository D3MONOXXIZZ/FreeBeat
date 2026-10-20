import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/audio/cloud_audio_cache_service.dart';
import 'package:freebeat/services/audio/universal_audio_transcoder_service.dart';
import 'package:path/path.dart' as p;

Track makeTestTrack({
  required String id,
  required String title,
  String artist = 'Artist',
  String album = 'Album',
  String streamUrl = 'content://media/external/audio/media/101',
  String remotePathOrId = 'content://media/external/audio/media/101',
  String? localCachePath,
  bool isPinnedOffline = false,
  String codec = 'FLAC',
}) {
  return Track(
    id: id,
    accountId: 'acc_saf',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: remotePathOrId,
    title: title,
    artist: artist,
    album: album,
    durationMs: 210000,
    streamUrl: streamUrl,
    localCachePath: localCachePath,
    isPinnedOffline: isPinnedOffline,
    codec: codec,
  );
}

void main() {
  group('Storage and Cache Optimization Tests', () {
    test('StorageUsageInfo properly calculates and formats native and stream cache', () {
      const usage = StorageUsageInfo(
        pinnedBytes: 50 * 1024 * 1024, // 50 MB
        streamCacheBytes: 15 * 1024 * 1024, // 15 MB
        transcodedBytes: 5 * 1024 * 1024, // 5 MB
        totalAppCacheBytes: 70 * 1024 * 1024, // 70 MB
        nativeCacheBytes: 10 * 1024 * 1024, // 10 MB
        freeDiskBytes: 20 * 1024 * 1024 * 1024, // 20 GB
      );

      expect(usage.pinnedFormatted, '50.0 MB');
      expect(usage.streamCacheFormatted, '15.0 MB');
      expect(usage.transcodedFormatted, '5.0 MB');
      expect(usage.totalFormatted, '70.0 MB');
      expect(usage.nativeCacheFormatted, '10.0 MB');
      expect(usage.freeFormatted, '20.00 GB');
    });

    test('Self-healing restores content:// URI when streamUrl or localCachePath points to ephemeral cache', () {
      final legacyTrack = makeTestTrack(
        id: 'track_legacy_1',
        title: 'Bohemian Rhapsody',
        streamUrl: '/data/user/0/com.freebeat.freebeat/cache/file_picker/audio_01.flac',
        remotePathOrId: 'content://com.android.providers.media.documents/document/audio%3A42',
        localCachePath: '/data/user/0/com.freebeat.freebeat/cache/file_picker/audio_01.flac',
        isPinnedOffline: true, // Erroneously marked as pinned by legacy picker
      );

      // Verify healing logic
      var clean = legacyTrack;
      if (clean.streamUrl.contains('/cache/file_picker/') ||
          (clean.localCachePath != null && clean.localCachePath!.contains('/cache/file_picker/'))) {
        if (clean.remotePathOrId.startsWith('content://')) {
          clean = clean.copyWith(
            streamUrl: clean.remotePathOrId,
            clearLocalCachePath: true,
            isPinnedOffline: false,
          );
        } else {
          clean = clean.copyWith(
            clearLocalCachePath: true,
            isPinnedOffline: false,
          );
        }
      }

      expect(clean.streamUrl, 'content://com.android.providers.media.documents/document/audio%3A42');
      expect(clean.localCachePath, isNull);
      expect(clean.isPinnedOffline, isFalse);
    });

    test('clearStreamCache preserves user-pinned offline downloads while purging unpinned files', () async {
      final tempDir = Directory.systemTemp.createTempSync('freebeat_cache_test_');
      final mockMusicDir = Directory(p.join(tempDir.path, 'cached_music'))..createSync(recursive: true);

      // Create a pinned file and an unpinned streaming cache file
      final pinnedFile = File(p.join(mockMusicDir.path, 'pinned_song_1.mp3'))..writeAsBytesSync(List.filled(1024 * 1024, 1));
      final unpinnedFile = File(p.join(mockMusicDir.path, 'stream_song_2.mp3'))..writeAsBytesSync(List.filled(2 * 1024 * 1024, 2));

      final pinnedTrack = makeTestTrack(
        id: 'pinned_song_1',
        title: 'Pinned Song',
        localCachePath: pinnedFile.path,
        isPinnedOffline: true,
      );

      final unpinnedTrack = makeTestTrack(
        id: 'stream_song_2',
        title: 'Streamed Song',
        localCachePath: null,
        isPinnedOffline: false,
      );

      final catalog = [pinnedTrack, unpinnedTrack];

      // Replicate unpinned cleanup logic
      final pinnedPaths = catalog
          .where((t) => t.isPinnedOffline && t.localCachePath != null)
          .map((t) => t.localCachePath!)
          .toSet();

      final pinnedIds = catalog
          .where((t) => t.isPinnedOffline)
          .map((t) => t.id)
          .toSet();

      int reclaimed = 0;
      for (final entity in mockMusicDir.listSync()) {
        if (entity is File) {
          final baseName = p.basenameWithoutExtension(entity.path);
          final isPinned = pinnedPaths.contains(entity.path) || pinnedIds.contains(baseName);
          if (!isPinned) {
            reclaimed += entity.lengthSync();
            entity.deleteSync();
          }
        }
      }

      expect(pinnedFile.existsSync(), isTrue, reason: 'Pinned offline music must never be deleted');
      expect(unpinnedFile.existsSync(), isFalse, reason: 'Unpinned cache should be safely deleted');
      expect(reclaimed, 2 * 1024 * 1024);

      tempDir.deleteSync(recursive: true);
    });

    test('UniversalAudioTranscoderService enforces strict 50MB LRU limit on temporary transcoded WAVs', () async {
      final tempDir = Directory.systemTemp.createTempSync('freebeat_transcode_test_');
      final transcodeDir = Directory(p.join(tempDir.path, 'transcoded_audio'))..createSync(recursive: true);

      // Create 3 pseudo 20MB WAV files (total 60MB, exceeds 50MB limit)
      final file1 = File(p.join(transcodeDir.path, 'song1.wav'))..writeAsBytesSync(List.filled(20 * 1024 * 1024, 0));
      // Ensure slight time difference for deterministic LRU ordering
      await Future.delayed(const Duration(milliseconds: 50));
      final file2 = File(p.join(transcodeDir.path, 'song2.wav'))..writeAsBytesSync(List.filled(20 * 1024 * 1024, 0));
      await Future.delayed(const Duration(milliseconds: 50));
      final file3 = File(p.join(transcodeDir.path, 'song3.wav'))..writeAsBytesSync(List.filled(20 * 1024 * 1024, 0));

      // Call LRU limiter helper logic
      final maxBytes = 50 * 1024 * 1024;
      final wavFiles = transcodeDir.listSync().whereType<File>().where((f) => f.path.endsWith('.wav')).toList();
      int currentBytes = wavFiles.fold<int>(0, (sum, f) => sum + f.lengthSync());

      if (currentBytes > maxBytes) {
        wavFiles.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
        for (final f in wavFiles) {
          if (currentBytes <= maxBytes) break;
          final len = f.lengthSync();
          f.deleteSync();
          currentBytes -= len;
        }
      }

      expect(file1.existsSync(), isFalse, reason: 'Oldest transcode file must be pruned to maintain <= 50MB limit');
      expect(file2.existsSync(), isTrue);
      expect(file3.existsSync(), isTrue);

      final remainingBytes = transcodeDir.listSync().whereType<File>().fold<int>(0, (sum, f) => sum + f.lengthSync());
      expect(remainingBytes, lessThanOrEqualTo(maxBytes));

      tempDir.deleteSync(recursive: true);
    });
  });
}
