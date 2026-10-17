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
    final lyrics = track.syncedLyrics;

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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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

                  // Phase 1: Secondary Action Bar (Queue, Lyrics Button, Hamburger Menu)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                      const SizedBox(width: 10),
                      _buildActionPill(
                        context: context,
                        icon: Icons.lyrics_rounded,
                        label: 'Lyrics',
                        isActive: lyrics.isNotEmpty,
                        onTap: _openFullscreenLyrics,
                      ),
                      const SizedBox(width: 10),
                      _buildActionPill(
                        context: context,
                        icon: Icons.menu_rounded,
                        label: 'More',
                        isActive: playback.isSleepTimerActive ||
                            playback.playbackSpeed != 1.0 ||
                            playback.pitch != 1.0 ||
                            playback.isLoopActive,
                        onTap: () => _showPlaybackOptionsMenu(context),
                      ),
                    ],
                  ),

                  const Spacer(flex: 1),

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

  void _showPlaybackOptionsMenu(BuildContext context) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;
    final playback = ref.read(playbackProvider);
    final track = playback.currentTrack;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.tune_rounded,
                        color: cs.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Playback Options',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(
                    playback.isSleepTimerActive
                        ? Icons.bedtime_rounded
                        : Icons.bedtime_outlined,
                    color: playback.isSleepTimerActive ? cs.primary : null,
                  ),
                  title: const Text('Sleep Timer',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    playback.isSleepTimerActive
                        ? 'Remaining: ${playback.formattedSleepTimerRemaining}'
                        : 'Turn off playback automatically',
                  ),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: playback.isSleepTimerActive
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      playback.isSleepTimerActive
                          ? playback.formattedSleepTimerRemaining
                          : 'Off',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: playback.isSleepTimerActive
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    showSleepTimerModal(context);
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.speed_rounded,
                    color: (playback.playbackSpeed != 1.0 ||
                            playback.pitch != 1.0)
                        ? cs.primary
                        : null,
                  ),
                  title: const Text('Playback Speed & Pitch',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Fine-grained tempo & pitch shifting'),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (playback.playbackSpeed != 1.0 ||
                              playback.pitch != 1.0)
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${playback.playbackSpeed.toStringAsFixed(playback.playbackSpeed % 1 == 0 ? 0 : 2)}x',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: (playback.playbackSpeed != 1.0 ||
                                playback.pitch != 1.0)
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    showPlaybackSpeedModal(context);
                  },
                ),
                ListTile(
                  leading: Icon(
                    playback.isLoopActive
                        ? Icons.repeat_on_rounded
                        : Icons.all_inclusive_rounded,
                    color: playback.isLoopActive ? cs.primary : null,
                  ),
                  title: const Text('A-B Repeat Loop',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Loop a specific section seamlessly'),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: playback.isLoopActive
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      playback.isLoopActive ? 'Active' : 'Off',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: playback.isLoopActive
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    showABLoopModal(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('Audio Signal Path & Specs',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${track.codec} • ${track.bitDepth}-Bit • ${track.formattedSampleRate}'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const SignalPathSheet(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              size: 16,
              color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
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
