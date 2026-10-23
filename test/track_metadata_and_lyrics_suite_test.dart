import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/services/metadata/artwork_and_lyrics_service.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/fullscreen_lyrics_screen.dart';
import 'package:freebeat/ui/widgets/track_metadata_editor_modal.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track Model Metadata & Synced Lyrics Serialization', () {
    test('Track correctly serializes and deserializes genre, year, and lyricsOffsetMs', () {
      const sampleLyrics = [
        LyricLine(timestampMs: 12000, text: 'First verse singing'),
        LyricLine(timestampMs: 25500, text: 'Second chorus singing'),
      ];

      final track = Track(
        id: 'test_meta_1',
        accountId: 'acc_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'cloud_path/song.flac',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        durationMs: 240000,
        streamUrl: 'https://cloud.example.com/stream/song.flac',
        genre: 'Progressive Melodic Bass',
        year: 2024,
        lyricsOffsetMs: 350,
        syncedLyrics: sampleLyrics,
      );

      final map = track.toMap();
      expect(map['genre'], 'Progressive Melodic Bass');
      expect(map['year'], 2024);
      expect(map['lyricsOffsetMs'], 350);
      expect(map['syncedLyricsJson'], isNotNull);

      final restored = Track.fromMap(map);
      expect(restored.id, track.id);
      expect(restored.genre, 'Progressive Melodic Bass');
      expect(restored.year, 2024);
      expect(restored.lyricsOffsetMs, 350);
      expect(restored.syncedLyrics.length, 2);
      expect(restored.syncedLyrics[0].timestampMs, 12000);
      expect(restored.syncedLyrics[0].text, 'First verse singing');
      expect(restored.syncedLyrics[1].timestampMs, 25500);
      expect(restored.syncedLyrics[1].text, 'Second chorus singing');
    });

    test('Track.copyWith preserves and updates metadata and lyrics offset', () {
      final track = Track(
        id: 'test_meta_2',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/storage/emulated/0/Music/song.mp3',
        title: 'Song A',
        artist: 'Artist A',
        album: 'Album A',
        durationMs: 180000,
        streamUrl: '/storage/emulated/0/Music/song.mp3',
        genre: 'Rock',
        year: 2020,
        lyricsOffsetMs: 0,
      );

      final updated = track.copyWith(
        title: 'Song B',
        artist: 'Artist B',
        genre: 'Alternative Rock',
        year: 2023,
        lyricsOffsetMs: -250,
      );

      expect(updated.title, 'Song B');
      expect(updated.artist, 'Artist B');
      expect(updated.album, 'Album A');
      expect(updated.genre, 'Alternative Rock');
      expect(updated.year, 2023);
      expect(updated.lyricsOffsetMs, -250);
    });
  });

  group('LibraryDatabase In-Memory Persistence', () {
    test('LibraryDatabase stores and retrieves metadata and lyrics', () async {
      final db = LibraryDatabase();
      await db.init();

      const lyrics = [
        LyricLine(timestampMs: 5000, text: 'Hello world'),
      ];

      final track = Track(
        id: 'db_track_1',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/music/test.flac',
        title: 'DB Song',
        artist: 'DB Artist',
        album: 'DB Album',
        durationMs: 120000,
        streamUrl: '/music/test.flac',
        genre: 'Ambient',
        year: 2025,
        lyricsOffsetMs: 500,
        syncedLyrics: lyrics,
      );

      await db.upsertTracks([track]);
      final loaded = await db.loadTracks();
      expect(loaded.any((t) => t.id == 'db_track_1'), isTrue);

      final fetched = loaded.firstWhere((t) => t.id == 'db_track_1');
      expect(fetched.genre, 'Ambient');
      expect(fetched.year, 2025);
      expect(fetched.lyricsOffsetMs, 500);
      expect(fetched.syncedLyrics.length, 1);
      expect(fetched.syncedLyrics.first.text, 'Hello world');
    });
  });

  group('ArtworkAndLyricsService Online Search & Parsing', () {
    test('parseLrcContent parses timestamps, sorting, and fractionals', () {
      const rawLrc = '''
[ti:Test Title]
[ar:Test Artist]
[01:05.50]Chorus line here
[00:15.200]First verse line here
[00:02.05]Intro melody
''';
      final parsed = ArtworkAndLyricsService.parseLrcContent(rawLrc);
      expect(parsed.length, 3);
      // Sorted in ascending order:
      expect(parsed[0].text, 'Intro melody');
      expect(parsed[0].timestampMs, 2050);

      expect(parsed[1].text, 'First verse line here');
      expect(parsed[1].timestampMs, 15200);

      expect(parsed[2].text, 'Chorus line here');
      expect(parsed[2].timestampMs, 65500);
    });

    test('searchOnlineLyrics queries LRCLIB and maps candidates correctly', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'lrclib.net' && request.url.path == '/api/search') {
          final query = request.url.queryParameters['q'];
          expect(query, contains('Illenium'));
          final responseJson = jsonEncode([
            {
              'id': 12345,
              'trackName': 'Needed You',
              'artistName': 'ILLENIUM',
              'albumName': 'Awake',
              'duration': 245,
              'syncedLyrics': '[00:10.00] First line\n[00:20.00] Second line',
              'plainLyrics': 'First line\nSecond line',
            }
          ]);
          return http.Response(responseJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final service = ArtworkAndLyricsService(client: mockClient);
      final results = await service.searchOnlineLyrics(query: 'Illenium Needed You');

      expect(results.length, 1);
      expect(results.first.trackName, 'Needed You');
      expect(results.first.artistName, 'ILLENIUM');
      expect(results.first.hasSyncedLyrics, isTrue);
      expect(results.first.parsedSyncedLyrics.length, 2);
      expect(results.first.parsedSyncedLyrics[0].timestampMs, 10000);
      expect(results.first.parsedSyncedLyrics[0].text, 'First line');
    });

    test('searchOnlineArtwork queries iTunes and returns high-res artwork', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'itunes.apple.com' && request.url.path == '/search') {
          final responseJson = jsonEncode({
            'resultCount': 1,
            'results': [
              {
                'trackName': 'Needed You',
                'artistName': 'ILLENIUM',
                'collectionName': 'Awake',
                'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/Music/100x100bb.jpg',
              }
            ]
          });
          return http.Response(responseJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final service = ArtworkAndLyricsService(client: mockClient);
      final results = await service.searchOnlineArtwork(query: 'Awake Illenium', limit: 5);

      expect(results.length, 1);
      expect(results.first.artworkUrl, contains('1400x1400bb.jpg'));
      expect(results.first.album, 'Awake');
    });
  });

  group('Playback Timing Offset Calibration', () {
    test('PlaybackState.activeLyricIndex reacts to lyricsOffsetMs', () {
      const lyrics = [
        LyricLine(timestampMs: 10000, text: 'Line 1'),
        LyricLine(timestampMs: 20000, text: 'Line 2'),
        LyricLine(timestampMs: 30000, text: 'Line 3'),
      ];

      final trackZeroOffset = Track(
        id: 't1',
        accountId: 'acc1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: 'path',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 60000,
        streamUrl: 'url',
        lyricsOffsetMs: 0,
        syncedLyrics: lyrics,
      );

      // At position 19500ms with offset 0ms: Line 1 (10000ms <= 19500 < 20000ms)
      final state1 = PlaybackViewState(
        currentTrack: trackZeroOffset,
        queue: [trackZeroOffset],
        isPlaying: true,
        positionMs: 19500,
      );
      expect(state1.activeLyricIndex, 0);

      // Nudge offset forward by +1000ms: effective position is 19500 + 1000 = 20500ms
      // Now Line 2 is active!
      final trackOffsetAhead = trackZeroOffset.copyWith(lyricsOffsetMs: 1000);
      final state2 = PlaybackViewState(
        currentTrack: trackOffsetAhead,
        queue: [trackOffsetAhead],
        isPlaying: true,
        positionMs: 19500,
      );
      expect(state2.activeLyricIndex, 1);

      // Nudge offset backward by -10000ms: effective position is 19500 - 10000 = 9500ms (< 10000ms)
      // Result is index 0 (initial before any line)
      final trackOffsetBehind = trackZeroOffset.copyWith(lyricsOffsetMs: -10000);
      final state3 = PlaybackViewState(
        currentTrack: trackOffsetBehind,
        queue: [trackOffsetBehind],
        isPlaying: true,
        positionMs: 19500,
      );
      expect(state3.activeLyricIndex, 0);
    });

    testWidgets('FullscreenLyricsScreen renders lyrics and opens timing calibration', (tester) async {
      const lyrics = [
        LyricLine(timestampMs: 2000, text: 'First line singing'),
        LyricLine(timestampMs: 6000, text: 'Second line singing'),
      ];

      final track = Track(
        id: 'test_track_live',
        accountId: 'acc1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: 'path',
        title: 'Calibration Song',
        artist: 'Calibration Artist',
        album: 'Calibration Album',
        durationMs: 60000,
        streamUrl: 'url',
        syncedLyrics: lyrics,
        lyricsOffsetMs: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackProvider.overrideWith((ref) => _MockPlaybackNotifier(ref, track)),
          ],
          child: const MaterialApp(
            home: FullscreenLyricsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Calibration Song'), findsNWidgets(2));
      expect(find.text('First line singing'), findsOneWidget);
      expect(find.text('Second line singing'), findsOneWidget);
      expect(find.text('SYNCED'), findsOneWidget);

      // Tap the calibration pill in the header
      await tester.tap(find.text('SYNCED'));
      await tester.pumpAndSettle();

      // Modal sheet should now be open
      expect(find.text('Lyrics Timing Calibration'), findsOneWidget);
      expect(find.text('0.0s (In-Sync)'), findsOneWidget);
      expect(find.text('+0.5s'), findsOneWidget);
      expect(find.text('-0.5s'), findsOneWidget);

      // Tap +0.5s chip
      await tester.tap(find.text('+0.5s'));
      await tester.pumpAndSettle();

      // Tap Done
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });
  });

  group('TrackMetadataEditorSheet Widget Test', () {
    testWidgets('Populates fields from track and triggers updateTrack', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialTrack = Track(
        id: 'edit_track_1',
        accountId: 'acc1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: 'path.mp3',
        title: 'Original Title',
        artist: 'Original Artist',
        album: 'Original Album',
        genre: 'Electronic',
        year: 2021,
        durationMs: 180000,
        streamUrl: 'path.mp3',
      );

      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      container.read(tracksCatalogProvider.notifier).loadSampleDemoTracks();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showTrackMetadataEditorModal(context, initialTrack),
                    child: const Text('Open Editor'),
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Tap to open modal
      await tester.tap(find.text('Open Editor'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Metadata & Artwork'), findsOneWidget);
      expect(find.text('Original Title'), findsOneWidget);
      expect(find.text('Original Artist'), findsOneWidget);
      expect(find.text('Original Album'), findsOneWidget);
      expect(find.text('Electronic'), findsOneWidget);
      expect(find.text('2021'), findsOneWidget);
      expect(find.text('Pick Gallery'), findsOneWidget);
      expect(find.text('Search Online'), findsOneWidget);

      // Edit title
      await tester.enterText(find.widgetWithText(TextFormField, 'Original Title'), 'Updated Epic Song');
      await tester.pumpAndSettle();

      // Scroll to Save Changes and tap
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Modal closed
      expect(find.text('Edit Metadata & Artwork'), findsNothing);
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
}

class _MockPlaybackNotifier extends PlaybackNotifier {
  _MockPlaybackNotifier(Ref ref, Track initialTrack) : super(ref, [initialTrack]) {
    state = PlaybackViewState(
      currentTrack: initialTrack,
      isPlaying: true,
      positionMs: 3000,
      queue: [initialTrack],
    );
  }

  @override
  void setLyricsOffsetMs(int offsetMs) {
    state = state.copyWith(
      currentTrack: state.currentTrack.copyWith(lyricsOffsetMs: offsetMs),
    );
  }

  @override
  void updateCurrentTrackLyrics(List<LyricLine> lyrics) {
    state = state.copyWith(
      currentTrack: state.currentTrack.copyWith(syncedLyrics: lyrics),
    );
  }
}
