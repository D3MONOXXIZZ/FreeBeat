import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/ab_loop_modal.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/nav_pill.dart';
import '../widgets/playback_speed_modal.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/signal_path_sheet.dart';
import '../widgets/sleep_timer_modal.dart';
import '../widgets/waveform_seekbar.dart';
import 'artist_details_screen.dart';
import 'fullscreen_lyrics_screen.dart';
import 'track_details_screen.dart';

/// Full-Screen Google Pixel Material 3 Expressive Now Playing Screen.
/// Strictly implements Screen 2 in Figma inspiration:
/// 1. Ambient blurred colored aura derived from current track artwork
/// 2. Top Bar: Collapse chevron, Connected Output Chip (`Pixel Buds Optimized`), and EQ icon
/// 3. Hero 32dp Squircle Artwork with ambient colored drop glow
/// 4. Track title & artist in bold Google Sans with favorite toggle
/// 5. Dynamic Multi-Bar Waveform Seekbar with micro-haptic scrubbing
/// 6. Large circular Play/Pause button with spring scale & tactile pulses
/// 7. Bottom Peekable Lyrics Drawer expanding into Fullscreen Karaoke Lyrics
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({
    super.key,
    required this.onOpenDspStudio,
  });

  final VoidCallback onOpenDspStudio;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _openFullscreenLyrics() {
    PixelHaptics.sheetExpand();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const FullscreenLyricsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
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
    final route = ref.watch(audioRouteInfoProvider);
    final quality = ref.watch(audioQualityProvider).effectiveStreamingTier;
    final lyrics = track.syncedLyrics;
    final activeLyricIdx = playback.activeLyricIndex;
    final activeLyricText = (activeLyricIdx >= 0 && activeLyricIdx < lyrics.length)
        ? lyrics[activeLyricIdx].text
        : (lyrics.isNotEmpty ? lyrics.first.text : '');

    return Scaffold(
      body: Stack(
        children: [
          // 1. Ambient Dynamic Gradient Background
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.45),
                radius: 1.35,
                colors: [
                  track.dominantColor.withValues(alpha: 0.40),
                  cs.surface.withValues(alpha: 0.95),
                  cs.surfaceContainerLowest,
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  // 2. Top Bar: Collapse, Connected Output Chip, EQ Action
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 32,
                        ),
                        onPressed: () {
                          PixelHaptics.tick();
                          Navigator.of(context).pop();
                        },
                      ),
                      // Connected Output Chip
                      SpringPressScale(
                        onTap: () {
                          PixelHaptics.sheetExpand();
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => const SignalPathSheet(),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHigh.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                route.isBluetooth
                                    ? Icons.headphones_rounded
                                    : Icons.graphic_eq_rounded,
                                size: 15,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                route.isBluetooth
                                    ? '${route.deviceName} (${route.bluetoothCodecName})'
                                    : (quality.isLossless
                                        ? 'Hi-Fi 24-Bit / 96k Direct'
                                        : '${quality.kbps}k Direct Play'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded, size: 24),
                        tooltip: 'Up Next Queue',
                        onPressed: () {
                          PixelHaptics.sheetExpand();
                          showQueueBottomSheet(context);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.info_outline_rounded, size: 24),
                        tooltip: 'Track Details',
                        onPressed: () {
                          PixelHaptics.tick();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TrackDetailsScreen(track: track),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 24),
                        tooltip: 'Poweramp EQ',
                        onPressed: () {
                          PixelHaptics.sheetExpand();
                          Navigator.of(context).pop();
                          widget.onOpenDspStudio();
                        },
                      ),
                    ],
                  ),

                  const Spacer(flex: 1),

                  // 3. Hero Album Artwork Card with Ambient Colored Drop Glow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: GestureDetector(
                        onTap: () {
                          PixelHaptics.tick();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TrackDetailsScreen(track: track),
                            ),
                          );
                        },
                        child: Hero(
                          tag: 'album_art_${track.id}',
                          child: MaterialYouAlbumCover(
                            track: track,
                            size: double.infinity,
                            borderRadius: 32,
                            showQualityBadge: true,
                            showSourceBadge: true,
                            isPlaying: playback.isPlaying,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),

                  // 4. Track Title, Artist & Actions
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title.isEmpty ? 'Ready to Stream' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                if (track.artist.isNotEmpty &&
                                    track.artist !=
                                        'Connect cloud storage or import songs') {
                                  PixelHaptics.tick();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ArtistDetailsScreen(
                                        artistName: track.artist,
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      track.artist.isEmpty
                                          ? 'Connect cloud storage or import songs'
                                          : track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (track.artist.isNotEmpty &&
                                      track.artist !=
                                          'Connect cloud storage or import songs') ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          track.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: track.isFavorite ? cs.error : cs.onSurfaceVariant,
                          size: 26,
                        ),
                        onPressed: () {
                          PixelHaptics.tick();
                          if (track.id.isNotEmpty) {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .toggleFavorite(track.id);
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 5. Dynamic Audio Waveform Seekbar
                  WaveformSeekbar(
                    progress: playback.progressFraction,
                    bufferedProgress: track.durationMs > 0
                        ? (playback.bufferedPositionMs / track.durationMs)
                            .clamp(0.0, 1.0)
                        : 0.0,
                    isPlaying: playback.isPlaying,
                    primaryColor: cs.primary,
                    onSeek: (frac) {
                      if (track.durationMs > 0) {
                        final targetMs = (frac * track.durationMs).round();
                        ref.read(playbackProvider.notifier).seekToMs(targetMs);
                      }
                    },
                  ),

                  const SizedBox(height: 6),

                  // Duration text
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(playback.positionMs),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _formatDuration(track.durationMs),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 6. Expressive Transport Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: playback.isShuffle
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).toggleShuffle(),
                      ),
                      IconButton(
                        iconSize: 42,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).skipPrevious(),
                      ),
                      // Large Circular Play/Pause Button (72dp)
                      SpringPressScale(
                        onTap: () =>
                            ref.read(playbackProvider.notifier).togglePlayPause(),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primaryContainer,
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.25),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Icon(
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 38,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        iconSize: 42,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).skipNext(),
                      ),
                      IconButton(
                        icon: Icon(
                          playback.repeatMode == 2
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: playback.repeatMode > 0
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).cycleRepeatMode(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Phase 1: Secondary Action Bar (Queue, Sleep Timer, Speed/Pitch, A-B Loop)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionPill(
                        context: context,
                        icon: Icons.queue_music_rounded,
                        label: playback.upNextQueue.isNotEmpty
                            ? 'Queue (${playback.upNextQueue.length})'
                            : 'Queue',
                        isActive: playback.upNextQueue.isNotEmpty,
                        onTap: () => showQueueBottomSheet(context),
                      ),
                      _buildActionPill(
                        context: context,
                        icon: playback.isSleepTimerActive
                            ? Icons.bedtime_rounded
                            : Icons.bedtime_outlined,
                        label: playback.isSleepTimerActive
                            ? playback.formattedSleepTimerRemaining
                            : 'Timer',
                        isActive: playback.isSleepTimerActive,
                        onTap: () => showSleepTimerModal(context),
                      ),
                      _buildActionPill(
                        context: context,
                        icon: Icons.speed_rounded,
                        label:
                            '${playback.playbackSpeed.toStringAsFixed(playback.playbackSpeed % 1 == 0 ? 0 : 2)}x',
                        isActive: playback.playbackSpeed != 1.0 ||
                            playback.pitch != 1.0,
                        onTap: () => showPlaybackSpeedModal(context),
                      ),
                      _buildActionPill(
                        context: context,
                        icon: playback.isLoopActive
                            ? Icons.repeat_on_rounded
                            : Icons.all_inclusive_rounded,
                        label: playback.isLoopActive ? 'Loop ON' : 'A-B',
                        isActive:
                            playback.isLoopActive || playback.loopPointA != null,
                        onTap: () => showABLoopModal(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 7. Bottom Peekable Lyrics Drawer
                  SpringPressScale(
                    onTap: _openFullscreenLyrics,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lyrics_rounded, size: 20, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Lyrics',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
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
                                        'LIVE',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: cs.onSecondaryContainer,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  activeLyricText.isNotEmpty
                                      ? activeLyricText
                                      : 'Tap to expand Google Style music typography',
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
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 24,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const AndroidGestureHandle(
                    margin: EdgeInsets.only(top: 6, bottom: 8),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPill({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SpringPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? cs.primaryContainer
              : cs.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isActive
                ? cs.primary.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
