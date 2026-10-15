import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/signal_path_sheet.dart';
import '../widgets/squiggly_slider.dart';

/// Full-Screen Google Pixel Material 3 Expressive Now Playing Sheet.
/// Features:
/// - Album-art-seeded adaptive gradient
/// - Live Hi-Fi / Bitrate Signal Path Badge (opens [SignalPathSheet])
/// - Interactive Time-Synced LRC Lyrics View (tap any line to seek)
/// - Animated Pixel [SquigglySlider] seekbar
/// - Morphing Play/Pause squircle button with custom Pixel LRA haptics
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
  bool _showSyncedLyrics = false;

  String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final track = playback.currentTrack;
    final quality = ref.watch(audioQualityProvider).effectiveStreamingTier;
    final dsp = ref.watch(powerampDspProvider);
    final activeLyricIdx = playback.activeLyricIndex;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              track.dominantColor.withValues(alpha: 0.45),
              cs.surface,
              cs.surfaceContainerLowest,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              children: [
                // 1. Top Bar: Collapse, Cloud Source Pill, Lyrics & EQ Toggles
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                      onPressed: () {
                        PixelHaptics.tick();
                        Navigator.of(context).pop();
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'STREAMING FROM ${track.providerType.displayName.toUpperCase()}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.album,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _showSyncedLyrics
                            ? Icons.album_rounded
                            : Icons.lyrics_rounded,
                        color: _showSyncedLyrics ? cs.primary : cs.onSurface,
                      ),
                      tooltip: 'Toggle Synced Lyrics',
                      onPressed: () {
                        PixelHaptics.tick();
                        setState(() => _showSyncedLyrics = !_showSyncedLyrics);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 2. Center Stage: Expressive Album Art OR Interactive Synced Lyrics
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: _showSyncedLyrics
                        ? _buildSyncedLyricsView(context, playback, activeLyricIdx)
                        : _buildExpressiveArtworkCard(context, track),
                  ),
                ),

                const SizedBox(height: 16),

                // 3. Interactive Hi-Fi / Bitrate Signal Path Badge
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          quality.isLossless
                              ? track.qualityBadgeText
                              : '${quality.label.toUpperCase()} • ${quality.kbps} KBPS ${quality.codec}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '• DSP ${dsp.eqEnabled ? "10-BAND" : "DIRECT"}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 4. Track Title, Artist & Favorite / Pin Actions
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${track.artist} • ${track.album}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        track.isPinnedOffline
                            ? Icons.offline_pin_rounded
                            : Icons.download_for_offline_outlined,
                        color: track.isPinnedOffline
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      onPressed: () {
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .togglePinOffline(track.id);
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        track.isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: track.isFavorite
                            ? cs.error
                            : cs.onSurfaceVariant,
                      ),
                      onPressed: () {
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .toggleFavorite(track.id);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 5. Signature Pixel Squiggly Seekbar
                SquigglySlider(
                  value: playback.progressFraction,
                  bufferedValue:
                      (playback.bufferedPositionMs / track.durationMs)
                          .clamp(0.0, 1.0),
                  isPlaying: playback.isPlaying,
                  onChanged: (fraction) {
                    final targetMs = (fraction * track.durationMs).round();
                    ref
                        .read(playbackProvider.notifier)
                        .seekToMs(targetMs);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(playback.positionMs),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        _formatDuration(track.durationMs),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

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
                      iconSize: 38,
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: () =>
                          ref.read(playbackProvider.notifier).skipPrevious(),
                    ),
                    MorphingPlayPauseButton(
                      isPlaying: playback.isPlaying,
                      size: 74,
                      onPressed: () =>
                          ref.read(playbackProvider.notifier).togglePlayPause(),
                    ),
                    IconButton(
                      iconSize: 38,
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

                const SizedBox(height: 14),

                // 7. Bottom Quick Actions: Synced Lyrics & Poweramp 10-Band EQ Studio
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        PixelHaptics.tick();
                        setState(() => _showSyncedLyrics = !_showSyncedLyrics);
                      },
                      icon: Icon(
                        Icons.lyrics_outlined,
                        size: 18,
                        color: _showSyncedLyrics ? cs.primary : cs.onSurfaceVariant,
                      ),
                      label: Text(
                        _showSyncedLyrics ? 'Show Artwork' : 'Synced Lyrics (.LRC)',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        PixelHaptics.sheetExpand();
                        Navigator.of(context).pop();
                        widget.onOpenDspStudio();
                      },
                      icon: const Icon(Icons.equalizer_rounded, size: 18),
                      label: const Text('Poweramp 10-Band EQ'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpressiveArtworkCard(BuildContext context, dynamic track) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('artwork_view'),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: cs.surfaceContainerHigh,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipPath(
                clipper: ScallopedBadgeClipper(lobes: 12, depth: 0.07),
                child: Container(
                  width: 170,
                  height: 170,
                  color: cs.primaryContainer,
                  child: Icon(
                    track.providerType.icon,
                    size: 74,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              Positioned(
                bottom: 18,
                right: 18,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${track.bitDepth}-BIT / ${(track.sampleRateHz / 1000).toInt()}kHz',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncedLyricsView(
    BuildContext context,
    PlaybackViewState playback,
    int activeIdx,
  ) {
    final cs = Theme.of(context).colorScheme;
    final lyrics = playback.currentTrack.syncedLyrics;

    return Container(
      key: const ValueKey('lyrics_view'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        itemCount: lyrics.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (context, index) {
          final line = lyrics[index];
          final isActive = index == activeIdx;
          return GestureDetector(
            onTap: () {
              PixelHaptics.tick(intensity: 0.7);
              ref
                  .read(playbackProvider.notifier)
                  .seekToMs(line.timestampMs);
            },
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 240),
              style: TextStyle(
                fontSize: isActive ? 20 : 15.5,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                color: isActive
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.65),
              ),
              child: Text(line.text),
            ),
          );
        },
      ),
    );
  }
}
