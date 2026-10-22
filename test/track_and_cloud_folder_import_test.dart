// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';
import 'package:freebeat/ui/screens/library_screen.dart';
import 'package:freebeat/ui/screens/main_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
  });

  group('Track & Cloud Folder Import Tests', () {
    test('Spotify individual track link import extracts metadata & artwork', () async {
      final service = PlaylistImportService();
      // Track: ILLENIUM - Needed You
      const trackUrl = 'https://open.spotify.com/track/69hRZ2PUkMc61HXFicoMUk';
      final res = await service.importFromUrl(trackUrl, []);

      expect(res.totalParsed, 1);
      expect(res.title, 'Needed You');
      expect(res.missingTracks.length, 1);
      expect(res.missingTracks.first.title, 'Needed You');
      expect(res.missingTracks.first.artist, contains('ILLENIUM'));
      expect(res.artworkUrl, isNotNull);
      expect(res.artworkUrl!.isNotEmpty, isTrue);
      print('Spotify single track: "${res.title}" by "${res.missingTracks.first.artist}" [Art: ${res.artworkUrl}]');
    });

    test('YouTube video single track link import extracts clean metadata', () async {
      final service = PlaylistImportService();
      const ytUrl = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
      final res = await service.importFromUrl(ytUrl, []);

      expect(res.totalParsed, 1);
      expect(res.title.toLowerCase(), contains('never gonna give you up'));
      expect(res.missingTracks.first.artist.toLowerCase(), contains('rick astley'));
      expect(res.artworkUrl, isNotNull);
      print('YouTube single track: "${res.title}" by "${res.missingTracks.first.artist}" [Art: ${res.artworkUrl}]');
    });

    testWidgets('LibraryScreen Add Button reveals Add to Library options modal', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LibraryScreen(showFab: true),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find Floating Action Button
      final fabFinder = find.byType(FloatingActionButton);
      expect(fabFinder, findsOneWidget);

      // Tap FAB to open Add to Library bottom sheet
      await tester.tap(fabFinder);
      await tester.pumpAndSettle();

      // Verify the 4 key import options are presented
      expect(find.text('Add to Library'), findsOneWidget);
      expect(find.text('Import from Link'), findsOneWidget);
      expect(find.text('Import Folder from Cloud'), findsOneWidget);
      expect(find.text('Pick Audio Files'), findsOneWidget);
      expect(find.text('New Playlist'), findsOneWidget);
    });

    testWidgets('MainShell big + button next to mini player in library also opens Add to Library modal', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: MainShell(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Navigate to Library tab (index 1)
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();

      // Find the big + FAB in MainShell next to mini player
      final shellFab = find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.byIcon(Icons.add_rounded),
      );
      expect(shellFab, findsOneWidget);

      // Tap the shell FAB
      await tester.tap(shellFab);
      await tester.pumpAndSettle();

      // Verify it opens the Add to Library modal, NOT directly opening file picker
      expect(find.text('Add to Library'), findsOneWidget);
      expect(find.text('Import from Link'), findsOneWidget);
      expect(find.text('Import Folder from Cloud'), findsOneWidget);
      expect(find.text('Pick Audio Files'), findsOneWidget);
      expect(find.text('New Playlist'), findsOneWidget);
    });
  });
}
