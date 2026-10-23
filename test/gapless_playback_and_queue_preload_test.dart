import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/audio_quality_settings.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_audio_cache_service.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late SecureCredentialStore credStore;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('freebeat_gapless_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => testDir.path,
    );
    credStore = SecureCredentialStore();
  });

  tearDown(() {
    try {
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Gapless Playback & 5-Track Queue Preload Tests', () {
    test('preloadQueueTracks selects the next 5 upcoming tracks in circular queue', () async {
      final downloadedTrackIds = <String>[];
      final mockClient = MockClient((request) async {
        return http.Response('MOCK_AUDIO_DATA_FOR_PRELOADING_1234567890', 200, headers: {
          'content-type': 'audio/mpeg',
          'content-length': '40',
        });
      });

      final cacheService = CloudAudioCacheService(
        credentialStore: credStore,
        client: mockClient,
      );

      final queue = List.generate(
        10,
        (i) => Track(
          id: 'track_idx_$i',
          accountId: 'acc_test',
          providerType: CloudProviderType.googleDrive,
          remotePathOrId: 'remote_$i',
          title: 'Track Title $i',
          artist: 'Artist $i',
          album: 'Test Album',
          durationMs: 180000,
          streamUrl: 'https://example.com/audio_$i.mp3',
          codec: 'MP3',
          bitDepth: 16,
          sampleRateHz: 44100,
          bitrateKbps: 320,
        ),
      );

      // Current track is index 2. Upcoming 5 tracks should be: 3, 4, 5, 6, 7
      await cacheService.preloadQueueTracks(
        queue,
        currentTrackId: 'track_idx_2',
        preloadCount: 5,
        onTrackCached: (updated) {
          downloadedTrackIds.add(updated.id);
        },
      );

      // Verify exactly 5 tracks were cached
      expect(downloadedTrackIds.length, equals(5));
      expect(downloadedTrackIds, contains('track_idx_3'));
      expect(downloadedTrackIds, contains('track_idx_4'));
      expect(downloadedTrackIds, contains('track_idx_5'));
      expect(downloadedTrackIds, contains('track_idx_6'));
      expect(downloadedTrackIds, contains('track_idx_7'));
      expect(downloadedTrackIds.contains('track_idx_2'), isFalse);
    });

    test('preloadQueueTracks wraps around queue end for seamless circular playback', () async {
      final downloadedTrackIds = <String>[];
      final mockClient = MockClient((request) async {
        return http.Response('MOCK_AUDIO_DATA_FOR_CIRCULAR_PRELOADING', 200, headers: {
          'content-type': 'audio/mpeg',
          'content-length': '38',
        });
      });

      final cacheService = CloudAudioCacheService(
        credentialStore: credStore,
        client: mockClient,
      );

      final queue = List.generate(
        6,
        (i) => Track(
          id: 'song_$i',
          accountId: 'acc_test',
          providerType: CloudProviderType.googleDrive,
          remotePathOrId: 'remote_$i',
          title: 'Song $i',
          artist: 'Artist $i',
          album: 'Wrap Album',
          durationMs: 200000,
          streamUrl: 'https://example.com/stream_$i.mp3',
          codec: 'MP3',
        ),
      );

      // Current track is index 4 in a 6-song queue.
      // Next 5 songs wrapped: index 5, 0, 1, 2, 3
      await cacheService.preloadQueueTracks(
        queue,
        currentTrackId: 'song_4',
        preloadCount: 5,
        onTrackCached: (updated) {
          downloadedTrackIds.add(updated.id);
        },
      );

      expect(downloadedTrackIds.length, equals(5));
      expect(downloadedTrackIds, equals(['song_5', 'song_0', 'song_1', 'song_2', 'song_3']));
    });

    test('CloudStreamProxy detects preloaded local files and serves with Range support', () async {
      final cacheDir = Directory('${testDir.path}/cached_music');
      cacheDir.createSync(recursive: true);

      final testTrack = Track(
        id: 'preloaded_audiophile_track',
        accountId: 'acc_test',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'remote_file_99',
        title: 'Preloaded Song',
        artist: 'Hi-Fi Master',
        album: 'Audiophile Master Tape',
        durationMs: 300000,
        streamUrl: 'https://example.com/audiophile.flac',
        codec: 'FLAC',
        bitDepth: 24,
        sampleRateHz: 96000,
        bitrateKbps: 1411,
      );

      const account = CloudAccount(
        id: 'acc_test',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Google Drive',
        endpointOrFolder: '/',
      );

      // Pre-create the cached audio file on disk (> 1024 bytes)
      final dummyBytes = List<int>.generate(8192, (i) => i % 256);
      final cachedFile = File('${cacheDir.path}/${testTrack.id}.flac');
      cachedFile.writeAsBytesSync(dummyBytes);

      final proxy = CloudStreamProxy(
        credentialStore: credStore,
        connectorRegistry: CloudConnectorRegistry(),
      );
      await proxy.start();

      proxy.updateCatalog(
        tracks: [testTrack],
        accounts: [account],
        activeTier: AudioQualityTier.hifiLossless,
      );

      final proxyUrl = proxy.buildPlaybackUrl(testTrack, AudioQualityTier.hifiLossless);
      expect(proxyUrl, startsWith('http://127.0.0.1:'));

      // Test byte-range request (e.g. bytes=100-499)
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(proxyUrl));
      req.headers['range'] = 'bytes=100-499';
      final streamedResponse = await client.send(req);

      expect(streamedResponse.statusCode, equals(206)); // Partial Content
      expect(streamedResponse.headers['accept-ranges'], equals('bytes'));
      expect(streamedResponse.headers['content-range'], equals('bytes 100-499/8192'));
      expect(streamedResponse.contentLength, equals(400));

      final responseBytes = await streamedResponse.stream.toBytes();
      expect(responseBytes.length, equals(400));
      expect(responseBytes, equals(dummyBytes.sublist(100, 500)));

      proxy.dispose();
    });
  });
}
