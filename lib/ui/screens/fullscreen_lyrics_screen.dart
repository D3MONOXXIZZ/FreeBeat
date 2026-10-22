import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';

/// Fullscreen Synchronized Karaoke Lyrics Screen (Google Pixel Material You Style).
/// Strictly mirrors Screen 6 in Figma inspiration:
/// - Edge-to-edge ambient gradient aura derived from current album art
/// - Karaoke-style progress typography with active line magnification
/// - Instant tap-to-seek timestamp alignment with tactile tick haptics
/// - Floating bottom mini-controls dock for uninterrupted playback control
class FullscreenLyricsScreen extends ConsumerStatefulWidget {
  const FullscreenLyricsScreen({super.key});

  @override
  ConsumerState<FullscreenLyricsScreen> createState() =>
      _FullscreenLyricsScreenState();
}

class _FullscreenLyricsScreenState
    extends ConsumerState<FullscreenLyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLyric(int index, int totalCount) {
    if (index == _lastActiveIndex || !_scrollController.hasClients) return;
    _lastActiveIndex = index;

    // Smooth auto-scroll to center the active singing line
    const itemHeight = 76.0;
    final targetOffset = (index * itemHeight) - 180.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final track = playback.currentTrack;
    final lyrics = track.syncedLyrics;
    final activeIndex = playback.activeLyricIndex;

    // Trigger auto-scroll on lyric progress change
    if (lyrics.isNotEmpty && activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLyric(activeIndex, lyrics.length);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Ambient Blurred Gradient Aura Background
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.4),
                radius: 1.4,
                colors: [
                  track.dominantColor.withValues(alpha: 0.50),
                  cs.surface.withValues(alpha: 0.90),
                  cs.surface,
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 2. Top Header with Back button, Track Title & Menu
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, size: 24),
                        onPressed: () {
                          PixelHaptics.tick();
                          Navigator.of(context).pop();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title.isEmpty ? 'Now Playing' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              track.artist.isEmpty ? 'FreeBeat' : track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'SYNCED LRC',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 3. Lyrics Scroll Area
                Expanded(
                  child: lyrics.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.lyrics_outlined,
                                    size: 32,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No Time-Synced Lyrics Found',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Place a .lrc file in your cloud folder or audio tags with [mm:ss.xx] timestamps to enable karaoke mode.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(24, 40, 24, 140),
                          itemCount: lyrics.length,
                          itemBuilder: (context, index) {
                            final line = lyrics[index];
                            final isActive = index == activeIndex;
                            final isPassed = index < activeIndex;

                            return InkWell(
                              onTap: () {
                                PixelHaptics.tick();
                                ref
                                    .read(playbackProvider.notifier)
                                    .seekToMs(line.timestampMs);
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? cs.primaryContainer.withValues(alpha: 0.35)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  line.text,
                                  style: TextStyle(
                                    fontSize: isActive ? 24 : 18,
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    height: 1.35,
                                    color: isActive
                                        ? cs.onSurface
                                        : (isPassed
                                            ? cs.onSurfaceVariant.withValues(alpha: 0.40)
                                            : cs.onSurfaceVariant.withValues(alpha: 0.65)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // 4. Floating Mini-Dock at Bottom
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SpringPressScale(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    MaterialYouAlbumCover(
                      track: track,
                      size: 42,
                      borderRadius: 12,
                      showQualityBadge: false,
                      showSourceBadge: false,
                      showPlayingAnimation: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title.isEmpty ? 'FreeBeat' : track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            track.artist.isEmpty ? 'Lossless Stream' : track.artist,
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
                    IconButton(
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 36,
                        color: cs.primary,
                      ),
                      onPressed: () {
                        PixelHaptics.playPauseToggle();
                        ref.read(playbackProvider.notifier).togglePlayPause();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
