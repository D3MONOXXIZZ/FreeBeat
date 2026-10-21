import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/services/audio/track_audio_tagger_service.dart';
import 'package:freebeat/services/cloud/universal_cloud_upload_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
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
  });
}
