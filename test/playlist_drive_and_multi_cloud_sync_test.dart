import 'dart:convert';
import 'dart:io';
import 'package:dart_des/dart_des.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/services/audio/missing_track_audio_resolver.dart';
import 'package:freebeat/services/audio/track_audio_tagger_service.dart';
import 'package:freebeat/services/cloud/universal_cloud_upload_service.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';
import 'package:freebeat/services/playlist/playlist_missing_tracks_sync_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/widgets/cloud_sync_progress_banner.dart';
import 'package:freebeat/ui/widgets/playlist_import_modal.dart';

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
  });

  group('MissingTrackAudioResolver & Fallback Engine', () {
    test('Piped API fallback extracts audio candidates correctly', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('/search?q=')) {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'url': '/watch?v=mockVideo123',
                  'title': 'Test Song - Official Audio',
                  'uploaderName': 'Test Artist',
                  'duration': 210,
                }
              ]
            }),
            200,
          );
        } else if (url.contains('/streams/mockVideo123')) {
          return http.Response(
            jsonEncode({
              'audioStreams': [
                {
                  'url': 'https://mock.stream.server/audio.m4a',
                  'format': 'm4a',
                  'bitrate': 256000,
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = MissingTrackAudioResolver(httpClient: mockClient);
      final candidate = await resolver.resolveTrackAudio(
        title: 'Test Song',
        artist: 'Test Artist',
        expectedDurationMs: 210000,
      );

      expect(candidate, isNotNull);
      expect(candidate!.sourceId, equals('mockVideo123'));
      expect(candidate.format, equals('m4a'));
      expect(candidate.bitrateKbps, equals(256));
      expect(candidate.streamUrl, equals('https://mock.stream.server/audio.m4a'));
    });

    test('iTunes API resolves AAC stream candidate instantly with metadata', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('itunes.apple.com/search')) {
          return http.Response(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {
                  'trackId': 998877,
                  'trackName': 'Hello',
                  'artistName': 'Adele',
                  'collectionName': '25',
                  'previewUrl': 'https://audio-ssl.itunes.apple.com/m4a/hello.m4a',
                  'artworkUrl100': 'https://is1-ssl.mzstatic.com/100x100bb.jpg',
                  'trackTimeMillis': 295502,
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = MissingTrackAudioResolver(httpClient: mockClient);
      final candidate = await resolver.resolveTrackAudio(
        title: 'Hello',
        artist: 'Adele',
        expectedDurationMs: 295000,
      );

      expect(candidate, isNotNull);
      expect(candidate!.sourceId, equals('itunes_998877'));
      expect(candidate.sourceTitle, equals('Hello'));
      expect(candidate.channelOrArtist, equals('Adele'));
      expect(candidate.album, equals('25'));
      expect(candidate.streamUrl, equals('https://audio-ssl.itunes.apple.com/m4a/hello.m4a'));
      expect(candidate.format, equals('m4a'));
      expect(candidate.bitrateKbps, equals(256));
      expect(candidate.artworkUrl, contains('600x600bb'));
    });

    test('Direct preview URL passes through immediately with 0ms delay', () async {
      final resolver = MissingTrackAudioResolver();
      final candidate = await resolver.resolveTrackAudio(
        title: 'Direct Song',
        artist: 'Direct Artist',
        directPreviewUrl: 'https://p.scdn.co/mp3-preview/direct123.mp3',
        preferredArtworkUrl: 'https://i.scdn.co/image/art123.jpg',
        preferredAlbum: 'Direct Album',
      );

      expect(candidate, isNotNull);
      expect(candidate!.streamUrl, equals('https://p.scdn.co/mp3-preview/direct123.mp3'));
      expect(candidate.format, equals('mp3'));
      expect(candidate.artworkUrl, equals('https://i.scdn.co/image/art123.jpg'));
      expect(candidate.album, equals('Direct Album'));
    });

    test('JioSaavn full-length studio engine resolves 320kbps full song with DES decryption', () async {
      final key = utf8.encode('38346591');
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS5);
      final rawUrl = utf8.encode('https://aac.saavncdn.com/123/mock_song_96.mp4');
      final encBytes = des.encrypt(rawUrl);
      final encB64 = base64Encode(encBytes);

      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('jiosaavn.com/api.php') && url.contains('search.getResults')) {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 'saavn_track_456',
                  'song': 'Blinding Lights',
                  'primary_artists': 'The Weeknd',
                  'album': 'After Hours',
                  'duration': '200',
                  'image': 'https://c.saavncdn.com/123/art_150x150.jpg',
                  'encrypted_media_url': encB64,
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = MissingTrackAudioResolver(httpClient: mockClient);
      final candidate = await resolver.resolveTrackAudio(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        expectedDurationMs: 200000,
      );

      expect(candidate, isNotNull);
      expect(candidate!.sourceId, equals('saavn_saavn_track_456'));
      expect(candidate.sourceTitle, equals('Blinding Lights'));
      expect(candidate.channelOrArtist, equals('The Weeknd'));
      expect(candidate.album, equals('After Hours'));
      expect(candidate.streamUrl, equals('https://aac.saavncdn.com/123/mock_song_320.mp4'));
      expect(candidate.format, equals('m4a'));
      expect(candidate.bitrateKbps, equals(320));
      expect(candidate.durationMs, equals(200000));
      expect(candidate.isFullLength, isTrue);
      expect(candidate.artworkUrl, contains('500x500'));
    });

    test('TrackMatchScorer rigorously identifies authentic artists and eliminates covers, karaoke, and lullabies', () {
      // Authentic match
      final match1 = TrackMatchScorer.evaluate(
        targetTitle: 'Cruel Summer',
        targetArtist: 'Taylor Swift',
        candidateTitle: 'Cruel Summer',
        candidateArtist: 'Taylor Swift',
        targetDurationMs: 178000,
        candidateDurationMs: 178000,
      );
      expect(match1.isMatch, isTrue);
      expect(match1.score, greaterThanOrEqualTo(1.0));

      // Cover band rejection
      final coverMatch = TrackMatchScorer.evaluate(
        targetTitle: 'Come Together',
        targetArtist: 'The Beatles',
        candidateTitle: 'Come Together',
        candidateArtist: 'Sound Unlimited Electronic Orchestra',
        targetDurationMs: 260000,
        candidateDurationMs: 276000,
      );
      expect(coverMatch.isMatch, isFalse);
      expect(coverMatch.isDisqualified, isTrue);

      // Karaoke rejection
      final karaokeMatch = TrackMatchScorer.evaluate(
        targetTitle: 'Bohemian Rhapsody',
        targetArtist: 'Queen',
        candidateTitle: 'Bohemian Rhapsody (By Queen) (Instrumental Karaoke Version)',
        candidateArtist: 'ZZang KARAOKE',
        targetDurationMs: 354000,
        candidateDurationMs: 361000,
      );
      expect(karaokeMatch.isMatch, isFalse);
      expect(karaokeMatch.isDisqualified, isTrue);

      // Lullaby rejection
      final lullabyMatch = TrackMatchScorer.evaluate(
        targetTitle: 'Birds of a Feather',
        targetArtist: 'Billie Eilish',
        candidateTitle: 'BIRDS OF A FEATHER',
        candidateArtist: 'Lullapop',
        targetDurationMs: 210000,
        candidateDurationMs: 188000,
      );
      expect(lullabyMatch.isMatch, isFalse);
      expect(lullabyMatch.isDisqualified, isTrue);

      // Collaboration match
      final collabMatch = TrackMatchScorer.evaluate(
        targetTitle: 'Get Lucky',
        targetArtist: 'Daft Punk feat. Pharrell Williams',
        candidateTitle: 'Get Lucky (Radio Edit - feat. Pharrell Williams and Nile Rodgers)',
        candidateArtist: 'Daft Punk, Pharrell Williams, Nile Rodgers',
        targetDurationMs: 248000,
        candidateDurationMs: 248000,
      );
      expect(collabMatch.isMatch, isTrue);

      // Remix rejection
      final remixMatch = TrackMatchScorer.evaluate(
        targetTitle: 'City to City',
        targetArtist: 'JANI',
        candidateTitle: 'City to City (Club Remix)',
        candidateArtist: 'JANI',
        targetDurationMs: 205000,
        candidateDurationMs: 205000,
      );
      expect(remixMatch.isMatch, isFalse);
      expect(remixMatch.isDisqualified, isTrue);

      // Live performance rejection
      final liveMatch = TrackMatchScorer.evaluate(
        targetTitle: 'On & On',
        targetArtist: 'Shamoon Ismail',
        candidateTitle: 'On & On (Live in Concert)',
        candidateArtist: 'Shamoon Ismail',
        targetDurationMs: 190000,
        candidateDurationMs: 190000,
      );
      expect(liveMatch.isMatch, isFalse);
      expect(liveMatch.isDisqualified, isTrue);

      // Primary artist enforcement rejection
      final missingPrimaryMatch = TrackMatchScorer.evaluate(
        targetTitle: 'Na Milay',
        targetArtist: 'HAVI, Afifa Moin, Arsalan Hasan, Haider Abbas',
        candidateTitle: 'Na Milay',
        candidateArtist: 'Arsalan Hasan',
        targetDurationMs: 285000,
        candidateDurationMs: 285000,
      );
      expect(missingPrimaryMatch.isMatch, isFalse);
      expect(missingPrimaryMatch.isDisqualified, isTrue);

      // Partial title / substring rejection
      final partialTitleMatch = TrackMatchScorer.evaluate(
        targetTitle: 'City to City',
        targetArtist: 'JANI',
        candidateTitle: 'City',
        candidateArtist: 'JANI',
        targetDurationMs: 205000,
        candidateDurationMs: 205000,
      );
      expect(partialTitleMatch.isMatch, isFalse);
      expect(partialTitleMatch.isDisqualified, isTrue);

      // Duration tolerance (> 40s) rejection
      final durationMismatched = TrackMatchScorer.evaluate(
        targetTitle: 'Faasle',
        targetArtist: 'Kaavish',
        candidateTitle: 'Faasle',
        candidateArtist: 'Kaavish',
        targetDurationMs: 311000,
        candidateDurationMs: 260000, // 51s difference
      );
      expect(durationMismatched.isMatch, isFalse);
      expect(durationMismatched.isDisqualified, isTrue);
    });

    test('JioSaavn engine bypasses cover band at index 0 and selects genuine artist at index 1', () async {
      final key = utf8.encode('38346591');
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS5);
      final rawCoverUrl = utf8.encode('https://aac.saavncdn.com/123/cover_song_96.mp4');
      final rawAuthenticUrl = utf8.encode('https://aac.saavncdn.com/123/authentic_queen_96.mp4');
      final encCoverB64 = base64Encode(des.encrypt(rawCoverUrl));
      final encAuthenticB64 = base64Encode(des.encrypt(rawAuthenticUrl));

      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('jiosaavn.com/api.php') && url.contains('search.getResults')) {
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 'cover_0',
                  'song': 'Bohemian Rhapsody',
                  'primary_artists': 'The Cat And Owl',
                  'duration': '393',
                  'encrypted_media_url': encCoverB64,
                },
                {
                  'id': 'authentic_1',
                  'song': 'Bohemian Rhapsody',
                  'primary_artists': 'Queen',
                  'album': 'A Night at the Opera',
                  'duration': '354',
                  'image': 'https://c.saavncdn.com/queen/art_150x150.jpg',
                  'encrypted_media_url': encAuthenticB64,
                },
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final resolver = MissingTrackAudioResolver(httpClient: mockClient);
      final candidate = await resolver.resolveTrackAudio(
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        expectedDurationMs: 354000,
      );

      expect(candidate, isNotNull);
      expect(candidate!.channelOrArtist, equals('Queen'));
      expect(candidate.sourceId, equals('saavn_authentic_1'));
      expect(candidate.streamUrl, contains('authentic_queen_320.mp4'));
    });
  });

  group('TrackAudioTaggerService & PreparedTrackAudio', () {
    test('Downloads stream chunks, tags metadata, and purges scratch file', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'mock.stream.server') {
          return http.Response.bytes(
            List.filled(1024, 65), // 1KB mock audio
            200,
          );
        }
        if (request.url.host == 'itunes.apple.com') {
          return http.Response(
            jsonEncode({
              'resultCount': 1,
              'results': [
                {
                  'trackName': 'Midnight City',
                  'artistName': 'M83',
                  'collectionName': 'Hurry Up, We\'re Dreaming',
                  'artworkUrl100': 'https://itunes.com/art100.jpg',
                }
              ]
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final tagger = TrackAudioTaggerService(httpClient: mockClient);
      const candidate = AudioStreamCandidate(
        streamUrl: 'https://mock.stream.server/track.m4a',
        format: 'm4a',
        bitrateKbps: 256,
        sourceId: 'src_123',
        sourceTitle: 'Midnight City',
        channelOrArtist: 'M83',
        durationMs: 244000,
      );

      final prepared = await tagger.downloadAndPrepareAudio(
        candidate: candidate,
        targetTitle: 'Midnight City',
        targetArtist: 'M83',
      );

      expect(prepared.title, equals('Midnight City'));
      expect(prepared.artist, equals('M83'));
      expect(await prepared.file.exists(), isTrue);
      expect(prepared.sizeBytes, equals(1024));

      // Test zero-storage purging
      await prepared.purge();
      expect(await prepared.file.exists(), isFalse);
    });
  });

  group('UniversalCloudUploadService Multi-Cloud Matrix', () {
    late File scratchFile;

    setUp(() async {
      scratchFile = File('${Directory.systemTemp.path}/test_scratch_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await scratchFile.writeAsBytes(List.filled(2048, 70));
    });

    tearDown(() async {
      if (await scratchFile.exists()) {
        await scratchFile.delete().catchError((_) => scratchFile);
      }
    });

    test('Uploads to Google Drive via multipart upload and purges scratch file', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/upload/drive/v3/files')) {
          expect(request.headers['Authorization'], contains('Bearer mock_gdrive_token'));
          expect(request.headers['Content-Type'], contains('multipart/related'));
          return http.Response(jsonEncode({'id': 'drive_file_999', 'name': 'test.m4a'}), 200);
        }
        if (request.url.host == 'www.googleapis.com' && request.method == 'POST') {
          return http.Response(jsonEncode({'id': 'folder_sub'}), 200);
        }
        if (request.url.host == 'www.googleapis.com') {
          // Folder query or create
          return http.Response(jsonEncode({'files': [{'id': 'folder_root'}]}), 200);
        }
        return http.Response('{}', 200);
      });

      final uploader = UniversalCloudUploadService(httpClient: mockClient);
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'M83 - Midnight City.m4a',
        title: 'Midnight City',
        artist: 'M83',
        album: 'Synthwave Mix',
        format: 'm4a',
        durationMs: 244000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_gdrive',
        providerType: CloudProviderType.googleDrive,
        displayName: 'My Google Drive',
        endpointOrFolder: '/',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {'accessToken': 'mock_gdrive_token'},
        playlistName: 'Synthwave Mix',
      );

      expect(track.id, equals('gdrive_drive_file_999'));
      expect(track.providerType, equals(CloudProviderType.googleDrive));
      expect(track.streamUrl, contains('drive/v3/files/drive_file_999?alt=media'));
      // Scratch file must be purged after upload
      expect(await scratchFile.exists(), isFalse);
    });

    test('Uploads to Microsoft OneDrive via Graph v1.0 and purges scratch file', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'graph.microsoft.com') {
          expect(request.method, equals('PUT'));
          expect(request.headers['Authorization'], contains('Bearer mock_onedrive_token'));
          return http.Response(
            jsonEncode({
              'id': 'onedrive_item_888',
              '@microsoft.graph.downloadUrl': 'https://onedrive.live.com/download/888',
            }),
            201,
          );
        }
        return http.Response('{}', 200);
      });

      final uploader = UniversalCloudUploadService(httpClient: mockClient);
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Test Artist - Song.m4a',
        title: 'Song',
        artist: 'Test Artist',
        album: 'Chill Playlist',
        format: 'm4a',
        durationMs: 180000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_onedrive',
        providerType: CloudProviderType.oneDrive,
        displayName: 'Personal OneDrive',
        endpointOrFolder: '/',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {'accessToken': 'mock_onedrive_token'},
        playlistName: 'Chill Playlist',
      );

      expect(track.id, equals('onedrive_onedrive_item_888'));
      expect(track.providerType, equals(CloudProviderType.oneDrive));
      expect(track.streamUrl, equals('https://onedrive.live.com/download/888'));
      expect(await scratchFile.exists(), isFalse);
    });

    test('Uploads to Dropbox v2 and purges scratch file', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'content.dropboxapi.com') {
          expect(request.headers['Dropbox-API-Arg'], contains('/FreeBeat Music/'));
          return http.Response(
            jsonEncode({
              'id': 'id:dropbox_file_777',
              'path_lower': '/freebeat music/workout/song.m4a',
              'name': 'song.m4a',
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final uploader = UniversalCloudUploadService(httpClient: mockClient);
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Artist - Song.m4a',
        title: 'Song',
        artist: 'Artist',
        album: 'Workout',
        format: 'm4a',
        durationMs: 200000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_dropbox',
        providerType: CloudProviderType.dropbox,
        displayName: 'My Dropbox',
        endpointOrFolder: '/',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {'accessToken': 'mock_dbx_token'},
        playlistName: 'Workout',
      );

      expect(track.providerType, equals(CloudProviderType.dropbox));
      expect(track.streamUrl, equals('https://content.dropboxapi.com/2/files/download'));
      expect(await scratchFile.exists(), isFalse);
    });

    test('Uploads to WebDAV / Nextcloud with MKCOL & PUT', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'MKCOL') {
          return http.Response('', 201);
        }
        if (request.method == 'PUT') {
          expect(request.headers['Authorization'], contains('Basic'));
          return http.Response('', 201);
        }
        return http.Response('', 200);
      });

      final uploader = UniversalCloudUploadService(httpClient: mockClient);
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Artist - Song.m4a',
        title: 'Song',
        artist: 'Artist',
        album: 'Nextcloud Mix',
        format: 'm4a',
        durationMs: 200000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_webdav',
        providerType: CloudProviderType.webdav,
        displayName: 'Home Nextcloud',
        endpointOrFolder: 'https://cloud.example.com/remote.php/webdav',
        usernameOrEmail: 'user',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {'password': 'mock_password'},
        playlistName: 'Nextcloud Mix',
      );

      expect(track.providerType, equals(CloudProviderType.webdav));
      expect(track.streamUrl, contains('https://cloud.example.com/remote.php/webdav/FreeBeat%20Music/'));
      expect(await scratchFile.exists(), isFalse);
    });

    test('Uploads to S3 storage via SigV4 PUT and preserves streaming compatibility', () async {
      final mockClient = MockClient((request) async {
        if (request.method == 'PUT') {
          expect(request.url.query, contains('X-Amz-Signature'));
          return http.Response('', 200);
        }
        return http.Response('', 200);
      });

      final uploader = UniversalCloudUploadService(httpClient: mockClient);
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Artist - Song.m4a',
        title: 'Song',
        artist: 'Artist',
        album: 'S3 High-Fi',
        format: 'm4a',
        durationMs: 200000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_s3',
        providerType: CloudProviderType.s3,
        displayName: 'Wasabi / S3',
        endpointOrFolder: 'https://s3.wasabisys.com',
        bucketOrShareName: 'my-lossless-bucket',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {'accessKeyId': 'testKey', 'secretAccessKey': 'testSecret'},
        playlistName: 'S3 High-Fi',
      );

      expect(track.providerType, equals(CloudProviderType.s3));
      expect(track.streamUrl, equals('https://s3.wasabisys.com/my-lossless-bucket/FreeBeat Music/S3 High-Fi/Artist - Song.m4a'));
      expect(await scratchFile.exists(), isFalse);
    });

    test('Copies to Local Device Storage fallback when selected', () async {
      final uploader = UniversalCloudUploadService();
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Offline_Track.m4a',
        title: 'Offline Track',
        artist: 'Local Artist',
        album: 'Device Playlist',
        format: 'm4a',
        durationMs: 150000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_local',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Device Storage (Offline)',
        endpointOrFolder: '/imported_music/',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {},
        playlistName: 'Device Playlist',
      );

      expect(track.providerType, equals(CloudProviderType.androidSaf));
      expect(track.isPinnedOffline, isFalse);
      expect(File(track.localCachePath!).existsSync(), isTrue);
      // Clean up destination
      File(track.localCachePath!).deleteSync();
    });

    test('Gracefully falls back to on-device storage when remote cloud token is missing', () async {
      final uploader = UniversalCloudUploadService();
      final prepared = PreparedTrackAudio(
        file: scratchFile,
        filename: 'Missing_Token_Song.m4a',
        title: 'Missing Token Song',
        artist: 'SAF Artist',
        album: 'SAF Mix',
        format: 'm4a',
        durationMs: 180000,
        sizeBytes: 2048,
        bitrateKbps: 256,
      );

      const account = CloudAccount(
        id: 'acc_saf_gdrive',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Google Drive (SAF)',
        endpointOrFolder: 'Android App Storage (Google Drive)',
      );

      final track = await uploader.uploadPreparedTrack(
        preparedAudio: prepared,
        account: account,
        secrets: {}, // Empty secrets from SAF mount
        playlistName: 'SAF Mix',
      );

      expect(track, isNotNull);
      expect(track.title, equals('Missing Token Song'));
      expect(track.isPinnedOffline, isFalse);
      expect(File(track.localCachePath!).existsSync(), isTrue);
      File(track.localCachePath!).deleteSync();
    });
  });

  group('PlaylistMissingTracksSyncService State and Queue Coordinator', () {
    test('Processes queue, updates catalog and appends to playlist', () async {
      final mockResolver = MissingTrackAudioResolver(
        customResolver: ({required title, required artist, expectedDurationMs}) async {
          return const AudioStreamCandidate(
            streamUrl: 'https://mock.stream/solar.m4a',
            format: 'm4a',
            bitrateKbps: 256,
            sourceId: 'solar_123',
            sourceTitle: 'Solar Power',
            channelOrArtist: 'Lorde',
            durationMs: 193000,
          );
        },
      );

      final mockTagger = TrackAudioTaggerService(
        httpClient: MockClient((req) async {
          return http.Response.bytes(List.filled(512, 1), 200);
        }),
      );

      final container = ProviderContainer(
        overrides: [
          playlistMissingTracksSyncProvider.overrideWith((ref) {
            return PlaylistMissingTracksSyncNotifier(
              ref: ref,
              resolver: mockResolver,
              tagger: mockTagger,
              uploader: UniversalCloudUploadService(
                httpClient: MockClient((req) async => http.Response('{}', 200)),
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      // Create a test playlist
      final playlist = await container.read(playlistsProvider.notifier).createPlaylist(
            'Test Cloud Mix',
            description: 'Imported test playlist',
            initialTrackIds: [],
          );

      const testAccount = CloudAccount(
        id: 'acc_local_test',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Test Local Storage',
        endpointOrFolder: '/imported_music/',
      );

      final syncNotifier = container.read(playlistMissingTracksSyncProvider.notifier);

      // Verify initial state
      expect(container.read(playlistMissingTracksSyncProvider).isSyncing, isFalse);

      final missingList = [
        const MissingTrackItem(title: 'Solar Power', artist: 'Lorde', expectedDurationMs: 193000),
      ];

      await syncNotifier.startSync(
        missingTracks: missingList,
        playlistId: playlist.id,
        playlistTitle: playlist.title,
        account: testAccount,
      );

      // State after completion
      final finalState = container.read(playlistMissingTracksSyncProvider);
      expect(finalState.isSyncing, isFalse);
      expect(finalState.totalCount, equals(1));
      expect(finalState.completedCount, equals(1));
      expect(finalState.uploadedTracks.length, equals(1));

      // Verify track catalog has the new track
      final catalog = container.read(tracksCatalogProvider);
      expect(catalog.any((t) => t.title == 'Solar Power'), isTrue);

      // Verify playlist has the newly added track id
      final updatedPlaylists = container.read(playlistsProvider);
      final updatedPlaylist = updatedPlaylists.firstWhere((p) => p.id == playlist.id);
      expect(updatedPlaylist.trackIds, contains(finalState.uploadedTracks.first.id));
    });

    test('Processes large track queue in discrete batches of 10 tracks', () async {
      final mockResolver = MissingTrackAudioResolver(
        customResolver: ({required title, required artist, expectedDurationMs}) async {
          return AudioStreamCandidate(
            streamUrl: 'https://mock.stream/$title.m4a',
            format: 'm4a',
            bitrateKbps: 256,
            sourceId: 'id_$title',
            sourceTitle: title,
            channelOrArtist: artist,
            durationMs: 200000,
          );
        },
      );

      final mockTagger = TrackAudioTaggerService(
        httpClient: MockClient((req) async {
          return http.Response.bytes(List.filled(256, 1), 200);
        }),
      );

      final container = ProviderContainer(
        overrides: [
          playlistMissingTracksSyncProvider.overrideWith((ref) {
            return PlaylistMissingTracksSyncNotifier(
              ref: ref,
              resolver: mockResolver,
              tagger: mockTagger,
              uploader: UniversalCloudUploadService(
                httpClient: MockClient((req) async => http.Response('{}', 200)),
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final playlist = await container.read(playlistsProvider.notifier).createPlaylist(
            'Batch Test Mix',
            description: 'Batch 10 track test',
            initialTrackIds: [],
          );

      const testAccount = CloudAccount(
        id: 'acc_batch_test',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Test Local Storage',
        endpointOrFolder: '/imported_music/',
      );

      final syncNotifier = container.read(playlistMissingTracksSyncProvider.notifier);

      // Create 23 missing tracks (expecting batches of 10: 10 + 10 + 3)
      final missingList = List.generate(
        23,
        (i) => MissingTrackItem(
          title: 'Track ${i + 1}',
          artist: 'Artist ${i + 1}',
          expectedDurationMs: 200000,
        ),
      );

      await syncNotifier.startSync(
        missingTracks: missingList,
        playlistId: playlist.id,
        playlistTitle: playlist.title,
        account: testAccount,
      );

      final finalState = container.read(playlistMissingTracksSyncProvider);
      expect(finalState.isSyncing, isFalse);
      expect(finalState.totalCount, equals(23));
      expect(finalState.completedCount, equals(23));
      expect(finalState.uploadedTracks.length, equals(23));

      // Verify all 23 tracks are in catalog and playlist
      final catalog = container.read(tracksCatalogProvider);
      for (var i = 1; i <= 23; i++) {
        expect(catalog.any((t) => t.title == 'Track $i'), isTrue);
      }

      final updatedPlaylists = container.read(playlistsProvider);
      final updatedPlaylist = updatedPlaylists.firstWhere((p) => p.id == playlist.id);
      expect(updatedPlaylist.trackIds.length, equals(23));
    });

    testWidgets('CloudSyncProgressBanner renders correctly when sync is active', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CloudSyncProgressBanner(),
            ),
          ),
        ),
      );

      // Banner should be hidden initially
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('PlaylistImportResult & Modal Integration', () {
    test('PlaylistImportResult parses and constructs MissingTrackItem entries', () {
      final result = PlaylistImportResult(
        title: 'Dream Pop',
        description: 'Imported from Spotify',
        matchedTracks: [],
        unmatchedTrackNames: [
          'Beach House - Space Song',
          'Cocteau Twins - Cherry-coloured Funk',
        ],
        totalParsed: 2,
        sourceType: 'spotify',
      );

      expect(result.missingTracks.length, equals(2));
      expect(result.missingTracks[0].title, equals('Space Song'));
      expect(result.missingTracks[0].artist, equals('Beach House'));
      expect(result.missingTracks[1].title, equals('Cherry-coloured Funk'));
      expect(result.missingTracks[1].artist, equals('Cocteau Twins'));
    });

    testWidgets('PlaylistImportModal displays cloud sync card and destination picker', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('Home')),
            ),
          ),
        ),
      );

      final context = tester.element(find.text('Home'));
      showPlaylistImportModal(context);
      await tester.pumpAndSettle();

      // Modal should be visible with Spotify / Apple branding and input fields
      expect(find.text('Import Playlist'), findsOneWidget);
      expect(find.text('Match Tracks'), findsOneWidget);
      expect(find.text('Save Playlist'), findsOneWidget);
      expect(find.text('Get Missing Tracks'), findsOneWidget);
    });

    test('Spotify Embed parsing extracts exact playlist name and tracks', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('open.spotify.com/oembed')) {
          return http.Response(
            jsonEncode({
              'title': "Today's Top Hits",
              'thumbnail_url': 'https://image.spotify.com/tth.jpg',
            }),
            200,
          );
        } else if (url.contains('open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M')) {
          final nextData = {
            'props': {
              'pageProps': {
                'state': {
                  'data': {
                    'entity': {
                      'name': "Today's Top Hits",
                      'subtitle': 'The hottest hits right now',
                      'trackList': [
                        {
                          'title': 'expectations',
                          'subtitle': 'Olivia Rodrigo, Chappell Roan',
                          'duration': 223935,
                        },
                        {
                          'title': 'Nicole Kidman',
                          'subtitle': 'ADÉLA',
                          'duration': 181270,
                        },
                      ],
                    },
                  },
                },
              },
            },
          };
          return http.Response(
            '<html><head><script id="__NEXT_DATA__" type="application/json">${jsonEncode(nextData)}</script></head><body></body></html>',
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = PlaylistImportService(httpClient: mockClient);
      final result = await service.importFromUrl(
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc123',
        [],
      );

      expect(result.title, equals("Today's Top Hits"));
      expect(result.totalParsed, equals(2));
      expect(result.missingTracks.length, equals(2));
      expect(result.missingTracks[0].title, equals('expectations'));
      expect(result.missingTracks[0].artist, equals('Olivia Rodrigo, Chappell Roan'));
      expect(result.missingTracks[0].expectedDurationMs, equals(223935));
      expect(result.missingTracks[1].title, equals('Nicole Kidman'));
      expect(result.missingTracks[1].artist, equals('ADÉLA'));
    });

    test('Apple Music parsing extracts exact playlist name and tracks', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('music.apple.com/api/oembed')) {
          return http.Response(
            jsonEncode({
              'title': "Today's Hits",
              'thumbnail_url': 'https://image.apple.com/tth.jpg',
            }),
            200,
          );
        } else if (url.contains('music.apple.com/us/playlist/todays-hits')) {
          final jsonLd = {
            '@context': 'http://schema.org',
            '@type': 'MusicPlaylist',
            'name': "Today's Hits",
            'description': 'Listen to Today\'s Hits',
            'track': [
              {
                '@type': 'MusicRecording',
                'name': 'expectations',
                'duration': 'PT3M43S',
                'byArtist': [
                  {'name': 'Olivia Rodrigo'}
                ],
              },
            ],
          };
          return http.Response(
            '<html><head><script id="schema:music-playlist" type="application/ld+json">${jsonEncode(jsonLd)}</script></head><body></body></html>',
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = PlaylistImportService(httpClient: mockClient);
      final result = await service.importFromUrl(
        'https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb',
        [],
      );

      expect(result.title, equals("Today's Hits"));
      expect(result.totalParsed, equals(1));
      expect(result.missingTracks.length, equals(1));
      expect(result.missingTracks[0].title, equals('expectations'));
      expect(result.missingTracks[0].artist, equals('Olivia Rodrigo'));
      expect(result.missingTracks[0].expectedDurationMs, equals(223000));
    });
  });
}
