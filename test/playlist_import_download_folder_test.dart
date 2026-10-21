import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/services/audio/track_audio_tagger_service.dart';
import 'package:freebeat/services/cloud/universal_cloud_upload_service.dart';
import 'package:freebeat/services/playlist/playlist_missing_tracks_sync_service.dart';
import 'package:freebeat/state/app_providers.dart';

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
      const MethodChannel('com.freebeat.app/pixel_haptics'),
      (MethodCall methodCall) async => null,
    );
  });

  group('Download Folder Resolution and Local Storage Fallback', () {
    test('resolveMusicStorageDirectory resolves folder named after playlist', () async {
      final dir = await UniversalCloudUploadService.resolveMusicStorageDirectory(
        'Test Synthwave Hits',
      );
      expect(dir.existsSync(), isTrue);
      expect(dir.path.contains('Test Synthwave Hits'), isTrue);
    });

    test('getPublicMusicStorageAddress returns formatted folder string', () async {
      final address = await UniversalCloudUploadService.getPublicMusicStorageAddress(
        playlistName: 'Cyberpunk 2077 OST',
      );
      expect(address.isNotEmpty, isTrue);
      expect(address.contains('Cyberpunk 2077 OST'), isTrue);
    });

    test('uploadToLocalStorage creates track inside playlist folder', () async {
      final uploader = UniversalCloudUploadService();
      final scratchFile = File('${Directory.systemTemp.path}/test_scratch_song.mp3')
        ..writeAsBytesSync(List.filled(1024, 7));

      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Neon_City.mp3',
        title: 'Neon City',
        artist: 'Retrowave Guy',
        album: 'Test Synthwave Hits',
        format: 'mp3',
        durationMs: 180000,
        sizeBytes: 1024,
        bitrateKbps: 320,
      );

      const account = CloudAccount(
        id: 'device_storage_import',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Device Storage (FreeBeat Music)',
        endpointOrFolder: '/FreeBeat Music/',
      );

      final track = await uploader.uploadToLocalStorage(
        preparedAudio: prepared,
        account: account,
        playlistName: 'Test Synthwave Hits',
      );

      expect(track.id.startsWith('local_'), isTrue);
      expect(track.title, equals('Neon City'));
      expect(track.artist, equals('Retrowave Guy'));
      expect(File(track.streamUrl).existsSync(), isTrue);
      expect(track.streamUrl.contains('Test Synthwave Hits'), isTrue);
      expect(track.isPinnedOffline, isFalse);

      if (File(track.streamUrl).existsSync()) {
        File(track.streamUrl).deleteSync();
      }
    });

    test('startSync prompts user when remote cloud credentials are missing and does not silently download', () async {
      final container = ProviderContainer(
        overrides: [
          credentialStoreProvider.overrideWithValue(SecureCredentialStore()),
        ],
      );

      final notifier = container.read(playlistMissingTracksSyncProvider.notifier);

      const unauthenticatedDriveAccount = CloudAccount(
        id: 'unauthed_drive_acc',
        providerType: CloudProviderType.googleDrive,
        displayName: 'My Google Drive',
        endpointOrFolder: 'root',
      );

      final missingTracks = [
        const MissingTrackItem(title: 'Resonance', artist: 'HOME'),
      ];

      // Start sync without prior approval
      final syncFuture = notifier.startSync(
        missingTracks: missingTracks,
        playlistId: 'pl_test_123',
        playlistTitle: 'Vaporwave Dreams',
        account: unauthenticatedDriveAccount,
        fallbackToLocalStorageApproved: false,
      );

      // Allow microtask tick
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(playlistMissingTracksSyncProvider);

      // Verify that pendingAuthPrompt is set and sync is waiting for user decision
      expect(state.pendingAuthPrompt, isNotNull);
      expect(state.pendingAuthPrompt!.account.displayName, equals('My Google Drive'));
      expect(state.pendingAuthPrompt!.playlistTitle, equals('Vaporwave Dreams'));
      expect(state.fallbackToLocalStorageApproved, isFalse);

      // Simulate user confirming fallback to device storage
      notifier.confirmAuthFallbackToLocalStorage();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final stateAfterConfirm = container.read(playlistMissingTracksSyncProvider);
      expect(stateAfterConfirm.pendingAuthPrompt, isNull);
      expect(stateAfterConfirm.fallbackToLocalStorageApproved, isTrue);

      notifier.cancelSync();
      await syncFuture;
    });

    test('startSync cancels without downloading when user cancels auth prompt', () async {
      final container = ProviderContainer(
        overrides: [
          credentialStoreProvider.overrideWithValue(SecureCredentialStore()),
        ],
      );

      final notifier = container.read(playlistMissingTracksSyncProvider.notifier);

      const unauthenticatedDriveAccount = CloudAccount(
        id: 'unauthed_drive_acc_2',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Google Drive Account',
        endpointOrFolder: 'root',
      );

      final missingTracks = [
        const MissingTrackItem(title: 'Sunset', artist: 'The Midnight'),
      ];

      final syncFuture = notifier.startSync(
        missingTracks: missingTracks,
        playlistId: 'pl_test_456',
        playlistTitle: 'Synth Dreams',
        account: unauthenticatedDriveAccount,
        fallbackToLocalStorageApproved: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(playlistMissingTracksSyncProvider).pendingAuthPrompt, isNotNull);

      // User cancels
      notifier.cancelAuthPromptAndSync();

      await syncFuture;

      final finalState = container.read(playlistMissingTracksSyncProvider);
      expect(finalState.isSyncing, isFalse);
      expect(finalState.pendingAuthPrompt, isNull);
      expect(finalState.currentStatusText.contains('cancelled'), isTrue);
    });
  });
}
