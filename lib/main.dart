import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/metadata/artwork_extractor.dart';
import 'services/metadata/artwork_palette_extractor.dart';
import 'state/app_providers.dart';
import 'ui/screens/main_shell.dart';
import 'ui/theme/pixel_theme.dart';
import 'ui/widgets/ultra_free_scroll_physics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Unlock peak display refresh rate (90Hz / 120Hz / 144Hz) on Android devices
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (e) {
      debugPrint('High refresh rate unlock note: $e');
    }
  }

  // Global release error boundary: log errors and render graceful Material You fallback
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Uncaught Flutter Error: ${details.exceptionAsString()}');
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFF94A3B8), size: 40),
              const SizedBox(height: 12),
              const Text(
                'Something unexpected occurred.',
                style: TextStyle(color: Color(0xFFE2E8F0), fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                details.exceptionAsString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Resample touch inputs to match display vsync rate (eliminates touch desync & jitter on 90/120Hz LTPO displays)
  GestureBinding.instance.resamplingEnabled = true;

  // Initialize album artwork cache directory ahead of time
  unawaited(ArtworkExtractor.init());

  // Expanded image cache capacity so 592+ library thumbnails (~49 MB at 144x144 RGBA)
  // remain resident in memory without eviction or re-decoding during fast scrolling.
  PaintingBinding.instance.imageCache.maximumSize = 1000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 * 1024 * 1024; // 120 MB

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
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    // Reclaim raster and bitmap memory immediately under OS memory pressure
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ArtworkPaletteExtractor.trimMemory(keepCount: 5);
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
            scrollBehavior: const SmoothFreeScrollBehavior(),
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

/// Provides smooth, frictionless 120Hz fluid scrolling across the entire app.
class SmoothFreeScrollBehavior extends MaterialScrollBehavior {
  const SmoothFreeScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const UltraFreeScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
