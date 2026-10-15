import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Authentic Google Pixel Material 3 Expressive Theme.
/// Features:
/// - Deep obsidian/violet layered dark surfaces (matching M3 Expressive references)
/// - Vibrant pastel accent roles: Electric Lavender (#A78BFA), Neon Lime (#C4F93B), Coral Pink (#F472B6)
/// - Authentic Google Sans / Plus Jakarta Sans display typography
/// - Expressive 24–32dp card squircle curvature and 999dp pill chips
class PixelTheme {
  // Signature Material 3 Expressive Dark Palette Tokens
  static const Color darkBackground = Color(0xFF0C0D14);
  static const Color surfaceLowest = Color(0xFF07080D);
  static const Color surfaceLow = Color(0xFF12131D);
  static const Color surfaceDefault = Color(0xFF181A26);
  static const Color surfaceHigh = Color(0xFF222433);
  static const Color surfaceHighest = Color(0xFF2C2E42);

  static const Color accentLavender = Color(0xFFA78BFA);
  static const Color accentNeonLime = Color(0xFFC4F93B);
  static const Color accentCoral = Color(0xFFFB7185);
  static const Color accentSky = Color(0xFF38BDF8);

  static ThemeData buildDarkTheme({
    ColorScheme? wallpaperDynamicScheme,
    required Color activeTrackSeedColor,
  }) {
    final trackScheme = ColorScheme.fromSeed(
      seedColor: activeTrackSeedColor,
      brightness: Brightness.dark,
    );

    final dynamicPrimary = Color.lerp(accentLavender, trackScheme.primary, 0.35)!;

    // Merge dynamic seed with high-contrast Expressive surfaces
    final effectiveScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: dynamicPrimary,
      onPrimary: const Color(0xFF1E1035),
      primaryContainer: const Color(0xFF372857),
      onPrimaryContainer: const Color(0xFFEDE9FE),
      secondary: accentNeonLime,
      onSecondary: const Color(0xFF142400),
      secondaryContainer: const Color(0xFF274205),
      onSecondaryContainer: const Color(0xFFE2F899),
      tertiary: accentCoral,
      onTertiary: const Color(0xFF4C0519),
      tertiaryContainer: const Color(0xFF70132B),
      onTertiaryContainer: const Color(0xFFFFDDE4),
      error: const Color(0xFFFFB4AB),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: darkBackground,
      onSurface: const Color(0xFFF1F0F7),
      onSurfaceVariant: const Color(0xFFC7C5D5),
      outline: const Color(0xFF767487),
      outlineVariant: const Color(0xFF454556),
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: const Color(0xFFE3E2E9),
      onInverseSurface: const Color(0xFF1B1B21),
      inversePrimary: const Color(0xFF6D28D9),
      surfaceContainerLowest: surfaceLowest,
      surfaceContainerLow: surfaceLow,
      surfaceContainer: surfaceDefault,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHighest,
    );

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ).copyWith(
      displayLarge: GoogleFonts.outfit(
        fontSize: 34,
        fontWeight: FontWeight.w900,
        letterSpacing: -1.0,
        color: effectiveScheme.onSurface,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: effectiveScheme.onSurface,
      ),
      headlineLarge: GoogleFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: effectiveScheme.onSurface,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: effectiveScheme.onSurface,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: effectiveScheme.onSurface,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: effectiveScheme.onSurface,
      ),
      bodyLarge: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: effectiveScheme.onSurface,
      ),
      bodyMedium: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: effectiveScheme.onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: effectiveScheme,
      scaffoldBackgroundColor: effectiveScheme.surface,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: effectiveScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: effectiveScheme.surfaceContainerLowest,
        indicatorColor: effectiveScheme.primaryContainer,
        height: 76,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? effectiveScheme.onSurface
                : effectiveScheme.onSurfaceVariant,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: effectiveScheme.surfaceContainerHigh,
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
