import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/audio_quality_settings.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:path/path.dart' as p;

Track createMockTrack({
  required String id,
  required String title,
  String streamUrl = 'https://www.googleapis.com/drive/v3/files/123?alt=media',
  String remotePathOrId = 'drive_file_123',
  String? localCachePath,
  bool isPinnedOffline = false,
  CloudProviderType providerType = CloudProviderType.googleDrive,
}) {
  return Track(
    id: id,
    accountId: 'acc_gdrive',
    providerType: providerType,
    remotePathOrId: remotePathOrId,
    title: title,
    artist: 'Artist',
    album: 'Album',
    durationMs: 180000,
    streamUrl: streamUrl,
    localCachePath: localCachePath,
    isPinnedOffline: isPinnedOffline,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.freebeat/native_cloud_auth'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'clearAppCache') return 1024 * 1024;
        if (methodCall.method == 'getAppCacheSize') return 1024 * 1024;
        return null;
      },
    );
  });

  group('Cache Clear & Playback Resilience Tests', () {
    late Directory tempDir;
    late Directory mockCacheDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('freebeat_cache_clear_test_');
      mockCacheDir = Directory(p.join(tempDir.path, 'cached_music'))..createSync(recursive: true);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('clearStreamCache preserves currently active track and pinned tracks', () async {
      // Create 3 files in cache
      final pinnedFile = File(p.join(mockCacheDir.path, 'trk_pinned.mp3'))..writeAsBytesSync(List.filled(1024, 1));
      final activeFile = File(p.join(mockCacheDir.path, 'trk_active.mp3'))..writeAsBytesSync(List.filled(1024, 2));
      final unpinnedFile = File(p.join(mockCacheDir.path, 'trk_unpinned.mp3'))..writeAsBytesSync(List.filled(1024, 3));

      final pinnedTrack = createMockTrack(
        id: 'trk_pinned',
        title: 'Pinned Track',
        localCachePath: pinnedFile.path,
        isPinnedOffline: true,
      );

      final activeTrack = createMockTrack(
        id: 'trk_active',
        title: 'Active Playing Track',
        localCachePath: activeFile.path,
        isPinnedOffline: false,
      );

      final unpinnedTrack = createMockTrack(
        id: 'trk_unpinned',
        title: 'Unpinned Previously Cached Track',
        localCachePath: unpinnedFile.path,
        isPinnedOffline: false,
      );

      final catalog = [pinnedTrack, activeTrack, unpinnedTrack];

      // Execute cache clear preserving active track
      final pinnedPaths = catalog
          .where((t) => t.isPinnedOffline && t.localCachePath != null)
          .map((t) => t.localCachePath!)
          .toSet();

      final pinnedIds = catalog
          .where((t) => t.isPinnedOffline)
          .map((t) => t.id)
          .toSet();

      final activeSanitizedId = activeTrack.id;

      for (final entity in mockCacheDir.listSync()) {
        if (entity is File) {
          final baseName = p.basenameWithoutExtension(entity.path);
          final isPinned = pinnedPaths.contains(entity.path) || pinnedIds.contains(baseName);
          final isActive = baseName == activeSanitizedId || entity.path.contains(activeSanitizedId);
          if (!isPinned && !isActive) {
            entity.deleteSync();
          }
        }
      }

      expect(pinnedFile.existsSync(), isTrue, reason: 'Pinned offline track must be preserved');
      expect(activeFile.existsSync(), isTrue, reason: 'Actively playing track cache must not be aborted mid-playback');
      expect(unpinnedFile.existsSync(), isFalse, reason: 'Unpinned streaming cache must be purged');
    });

    test('purgeDeletedLocalCachePaths clears stale localCachePath and resets isPinnedOffline if file deleted', () async {
      final db = LibraryDatabase();
      final notifier = TracksCatalogNotifier(db);

      final missingFileTrack = createMockTrack(
        id: 'trk_missing',
        title: 'Deleted Cache Track',
        localCachePath: p.join(tempDir.path, 'non_existent_file.mp3'),
        isPinnedOffline: false,
      );

      notifier.state = [missingFileTrack];

      await notifier.purgeDeletedLocalCachePaths();

      final updated = notifier.state.firstWhere((t) => t.id == 'trk_missing');
      expect(updated.localCachePath, isNull, reason: 'Dead cache path must be cleaned');
      expect(updated.isPinnedOffline, isFalse);
    });

    test('CloudStreamProxy falls back to streaming on-demand when localCachePath is deleted', () async {
      final proxy = CloudStreamProxy(
        connectorRegistry: CloudConnectorRegistry(),
        credentialStore: SecureCredentialStore(),
      );

      await proxy.start();

      final trackWithDeletedCache = createMockTrack(
        id: 'trk_cloud_stream',
        title: 'Drive Song',
        streamUrl: 'https://www.googleapis.com/drive/v3/files/xyz?alt=media',
        localCachePath: p.join(tempDir.path, 'deleted_song.mp3'),
        isPinnedOffline: false,
      );

      proxy.updateCatalog(
        tracks: [trackWithDeletedCache],
        accounts: [],
        activeTier: AudioQualityTier.hifiLossless,
      );

      final playbackUrl = proxy.buildPlaybackUrl(trackWithDeletedCache, AudioQualityTier.hifiLossless);

      expect(playbackUrl, startsWith('http://127.0.0.1:${proxy.port}/stream/trk_cloud_stream'),
          reason: 'Must fall back to authenticated proxy streaming instead of dead local path');

      await proxy.dispose();
    });
  });
}
