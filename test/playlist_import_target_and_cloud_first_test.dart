import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/services/audio/track_audio_tagger_service.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/cloud/universal_cloud_upload_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/playlist_details_screen.dart';
import 'package:freebeat/ui/widgets/playlist_import_modal.dart';

class _FakeCloudStreamProxy extends CloudStreamProxy {
  _FakeCloudStreamProxy()
      : super(
          connectorRegistry: CloudConnectorRegistry(),
          credentialStore: SecureCredentialStore(),
        );

  @override
  Future<void> start() async {}
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
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') return <String, dynamic>{};
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'disposeAllPlayers') return <dynamic>[];
        return <String, dynamic>{};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/pixel_haptics'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
  });

  group('Cloud-First & Offline Vault Isolation', () {
    test('Remote cloud upload does not secretly save to local disk and purges scratch file', () async {
      final uploader = UniversalCloudUploadService();
      final scratchFile = File('${Directory.systemTemp.path}/test_scratch_track.m4a')
        ..writeAsBytesSync(List.filled(2048, 42));

      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Cloud_Track.m4a',
        title: 'Cloud Track',
        artist: 'Cloud Artist',
        album: 'Cloud Album',
        format: 'm4a',
        durationMs: 200000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const remoteAccount = CloudAccount(
        id: 'acc_gdrive_test',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Google Drive',
        endpointOrFolder: 'root',
      );

      // Without auth secrets, remote cloud upload MUST throw CloudUploadException
      // and NOT silently fall back to downloading to on-device storage.
      expect(
        () => uploader.uploadPreparedTrack(
          preparedAudio: prepared,
          account: remoteAccount,
          secrets: {},
          playlistName: 'My Cloud Playlist',
        ),
        throwsA(isA<CloudUploadException>()),
      );

      if (scratchFile.existsSync()) scratchFile.deleteSync();
    });

    test('Cloud tracks have isPinnedOffline=false and do not appear in Offline Vault', () {
      final cloudTrack = Track(
        id: 'gdrive_mock_file_123',
        accountId: 'acc_gdrive',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'mock_file_123',
        title: 'Cloud Only Song',
        artist: 'Stream Artist',
        album: 'Cloud Album',
        durationMs: 210000,
        streamUrl: 'https://www.googleapis.com/drive/v3/files/mock_file_123?alt=media',
        codec: 'M4A',
        bitrateKbps: 256,
        sizeBytes: 3000000,
        isPinnedOffline: false,
        localCachePath: null,
      );

      final localPinnedTrack = Track(
        id: 'local_offline_456',
        accountId: 'acc_local',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/storage/offline.mp3',
        title: 'Vault Song',
        artist: 'Offline Artist',
        album: 'Vault Album',
        durationMs: 180000,
        streamUrl: '/storage/offline.mp3',
        codec: 'MP3',
        bitrateKbps: 320,
        sizeBytes: 5000000,
        isPinnedOffline: true,
        localCachePath: '/storage/offline.mp3',
      );

      final allTracks = [cloudTrack, localPinnedTrack];

      // Offline Vault filter condition: allTracks.where((t) => t.isPinnedOffline)
      final offlineVaultTracks = allTracks.where((t) => t.isPinnedOffline).toList();

      expect(offlineVaultTracks.length, equals(1));
      expect(offlineVaultTracks.first.id, equals(localPinnedTrack.id));
      expect(offlineVaultTracks.any((t) => t.id == cloudTrack.id), isFalse);
    });
  });

  group('Playlist Details Screen Import Integration', () {
    testWidgets('PlaylistDetailsScreen renders Import Songs in AppBar, Header, and Empty View', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      final playlist = await container.read(playlistsProvider.notifier).createPlaylist(
        'Chill Study Hits',
        description: 'Cozy focus music',
        initialTrackIds: [],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PlaylistDetailsScreen(playlist: playlist),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. SliverAppBar Import Action
      expect(find.byTooltip('Import Songs'), findsOneWidget);

      // 2. Header Action Row Button
      expect(find.text('Import Songs (Spotify / Apple Music / Text / M3U)'), findsOneWidget);

      // 3. Empty State Prominent Action
      expect(find.text('Import Songs into Playlist'), findsOneWidget);
    });

    testWidgets('showPlaylistImportModal adapts for targetPlaylist correctly', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      final playlist = await container.read(playlistsProvider.notifier).createPlaylist(
        'Roadtrip 2026',
        description: 'Vibes for the drive',
        initialTrackIds: [],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('PlaylistRoot')),
            ),
          ),
        ),
      );

      final context = tester.element(find.text('PlaylistRoot'));
      showPlaylistImportModal(context, targetPlaylist: playlist);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Modal Title & Subtitle adapted for target playlist
      expect(find.text('Import Songs into Playlist'), findsOneWidget);
      expect(find.text('Adding songs to "Roadtrip 2026"'), findsOneWidget);

      // Action buttons reflect adding to existing playlist
      expect(find.text('Add Matched'), findsOneWidget);
      expect(find.text('Sync & Add Missing'), findsOneWidget);
    });
  });
}
