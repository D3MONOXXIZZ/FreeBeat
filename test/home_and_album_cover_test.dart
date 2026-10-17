import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/home_screen.dart';
import 'package:freebeat/ui/widgets/material_you_album_cover.dart';

void main() {
  group('Artist & Album Filters and Top Picks Providers', () {
    const track1 = Track(
      id: 'track_1',
      accountId: 'acc_1',
      providerType: CloudProviderType.googleDrive,
      remotePathOrId: 'path_1',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      durationMs: 354000,
      streamUrl: 'https://example.com/song1.flac',
      codec: 'FLAC',
      bitDepth: 24,
      sampleRateHz: 96000,
    );

    const track2 = Track(
      id: 'track_2',
      accountId: 'acc_1',
      providerType: CloudProviderType.googleDrive,
      remotePathOrId: 'path_2',
      title: 'Love of My Life',
      artist: 'Queen',
      album: 'A Night at the Opera',
      durationMs: 219000,
      streamUrl: 'https://example.com/song2.flac',
      codec: 'FLAC',
      bitDepth: 24,
      sampleRateHz: 96000,
    );

    const track3 = Track(
      id: 'track_3',
      accountId: 'acc_2',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: 'path_3',
      title: 'Hotel California',
      artist: 'Eagles',
      album: 'Hotel California',
      durationMs: 391000,
      streamUrl: 'https://example.com/song3.flac',
      codec: 'FLAC',
    );

    test('availableArtistsProvider groups and counts artists accurately', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith(
            (ref) => _StaticCatalogNotifier([track1, track2, track3]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final artists = container.read(availableArtistsProvider);
      expect(artists.length, 2);
      expect(artists.first.name, 'Queen');
      expect(artists.first.trackCount, 2);
      expect(artists[1].name, 'Eagles');
      expect(artists[1].trackCount, 1);
    });

    test('availableAlbumsProvider groups and counts albums accurately', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith(
            (ref) => _StaticCatalogNotifier([track1, track2, track3]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final albums = container.read(availableAlbumsProvider);
      expect(albums.length, 2);
      expect(albums.first.title, 'A Night at the Opera');
      expect(albums.first.trackCount, 2);
      expect(albums[1].title, 'Hotel California');
    });

    test('filteredTracksProvider filters by selected artist and album', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith(
            (ref) => _StaticCatalogNotifier([track1, track2, track3]),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Initially all 3
      expect(container.read(filteredTracksProvider).length, 3);

      // Filter by Queen
      container.read(selectedArtistFilterProvider.notifier).state = 'Queen';
      expect(container.read(filteredTracksProvider).length, 2);
      expect(container.read(filteredTracksProvider).every((t) => t.artist == 'Queen'), isTrue);

      // Filter by Eagles
      container.read(selectedArtistFilterProvider.notifier).state = 'Eagles';
      expect(container.read(filteredTracksProvider).length, 1);
      expect(container.read(filteredTracksProvider).first.title, 'Hotel California');

      // Clear artist filter
      container.read(selectedArtistFilterProvider.notifier).state = null;
      expect(container.read(filteredTracksProvider).length, 3);

      // Filter by Album
      container.read(selectedAlbumFilterProvider.notifier).state = 'A Night at the Opera';
      expect(container.read(filteredTracksProvider).length, 2);
    });

    test('topPicksProvider generates daily randomized picks with shuffle support', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith(
            (ref) => _StaticCatalogNotifier([track1, track2, track3]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final picks = container.read(topPicksProvider);
      expect(picks, isNotEmpty);
      expect(picks.length, 3);

      // Change seed
      container.read(topPicksSeedProvider.notifier).state = 42;
      final reRolled = container.read(topPicksProvider);
      expect(reRolled, isNotEmpty);
    });
  });

  group('MaterialYouAlbumCover Widget Tests', () {
    const hiResTrack = Track(
      id: 'test_track',
      accountId: 'acc_1',
      providerType: CloudProviderType.googleDrive,
      remotePathOrId: 'path',
      title: 'Midnight Sun',
      artist: 'Aura',
      album: 'Solaris',
      durationMs: 240000,
      streamUrl: 'https://example.com/audio.flac',
      codec: 'FLAC',
      bitDepth: 24,
      sampleRateHz: 96000,
      dominantColorValue: 0xFF6750A4,
    );

    testWidgets('MaterialYouAlbumCover renders procedural monogram, HI-RES badge and source icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
          ),
          home: const Scaffold(
            body: Center(
              child: MaterialYouAlbumCover(
                track: hiResTrack,
                size: 160,
                borderRadius: 24,
                showPlayButton: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check initials in monogram
      expect(find.text('MA'), findsOneWidget); // Midnight Sun + Aura initials
      expect(find.text('HI-RES'), findsOneWidget);
      expect(find.byIcon(Icons.add_to_drive_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });
  });

  group('HomeScreen Interactive Filtering Widget Tests', () {
    const track1 = Track(
      id: 'track_1',
      accountId: 'acc_1',
      providerType: CloudProviderType.googleDrive,
      remotePathOrId: 'path_1',
      title: 'Bohemian Rhapsody',
      artist: 'Queen',
      album: 'A Night at the Opera',
      durationMs: 354000,
      streamUrl: 'https://example.com/song1.flac',
    );

    const track2 = Track(
      id: 'track_2',
      accountId: 'acc_2',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: 'path_2',
      title: 'Hotel California',
      artist: 'Eagles',
      album: 'Hotel California',
      durationMs: 391000,
      streamUrl: 'https://example.com/song2.flac',
    );

    testWidgets('HomeScreen renders Top Picks for Today, Artists and Albums sections with interactive filtering', (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith(
              (ref) => _StaticCatalogNotifier([track1, track2]),
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
            ),
            home: Scaffold(
              body: HomeScreen(
                onOpenNowPlaying: () {},
                onNavigateToTab: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sections are visible
      expect(find.text('Pixel Playlists'), findsOneWidget);
      expect(find.text('Top Picks for Today'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Artists in Your Library'), findsOneWidget);
      expect(find.text('New Albums'), findsWidgets);
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Bohemian Rhapsody'), findsWidgets);
      expect(find.text('Hotel California'), findsWidgets);

      // Tap on Artists filter category pill
      await tester.tap(find.text('Artists').first);
      await tester.pumpAndSettle();

      // Verify artist filter sub-bar appears
      expect(find.text('Filter by Artist (2)'), findsOneWidget);
      expect(find.text('Queen (1)'), findsOneWidget);
      expect(find.text('Eagles (1)'), findsOneWidget);

      // Select 'Queen' filter chip
      await tester.tap(find.text('Queen (1)'));
      await tester.pumpAndSettle();

      // Check that tracks list is filtered to Queen
      expect(find.text('Tracks by Queen'), findsOneWidget);
      expect(find.text('Bohemian Rhapsody'), findsWidgets);
      expect(find.text('Hotel California'), findsNothing);

      // Clear filter using the active filter banner close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Both tracks visible again
      expect(find.text('Recently Added'), findsOneWidget);
      expect(find.text('Hotel California'), findsWidgets);
    });
  });
}

class _StaticCatalogNotifier extends TracksCatalogNotifier {
  _StaticCatalogNotifier(List<Track> initialTracks) : super() {
    state = initialTracks;
  }
}
