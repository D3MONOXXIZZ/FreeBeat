import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import 'clouds_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'poweramp_dsp_screen.dart';

/// Main Google Pixel Material 3 Expressive Navigation Shell.
/// Features:
/// - Layered M3 Expressive destinations
/// - Spotify-style floating docked Mini-Player with squircle album art,
///   favorite heart toggle, audio route badge, and squiggly progress line.
/// - Authentic M3 Expressive navigation bar with pill indicators.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  void _openFullNowPlaying() {
    PixelHaptics.sheetExpand();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            NowPlayingScreen(
          onOpenDspStudio: () {
            setState(() => _selectedIndex = 2);
          },
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final track = playback.currentTrack;

    final pages = [
      HomeScreen(
        onOpenNowPlaying: _openFullNowPlaying,
        onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
      ),
      const LibraryScreen(),
      const PowerampDspScreen(),
      const CloudsScreen(),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),

            // Spotify-Style Floating Docked Mini-Player above NavigationBar
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: SpringPressScale(
                onTap: _openFullNowPlaying,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                          child: Row(
                            children: [
                              // Squircle Album Artwork with Dominant Seed Color
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    colors: [
                                      track.dominantColor,
                                      track.dominantColor.withValues(alpha: 0.5),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    playback.isPlaying
                                        ? Icons.equalizer_rounded
                                        : track.providerType.icon,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Track Title & Live Audio Route
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFC4F93B)
                                                .withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${track.bitDepth}-BIT',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFFC4F93B),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${track.artist} • ${track.providerType.displayName}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Favorite Toggle Button
                              IconButton(
                                icon: Icon(
                                  track.isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  color: track.isFavorite
                                      ? const Color(0xFFFB7185)
                                      : cs.onSurfaceVariant,
                                  size: 22,
                                ),
                                onPressed: () {
                                  ref
                                      .read(tracksCatalogProvider.notifier)
                                      .toggleFavorite(track.id);
                                },
                              ),

                              // Morphing Play/Pause Button
                              IconButton(
                                icon: Icon(
                                  playback.isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 36,
                                  color: cs.primary,
                                ),
                                onPressed: () {
                                  ref
                                      .read(playbackProvider.notifier)
                                      .togglePlayPause();
                                },
                              ),
                            ],
                          ),
                        ),

                        // Sleek Track Progress Bar
                        LinearProgressIndicator(
                          value: playback.progressFraction,
                          minHeight: 2.5,
                          backgroundColor:
                              cs.onSurfaceVariant.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) {
          PixelHaptics.tick(intensity: 0.7);
          setState(() => _selectedIndex = idx);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Your Mix',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.equalizer_rounded),
            selectedIcon: Icon(Icons.graphic_eq_rounded),
            label: 'Poweramp EQ',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_outlined),
            selectedIcon: Icon(Icons.cloud_done_rounded),
            label: 'Clouds',
          ),
        ],
      ),
    );
  }
}
