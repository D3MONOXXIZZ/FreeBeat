import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';
import 'package:freebeat/ui/screens/playlist_details_screen.dart';
import 'package:freebeat/ui/widgets/add_to_playlist_modal.dart';
import 'package:freebeat/ui/widgets/generative_playlist_cover.dart';
import 'package:freebeat/ui/widgets/playlist_import_modal.dart';
import 'package:freebeat/ui/widgets/playlist_qr_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Track makeTestTrack({
    required String id,
    required String title,
    required String artist,
    String album = 'Test Album',
    bool isHiRes = false,
    bool isPinnedOffline = false,
    bool isFavorite = false,
    int playCount = 0,
    int durationMs = 210000,
    int bitDepth = 16,
    int sampleRateHz = 44100,
  }) {
    return Track(
      id: id,
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/$id.flac',
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      streamUrl: 'https://cdn.freebeat.local/$id.flac',
      bitDepth: bitDepth,
      sampleRateHz: sampleRateHz,
      codec: 'FLAC',
      isPinnedOffline: isPinnedOffline,
      isFavorite: isFavorite,
      playCount: playCount,
    );
  }

  group('Phase 2: Playlist Model & Serialization Tests', () {
    test('Playlist toMap and fromMap serialization round-trip', () {
      final now = DateTime.now();
      final playlist = Playlist(
        id: 'test_p1',
        title: 'Late Night Synthwave',
        description: 'Atmospheric retro synths',
        trackIds: const ['t1', 't2', 't3'],
        createdAt: now,
        updatedAt: now,
        isSmart: false,
        colorSeedValue: 0xFF6750A4,
      );

      final map = playlist.toMap();
      expect(map['id'], 'test_p1');
      expect(map['title'], 'Late Night Synthwave');
      expect(map['isSmart'], 0);

      final restored = Playlist.fromMap(map);
      expect(restored.id, playlist.id);
      expect(restored.title, playlist.title);
      expect(restored.description, playlist.description);
      expect(restored.trackIds, ['t1', 't2', 't3']);
      expect(restored.isSmart, isFalse);
      expect(restored.colorSeedValue, 0xFF6750A4);
    });

    test('Playlist copyWith updates specified properties correctly', () {
      final playlist = Playlist(
        id: 'p1',
        title: 'Original Title',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final updated = playlist.copyWith(
        title: 'New Title',
        trackIds: ['track_99'],
        isSmart: true,
        smartType: 'hires',
      );

      expect(updated.title, 'New Title');
      expect(updated.trackIds, ['track_99']);
      expect(updated.isSmart, isTrue);
      expect(updated.smartType, 'hires');
      expect(updated.id, 'p1');
    });
  });

  group('Phase 2: PlaylistsNotifier State Management Tests', () {
    test('Create, rename, add track, reorder, remove track, and delete playlist',
        () async {
      final notifier = PlaylistsNotifier(null);

      // 1. Create playlist
      final p1 = await notifier.createPlaylist(
        'Study Focus',
        description: 'Lo-Fi and Ambient',
      );
      expect(notifier.state.length, 1);
      expect(notifier.state.first.title, 'Study Focus');
      expect(notifier.state.first.trackIds, isEmpty);

      // 2. Add tracks
      await notifier.addTrackToPlaylist(p1.id, 'track_1');
      await notifier.addTrackToPlaylist(p1.id, 'track_2');
      await notifier.addTrackToPlaylist(p1.id, 'track_3');
      expect(notifier.state.first.trackIds, ['track_1', 'track_2', 'track_3']);

      // 3. Reorder tracks
      await notifier.reorderTracks(p1.id, 0, 3); // move track_1 to end
      expect(notifier.state.first.trackIds, ['track_2', 'track_3', 'track_1']);

      // 4. Remove a track
      await notifier.removeTrackFromPlaylist(p1.id, 'track_3');
      expect(notifier.state.first.trackIds, ['track_2', 'track_1']);

      // 5. Rename playlist
      await notifier.renamePlaylist(
        p1.id,
        'Deep Work',
        description: 'High concentration audio',
      );
      expect(notifier.state.first.title, 'Deep Work');
      expect(notifier.state.first.description, 'High concentration audio');

      // 6. Delete playlist
      await notifier.deletePlaylist(p1.id);
      expect(notifier.state, isEmpty);
    });

    test('Export playlist to valid .m3u8 format with EXTM3U and EXTINF', () {
      final notifier = PlaylistsNotifier(null);
      final tracks = [
        makeTestTrack(
          id: 't1',
          title: 'Midnight City',
          artist: 'M83',
          durationMs: 244000,
        ),
        makeTestTrack(
          id: 't2',
          title: 'Resonance',
          artist: 'HOME',
          durationMs: 212000,
        ),
      ];

      final playlist = Playlist(
        id: 'synth_pl',
        title: 'Synth Classics',
        trackIds: ['t1', 't2'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final m3u8 = notifier.exportPlaylistM3u8(playlist, tracks);
      expect(m3u8, contains('#EXTM3U'));
      expect(m3u8, contains('#PLAYLIST:Synth Classics'));
      expect(m3u8, contains('#EXTINF:244,M83 - Midnight City'));
      expect(m3u8, contains('https://cdn.freebeat.local/t1.flac'));
      expect(m3u8, contains('#EXTINF:212,HOME - Resonance'));
    });
  });

  group('Phase 2: Smart Playlists & Deduplication Engine Tests', () {
    test('Smart playlists derive from catalog dynamically', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith((ref) {
            final notifier = TracksCatalogNotifier(null, null);
            notifier.state = [
              makeTestTrack(
                id: 'hires_1',
                title: 'HiRes Song 1',
                artist: 'Audiophile Master',
                bitDepth: 24,
                sampleRateHz: 96000,
              ),
              makeTestTrack(
                id: 'offline_1',
                title: 'Offline Cached Track',
                artist: 'Local Hero',
                isPinnedOffline: true,
              ),
              makeTestTrack(
                id: 'fav_1',
                title: 'Heart Track',
                artist: 'Favorite Band',
                isFavorite: true,
              ),
              makeTestTrack(
                id: 'heavy_1',
                title: 'Top Played Song',
                artist: 'Rotation King',
                playCount: 120,
              ),
            ];
            return notifier;
          }),
        ],
      );

      final smartPlaylists = container.read(smartPlaylistsProvider);
      expect(smartPlaylists.length, greaterThanOrEqualTo(5));

      final hires = smartPlaylists.firstWhere((p) => p.smartType == 'hires');
      expect(hires.trackIds, contains('hires_1'));

      final offline =
          smartPlaylists.firstWhere((p) => p.smartType == 'offline');
      expect(offline.trackIds, contains('offline_1'));

      final favs =
          smartPlaylists.firstWhere((p) => p.smartType == 'favorites');
      expect(favs.trackIds, contains('fav_1'));

      final rotation =
          smartPlaylists.firstWhere((p) => p.smartType == 'heavy_rotation');
      expect(rotation.trackIds, contains('heavy_1'));
    });

    test('Duplicate tracks detection and removal', () async {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith((ref) {
            final notifier = TracksCatalogNotifier(null, null);
            notifier.state = [
              makeTestTrack(
                id: 'dup_lossy',
                title: 'Starlight',
                artist: 'Muse',
                bitDepth: 16,
                sampleRateHz: 44100,
              ),
              makeTestTrack(
                id: 'dup_hires',
                title: 'Starlight',
                artist: 'Muse',
                bitDepth: 24,
                sampleRateHz: 96000,
              ),
              makeTestTrack(
                id: 'unique_track',
                title: 'Knights of Cydonia',
                artist: 'Muse',
              ),
            ];
            return notifier;
          }),
        ],
      );

      final duplicates = container.read(duplicateTracksProvider);
      expect(duplicates.length, 1);
      final key = 'starlight__muse';
      expect(duplicates.containsKey(key), isTrue);
      expect(duplicates[key]?.length, 2);

      // Deduplicate by removing the lower quality duplicate
      await container
          .read(tracksCatalogProvider.notifier)
          .removeTracks(['dup_lossy']);

      final afterDeduplication = container.read(duplicateTracksProvider);
      expect(afterDeduplication.isEmpty, isTrue);

      final remaining = container.read(tracksCatalogProvider);
      expect(remaining.map((t) => t.id).toList(), ['dup_hires', 'unique_track']);
    });
  });

  group('Phase 2: Widgets & UI Rendering Tests', () {
    testWidgets('GenerativePlaylistCover renders without errors',
        (tester) async {
      final playlist = Playlist(
        id: 'p_gen',
        title: 'Ocean Waves & Ambient Lofi',
        trackIds: const ['t1'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        colorSeedValue: 0xFF006782,
        isSmart: true,
        smartType: 'hires',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: GenerativePlaylistCover(
                playlist: playlist,
                size: 160,
                borderRadius: 24,
                showBadge: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(GenerativePlaylistCover), findsOneWidget);
      expect(find.text('SMART'), findsOneWidget);
    });

    testWidgets('PlaylistDetailsScreen renders metadata, actions, and tracks',
        (tester) async {
      final testTrack = makeTestTrack(
        id: 't_details_1',
        title: 'Veridis Quo',
        artist: 'Daft Punk',
        durationMs: 345000,
        bitDepth: 24,
        sampleRateHz: 96000,
      );

      final playlist = Playlist(
        id: 'p_details',
        title: 'French Touch Vault',
        description: 'Electronic masters',
        trackIds: [testTrack.id],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(null, null);
              notifier.state = [testTrack];
              return notifier;
            }),
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = [playlist];
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: PlaylistDetailsScreen(playlist: playlist),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('French Touch Vault'), findsWidgets);
      expect(find.text('Play All'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Veridis Quo'), findsOneWidget);
      expect(find.textContaining('Daft Punk'), findsOneWidget);
    });

    testWidgets('showAddToPlaylistModal displays bottom sheet with track details',
        (tester) async {
      final track = makeTestTrack(
        id: 'modal_t1',
        title: 'Solaris',
        artist: 'Cliff Martinez',
      );

      final playlist = Playlist(
        id: 'modal_p1',
        title: 'Soundtracks',
        trackIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistsProvider.overrideWith((ref) {
              final notifier = PlaylistsNotifier(null);
              notifier.state = [playlist];
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showAddToPlaylistModal(context, track),
                    child: const Text('Open Modal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.text('Soundtracks'), findsOneWidget);
      expect(find.textContaining('Solaris'), findsOneWidget);
    });

    testWidgets('showPlaylistQrModal displays QR code and action buttons',
        (tester) async {
      final track = makeTestTrack(
        id: 'qr_t1',
        title: 'Instant Crush',
        artist: 'Daft Punk',
      );

      final playlist = Playlist(
        id: 'qr_p1',
        title: 'Daft Punk Favorites',
        trackIds: [track.id],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showPlaylistQrModal(context, playlist, [track]),
                  child: const Text('Share QR'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Share QR'));
      await tester.pumpAndSettle();

      expect(find.text('QR SHARE'), findsOneWidget);
      expect(find.text('Daft Punk Favorites'), findsOneWidget);
      expect(find.text('Copy .M3U8'), findsOneWidget);
      expect(find.text('Copy Code'), findsOneWidget);
    });

    testWidgets('showPlaylistImportModal displays input and buttons',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showPlaylistImportModal(context),
                    child: const Text('Open Importer'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Importer'));
      await tester.pumpAndSettle();

      expect(find.text('Import Playlist'), findsOneWidget);
      expect(find.text('Pick .M3U File'), findsOneWidget);
      expect(find.text('Match Tracks'), findsOneWidget);
    });
  });

  group('Phase 2: PlaylistImportService Matching & Parsing Tests', () {
    const service = PlaylistImportService();

    final libraryTracks = [
      makeTestTrack(
        id: 'lib_1',
        title: 'Veridis Quo',
        artist: 'Daft Punk',
      ),
      makeTestTrack(
        id: 'lib_2',
        title: 'Resonance',
        artist: 'HOME',
      ),
      makeTestTrack(
        id: 'lib_3',
        title: 'Midnight City (Remastered 2011)',
        artist: 'M83',
      ),
    ];

    test('parseTextOrCsv matches tracks and records missing entries', () {
      const text = '''
Daft Punk - Veridis Quo
HOME - Resonance
NonExistent Artist - Ghost Track
M83 - Midnight City
''';

      final result = service.parseTextOrCsv(text, libraryTracks);
      expect(result.totalParsed, 4);
      expect(result.matchedCount, 3);
      expect(result.unmatchedCount, 1);
      expect(result.matchedTracks.map((t) => t.id).toList(),
          containsAll(['lib_1', 'lib_2', 'lib_3']));
      expect(result.unmatchedTrackNames.first,
          contains('NonExistent Artist - Ghost Track'));
    });

    test('parseM3u parses EXTM3U and matches by streamUrl and title', () {
      const m3u = '''
#EXTM3U
#PLAYLIST:Synthwave Classics
#EXTINF:240,Daft Punk - Veridis Quo
https://cdn.freebeat.local/lib_1.flac
#EXTINF:210,HOME - Resonance
https://cdn.freebeat.local/lib_2.flac
''';

      final result = service.parseM3u(m3u, libraryTracks);
      expect(result.title, 'Synthwave Classics');
      expect(result.matchedCount, 2);
      expect(result.matchedTracks.map((t) => t.id),
          containsAll(['lib_1', 'lib_2']));
    });

    test('findBestMatch normalizes punctuation and fuzzy tags', () {
      final match = PlaylistImportService.findBestMatch(
        'Midnight City',
        'M83',
        libraryTracks,
      );
      expect(match, isNotNull);
      expect(match!.id, 'lib_3');
    });
  });

  group('Phase 2: Mood & Energy Auto-Clustering Tests', () {
    test('smartPlaylistsProvider derives energy, chill, and focus playlists', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith((ref) {
            final notifier = TracksCatalogNotifier(null, null);
            notifier.state = [
              makeTestTrack(
                id: 't_energy',
                title: 'High Energy Beat (Club Remix)',
                artist: 'Electro Power',
              ),
              makeTestTrack(
                id: 't_chill',
                title: 'Ocean Chill Ambient Piano',
                artist: 'Relaxing Vibes',
                durationMs: 320000,
              ),
              makeTestTrack(
                id: 't_focus',
                title: 'Deep Synthwave Study Session',
                artist: 'Focus Maestro',
              ),
            ];
            return notifier;
          }),
        ],
      );

      final smartPlaylists = container.read(smartPlaylistsProvider);

      final energy =
          smartPlaylists.firstWhere((p) => p.smartType == 'energy');
      expect(energy.title, 'High Energy & Workout');
      expect(energy.trackIds, contains('t_energy'));

      final chill =
          smartPlaylists.firstWhere((p) => p.smartType == 'chill');
      expect(chill.title, 'Chill & Ambient Vibe');
      expect(chill.trackIds, contains('t_chill'));

      final focus =
          smartPlaylists.firstWhere((p) => p.smartType == 'focus');
      expect(focus.title, 'Late Night & Focus');
      expect(focus.trackIds, contains('t_focus'));
    });
  });
}

