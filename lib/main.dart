import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/app_providers.dart';
import 'ui/screens/main_shell.dart';
import 'ui/theme/pixel_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Resample touch inputs to match display vsync rate (eliminates touch desync & jitter on 90/120Hz LTPO displays)
  GestureBinding.instance.resamplingEnabled = true;

  // Enforce true Android edge-to-edge drawing behind status & navigation bars
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Set initial system overlay style respecting system brightness before first frame
  final initialBrightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  final isInitialDark = initialBrightness == Brightness.dark;
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          isInitialDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isInitialDark ? Brightness.light : Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: FreeBeatApp(),
    ),
  );
}

class FreeBeatApp extends ConsumerStatefulWidget {
  const FreeBeatApp({super.key});

  @override
  ConsumerState<FreeBeatApp> createState() => _FreeBeatAppState();
}

class _FreeBeatAppState extends ConsumerState<FreeBeatApp>
    with WidgetsBindingObserver {
  bool _isAppInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final inForeground = state == AppLifecycleState.resumed;
    if (_isAppInForeground != inForeground) {
      setState(() {
        _isAppInForeground = inForeground;
      });
    }
    if (inForeground) {
      ref.read(playbackProvider.notifier).resyncWithActivePlayer();
    }
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    final brightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Notify Riverpod and trigger root widget rebuild immediately without restart
    ref.read(systemBrightnessProvider.notifier).updateBrightness(brightness);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final activeTrackSeedColor = Color(ref.watch(
      playbackProvider.select((p) => p.currentTrack.dominantColorValue),
    ));
    final themeMode = ref.watch(themeModeProvider);
    final isPowerSaver = ref.watch(effectivePowerSaverActiveProvider);
    final powerSaverSettings = ref.watch(powerSaverProvider);
    // Explicitly watch systemBrightnessProvider to react to brightness state updates
    ref.watch(systemBrightnessProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // Explicitly generate both complete light and dark ColorSchemes
        final lightColorScheme = PixelTheme.buildLightColorScheme(
          wallpaperDynamicScheme: lightDynamic,
          activeTrackSeedColor: activeTrackSeedColor,
        );

        final darkColorScheme = PixelTheme.buildDarkColorScheme(
          wallpaperDynamicScheme: darkDynamic,
          activeTrackSeedColor: activeTrackSeedColor,
          amoledPitchBlack: isPowerSaver && powerSaverSettings.amoledPitchBlack,
        );

        final lightTheme = PixelTheme.buildThemeFromScheme(
          lightColorScheme,
          Brightness.light,
        );

        final darkTheme = PixelTheme.buildThemeFromScheme(
          darkColorScheme,
          Brightness.dark,
        );

        return TickerMode(
          enabled: _isAppInForeground,
          child: MaterialApp(
            title: 'FreeBeat',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: themeMode, // Strictly bound to ThemeMode.system by default
          builder: (context, child) {
            // Read active effective theme brightness (respects ThemeMode.system / light / dark)
            final effectiveTheme = Theme.of(context);
            final isDark = effectiveTheme.brightness == Brightness.dark;

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness: effectiveTheme.brightness,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const MainShell(),
        ),
      );
      },
    );
  }
}
