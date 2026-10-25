import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Authentic Google Pixel Material 3 Expressive Design System (Material You).
///
/// Strictly adheres to:
/// 1. Monet Dynamic Palette using base seed #6750A4 (Deep Violet) or wallpaper dynamic colors.
/// 2. Full M3 color roles & tonal elevation (zero heavy drop shadows).
/// 3. Google Sans (or geometric sans fallback) for all headings/titles and Roboto for body text.
/// 4. Extremely rounded shapes: 28dp for dialogs, cards, FABs; Stadium/pill (100dp) for buttons, chips, indicators.
/// 5. Collapsing Large Top App Bars, 80dp+ NavigationBar with pill active indicator, thick M3 switches and sliders.
class PixelTheme {
  // Base seed color specified by user: Deep Violet (#6750A4)
  static const Color kSeedDeepViolet = Color(0xFF6750A4);

  // ───────────────────────────────────────────────────────────────────────────
  // Text Theme: Google Sans for headings/titles, Roboto for body
  // ───────────────────────────────────────────────────────────────────────────
  static TextTheme _buildTextTheme(ColorScheme cs) {
    // Primary display & title font: Google Sans (Stock Pixel system font)
    const googleSansFamily = 'Google Sans';
    const fontFallbacks = ['Open Sans', 'Roboto', 'sans-serif'];

    // Body font: Roboto (Standard Android system font)
    const robotoFamily = 'Roboto';

    TextStyle headingStyle({
      required double fontSize,
      required FontWeight fontWeight,
      double? letterSpacing,
      double? height,
    }) {
      return TextStyle(
        fontFamily: googleSansFamily,
        fontFamilyFallback: fontFallbacks,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: cs.onSurface,
      );
    }

    TextStyle bodyStyle({
      required double fontSize,
      required FontWeight fontWeight,
      Color? color,
      double? letterSpacing,
      double? height,
    }) {
      return TextStyle(
        fontFamily: robotoFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
        color: color ?? cs.onSurface,
      );
    }

    return TextTheme(
      // Display: large hero numbers / expressive playback counters
      displayLarge: headingStyle(
        fontSize: 57,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        height: 1.12,
      ),
      displayMedium: headingStyle(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.15,
      ),
      displaySmall: headingStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        height: 1.2,
      ),

      // Headline: Top App Bars & section heroes
      headlineLarge: headingStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: headingStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      headlineSmall: headingStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),

      // Title: list items, card headers, tabs
      titleLarge: headingStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: headingStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.15,
      ),
      titleSmall: headingStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),

      // Body: Roboto body text
      bodyLarge: bodyStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
      bodyMedium: bodyStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: cs.onSurfaceVariant,
        letterSpacing: 0.25,
      ),
      bodySmall: bodyStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: cs.onSurfaceVariant,
        letterSpacing: 0.4,
      ),

      // Labels: Buttons, chips, navigation items
      labelLarge: headingStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
      labelMedium: headingStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      labelSmall: headingStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dual Color Schemes (Explicitly derived from seed #6750A4 or wallpaper)
  // ───────────────────────────────────────────────────────────────────────────

  /// Generates the complete Material 3 Dark ColorScheme explicitly derived from
  /// the primary seed color #6750A4 (or Android wallpaper dynamic colors).
  static ColorScheme buildDarkColorScheme({
    ColorScheme? wallpaperDynamicScheme,
    Color activeTrackSeedColor = kSeedDeepViolet,
    bool amoledPitchBlack = false,
  }) {
    final baseScheme = wallpaperDynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: kSeedDeepViolet,
          brightness: Brightness.dark,
        );

    final isStaleGreen = activeTrackSeedColor.toARGB32() == 0xFF3DDC84 ||
        activeTrackSeedColor.toARGB32() == 0xFF1DB954;
    final effectiveSeed = isStaleGreen ? kSeedDeepViolet : activeTrackSeedColor;

    ColorScheme scheme = baseScheme;

    if (effectiveSeed != kSeedDeepViolet &&
        wallpaperDynamicScheme == null) {
      final trackScheme = ColorScheme.fromSeed(
        seedColor: effectiveSeed,
        brightness: Brightness.dark,
      );
      scheme = baseScheme.copyWith(
        primary: Color.lerp(baseScheme.primary, trackScheme.primary, 0.45),
        primaryContainer: Color.lerp(
            baseScheme.primaryContainer, trackScheme.primaryContainer, 0.45),
        tertiary: trackScheme.tertiary,
      );
    }

    if (amoledPitchBlack) {
      return scheme.copyWith(
        surface: Colors.black,
        surfaceDim: Colors.black,
        surfaceBright: const Color(0xFF121212),
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF080808),
        surfaceContainer: const Color(0xFF101010),
        surfaceContainerHigh: const Color(0xFF181818),
        surfaceContainerHighest: const Color(0xFF222222),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFC4C4C4),
      );
    }

    return scheme;
  }

  /// Generates the complete Material 3 Light ColorScheme explicitly derived from
  /// the primary seed color #6750A4 (or Android wallpaper dynamic colors).
  static ColorScheme buildLightColorScheme({
    ColorScheme? wallpaperDynamicScheme,
    Color activeTrackSeedColor = kSeedDeepViolet,
  }) {
    final baseScheme = wallpaperDynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: kSeedDeepViolet,
          brightness: Brightness.light,
        );

    final isStaleGreen = activeTrackSeedColor.toARGB32() == 0xFF3DDC84 ||
        activeTrackSeedColor.toARGB32() == 0xFF1DB954;
    final effectiveSeed = isStaleGreen ? kSeedDeepViolet : activeTrackSeedColor;

    if (effectiveSeed != kSeedDeepViolet &&
        wallpaperDynamicScheme == null) {
      final trackScheme = ColorScheme.fromSeed(
        seedColor: effectiveSeed,
        brightness: Brightness.light,
      );
      return baseScheme.copyWith(
        primary: Color.lerp(baseScheme.primary, trackScheme.primary, 0.45),
        primaryContainer: Color.lerp(
            baseScheme.primaryContainer, trackScheme.primaryContainer, 0.45),
        tertiary: trackScheme.tertiary,
      );
    }
    return baseScheme;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Dark Theme (Default for Pixel Hi-Fi Experience)
  // ───────────────────────────────────────────────────────────────────────────
  static ThemeData buildDarkTheme({
    ColorScheme? wallpaperDynamicScheme,
    Color activeTrackSeedColor = kSeedDeepViolet,
  }) {
    final colorScheme = buildDarkColorScheme(
      wallpaperDynamicScheme: wallpaperDynamicScheme,
      activeTrackSeedColor: activeTrackSeedColor,
    );
    return _buildTheme(colorScheme, Brightness.dark);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Light Theme (Full Day/Night Monet Support)
  // ───────────────────────────────────────────────────────────────────────────
  static ThemeData buildLightTheme({
    ColorScheme? wallpaperDynamicScheme,
    Color activeTrackSeedColor = kSeedDeepViolet,
  }) {
    final colorScheme = buildLightColorScheme(
      wallpaperDynamicScheme: wallpaperDynamicScheme,
      activeTrackSeedColor: activeTrackSeedColor,
    );
    return _buildTheme(colorScheme, Brightness.light);
  }

  /// Builds a complete Material 3 theme directly from an explicit ColorScheme.
  static ThemeData buildThemeFromScheme(ColorScheme cs, Brightness brightness) {
    return _buildTheme(cs, brightness);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared M3 Theme Builder (Shapes, Corner Radii, Elevation & Components)
  // ───────────────────────────────────────────────────────────────────────────
  static ThemeData _buildTheme(ColorScheme cs, Brightness brightness) {
    final textTheme = _buildTextTheme(cs);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      textTheme: textTheme,

      // Zero drop shadow, tonal elevation via surfaceContainer
      cardTheme: CardThemeData(
        elevation: 0,
        color: cs.surfaceContainerLow,
        surfaceTintColor: cs.surfaceTint,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),

      // Dialogs: Strict 28dp corner radius
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: cs.surfaceContainerHigh,
        surfaceTintColor: cs.surfaceTint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),

      // BottomSheet: 28dp top radius, tonal elevation
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 0,
        backgroundColor: cs.surfaceContainerLow,
        surfaceTintColor: cs.surfaceTint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      // Large Top App Bar: Blends seamlessly with background, tints on scroll
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: cs.surface,
        surfaceTintColor: cs.surfaceTint,
        foregroundColor: cs.onSurface,
        centerTitle: false,
        titleTextStyle: textTheme.headlineMedium?.copyWith(
          color: cs.onSurface,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: brightness,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
      ),

      // Global Icon Theme
      iconTheme: IconThemeData(
        color: cs.onSurface,
      ),

      // List Tile Theme
      listTileTheme: ListTileThemeData(
        iconColor: cs.onSurfaceVariant,
        textColor: cs.onSurface,
        titleTextStyle: textTheme.titleMedium?.copyWith(color: cs.onSurface),
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),

      // Floating SnackBar
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: TextStyle(color: cs.onInverseSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),

      // Popup Menu Theme
      popupMenuTheme: PopupMenuThemeData(
        elevation: 2,
        color: cs.surfaceContainerHigh,
        surfaceTintColor: cs.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(color: cs.onSurface),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
      ),

      // Bottom Navigation Bar: Tall (80dp+ height) with stadium pill indicator, no shadow
      navigationBarTheme: NavigationBarThemeData(
        height: 82,
        elevation: 0,
        backgroundColor: cs.surfaceContainer,
        surfaceTintColor: cs.surfaceTint,
        indicatorColor: cs.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: isSelected
                ? cs.onSecondaryContainer
                : cs.onSurfaceVariant,
          );
        }),
      ),

      // Floating Action Button: 28dp corner radius, Primary Container fill
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),

      // Filled Button: Stadium pill shape with generous horizontal padding
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Outlined Button: Stadium pill shape
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: BorderSide(color: cs.outlineVariant),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // Chips: Fully pill-shaped stadium borders
      chipTheme: ChipThemeData(
        elevation: 0,
        pressElevation: 0,
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainerHigh,
        selectedColor: cs.secondaryContainer,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),

      // Segmented Button: Fully pill-shaped stadium borders
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return cs.secondaryContainer;
            }
            return cs.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return cs.onSecondaryContainer;
            }
            return cs.onSurfaceVariant;
          }),
        ),
      ),

      // Switches: Thick, expressive M3 switch with prominent thumb
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.onPrimary;
          }
          return cs.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.primary;
          }
          return cs.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return cs.outline;
        }),
      ),

      // Sliders: Thick expressive track, pill thumb
      sliderTheme: SliderThemeData(
        trackHeight: 12,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 10,
          elevation: 0,
        ),
        activeTrackColor: cs.primary,
        inactiveTrackColor: cs.surfaceContainerHighest,
        thumbColor: cs.primary,
        overlayColor: cs.primary.withValues(alpha: 0.12),
      ),

      // Dividers: Subtle outline variant
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.4),
        thickness: 1,
        space: 1,
      ),

      // Material 3 Page Transitions Theme (Predictive Back on Android 14+)
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
