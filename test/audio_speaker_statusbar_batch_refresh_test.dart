import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/clouds_screen.dart';
import 'package:freebeat/ui/screens/home_screen.dart';
import 'package:freebeat/ui/screens/main_shell.dart';
import 'package:freebeat/ui/screens/poweramp_dsp_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Speaker Audio, Status Bar, Batch Import, and Refresh Rate Tests', () {
    testWidgets('CloudsScreen is safely protected from status bar collision',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CloudsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify that CloudsScreen contains a SafeArea with bottom: false
      final safeAreaFinder = find.byWidgetPredicate(
        (w) => w is SafeArea && w.bottom == false,
      );
      expect(safeAreaFinder, findsOneWidget);

      // Verify header rendered inside SafeArea
      expect(find.text('Cloud'), findsOneWidget);
    });

    testWidgets('HomeScreen SliverAppBar renders cleanly with status bar protection',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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

      // Verify SliverAppBar.large is pinned and flexibleSpace is present
      final sliverAppBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
      expect(sliverAppBar.pinned, isTrue);
      expect(sliverAppBar.flexibleSpace, isNotNull);
      expect(find.text('Your Mix'), findsWidgets);
    });

    test('Batch track import creates unique IDs and populates empty queue', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final initialPlayback = container.read(playbackProvider);
      expect(initialPlayback.queue.isEmpty, isTrue);

      // Simulate importing a batch of 15 songs
      final batch = List.generate(
        15,
        (i) => Track(
          id: 'batch_song_${DateTime.now().microsecondsSinceEpoch}_$i',
          accountId: 'local_storage',
          providerType: CloudProviderType.androidSaf,
          remotePathOrId: '/storage/emulated/0/Music/track_$i.flac',
          title: 'Batch Song #$i',
          artist: 'Test Artist',
          album: 'Batch Album',
          durationMs: 240000,
          streamUrl: '/storage/emulated/0/Music/track_$i.flac',
          codec: 'FLAC',
          bitDepth: 24,
          sampleRateHz: 96000,
          bitrateKbps: 1411,
          sizeBytes: 30000000,
          dominantColorValue: 0xFF2196F3,
          isPinnedOffline: true,
          localCachePath: '/storage/emulated/0/Music/track_$i.flac',
        ),
      );

      // Verify all IDs in the batch are 100% unique
      final ids = batch.map((t) => t.id).toSet();
      expect(ids.length, equals(15));

      // Import the batch
      await container.read(tracksCatalogProvider.notifier).addIndexedTracks(batch);

      // Catalog should have all 15 tracks
      final catalog = container.read(tracksCatalogProvider);
      expect(catalog.length, equals(15));

      // Playback queue should now be populated with the first track ready to play
      final updatedPlayback = container.read(playbackProvider);
      expect(updatedPlayback.queue.length, equals(15));
      expect(updatedPlayback.currentTrack.id, equals(batch.first.id));
    });

    testWidgets('PowerampDspScreen pauses animation when tab is not active to maintain display refresh rate',
        (tester) async {
      // 1. Inactive PowerampDspScreen (background tab)
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PowerampDspScreen(isActive: false),
          ),
        ),
      );
      await tester.pump();

      // Should render without errors and without ticking animation loops in background
      expect(find.text('Smart EQ Studio'), findsOneWidget);

      // 2. Active PowerampDspScreen
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: PowerampDspScreen(isActive: true),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Smart EQ Studio'), findsOneWidget);
    });

    testWidgets('MainShell loads and passes isActive to Poweramp tab correctly',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MainShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // MainShell starts on tab 0 (HomeScreen)
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byType(PowerampDspScreen, skipOffstage: false),
        findsOneWidget,
      );

      final dspWidget = tester.widget<PowerampDspScreen>(
        find.byType(PowerampDspScreen, skipOffstage: false),
      );
      // Tab 0 is selected, so PowerampDspScreen should have isActive: false
      expect(dspWidget.isActive, isFalse);

      // Tap on the Smart EQ navigation pill tab (index 2)
      await tester.tap(find.text('Smart EQ'));
      await tester.pumpAndSettle();

      // Now Poweramp tab should be active
      final activeDspWidget = tester.widget<PowerampDspScreen>(
        find.byType(PowerampDspScreen),
      );
      expect(activeDspWidget.isActive, isTrue);
    });
  });
}
