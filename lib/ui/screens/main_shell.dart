import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/add_to_library_modal.dart';
import '../widgets/mini_player_dock.dart';
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
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
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
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildLibraryAddFab(ColorScheme cs) {
    return SizedBox(
      width: 50,
      height: 50,
      child: FloatingActionButton(
        shape: const CircleBorder(),
        elevation: 4,
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        tooltip: 'Add to Library',
        onPressed: () => showAddToLibraryModal(context, ref),
        child: const Icon(
          Icons.add_rounded,
          size: 26,
        ),
      ),
    );
  }

  Widget _buildMiniPlayerPill(
    ColorScheme cs,
    bool isPlaying,
    Track track, {
    double? width,
    bool fullWidth = false,
  }) {
    return MiniPlayerDock(
      width: width,
      fullWidth: fullWidth,
      onTap: _openFullNowPlaying,
      onOpenDspStudio: () => setState(() => _selectedIndex = 2),
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
      const LibraryScreen(showFab: false),
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
        child: RepaintBoundary(
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

              // Floating Docked Mini-Player Pill & Library Add FAB
              if (hasActiveQueue && track.id.isNotEmpty) ...[
                if (_selectedIndex == 1)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final availableWidth = constraints.maxWidth;
                      // Keep mini player centered to nav pill with safe clearance for the 50dp right-aligned FAB
                      final maxHalfWidth = (availableWidth / 2) - 58;
                      final pillWidth = (maxHalfWidth * 2).clamp(230.0, 268.0);
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Center(
                            child: _buildMiniPlayerPill(
                              cs,
                              isPlaying,
                              track,
                              width: pillWidth,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            child: _buildLibraryAddFab(cs),
                          ),
                        ],
                      );
                    },
                  )
                else
                  _buildMiniPlayerPill(
                    cs,
                    isPlaying,
                    track,
                    width: 310,
                  ),
                const SizedBox(height: 8),
              ] else if (_selectedIndex == 1) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildLibraryAddFab(cs),
                ),
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
                        label: 'Smart EQ',
                      ),
                      NavPillDestination(
                        icon: Icons.cloud_outlined,
                        selectedIcon: Icons.cloud_done_rounded,
                        label: 'Cloud',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}
