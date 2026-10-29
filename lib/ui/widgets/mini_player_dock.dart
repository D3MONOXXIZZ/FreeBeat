import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../screens/now_playing_screen.dart';
import 'material_you_album_cover.dart';

class MiniPlayerDock extends ConsumerWidget {
  const MiniPlayerDock({
    super.key,
    this.width,
    this.fullWidth = false,
    this.onTap,
    this.onOpenDspStudio,
  });

  final double? width;
  final bool fullWidth;
  final VoidCallback? onTap;
  final VoidCallback? onOpenDspStudio;

  void _openNowPlaying(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    PixelHaptics.sheetExpand();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (context, animation, secondaryAnimation) =>
            NowPlayingScreen(
          onOpenDspStudio: onOpenDspStudio ?? () {},
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeOutCubic,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTrack =
        ref.watch(playbackProvider.select((p) => p.currentTrack));
    if (activeTrack.id.isEmpty) return const SizedBox.shrink();

    final isPlaying = ref.watch(playbackProvider.select((p) => p.isPlaying));
    final cs = Theme.of(context).colorScheme;
    final accentColor = cs.primary;

    final pillWidget = RepaintBoundary(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openNowPlaying(context),
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: fullWidth ? double.infinity : (width ?? 356),
            height: 58,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          MaterialYouAlbumCover(
                            track: activeTrack,
                            size: 42,
                            borderRadius: 14,
                            showQualityBadge: false,
                            showSourceBadge: false,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeTrack.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeTrack.artist,
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
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded),
                            color: cs.onSurfaceVariant,
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            tooltip: 'Previous',
                            onPressed: () {
                              PixelHaptics.tick();
                              ref.read(playbackProvider.notifier).skipPrevious();
                            },
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              backgroundColor: cs.primaryContainer,
                              foregroundColor: cs.onPrimaryContainer,
                            ),
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 19,
                            ),
                            onPressed: () {
                              PixelHaptics.tick();
                              ref
                                  .read(playbackProvider.notifier)
                                  .togglePlayPause();
                            },
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded),
                            color: cs.onSurfaceVariant,
                            iconSize: 20,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            onPressed: () {
                              PixelHaptics.tick();
                              ref.read(playbackProvider.notifier).skipNext();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 0,
                    child: RepaintBoundary(
                      child: _MiniPlayerProgressBar(
                        primaryColor: accentColor,
                        backgroundColor:
                            cs.onSurfaceVariant.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (fullWidth) {
      return pillWidget;
    }
    return Align(
      alignment: Alignment.center,
      child: pillWidget,
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
