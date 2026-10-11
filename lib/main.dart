import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/app_providers.dart';
import 'ui/screens/main_shell.dart';
import 'ui/theme/pixel_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        final theme = PixelTheme.buildDarkTheme(
          wallpaperDynamicScheme: darkDynamic,
          activeTrackSeedColor: activeTrack.dominantColor,
        );

        return MaterialApp(
          title: 'FreeBeat',
          debugShowCheckedModeBanner: false,
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.dark,
          home: const MainShell(),
        );
      },
    );
  }
}
