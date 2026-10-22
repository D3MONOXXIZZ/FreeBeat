import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../screens/now_playing_screen.dart';
import 'expressive_shapes.dart';
import 'material_you_album_cover.dart';

/// Floating Material You Mini Player Dock.
/// Displays active album art, track details, playback controls, and real-time progress.
class MiniPlayerDock extends ConsumerWidget {
  const MiniPlayerDock({
    super.key,
    this.width,
    this.fullWidth = true,
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
        pageBuilder: (context, animation, secondaryAnimation) =>
            NowPlayingScreen(
          onOpenDspStudio: onOpenDspStudio ?? () {},
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
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(playbackProvider.select((p) => p.currentTrack));
    final isPlaying = ref.watch(playbackProvider.select((p) => p.isPlaying));

    if (track.id.isEmpty) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;

    final pillWidget = SizedBox(
      width: fullWidth ? double.infinity : (width ?? 310),
      height: 52,
      child: SpringPressScale(
        onTap: () => _openNowPlaying(context),
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
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 16,
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
                        showPlayingAnimation: false,
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
                                fontSize: 10.5,
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
                          minWidth: 30,
                          minHeight: 30,
                        ),
                        onPressed: () {
                          PixelHaptics.tick();
                          ref.read(playbackProvider.notifier).skipNext();
                        },
                      ),
                    ],
                  ),
                ),

                // Slim Track Progress Bar at bottom of mini player
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: RepaintBoundary(
                    child: _MiniPlayerProgressBar(
                      primaryColor: cs.primary,
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
