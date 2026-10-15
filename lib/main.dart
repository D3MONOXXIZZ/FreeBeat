import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/app_providers.dart';
import 'ui/screens/main_shell.dart';
import 'ui/theme/pixel_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Enforce true Android edge-to-edge drawing behind status & navigation bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(
    const ProviderScope(
      child: FreeBeatApp(),
    ),
  );
}

class FreeBeatApp extends ConsumerWidget {
  const FreeBeatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTrack = ref.watch(playbackProvider).currentTrack;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightTheme = PixelTheme.buildLightTheme(
          wallpaperDynamicScheme: lightDynamic,
          activeTrackSeedColor: activeTrack.dominantColor,
        );

        final darkTheme = PixelTheme.buildDarkTheme(
          wallpaperDynamicScheme: darkDynamic,
          activeTrackSeedColor: activeTrack.dominantColor,
        );

        return MaterialApp(
          title: 'FreeBeat',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.dark, // Default to Dark mode with full Light mode support
          home: const MainShell(),
        );
      },
    );
  }
}
