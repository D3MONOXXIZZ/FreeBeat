import 'package:flutter/material.dart';

/// Rule U1: Authentic Google Pixel Material 3 Expressive (Material You) Theme.
/// Blends Android 12–16 Wallpaper Monet `DynamicColorBuilder` palettes with the
/// currently playing track's dominant album art seed color.
class PixelTheme {
  static ThemeData buildDarkTheme({
    ColorScheme? wallpaperDynamicScheme,
    required Color activeTrackSeedColor,
  }) {
    final trackScheme = ColorScheme.fromSeed(
      seedColor: activeTrackSeedColor,
      brightness: Brightness.dark,
    );

    final effectiveScheme = wallpaperDynamicScheme != null
        ? ColorScheme.lerp(wallpaperDynamicScheme, trackScheme, 0.65)
        : trackScheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: effectiveScheme,
      scaffoldBackgroundColor: effectiveScheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: effectiveScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: effectiveScheme.surfaceContainer,
        indicatorColor: effectiveScheme.secondaryContainer,
        height: 74,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: effectiveScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),
    );
  }
}
