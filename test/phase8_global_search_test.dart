import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/search/audiophile_search_engine.dart';
import 'package:freebeat/services/search/search_history_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/search_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<Track> dummyTracks = [
    const Track(
      id: 't1',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/eagles_hotel_california.flac',
      title: 'Hotel California',
      artist: 'Eagles',
      album: 'Hotel California (Remastered)',
      durationMs: 391000,
      streamUrl: 'file:///music/eagles_hotel_california.flac',
      bitrateKbps: 9216,
      bitDepth: 24,
      sampleRateHz: 192000,
      codec: 'FLAC',
      isPinnedOffline: true,
    ),
    const Track(
      id: 't2',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/pink_floyd_time.wma',
      title: 'Time',
      artist: 'Pink Floyd',
      album: 'The Dark Side of the Moon',
      durationMs: 413000,
      streamUrl: 'file:///music/pink_floyd_time.wma',
      bitrateKbps: 320,
      bitDepth: 16,
      sampleRateHz: 44100,
      codec: 'WMA',
      isPinnedOffline: false,
    ),
    const Track(
      id: 't3',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/daft_punk_get_lucky.m4a',
      title: 'Get Lucky',
      artist: 'Daft Punk',
      album: 'Random Access Memories',
      durationMs: 369000,
      streamUrl: 'file:///music/daft_punk_get_lucky.m4a',
      bitrateKbps: 256,
      bitDepth: 16,
      sampleRateHz: 44100,
      codec: 'M4A',
      isPinnedOffline: true,
    ),
    const Track(
      id: 't4',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/miles_davis_so_what.wav',
      title: 'So What',
      artist: 'Miles Davis',
      album: 'Kind of Blue',
      durationMs: 562000,
      streamUrl: 'file:///music/miles_davis_so_what.wav',
      bitrateKbps: 4608,
      bitDepth: 24,
      sampleRateHz: 96000,
      codec: 'WAV',
      isPinnedOffline: false,
    ),
    const Track(
      id: 't5',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/queen_bohemian_rhapsody.mp3',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      durationMs: 354000,
      streamUrl: 'file:///music/queen_bohemian_rhapsody.mp3',
      bitrateKbps: 320,
      bitDepth: 16,
      sampleRateHz: 44100,
      codec: 'MP3',
      isPinnedOffline: false,
    ),
  ];

  final List<Playlist> dummyPlaylists = [
    Playlist(
      id: 'pl1',
      title: 'Audiophile Master Classics',
      trackIds: const ['t1', 't4'],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
    Playlist(
      id: 'pl2',
      title: 'Rock Legends',
      trackIds: const ['t1', 't2', 't5'],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];


  group('Phase 8: SearchHistoryService Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('addQuery adds items, trims whitespace, and maintains LRU order',
        () async {
      final service = SearchHistoryService(maxHistoryItems: 5);
      await service.addQuery('Pink Floyd');
      await service.addQuery('  Hotel California  ');
      await service.addQuery('FLAC');

      expect(service.history, equals(['FLAC', 'Hotel California', 'Pink Floyd']));

      // Adding existing query moves it to top
      await service.addQuery('pink floyd');
      expect(service.history, equals(['pink floyd', 'FLAC', 'Hotel California']));
    });

    test('enforces maxHistoryItems cap', () async {
      final service = SearchHistoryService(maxHistoryItems: 3);
      await service.addQuery('Q1');
      await service.addQuery('Q2');
      await service.addQuery('Q3');
      await service.addQuery('Q4');

      expect(service.history.length, equals(3));
      expect(service.history, equals(['Q4', 'Q3', 'Q2']));
    });

    test('removeQuery and clearHistory operate cleanly', () async {
      final service = SearchHistoryService();
      await service.addQuery('Item 1');
      await service.addQuery('Item 2');
      await service.removeQuery('Item 1');

      expect(service.history, equals(['Item 2']));

      await service.clearHistory();
      expect(service.history.isEmpty, isTrue);
    });
  });

  group('Phase 8: AudiophileSearchEngine Unit Tests', () {
    test('Empty query with filter "all" returns empty SearchResultGroup', () {
      final res = AudiophileSearchEngine.search(
        query: '',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.all,
      );

      expect(res.isEmpty, isTrue);
      expect(res.totalCount, equals(0));
    });

    test('Fuzzy matches track title, artist, and album', () {
      // Match by title
      final titleRes = AudiophileSearchEngine.search(
        query: 'hotel',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
      );
      expect(titleRes.tracks.length, equals(1));
      expect(titleRes.tracks.first.title, equals('Hotel California'));
      expect(titleRes.topMatch?.title, equals('Hotel California'));

      // Match by artist
      final artistRes = AudiophileSearchEngine.search(
        query: 'pink floyd',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
      );
      expect(artistRes.tracks.first.artist, equals('Pink Floyd'));
      expect(artistRes.artists, contains('Pink Floyd'));

      // Match by album
      final albumRes = AudiophileSearchEngine.search(
        query: 'random access',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
      );
      expect(albumRes.tracks.first.album, equals('Random Access Memories'));
      expect(albumRes.albums.containsKey('Random Access Memories'), isTrue);
    });

    test('Matches codec queries (FLAC, WMA, M4A, WAV, MP3)', () {
      final flacRes = AudiophileSearchEngine.search(
        query: 'flac',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
      );
      expect(flacRes.tracks.any((t) => t.codec == 'FLAC'), isTrue);

      final wmaRes = AudiophileSearchEngine.search(
        query: 'wma',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
      );
      expect(wmaRes.tracks.any((t) => t.codec == 'WMA'), isTrue);
      expect(wmaRes.tracks.first.title, equals('Time'));
    });

    test('Hi-Res 24-bit search matching', () {
      final hiResRes = AudiophileSearchEngine.search(
        query: 'hi-res',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
      );
      expect(hiResRes.tracks.every((t) => t.isHiRes), isTrue);
      expect(hiResRes.tracks.length, equals(2)); // Eagles (24/192) & Miles Davis (24/96)
    });

    test('FilterType hiRes only includes 24-bit or >48kHz tracks', () {
      final res = AudiophileSearchEngine.search(
        query: '',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.hiRes,
      );
      expect(res.tracks.length, equals(2));
      expect(res.tracks.every((t) => t.isHiRes), isTrue);
    });

    test('FilterType offline only includes pinned offline tracks', () {
      final res = AudiophileSearchEngine.search(
        query: '',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.offline,
      );
      expect(res.tracks.length, equals(2)); // t1 and t3
      expect(res.tracks.every((t) => t.isPinnedOffline), isTrue);
    });

    test('FilterType codec isolates specific formats (WMA, M4A, FLAC)', () {
      final wmaRes = AudiophileSearchEngine.search(
        query: '',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.wma,
      );
      expect(wmaRes.tracks.length, equals(1));
      expect(wmaRes.tracks.first.codec, equals('WMA'));

      final m4aRes = AudiophileSearchEngine.search(
        query: '',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.m4a,
      );
      expect(m4aRes.tracks.length, equals(1));
      expect(m4aRes.tracks.first.codec, equals('M4A'));
    });

    test('FilterType artists/albums/playlists scopes results accurately', () {
      final artistsRes = AudiophileSearchEngine.search(
        query: '',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.artists,
      );
      expect(artistsRes.tracks.isEmpty, isTrue);
      expect(artistsRes.albums.isEmpty, isTrue);
      expect(artistsRes.playlists.isEmpty, isTrue);
      expect(artistsRes.artists.length, equals(5));

      final playlistsRes = AudiophileSearchEngine.search(
        query: 'rock',
        allTracks: dummyTracks,
        allPlaylists: dummyPlaylists,
        filter: SearchFilterType.playlists,
      );
      expect(playlistsRes.playlists.length, equals(1));
      expect(playlistsRes.playlists.first.title, equals('Rock Legends'));
    });
  });

  group('Phase 8: SearchScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'freebeat_search_history': ['Pink Floyd', 'Hi-Res Lossless'],
      });
    });

    testWidgets('SearchScreen renders search bar, filter chips, and explore shortcuts',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(null, null);
              notifier.state = dummyTracks;
              return notifier;
            }),
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = dummyPlaylists;
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search input field exists
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search songs, artists, FLAC, WMA...'), findsOneWidget);

      // Verify filter chips
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Hi-Res 24-Bit'), findsOneWidget);
      expect(find.text('FLAC'), findsOneWidget);
      expect(find.text('WMA'), findsOneWidget);
      expect(find.text('M4A / AAC'), findsOneWidget);

      // Verify Recent Searches from mock prefs
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('Pink Floyd'), findsOneWidget);
      expect(find.text('Hi-Res Lossless'), findsWidgets);

      // Verify Explore Audiophile Audio cards
      expect(find.text('Explore Audiophile Audio'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('FLAC Master'), findsOneWidget);
      expect(find.text('WMA & M4A'), findsOneWidget);
    });

    testWidgets('Entering query live updates results with Top Result and song list',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(null, null);
              notifier.state = dummyTracks;
              return notifier;
            }),
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = dummyPlaylists;
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter query
      await tester.enterText(find.byType(TextField), 'Hotel');
      await tester.pumpAndSettle();

      // Top Result section
      expect(find.text('Top Result'), findsOneWidget);
      expect(find.text('Hotel California'), findsWidgets);
      expect(find.text('Eagles'), findsWidgets);

      // Songs section
      expect(find.text('Songs (1)'), findsOneWidget);
    });

    testWidgets('Tapping Explore card switches filter chip and displays matched tracks',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(null, null);
              notifier.state = dummyTracks;
              return notifier;
            }),
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = dummyPlaylists;
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "WMA & M4A" explore card
      await tester.tap(find.text('WMA & M4A'));
      await tester.pumpAndSettle();

      // Songs (1) for WMA
      expect(find.text('Songs (1)'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Pink Floyd'), findsOneWidget);
    });

    testWidgets('Zero match query displays empty state and "Show All Formats" button',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(null, null);
              notifier.state = dummyTracks;
              return notifier;
            }),
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = dummyPlaylists;
              return notifier;
            }),
          ],
          child: const MaterialApp(
            home: SearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter non-matching query
      await tester.enterText(find.byType(TextField), 'NonexistentTrack12345');
      await tester.pumpAndSettle();

      expect(find.text('No matches for "NonexistentTrack12345"'), findsOneWidget);
      expect(find.text('Try checking for spelling or switching your filter chips.'),
          findsOneWidget);
    });
  });
}
