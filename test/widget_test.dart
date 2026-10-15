import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';

void main() {
  testWidgets(
    'FreeBeat boots Pixel M3 Expressive UI, navigates across tabs, and interacts with Poweramp 10-Band EQ & Now Playing',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: FreeBeatApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Home screen with Spotify layout & Your Mix
      expect(find.text('Your Mix'), findsWidgets);
      expect(find.text('Astral Meadow'), findsWidgets);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Jump back in'), findsOneWidget);

      // 2. Navigate to Library tab
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Your Library'), findsOneWidget);
      expect(find.text('Hi-Res 24-Bit'), findsOneWidget);

      // 3. Navigate to Poweramp 10-Band EQ Studio tab
      await tester.tap(find.text('Poweramp EQ'));
      await tester.pumpAndSettle();
      expect(find.text('Poweramp DSP Studio'), findsOneWidget);
      expect(find.text('PREAMP'), findsOneWidget);
      expect(find.text('16k'), findsOneWidget);

      // Switch to Rotary Tone Knobs & Stereo X sub-tab
      await tester.tap(find.text('Tone Knobs & Stereo X'));
      await tester.pumpAndSettle();
      expect(find.text('BASS TONE'), findsOneWidget);
      expect(find.text('TREBLE AIR'), findsOneWidget);
      expect(find.text('STEREO X'), findsOneWidget);

      // 4. Navigate to Clouds tab
      await tester.tap(find.text('Clouds'));
      await tester.pumpAndSettle();
      expect(find.text('Clouds & Hi-Fi Quality'), findsOneWidget);
      expect(find.text('Audio Bitrate & Hi-Fi Lossless Tiers'), findsOneWidget);

      await tester.drag(find.byType(ListView).last, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Bluetooth Codec & Device Compatibility'), findsOneWidget);

      // 5. Open Full Now Playing Screen by tapping the MiniPlayer
      await tester.tap(find.text('Your Mix').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Astral Meadow').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Poweramp 10-Band EQ'), findsOneWidget);
    },
  );
}
