import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';

void main() {
  testWidgets(
    'FreeBeat boots Pixel M3 Expressive UI, navigates across tabs, tests Settings hub, and handles zero seed data',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: FreeBeatApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Verify Home screen with M3 header and zero-seed empty state
      expect(find.text('Pixel Playlists'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Your Music, Everywhere'),
        300.0,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Your Music, Everywhere'), findsOneWidget);
      expect(find.text('Connect Cloud Storage'), findsOneWidget);

      // 2. Open Settings Hub from Top App Bar
      await tester.tap(find.byTooltip('Settings').first);
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Audio Quality'), findsOneWidget);
      expect(find.text('Bluetooth & Output'), findsOneWidget);
      expect(find.text('Storage & Sync'), findsOneWidget);
      expect(find.text('About FreeBeat'), findsOneWidget);

      // Navigate to Appearance sub-page
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('System Default'), findsOneWidget);

      // Return to Settings Hub, then back to Home
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Pixel Playlists'), findsOneWidget);

      // 3. Navigate to Library tab
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      expect(find.text('Your Library'), findsOneWidget);
      expect(find.text('Your Library is Empty'), findsOneWidget);

      // 4. Navigate to Smart EQ 10-Band Studio tab
      await tester.tap(find.text('Smart EQ'));
      await tester.pumpAndSettle();
      expect(find.text('Smart EQ Studio'), findsOneWidget);
      expect(find.text('PREAMP'), findsOneWidget);
      expect(find.text('16k'), findsOneWidget);

      // Switch to Rotary Tone Knobs & Stereo X sub-tab
      await tester.tap(find.text('Tone Knobs & Stereo X'));
      await tester.pumpAndSettle();
      expect(find.text('BASS TONE'), findsOneWidget);
      expect(find.text('TREBLE AIR'), findsOneWidget);
      expect(find.text('STEREO X'), findsOneWidget);

      // 5. Navigate to Cloud tab
      await tester.tap(find.text('Cloud'));
      await tester.pumpAndSettle();
      expect(find.text('Cloud'), findsWidgets);
      expect(find.text('No Cloud Accounts Connected'), findsOneWidget);
      expect(find.text('Connect a Cloud Drive'), findsOneWidget);

      // Verify installed cloud apps are housed inside the Add Cloud card
      await tester.tap(find.text('Add Cloud'));
      await tester.pumpAndSettle();
      expect(find.text('Add Cloud & Media Drive'), findsOneWidget);
      await tester.ensureVisible(find.text('Installed Apps'));
      await tester.tap(find.text('Installed Apps'));
      await tester.pumpAndSettle();
      expect(find.text('Installed Cloud Apps'), findsOneWidget);
      expect(find.text('Google Drive'), findsWidgets);
      expect(find.text('Microsoft OneDrive'), findsWidgets);
      expect(find.text('Dropbox'), findsWidgets);
    },
  );
}
