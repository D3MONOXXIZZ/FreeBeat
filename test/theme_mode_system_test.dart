import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/theme/pixel_theme.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Material 3 Dual Color Schemes & Monet Tonal Palette', () {
    test('Explicitly generates complete lightColorScheme derived from #6750A4', () {
      final lightCs = PixelTheme.buildLightColorScheme();

      expect(lightCs.brightness, Brightness.light);
      expect(lightCs.primary, isNotNull);
      expect(lightCs.onPrimary, isNotNull);
      expect(lightCs.primaryContainer, isNotNull);
      expect(lightCs.onPrimaryContainer, isNotNull);
      expect(lightCs.surface, isNotNull);
      expect(lightCs.onSurface, isNotNull);
      expect(lightCs.surfaceContainerLow, isNotNull);
      expect(lightCs.surfaceContainer, isNotNull);
      expect(lightCs.surfaceContainerHigh, isNotNull);
      expect(lightCs.surfaceTint, isNotNull);

      // Light surface must have high luminance and onSurface low luminance for readability
      expect(lightCs.surface.computeLuminance() > 0.7, isTrue);
      expect(lightCs.onSurface.computeLuminance() < 0.3, isTrue);
    });

    test('Explicitly generates complete darkColorScheme derived from #6750A4', () {
      final darkCs = PixelTheme.buildDarkColorScheme();

      expect(darkCs.brightness, Brightness.dark);
      expect(darkCs.primary, isNotNull);
      expect(darkCs.onPrimary, isNotNull);
      expect(darkCs.primaryContainer, isNotNull);
      expect(darkCs.onPrimaryContainer, isNotNull);
      expect(darkCs.surface, isNotNull);
      expect(darkCs.onSurface, isNotNull);
      expect(darkCs.surfaceContainerLow, isNotNull);
      expect(darkCs.surfaceContainer, isNotNull);
      expect(darkCs.surfaceContainerHigh, isNotNull);
      expect(darkCs.surfaceTint, isNotNull);

      // Dark surface must have low luminance and onSurface high luminance for readability
      expect(darkCs.surface.computeLuminance() < 0.3, isTrue);
      expect(darkCs.onSurface.computeLuminance() > 0.7, isTrue);
    });

    test('ThemeData surfaces and elevations invert properly between Light and Dark', () {
      final lightTheme = PixelTheme.buildLightTheme();
      final darkTheme = PixelTheme.buildDarkTheme();

      expect(lightTheme.useMaterial3, isTrue);
      expect(darkTheme.useMaterial3, isTrue);

      // Zero card drop shadow / tonal elevation via surfaceContainerLow
      expect(lightTheme.cardTheme.elevation, 0);
      expect(darkTheme.cardTheme.elevation, 0);

      // Card shapes strictly 28dp
      expect(
        (lightTheme.cardTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(28),
      );
      expect(
        (darkTheme.cardTheme.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(28),
      );

      // Surface tints present
      expect(lightTheme.cardTheme.surfaceTintColor, isNotNull);
      expect(darkTheme.cardTheme.surfaceTintColor, isNotNull);

      // Inverted typography colors
      expect(lightTheme.textTheme.headlineMedium?.color, lightTheme.colorScheme.onSurface);
      expect(darkTheme.textTheme.headlineMedium?.color, darkTheme.colorScheme.onSurface);
    });
  });

  group('Dynamic System Theme Binding & Reactive Switch Without Restart', () {
    testWidgets('App starts with ThemeMode.system and reacts immediately to device brightness changes',
        (WidgetTester tester) async {
      // 1. Set simulated system brightness to Dark
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

      await tester.pumpWidget(
        const ProviderScope(
          child: FreeBeatApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Find MaterialApp and verify themeMode is ThemeMode.system
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.themeMode, ThemeMode.system);

      // Verify active theme in context is Dark
      final BuildContext darkCtx = tester.element(find.text('Your Mix').first);
      expect(Theme.of(darkCtx).brightness, Brightness.dark);

      // 2. Toggle system brightness to Light (simulating user toggling Android quick settings)
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify active theme in context is now Light WITHOUT restart
      final BuildContext lightCtx = tester.element(find.text('Your Mix').first);
      expect(Theme.of(lightCtx).brightness, Brightness.light);

      // Verify light surface luminance
      final lightColorScheme = Theme.of(lightCtx).colorScheme;
      expect(lightColorScheme.surface.computeLuminance() > 0.7, isTrue);

      // 3. Toggle back to Dark
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      await tester.pumpAndSettle();

      final BuildContext reDarkCtx = tester.element(find.text('Your Mix').first);
      expect(Theme.of(reDarkCtx).brightness, Brightness.dark);
    });

    testWidgets('User can override theme mode via themeModeProvider without restart',
        (WidgetTester tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, child) {
              capturedRef = ref;
              return const FreeBeatApp();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state is ThemeMode.system
      expect(capturedRef.read(themeModeProvider), ThemeMode.system);

      // Explicitly force Light mode
      capturedRef.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      await tester.pump();
      await tester.pumpAndSettle();

      // Context should now be Light despite system being Dark
      final BuildContext ctx = tester.element(find.text('Your Mix').first);
      expect(Theme.of(ctx).brightness, Brightness.light);

      // Force Dark mode
      capturedRef.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      await tester.pump();
      await tester.pumpAndSettle();

      final BuildContext darkCtx = tester.element(find.text('Your Mix').first);
      expect(Theme.of(darkCtx).brightness, Brightness.dark);
    });
  });
}
