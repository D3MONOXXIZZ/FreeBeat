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

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  void _openNowPlaying() {
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
      onTap: _openNowPlaying,
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
      TickerMode(
        enabled: _selectedIndex == 0,
        child: RepaintBoundary(
          child: HomeScreen(
            onOpenNowPlaying: _openNowPlaying,
            onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
          ),
        ),
      ),
      TickerMode(
        enabled: _selectedIndex == 1,
        child: const RepaintBoundary(
          child: LibraryScreen(showFab: false),
        ),
      ),
      TickerMode(
        enabled: _selectedIndex == 2,
        child: RepaintBoundary(
          child: PowerampDspScreen(isActive: _selectedIndex == 2),
        ),
      ),
      TickerMode(
        enabled: _selectedIndex == 3,
        child: RepaintBoundary(
          child: CloudsScreen(
            onNavigateToTab: (idx) => setState(() => _selectedIndex = idx),
          ),
        ),
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: RepaintBoundary(
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                                    Expanded(
                                      child: Text(
                                        importProgress.statusMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: cs.onPrimaryContainer,
                                        ),
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

                if (hasActiveQueue && track.id.isNotEmpty) ...[
                  if (_selectedIndex == 1)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final availableWidth = constraints.maxWidth;
                        final pillWidth =
                            (availableWidth - 116).clamp(180.0, 310.0);
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            _buildMiniPlayerPill(
                              cs,
                              isPlaying,
                              track,
                              width: pillWidth,
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
