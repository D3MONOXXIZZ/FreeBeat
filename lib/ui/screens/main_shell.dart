import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/nav_pill.dart';
import 'clouds_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'poweramp_dsp_screen.dart';

/// Main Google Pixel Material 3 Navigation Shell.
/// Features:
/// - Floating Material 3 Expressive Navigation Pill Bar (stadium border, 100px radius).
/// - Floating docked Mini-Player pill with album art, skip controls, and progress bar.
/// - Authentic Android Pixel system gesture navigation pill at the bottom edge.
/// - Edge-to-edge drawing with smooth background page scrolling.
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

  Widget _buildMiniPlayerPill(
    ColorScheme cs,
    bool isPlaying,
    Track track,
  ) {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: 310,
        height: 50,
        child: SpringPressScale(
          onTap: _openFullNowPlaying,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        MaterialYouAlbumCover(
                          track: track,
                          size: 36,
                          borderRadius: 100,
                          showQualityBadge: false,
                          showSourceBadge: false,
                          isPlaying: isPlaying,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title.isEmpty ? 'FreeBeat' : track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${track.artist} • ${track.codec}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Play / Pause Circle Button
                        FilledButton(
                          onPressed: () {
                            ref
                                .read(playbackProvider.notifier)
                                .togglePlayPause();
                          },
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(34, 34),
                            backgroundColor: cs.primaryContainer,
                            foregroundColor: cs.onPrimaryContainer,
                          ),
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 20,
                          ),
                        ),

                        // Skip Next Button
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded),
                          color: cs.onSurfaceVariant,
                          iconSize: 20,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          onPressed: () {
                            PixelHaptics.tick();
                            ref.read(playbackProvider.notifier).skipNext();
                          },
                        ),
                      ],
                    ),
                  ),

                  // Slim Track Progress Bar at bottom of mini player (isolated consumer)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 0,
                    child: _MiniPlayerProgressBar(
                      primaryColor: cs.primary,
                      backgroundColor:
                          cs.onSurfaceVariant.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final track = ref.watch(playbackProvider.select((p) => p.currentTrack));
    final isPlaying = ref.watch(playbackProvider.select((p) => p.isPlaying));
    final hasActiveQueue =
        ref.watch(playbackProvider.select((p) => p.queue.isNotEmpty));
    final importProgress = ref.watch(importProgressProvider);

    final pages = [
      HomeScreen(
        onOpenNowPlaying: _openFullNowPlaying,
        onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
      ),
      const LibraryScreen(),
      PowerampDspScreen(isActive: _selectedIndex == 2),
      CloudsScreen(
        onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Global Real-Time Import Progress Indicator
              if (importProgress.isImporting) ...[
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Importing (${importProgress.current}/${importProgress.total})',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                  Text(
                                    importProgress.progressPercentage,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(100),
                                child: LinearProgressIndicator(
                                  value: importProgress.total > 0
                                      ? importProgress.progressFraction
                                      : null,
                                  minHeight: 3,
                                  backgroundColor: cs.onPrimaryContainer
                                      .withValues(alpha: 0.2),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    cs.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // Floating Docked Mini-Player Pill (Active playback only)
              if (hasActiveQueue && track.id.isNotEmpty) ...[
                _buildMiniPlayerPill(cs, isPlaying, track),
                const SizedBox(height: 8),
              ],

              // Material 3 Expressive Floating Navigation Pill
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 336),
                  child: MaterialYouNavPill(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (idx) {
                      setState(() => _selectedIndex = idx);
                    },
                    destinations: const [
                      NavPillDestination(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Your Mix',
                      ),
                      NavPillDestination(
                        icon: Icons.library_music_outlined,
                        selectedIcon: Icons.library_music_rounded,
                        label: 'Library',
                      ),
                      NavPillDestination(
                        icon: Icons.equalizer_rounded,
                        selectedIcon: Icons.graphic_eq_rounded,
                        label: 'Poweramp EQ',
                      ),
                      NavPillDestination(
                        icon: Icons.cloud_outlined,
                        selectedIcon: Icons.cloud_done_rounded,
                        label: 'Clouds',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerProgressBar extends ConsumerWidget {
  const _MiniPlayerProgressBar({
    required this.primaryColor,
    required this.backgroundColor,
  });

  final Color primaryColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress =
        ref.watch(playbackProvider.select((p) => p.progressFraction));
    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      backgroundColor: backgroundColor,
      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
    );
  }
}
