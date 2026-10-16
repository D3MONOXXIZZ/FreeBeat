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

/// Main Google Pixel Material 3 Navigation Shell.
/// Features:
/// - Edge-to-edge drawing with tall (82dp) M3 Navigation Bar and stadium pill indicators.
/// - Floating docked Mini-Player with 28dp corner radius, tonal elevation, squircle album art,
///   and expressive playback controls.
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
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),

          // Floating Docked Mini-Player above NavigationBar (Active playback only)
          if (playback.queue.isNotEmpty && track.id.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 10,
            child: SpringPressScale(
              onTap: _openFullNowPlaying,
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        child: Row(
                          children: [
                            // Squircle Album Artwork (14dp radius)
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [
                                    track.dominantColor,
                                    track.dominantColor.withValues(alpha: 0.55),
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
                                  color: cs.onPrimary,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Track Title (Google Sans) & Artist/Format (Roboto)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: cs.secondaryContainer,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '${track.bitDepth}-BIT',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSecondaryContainer,
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
                                            fontSize: 12,
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
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                                size: 22,
                              ),
                              onPressed: () {
                                ref
                                    .read(tracksCatalogProvider.notifier)
                                    .toggleFavorite(track.id);
                              },
                            ),

                            // Filled Tonal Play/Pause Button
                            FilledButton.tonal(
                              onPressed: () {
                                ref
                                    .read(playbackProvider.notifier)
                                    .togglePlayPause();
                              },
                              style: FilledButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: const EdgeInsets.all(10),
                                minimumSize: const Size(44, 44),
                                backgroundColor: cs.primaryContainer,
                                foregroundColor: cs.onPrimaryContainer,
                              ),
                              child: Icon(
                                playback.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 24,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Thick M3 Track Progress Bar
                      LinearProgressIndicator(
                        value: playback.progressFraction,
                        minHeight: 3,
                        backgroundColor:
                            cs.onSurfaceVariant.withValues(alpha: 0.12),
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
