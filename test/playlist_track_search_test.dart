import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/playlist_details_screen.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final track1 = Track(
    id: 'track_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/music/track1.flac',
    title: 'Starboy',
    artist: 'The Weeknd, Daft Punk',
    album: 'Starboy',
    durationMs: 230000,
    streamUrl: 'file:///music/track1.flac',
    codec: 'FLAC',
  );

  final track2 = Track(
    id: 'track_2',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/music/track2.mp3',
    title: 'Levitating',
    artist: 'Dua Lipa feat. DaBaby',
    album: 'Future Nostalgia',
    durationMs: 203000,
    streamUrl: 'file:///music/track2.mp3',
    codec: 'MP3',
  );

  final track3 = Track(
    id: 'track_3',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/music/track3.flac',
    title: 'Blinding Lights',
    artist: 'The Weeknd',
    album: 'After Hours',
    durationMs: 200000,
    streamUrl: 'file:///music/track3.flac',
    codec: 'FLAC',
  );

  final testPlaylist = Playlist(
    id: 'pl_search_test',
    title: 'Workout Hits',
    description: 'High energy tracks',
    trackIds: ['track_1', 'track_2', 'track_3'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Widget createWidget() {
    return ProviderScope(
      overrides: [
        smartPlaylistsProvider.overrideWith((ref) => [testPlaylist]),
        tracksCatalogProvider.overrideWith((ref) {
          final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
          notifier.state = [track1, track2, track3];
          return notifier;
        }),
      ],
      child: MaterialApp(
        home: PlaylistDetailsScreen(playlist: testPlaylist),
      ),
    );
  }

  group('Playlist Track Search Tests', () {
    testWidgets('Header displays Search button and quick Find in playlist bar trigger', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Verify search icon button is present in the app bar
      expect(find.byTooltip('Search in Playlist'), findsOneWidget);

      // Verify "Find in playlist..." trigger pill is present in the playlist header
      expect(find.text('Find in playlist...'), findsOneWidget);

      // Verify all 3 initial tracks are rendered
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Levitating'), findsOneWidget);
      expect(find.text('Blinding Lights'), findsOneWidget);
    });

    testWidgets('Tapping search icon enters search mode and filters tracks in real-time by title', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap the Search button in the app bar
      await tester.tap(find.byTooltip('Search in Playlist'));
      await tester.pumpAndSettle();

      // Search bar input should now be visible
      final searchFieldFinder = find.byType(TextField);
      expect(searchFieldFinder, findsOneWidget);
      expect(find.text('Search in "Workout Hits"...'), findsOneWidget);

      // Enter query "Starboy"
      await tester.enterText(searchFieldFinder, 'Starboy');
      await tester.pumpAndSettle();

      // "Starboy" should be visible in the list, "Levitating" and "Blinding Lights" should be filtered out
      expect(
        find.descendant(
          of: find.byType(SuperSliverList),
          matching: find.text('Starboy'),
        ),
        findsOneWidget,
      );
      expect(find.text('Levitating'), findsNothing);
      expect(find.text('Blinding Lights'), findsNothing);

      // Header indicates 1 track found
      expect(find.text('Found 1 of 3 tracks'), findsOneWidget);
    });

    testWidgets('Filters by artist name and featured artist', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      // Tap search trigger in body
      await tester.tap(find.text('Find in playlist...'));
      await tester.pumpAndSettle();

      // Search for "The Weeknd" (matches 2 tracks)
      await tester.enterText(find.byType(TextField), 'The Weeknd');
      await tester.pumpAndSettle();

      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Blinding Lights'), findsOneWidget);
      expect(find.text('Levitating'), findsNothing);
      expect(find.text('Found 2 of 3 tracks'), findsOneWidget);

      // Search for collaborator "DaBaby" (matches Levitating)
      await tester.enterText(find.byType(TextField), 'DaBaby');
      await tester.pumpAndSettle();

      expect(find.text('Levitating'), findsOneWidget);
      expect(find.text('Starboy'), findsNothing);
      expect(find.text('Blinding Lights'), findsNothing);
    });

    testWidgets('Displays no matches state and clears query properly', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search in Playlist'));
      await tester.pumpAndSettle();

      // Enter query with zero matches
      await tester.enterText(find.byType(TextField), 'NonExistentSongXYZ');
      await tester.pumpAndSettle();

      expect(find.text('No matches found'), findsOneWidget);
      expect(find.textContaining('No songs in "Workout Hits" match "NonExistentSongXYZ"'), findsOneWidget);
      expect(find.text('Clear Query'), findsOneWidget);

      // Tap "Clear Query" button
      await tester.tap(find.text('Clear Query'));
      await tester.pumpAndSettle();

      // All 3 tracks should reappear
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('Levitating'), findsOneWidget);
      expect(find.text('Blinding Lights'), findsOneWidget);
    });

    testWidgets('Exiting search mode restores normal playlist details header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));
      await tester.pumpWidget(createWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search in Playlist'));
      await tester.pumpAndSettle();

      // In search mode, cover art is collapsed
      expect(find.byTooltip('Close search'), findsOneWidget);

      // Tap Close search
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();

      // Normal playlist header elements are restored
      expect(find.text('Play All'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('Find in playlist...'), findsOneWidget);
      expect(find.byTooltip('Search in Playlist'), findsOneWidget);
    });
  });
}
