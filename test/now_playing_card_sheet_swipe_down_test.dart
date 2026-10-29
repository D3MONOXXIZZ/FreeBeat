import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/now_playing_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testTrack = Track(
    id: 'track_np_test',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '/music/song.flac',
    title: 'Love Lost',
    artist: 'Umair, Talha Anjum',
    album: 'Rockstar Without a Guitar',
    durationMs: 195000,
    streamUrl: 'file:///music/song.flac',
    codec: 'FLAC',
  );

  group('NowPlayingScreen Card Sheet & Swipe Down Tests', () {
    testWidgets('Renders in a card sheet with drag handle pill indicator and top rounded corners', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [testTrack];
              return notifier;
            }),
            playbackProvider.overrideWith((ref) {
              final notifier = PlaybackNotifier(ref);
              notifier.state = notifier.state.copyWith(
                currentTrack: testTrack,
                isPlaying: true,
                queue: [testTrack],
              );
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: NowPlayingScreen(onOpenDspStudio: () {}),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Verify PopScope wraps the card screen
      expect(find.byWidgetPredicate((w) => w is PopScope), findsOneWidget);

      // 2. Verify Card Sheet Drag Handle pill indicator exists
      final handleFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final box = widget.decoration as BoxDecoration;
          if (box.borderRadius == BorderRadius.circular(2.5)) {
            final constraints = widget.constraints;
            return constraints?.maxWidth == 38.0 && constraints?.maxHeight == 4.5;
          }
        }
        return false;
      });
      expect(handleFinder, findsOneWidget);

      // 3. Verify Card top rounded corners
      final clipRRectFinder = find.byWidgetPredicate((widget) {
        if (widget is ClipRRect) {
          return widget.borderRadius == const BorderRadius.vertical(top: Radius.circular(28));
        }
        return false;
      });
      expect(clipRRectFinder, findsOneWidget);

      // 4. Verify collapse down chevron button is present
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('Swiping down triggers interactive card slide down', (tester) async {
      await tester.binding.setSurfaceSize(const Size(412, 915));

      bool popped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tracksCatalogProvider.overrideWith((ref) {
              final notifier = TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
              notifier.state = [testTrack];
              return notifier;
            }),
            playbackProvider.overrideWith((ref) {
              final notifier = PlaybackNotifier(ref);
              notifier.state = notifier.state.copyWith(
                currentTrack: testTrack,
                isPlaying: true,
                queue: [testTrack],
              );
              return notifier;
            }),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).push(
                      PageRouteBuilder<void>(
                        opaque: false,
                        barrierColor: Colors.transparent,
                        pageBuilder: (_, __, ___) => NowPlayingScreen(onOpenDspStudio: () {}),
                      ),
                    ).then((_) {
                      popped = true;
                    });
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open the NowPlayingScreen
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(NowPlayingScreen), findsOneWidget);

      // Perform a downward swipe gesture
      await tester.drag(find.byIcon(Icons.keyboard_arrow_down_rounded), const Offset(0, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Card should smoothly slide down and pop the route
      expect(popped, isTrue);
    });
  });
}
