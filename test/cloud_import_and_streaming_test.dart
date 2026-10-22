import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/audio_quality_settings.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_audio_cache_service.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/services/auth/native_cloud_auth_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/clouds_screen.dart';

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
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'scanDirectory') {
          return [
            {
              'uri': 'content://com.android.externalstorage.documents/document/primary%3AMusic%2Ftrack1.flac',
              'name': 'track1.flac',
              'size': 25000000,
            },
            {
              'uri': 'content://com.android.externalstorage.documents/document/primary%3AMusic%2Ftrack2.mp3',
              'name': 'track2.mp3',
              'size': 8000000,
            },
          ];
        }
        if (methodCall.method == 'takePersistableUriPermission') {
          return true;
        }
        if (methodCall.method == 'pickDirectory') {
          return {
            'uri': 'content://com.android.externalstorage.documents/tree/primary%3AMusic',
            'name': 'Music',
          };
        }
        if (methodCall.method == 'readContentUriHeaderBytes') {
          return Uint8List.fromList([0x66, 0x4C, 0x61, 0x43]); // 'fLaC' header
        }
        if (methodCall.method == 'extractAudioMetadata') {
          return {
            'title': 'Test Song',
            'artist': 'Test Artist',
            'album': 'Test Album',
            'durationMs': 180000,
            'bitrateKbps': 320,
            'pictureBytes': Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01]),
          };
        }
        return null;
      },
    );
  });

  group('Cloud Import & Offline Status Tests', () {
    test('Imported tracks default to isPinnedOffline: false', () {
      final track = Track(
        id: 'test_imported_1',
        accountId: 'saf_account_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'gdrive_file_123',
        title: 'Morning Sun',
        artist: 'Chill Beats',
        album: 'Acoustic Dawn',
        durationMs: 180000,
        streamUrl: 'https://www.googleapis.com/drive/v3/files/123?alt=media',
        isPinnedOffline: false,
      );

      expect(track.isPinnedOffline, isFalse);
      expect(track.localCachePath, isNull);
    });

    test('CloudAudioCacheService with markPinnedOffline: false does not set isPinnedOffline', () async {
      final credStore = SecureCredentialStore();
      final cacheSvc = CloudAudioCacheService(credentialStore: credStore);

      final track = Track(
        id: 'stream_test_track',
        accountId: 'acc_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: '123',
        title: 'Stream Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 120000,
        streamUrl: 'https://www.googleapis.com/drive/v3/files/123?alt=media',
        isPinnedOffline: false,
      );

      // isTrackCached should be false when not pinned
      expect(cacheSvc.isTrackCached(track), isFalse);
    });
  });

  group('CloudStreamProxy & Direct Streaming Tests', () {
    test('CloudStreamProxy starts and generates loopback URL with tier', () async {
      final credStore = SecureCredentialStore();
      final registry = CloudConnectorRegistry();
      final proxy = CloudStreamProxy(
        connectorRegistry: registry,
        credentialStore: credStore,
      );

      await proxy.start();
      expect(proxy.isRunning, isTrue);
      expect(proxy.port, greaterThan(0));

      final testTrack = Track(
        id: 'drive_track_abc',
        accountId: 'acc_drive',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'abc',
        title: 'Cloud Symphony',
        artist: 'Orchestra',
        album: 'Lossless Collection',
        durationMs: 240000,
        streamUrl: 'https://www.googleapis.com/drive/v3/files/abc?alt=media',
        isPinnedOffline: false,
      );

      final account = const CloudAccount(
        id: 'acc_drive',
        providerType: CloudProviderType.googleDrive,
        displayName: 'My Google Drive',
        endpointOrFolder: '/',
      );

      proxy.updateCatalog(
        tracks: [testTrack],
        accounts: [account],
        activeTier: AudioQualityTier.hifiLossless,
      );

      final playbackUrl = proxy.buildPlaybackUrl(testTrack, AudioQualityTier.hifiLossless);
      expect(playbackUrl, startsWith('http://127.0.0.1:${proxy.port}/stream/drive_track_abc'));
      expect(playbackUrl, contains('tier=hifi_lossless'));

      // Test local cache path bypassing loopback proxy
      final localTrack = testTrack.copyWith(
        localCachePath: '/data/user/0/com.freebeat.freebeat/app_flutter/imported_music/song.flac',
        isPinnedOffline: true,
      );
      expect(proxy.buildPlaybackUrl(localTrack, AudioQualityTier.hifiLossless),
          '/data/user/0/com.freebeat.freebeat/app_flutter/imported_music/song.flac');

      // Test content:// URI bypassing loopback proxy
      final contentTrack = testTrack.copyWith(
        streamUrl: 'content://com.android.providers.media.documents/document/audio%3A123',
      );
      expect(proxy.buildPlaybackUrl(contentTrack, AudioQualityTier.hifiLossless),
          'content://com.android.providers.media.documents/document/audio%3A123');

      await proxy.dispose();
    });

    test('filteredTracksProvider with hifi filter checks track.isHiRes', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith((ref) {
            final cat = TracksCatalogNotifier(null, null);
            cat.state = [
              Track(
                id: 't1',
                accountId: 'a1',
                providerType: CloudProviderType.googleDrive,
                remotePathOrId: '1',
                title: 'Hi-Res Track',
                artist: 'Artist',
                album: 'Album',
                durationMs: 100000,
                streamUrl: 'url1',
                bitDepth: 24,
                sampleRateHz: 96000,
              ),
              Track(
                id: 't2',
                accountId: 'a1',
                providerType: CloudProviderType.googleDrive,
                remotePathOrId: '2',
                title: 'Standard Track',
                artist: 'Artist',
                album: 'Album',
                durationMs: 100000,
                streamUrl: 'url2',
                bitDepth: 16,
                sampleRateHz: 44100,
              ),
            ];
            return cat;
          }),
          selectedCloudFilterProvider.overrideWith((ref) => 'hifi'),
        ],
      );

      final filtered = container.read(filteredTracksProvider);
      expect(filtered.length, 1);
      expect(filtered.first.id, 't1');
      expect(filtered.first.isHiRes, isTrue);
    });
  });

  group('CloudsScreen Widget & UI Tests', () {
    testWidgets('CloudsScreen renders account track count and imported tracks card', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testAccount = const CloudAccount(
        id: 'acc_drive_1',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Personal Drive',
        endpointOrFolder: 'Google Drive App Storage',
      );

      final testTrack = Track(
        id: 'track_drive_1',
        accountId: 'acc_drive_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'file_1',
        title: 'Cosmic Beats',
        artist: 'Starlight',
        album: 'Nebula',
        durationMs: 215000,
        streamUrl: 'https://www.googleapis.com/drive/v3/files/1?alt=media',
        isPinnedOffline: false,
        codec: 'FLAC',
        bitDepth: 24,
        sampleRateHz: 96000,
      );

      final fakeProxy = _FakeCloudStreamProxy();
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(fakeProxy),
          cloudAccountsProvider.overrideWith((ref) {
            final acc = CloudAccountsNotifier(LibraryDatabase(), SecureCredentialStore());
            acc.state = [testAccount];
            return acc;
          }),
          tracksCatalogProvider.overrideWith((ref) {
            final cat = TracksCatalogNotifier(null, null);
            cat.state = [testTrack];
            return cat;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
            home: const Scaffold(
              body: CloudsScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check that account card shows track count
      expect(find.text('Personal Drive'), findsOneWidget);
      expect(find.textContaining('1 tracks indexed'), findsOneWidget);

      // Verify "Imported Tracks" library card was removed as requested
      expect(find.textContaining('Imported Tracks'), findsNothing);

      // Verify connected drive has direct action buttons to import tracks and manage allowed folder
      expect(find.text('Pick Audio Files from Google Drive'), findsOneWidget);
      expect(find.text('Allowed Folder'), findsOneWidget);
    });

    test('scanDirectoryNative retrieves directory tree entries via MethodChannel', () async {
      final authService = NativeCloudAuthService();
      final entries = await authService.scanDirectoryNative('content://primary:Music');
      expect(entries.length, 2);
      expect(entries[0]['name'], 'track1.flac');
      expect(entries[1]['name'], 'track2.mp3');
      expect(entries[0]['size'], 25000000);
    });

    test('SelectedFileEntry data model holds file properties cleanly', () {
      const entry = SelectedFileEntry(
        name: 'test_song.flac',
        path: '/storage/emulated/0/Music/test_song.flac',
        identifier: 'content://primary:Music/test_song.flac',
        size: 32000000,
      );
      expect(entry.name, 'test_song.flac');
      expect(entry.path, '/storage/emulated/0/Music/test_song.flac');
      expect(entry.identifier, 'content://primary:Music/test_song.flac');
      expect(entry.size, 32000000);
    });

    test('pickDirectoryNative and readContentUriHeaderBytes work correctly', () async {
      final authService = NativeCloudAuthService();
      final picked = await authService.pickDirectoryNative();
      expect(picked, isNotNull);
      expect(picked!.uri, 'content://com.android.externalstorage.documents/tree/primary%3AMusic');
      expect(picked.name, 'Music');

      final bytes = await authService.readContentUriHeaderBytes('content://test');
      expect(bytes, isNotNull);
      expect(bytes!.length, 4);
    });

    test('extractAudioMetadataNative extracts metadata and picture bytes', () async {
      final authService = NativeCloudAuthService();
      final meta = await authService.extractAudioMetadataNative('content://test/song.mp3');
      expect(meta, isNotNull);
      expect(meta!['title'], 'Test Song');
      expect(meta['artist'], 'Test Artist');
      expect(meta['album'], 'Test Album');
      expect(meta['durationMs'], 180000);
      expect(meta['pictureBytes'], isNotNull);
    });

    test('SelectedFileEntry holds scanned metadata fields', () {
      const entry = SelectedFileEntry(
        name: 'starboy.flac',
        path: '/storage/emulated/0/Music/starboy.flac',
        identifier: 'content://primary:Music/starboy.flac',
        size: 45000000,
        scannedTitle: 'Starboy',
        scannedArtist: 'The Weeknd',
        scannedAlbum: 'Starboy',
        scannedDurationMs: 230480,
        scannedAlbumArtUri: 'content://media/external/audio/albumart/123',
      );
      expect(entry.scannedTitle, 'Starboy');
      expect(entry.scannedArtist, 'The Weeknd');
      expect(entry.scannedAlbum, 'Starboy');
      expect(entry.scannedDurationMs, 230480);
      expect(entry.scannedAlbumArtUri, 'content://media/external/audio/albumart/123');
    });
  });
}

class _FakeCloudStreamProxy extends CloudStreamProxy {
  _FakeCloudStreamProxy()
      : super(
          connectorRegistry: CloudConnectorRegistry(),
          credentialStore: SecureCredentialStore(),
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}
