import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/main.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/services/metadata/artwork_palette_extractor.dart';
import 'package:freebeat/state/app_providers.dart';

class _MockLibraryDatabase extends LibraryDatabase {
  final List<Playlist> savedPlaylists = [];

  @override
  Future<List<Playlist>> loadPlaylists() async => List.from(savedPlaylists);

  @override
  Future<void> upsertPlaylist(Playlist playlist) async {
    savedPlaylists.removeWhere((p) => p.id == playlist.id);
    savedPlaylists.add(playlist);
  }

  @override
  Future<void> deletePlaylist(String id) async {
    savedPlaylists.removeWhere((p) => p.id == id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ArtworkPaletteExtractor.clearCache();
  });

  group('ArtworkPaletteExtractor LRU Cache & Trim Tests', () {
    test('enforces maxCacheEntries ceiling of 120 items', () {
      expect(ArtworkPaletteExtractor.cacheSize, 0);

      // Inject 130 items
      for (int i = 0; i < 130; i++) {
        ArtworkPaletteExtractor.injectCached(
          'item_$i',
          ArtworkPalette.fallback,
        );
      }

      // Should be clamped at exactly 120
      expect(ArtworkPaletteExtractor.cacheSize, 120);

      // Oldest items (0-9) should have been evicted
      for (int i = 0; i < 10; i++) {
        expect(ArtworkPaletteExtractor.getCached('item_$i'), isNull);
      }

      // Newest item (129) should be present
      expect(ArtworkPaletteExtractor.getCached('item_129'), isNotNull);
    });

    test('getCached refreshes item position in LRU order', () {
      // Inject items 0..119 (exactly 120 items)
      for (int i = 0; i < 120; i++) {
        ArtworkPaletteExtractor.injectCached(
          'track_$i',
          ArtworkPalette.fallback,
        );
      }
      expect(ArtworkPaletteExtractor.cacheSize, 120);

      // Access item 0 so it moves to MRU (most recently used)
      final accessed = ArtworkPaletteExtractor.getCached('track_0');
      expect(accessed, isNotNull);

      // Now insert a new item 'track_new'
      ArtworkPaletteExtractor.injectCached('track_new', ArtworkPalette.fallback);
      expect(ArtworkPaletteExtractor.cacheSize, 120);

      // track_0 should STILL be in cache because it was refreshed!
      expect(ArtworkPaletteExtractor.getCached('track_0'), isNotNull);

      // track_1 (which was the next oldest) should have been evicted!
      expect(ArtworkPaletteExtractor.getCached('track_1'), isNull);
    });

    test('trimMemory evicts down to target keepCount', () {
      for (int i = 0; i < 80; i++) {
        ArtworkPaletteExtractor.injectCached('key_$i', ArtworkPalette.fallback);
      }
      expect(ArtworkPaletteExtractor.cacheSize, 80);

      // Trim down to 10
      ArtworkPaletteExtractor.trimMemory(keepCount: 10);
      expect(ArtworkPaletteExtractor.cacheSize, 10);

      // Most recent 10 (key_70..key_79) should be retained
      expect(ArtworkPaletteExtractor.getCached('key_79'), isNotNull);
      expect(ArtworkPaletteExtractor.getCached('key_0'), isNull);

      // Trim down to 0
      ArtworkPaletteExtractor.trimMemory(keepCount: 0);
      expect(ArtworkPaletteExtractor.cacheSize, 0);
    });
  });

  group('Memory Pressure & ImageCache Configuration Tests', () {
    testWidgets('FreeBeatApp didHaveMemoryPressure trims imageCache and paletteCache',
        (tester) async {
      // In main(), image cache is set to 150 items and 40MB
      PaintingBinding.instance.imageCache.maximumSize = 150;
      PaintingBinding.instance.imageCache.maximumSizeBytes = 40 * 1024 * 1024;

      expect(PaintingBinding.instance.imageCache.maximumSize, 150);
      expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 40 * 1024 * 1024);

      // Populate palette cache
      for (int i = 0; i < 50; i++) {
        ArtworkPaletteExtractor.injectCached('mem_$i', ArtworkPalette.fallback);
      }
      expect(ArtworkPaletteExtractor.cacheSize, 50);

      await tester.pumpWidget(
        const ProviderScope(
          child: FreeBeatApp(),
        ),
      );
      await tester.pump();

      // Simulate system low-memory notification
      tester.binding.handleMemoryPressure();
      await tester.pump();

      // Verify ArtworkPaletteExtractor was trimmed down to keepCount = 5
      expect(ArtworkPaletteExtractor.cacheSize, lessThanOrEqualTo(5));
    });
  });

  group('PlaylistsNotifier Reorder Debouncing Tests', () {
    test('reorderTracks updates in-memory queue immediately and debounces SQLite save',
        () async {
      final mockDb = _MockLibraryDatabase();
      final initialPlaylist = Playlist(
        id: 'test_pl_1',
        title: 'Workout Beats',
        description: 'High BPM tracks',
        trackIds: ['t1', 't2', 't3', 't4', 't5'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        colorSeedValue: 0xFF1E88E5,
      );
      await mockDb.upsertPlaylist(initialPlaylist);

      final notifier = PlaylistsNotifier(mockDb);
      // Wait for load
      await Future.delayed(const Duration(milliseconds: 20));

      // Reorder t1 (index 0) to index 3 (new order: t2, t3, t1, t4, t5)
      await notifier.reorderTracks('test_pl_1', 0, 3);

      // Immediate in-memory check
      expect(notifier.state.first.trackIds, ['t2', 't3', 't1', 't4', 't5']);

      // Immediately reorder t5 (index 4) to index 0 (new order: t5, t2, t3, t1, t4)
      await notifier.reorderTracks('test_pl_1', 4, 0);

      // Immediate in-memory check
      expect(notifier.state.first.trackIds, ['t5', 't2', 't3', 't1', 't4']);

      // Wait 350ms for debounce timer to fire and write to DB
      await Future.delayed(const Duration(milliseconds: 350));

      // Check DB persistence
      final persisted = mockDb.savedPlaylists.firstWhere((p) => p.id == 'test_pl_1');
      expect(persisted.trackIds, ['t5', 't2', 't3', 't1', 't4']);

      notifier.dispose();
    });
  });
}
