import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/services/audio/cloud_audio_cache_service.dart';
import 'package:freebeat/services/metadata/artwork_extractor.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/artist_details_screen.dart';
import 'package:freebeat/ui/screens/track_details_screen.dart';

class _FakeCatalogNotifier extends TracksCatalogNotifier {
  _FakeCatalogNotifier(List<Track> tracks) : super() {
    state = tracks;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock path_provider method channel for headless test environment
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    },
  );

  const sampleTrack = Track(
    id: 'track_test_101',
    accountId: 'gdrive_account_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: '1a2b3c4d_drive_file_id',
    title: 'Comfortably Numb',
    artist: 'Pink Floyd',
    album: 'The Wall',
    durationMs: 382000,
    streamUrl: 'https://www.googleapis.com/drive/v3/files/1a2b3c4d_drive_file_id?alt=media',
    codec: 'FLAC',
    bitDepth: 24,
    sampleRateHz: 96000,
    bitrateKbps: 3200,
    sizeBytes: 95400000,
    isFavorite: false,
    isPinnedOffline: false,
  );

  const sampleTrack2 = Track(
    id: 'track_test_102',
    accountId: 'gdrive_account_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: '5e6f7g8h_drive_file_id',
    title: 'Hey You',
    artist: 'Pink Floyd',
    album: 'The Wall',
    durationMs: 280000,
    streamUrl: 'https://www.googleapis.com/drive/v3/files/5e6f7g8h_drive_file_id?alt=media',
    codec: 'FLAC',
    bitDepth: 24,
    sampleRateHz: 96000,
    bitrateKbps: 3100,
  );

  group('Cloud Audio Cache Service Unit Tests', () {
    test('CacheProgress correctly tracks state, bytes, and progress percentage', () {
      const progress = CacheProgress(
        state: CacheState.caching,
        progress: 0.5,
        bytesDownloaded: 50 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024,
      );

      expect(progress.progress, 0.5);
      expect(progress.state, CacheState.caching);
      expect(progress.bytesDownloaded, 50 * 1024 * 1024);
      expect(progress.totalBytes, 100 * 1024 * 1024);

      const completed = CacheProgress(
        state: CacheState.cached,
        progress: 1.0,
        bytesDownloaded: 100 * 1024 * 1024,
        totalBytes: 100 * 1024 * 1024,
        localPath: '/data/user/0/com.freebeat.app/cached_music/track_test_101.flac',
      );
      expect(completed.progress, 1.0);
      expect(completed.state, CacheState.cached);
      expect(completed.localPath, contains('track_test_101.flac'));
    });

    test('CloudAudioCacheService reports track caching state accurately', () async {
      final credStore = SecureCredentialStore();
      final service = CloudAudioCacheService(credentialStore: credStore);
      expect(service.isTrackCached(sampleTrack), isFalse);

      final cachedPath = await service.getCachedFilePath(sampleTrack);
      expect(cachedPath, isNull);
    });
  });

  group('Artwork Extractor Binary Parser Tests', () {
    test('extractEmbeddedArtwork gracefully returns null for non-existent file', () async {
      final nonExistentFile = File('non_existent_file_test_dummy.flac');
      final result = await ArtworkExtractor.extractEmbeddedArtwork(nonExistentFile, 'track_dummy');
      expect(result, isNull);
    });
  });

  group('Track Details Screen Widget Tests', () {
    testWidgets('Renders all M3 Track Details, hi-res specs, and action buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith(
              (ref) => _FakeCatalogNotifier([sampleTrack, sampleTrack2]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const TrackDetailsScreen(track: sampleTrack),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Metadata
      expect(find.text('Comfortably Numb'), findsOneWidget);
      expect(find.text('Pink Floyd'), findsWidgets);
      expect(find.text('The Wall'), findsWidgets);

      // Verify Audio Specification tags
      expect(find.text('FLAC'), findsWidgets);
      expect(find.text('24-Bit Audio'), findsOneWidget);
      expect(find.text('96 kHz'), findsOneWidget);
      expect(find.text('3200 kbps'), findsOneWidget);
      expect(find.text('Google Drive'), findsOneWidget);

      // Verify Buttons
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Cache Offline'), findsOneWidget);

      // Verify sections
      expect(find.text('Audio Specifications'), findsOneWidget);
      expect(find.text('Cloud Storage & Caching'), findsOneWidget);
      expect(find.text('Audio Output & DSP'), findsOneWidget);
    });
  });

  group('Artist Details Screen Widget Tests', () {
    testWidgets('Renders Artist Avatar, stats, album carousel, and track lists', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith(
              (ref) => _FakeCatalogNotifier([sampleTrack, sampleTrack2]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: const ArtistDetailsScreen(artistName: 'Pink Floyd'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Artist Name & Header
      expect(find.text('Pink Floyd'), findsWidgets);
      expect(find.textContaining('2 Songs • 1 Albums'), findsOneWidget);

      // Verify Action Buttons
      expect(find.text('Play All'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);

      // Verify Albums & Songs sections
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('The Wall'), findsWidgets);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Comfortably Numb'), findsOneWidget);
      expect(find.text('Hey You'), findsOneWidget);

      // Verify Audio Quality Profile
      expect(find.text('Library Audio Profile'), findsOneWidget);
      expect(find.text('2 Hi-Res 24-Bit'), findsOneWidget);
    });
  });
}
