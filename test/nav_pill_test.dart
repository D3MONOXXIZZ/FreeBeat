import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/ui/widgets/nav_pill.dart';

void main() {
  testWidgets('MaterialYouNavPill renders destinations and reacts to tap with active indicator',
      (tester) async {
    int selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Center(
                child: MaterialYouNavPill(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (idx) {
                    setState(() => selectedIndex = idx);
                  },
                  destinations: const [
                    NavPillDestination(
                      icon: Icons.home_outlined,
                      selectedIcon: Icons.home_rounded,
                      label: 'Your Mix',
                    ),
                    NavPillDestination(
                      icon: Icons.library_music_outlined,
                      selectedIcon: Icons.library_music_rounded,
                      label: 'Library',
                    ),
                    NavPillDestination(
                      icon: Icons.equalizer_rounded,
                      selectedIcon: Icons.graphic_eq_rounded,
                      label: 'Poweramp EQ',
                    ),
                    NavPillDestination(
                      icon: Icons.cloud_outlined,
                      selectedIcon: Icons.cloud_done_rounded,
                      label: 'Clouds',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    // Verify all 4 labels are present
    expect(find.text('Your Mix'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Poweramp EQ'), findsOneWidget);
    expect(find.text('Clouds'), findsOneWidget);

    // Initially "Your Mix" is selected
    expect(selectedIndex, 0);

    // Tap on "Library"
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(selectedIndex, 1);

    // Tap on "Clouds"
    await tester.tap(find.text('Clouds'));
    await tester.pumpAndSettle();

    expect(selectedIndex, 3);

    // Verify nav pill has been scaled down to 50dp height
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(MaterialYouNavPill),
        matching: find.byType(Container),
      ).first,
    );
    expect(container.constraints?.maxHeight ?? (tester.getSize(find.byType(MaterialYouNavPill)).height), 50.0);
  });

  testWidgets('AndroidGestureHandle renders signature Pixel home bar pill', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AndroidGestureHandle(),
        ),
      ),
    );

    expect(find.byType(AndroidGestureHandle), findsOneWidget);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(AndroidGestureHandle),
        matching: find.byType(Container),
      ),
    );

    expect(container.constraints?.maxWidth, 72.0);
    expect(container.constraints?.maxHeight, 4.5);
  });
}
