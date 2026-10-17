import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/nav_pill.dart';
import '../widgets/queue_bottom_sheet.dart';
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
    PlaybackViewState playback,
    Track track,
  ) {
    return SpringPressScale(
      onTap: _openFullNowPlaying,
      child: Container(
        height: 56,
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
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Row(
                  children: [
                    MaterialYouAlbumCover(
                      track: track,
                      size: 40,
                      borderRadius: 100,
                      showQualityBadge: false,
                      showSourceBadge: false,
                      isPlaying: playback.isPlaying,
                    ),
                    const SizedBox(width: 12),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            '${track.artist} • ${track.codec}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Previous / Rewind Button
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: cs.onSurfaceVariant,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () {
                        PixelHaptics.tick();
                        ref.read(playbackProvider.notifier).skipPrevious();
                      },
                    ),

                    // Play / Pause Circle Button
                    FilledButton(
                      onPressed: () {
                        ref.read(playbackProvider.notifier).togglePlayPause();
                      },
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(38, 38),
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                      ),
                      child: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 22,
                      ),
                    ),

                    // Skip Next Button
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      color: cs.onSurfaceVariant,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () {
                        PixelHaptics.tick();
                        ref.read(playbackProvider.notifier).skipNext();
                      },
                    ),

                    // Up Next Queue Button
                    IconButton(
                      icon: const Icon(Icons.queue_music_rounded),
                      color: cs.onSurfaceVariant,
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      tooltip: 'Up Next Queue',
                      onPressed: () {
                        PixelHaptics.sheetExpand();
                        showQueueBottomSheet(context);
                      },
                    ),
                  ],
                ),
              ),

              // Slim Track Progress Bar at bottom of mini player
              Positioned(
                left: 20,
                right: 20,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: playback.progressFraction,
                  minHeight: 2.5,
                  backgroundColor:
                      cs.onSurfaceVariant.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
            ],
          ),
        ),
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Floating Docked Mini-Player Pill (Active playback only)
              if (playback.queue.isNotEmpty && track.id.isNotEmpty) ...[
                _buildMiniPlayerPill(cs, playback, track),
                const SizedBox(height: 8),
              ],

              // Material 3 Expressive Floating Navigation Pill
              MaterialYouNavPill(
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

              // Signature Android Pixel Gesture Pill
              const AndroidGestureHandle(),
            ],
          ),
        ),
      ),
    );
  }
}
