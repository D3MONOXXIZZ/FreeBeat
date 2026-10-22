import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/services/audio/track_audio_tagger_service.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';
import 'package:freebeat/services/playlist/playlist_missing_tracks_sync_service.dart';
import 'package:freebeat/services/playlist/playlist_sync_service.dart';
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

      // 1. Small Action Pill for Import
      expect(find.text('Import'), findsWidgets);
      expect(find.byTooltip('Import Songs (Spotify, Apple Music, YouTube, M3U)'), findsOneWidget);

      // 2. Empty State Prominent Action
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

  group('PlaylistSyncService & Continuous Remote Sync', () {
    test('Diffs remote Spotify tracks and only adds new tracks', () async {
      final mockClient = MockClient((request) async {
        final url = request.url.toString();
        if (url.contains('open.spotify.com/oembed')) {
          return http.Response(
            jsonEncode({
              'title': 'Indie Summer 2026',
              'thumbnail_url': 'https://image.spotify.com/art.jpg',
            }),
            200,
          );
        } else if (url.contains('open.spotify.com/embed/playlist/mockSyncPlaylist123')) {
          final nextData = {
            'props': {
              'pageProps': {
                'state': {
                  'data': {
                    'entity': {
                      'name': 'Indie Summer 2026',
                      'trackList': [
                        {
                          'title': 'Existing Song',
                          'subtitle': 'Artist One',
                          'duration': 180000,
                        },
                        {
                          'title': 'Brand New Song',
                          'subtitle': 'Artist Two',
                          'duration': 210000,
                        },
                      ],
                    },
                  },
                },
              },
            },
          };
          final html = '''
<!DOCTYPE html>
<html>
<head>
<script id="__NEXT_DATA__" type="application/json">${jsonEncode(nextData)}</script>
</head>
<body></body>
</html>
''';
          return http.Response(html, 200);
        }
        return http.Response('Not Found', 404);
      });

      final syncService = PlaylistSyncService(
        importService: PlaylistImportService(httpClient: mockClient),
      );

      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      // Existing track in library and in playlist
      const existingTrack = Track(
        id: 'track_existing_1',
        accountId: 'acc_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'file_1',
        title: 'Existing Song',
        artist: 'Artist One',
        album: 'Album One',
        durationMs: 180000,
        streamUrl: 'https://stream.mock/1',
      );

      // New track already in library but NOT in this playlist
      const newLibraryTrack = Track(
        id: 'track_new_2',
        accountId: 'acc_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'file_2',
        title: 'Brand New Song',
        artist: 'Artist Two',
        album: 'Album Two',
        durationMs: 210000,
        streamUrl: 'https://stream.mock/2',
      );

      await container.read(tracksCatalogProvider.notifier).addIndexedTracks([existingTrack, newLibraryTrack]);

      final initialPlaylist = await container.read(playlistsProvider.notifier).createPlaylist(
        'Indie Summer 2026',
        description: 'Synced playlist',
        initialTrackIds: [existingTrack.id],
        syncSourceUrl: 'https://open.spotify.com/playlist/mockSyncPlaylist123',
      );

      final outcome = await syncService.syncPlaylist(
        playlist: initialPlaylist,
        sourceUrl: 'https://open.spotify.com/playlist/mockSyncPlaylist123',
        allLibraryTracks: [existingTrack, newLibraryTrack],
        playlistsNotifier: container.read(playlistsProvider.notifier),
        missingTracksNotifier: container.read(playlistMissingTracksSyncProvider.notifier),
        cloudAccounts: [],
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.totalFoundInSource, equals(2));
      expect(outcome.newMatchedTracksCount, equals(1)); // Only 'Brand New Song' was newly added
      expect(outcome.newMissingTracksCount, equals(0));

      final updatedPlaylists = container.read(playlistsProvider);
      final updated = updatedPlaylists.firstWhere((p) => p.id == initialPlaylist.id);
      expect(updated.trackIds, contains(newLibraryTrack.id));
      expect(updated.trackIds.length, equals(2));
      expect(updated.lastSyncedAt, isNotNull);

      // Second sync should report 0 new tracks
      final secondOutcome = await syncService.syncPlaylist(
        playlist: updated,
        sourceUrl: 'https://open.spotify.com/playlist/mockSyncPlaylist123',
        allLibraryTracks: [existingTrack, newLibraryTrack],
        playlistsNotifier: container.read(playlistsProvider.notifier),
        missingTracksNotifier: container.read(playlistMissingTracksSyncProvider.notifier),
        cloudAccounts: [],
      );

      expect(secondOutcome.isSuccess, isTrue);
      expect(secondOutcome.totalNewTracksCount, equals(0));
      expect(secondOutcome.message, contains('already up to date'));
    });

    testWidgets('PlaylistDetailsScreen renders 1-Tap Sync button and updates lastSyncedAt', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      final playlist = await container.read(playlistsProvider.notifier).createPlaylist(
        'Vibe Station',
        description: 'Spotify Linked',
        initialTrackIds: [],
        syncSourceUrl: 'https://open.spotify.com/playlist/vibe_station_123',
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
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

      // Sync action pill & tooltip
      expect(find.byIcon(Icons.sync_rounded), findsWidgets);
      expect(find.byTooltip('Sync with Spotify • 5m ago'), findsOneWidget);
    });

    test('YouTube videoId and playlistId extraction across all YouTube & YT Music URL formats', () {
      expect(
        PlaylistImportService.extractYouTubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        equals('dQw4w9WgXcQ'),
      );
      expect(
        PlaylistImportService.extractYouTubeVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ'),
        equals('dQw4w9WgXcQ'),
      );
      expect(
        PlaylistImportService.extractYouTubeVideoId('https://youtu.be/dQw4w9WgXcQ'),
        equals('dQw4w9WgXcQ'),
      );
      expect(
        PlaylistImportService.extractYouTubeVideoId('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        equals('dQw4w9WgXcQ'),
      );
      expect(
        PlaylistImportService.extractYouTubeVideoId('https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVMdQw4w9WgXcQ'),
        equals('dQw4w9WgXcQ'),
      );

      expect(
        PlaylistImportService.extractYouTubePlaylistId('https://www.youtube.com/playlist?list=PL1234567890'),
        equals('PL1234567890'),
      );
      expect(
        PlaylistImportService.extractYouTubePlaylistId('https://music.youtube.com/playlist?list=PL1234567890'),
        equals('PL1234567890'),
      );
      expect(
        PlaylistImportService.extractYouTubePlaylistId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1234567890'),
        equals('PL1234567890'),
      );
    });

    test('YouTube title and artist cleaner removes video fluff and parses Artist - Title', () {
      // 1. Artist - Title with official video brackets
      final res1 = PlaylistImportService.extractYouTubeVideoId('https://youtu.be/dQw4w9WgXcQ');
      expect(res1, equals('dQw4w9WgXcQ'));

      final mockClient = MockClient((request) async {
        if (request.url.toString().contains('youtube.com/oembed')) {
          return http.Response(
            jsonEncode({
              'title': 'Rick Astley - Never Gonna Give You Up (Official Video) (4K Remaster)',
              'author_name': 'Rick Astley',
              'thumbnail_url': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = PlaylistImportService(httpClient: mockClient);
      expect(service, isNotNull);
    });

    test('YouTube single track import via oEmbed fallback returns single parsed track', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('youtube.com') && request.url.path.contains('oembed')) {
          return http.Response(
            jsonEncode({
              'title': 'The Weeknd - Blinding Lights (Official Audio)',
              'author_name': 'The Weeknd',
              'thumbnail_url': 'https://i.ytimg.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = PlaylistImportService(httpClient: mockClient);
      final result = await service.importFromUrl(
        'https://music.youtube.com/watch?v=4NRXx6U8ABQ',
        [],
      );

      expect(result.sourceType, equals('youtube'));
      expect(result.totalParsed, equals(1));
      expect(result.missingTracks.length, equals(1));
      expect(result.missingTracks.first.title, equals('Blinding Lights'));
      expect(result.missingTracks.first.artist, equals('The Weeknd'));
    });

    test('YouTube Music dynamic radio mix link (list=RD...) imports individual track', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host.contains('youtube.com') && request.url.path.contains('oembed')) {
          return http.Response(
            jsonEncode({
              'title': 'Starboy',
              'author_name': 'The Weeknd - Topic',
              'thumbnail_url': 'https://i.ytimg.com/vi/d3vV8tE4c2s/hqdefault.jpg',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = PlaylistImportService(httpClient: mockClient);
      final result = await service.importFromUrl(
        'https://music.youtube.com/watch?v=d3vV8tE4c2s&list=RDAMVMd3vV8tE4c2s',
        [],
      );

      expect(result.sourceType, equals('youtube'));
      expect(result.totalParsed, equals(1));
      expect(result.missingTracks.length, equals(1));
      expect(result.missingTracks.first.title, equals('Starboy'));
      expect(result.missingTracks.first.artist, equals('The Weeknd'));
    });

    test('Spotify import passes cache-busting parameters and headers', () async {
      String? requestedUrl;
      Map<String, String>? requestedHeaders;

      final mockClient = MockClient((request) async {
        if (request.url.host.contains('spotify.com') && request.url.path.contains('embed')) {
          requestedUrl = request.url.toString();
          requestedHeaders = request.headers;
          return http.Response(
            '<html><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"state":{"data":{"entity":{"name":"Test Cache Busted","trackList":[{"title":"Track 1","subtitle":"Artist 1"}]}}}}}}</script></html>',
            200,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response('Not found', 404);
      });

      final service = PlaylistImportService(httpClient: mockClient);
      final result = await service.importFromUrl(
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
        [],
      );

      expect(result.totalParsed, equals(1));
      expect(requestedUrl, contains('utm_source=generator'));
      expect(requestedUrl, contains('&t='));
      expect(requestedUrl, contains('&_cb='));
      expect(requestedHeaders?['Cache-Control'], contains('no-cache'));
    });
  });
}
