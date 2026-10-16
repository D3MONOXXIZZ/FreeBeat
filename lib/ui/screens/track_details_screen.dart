import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/audio/cloud_audio_cache_service.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/material_you_album_cover.dart';
import 'artist_details_screen.dart';
import 'fullscreen_lyrics_screen.dart';

/// Stock Google Pixel Material 3 Expressive Track Details Page.
/// Displays comprehensive technical audio specs, cloud storage & cache status,
/// metadata attribution, DSP routing, and offline download controls.
class TrackDetailsScreen extends ConsumerWidget {
  const TrackDetailsScreen({
    super.key,
    required this.track,
  });

  final Track track;

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = (totalSec % 60).toString().padLeft(2, '0');
    return '$min:$sec ($ms ms)';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Unknown size';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1.0) {
      return '${mb.toStringAsFixed(1)} MB (${bytes.toString()} bytes)';
    }
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(1)} KB (${bytes.toString()} bytes)';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Watch live track state from catalog (in case of updates to cache or favorite)
    final catalog = ref.watch(tracksCatalogProvider);
    final liveTrack = catalog.firstWhere(
      (t) => t.id == track.id,
      orElse: () => track,
    );

    final playback = ref.watch(playbackProvider);
    final isPlaying = playback.isPlaying && playback.currentTrack.id == liveTrack.id;

    final cacheService = ref.watch(cloudAudioCacheServiceProvider);
    final cacheProgress = cacheService.getProgress(liveTrack.id);
    final isCached = liveTrack.isPinnedOffline ||
        (liveTrack.localCachePath != null &&
            File(liveTrack.localCachePath!).existsSync());

    final routeInfo = ref.watch(audioRouteInfoProvider);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─────────────────────────────────────────────────────────────────
          // 1. M3 Large Collapsing App Bar
          // ─────────────────────────────────────────────────────────────────
          SliverAppBar.large(
            title: const Text('Track Details'),
            actions: [
              IconButton(
                icon: Icon(
                  liveTrack.isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liveTrack.isFavorite ? cs.error : cs.onSurface,
                ),
                tooltip: 'Favorite',
                onPressed: () {
                  ref
                      .read(tracksCatalogProvider.notifier)
                      .toggleFavorite(liveTrack.id);
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ─────────────────────────────────────────────────────────────────
          // 2. Hero Album Artwork & Primary Actions
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Hero(
                      tag: 'album_art_${liveTrack.id}',
                      child: MaterialYouAlbumCover(
                        track: liveTrack,
                        size: 210,
                        borderRadius: 32,
                        showQualityBadge: true,
                        showSourceBadge: true,
                        isPlaying: isPlaying,
                        onPlayTap: () {
                          ref.read(playbackProvider.notifier).playTrack(liveTrack);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    liveTrack.title,
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: () {
                      PixelHaptics.tick();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistDetailsScreen(
                            artistName: liveTrack.artist,
                          ),
                        ),
                      );
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_rounded, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            liveTrack.artist,
                            style: textTheme.titleMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded,
                              size: 16, color: cs.primary),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    liveTrack.album,
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quick Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () {
                          if (isPlaying) {
                            ref.read(playbackProvider.notifier).togglePlayPause();
                          } else {
                            ref
                                .read(playbackProvider.notifier)
                                .playTrack(liveTrack);
                          }
                        },
                        icon: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(isPlaying ? 'Pause' : 'Play'),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          PixelHaptics.tick();
                          ref
                              .read(tracksCatalogProvider.notifier)
                              .togglePinOffline(liveTrack.id);
                        },
                        icon: Icon(
                          isCached
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                        ),
                        label: Text(
                          isCached
                              ? 'Cached'
                              : cacheProgress.state == CacheState.caching
                                  ? 'Caching ${(cacheProgress.progress * 100).toInt()}%'
                                  : 'Cache Offline',
                        ),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 3. Audio Specifications & Hi-Fi Quality
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _DetailSectionCard(
                title: 'Audio Specifications',
                icon: Icons.graphic_eq_rounded,
                children: [
                  _DetailRow(
                    label: 'Codec / Format',
                    value: liveTrack.codec.toUpperCase(),
                    badge: liveTrack.isHiRes
                        ? 'HI-RES'
                        : liveTrack.isLossless
                            ? 'LOSSLESS'
                            : 'LOSSY',
                    badgeColor: liveTrack.isHiRes
                        ? cs.primary
                        : liveTrack.isLossless
                            ? cs.secondary
                            : cs.outline,
                  ),
                  _DetailRow(
                    label: 'Bit Depth',
                    value: '${liveTrack.bitDepth}-Bit Audio',
                  ),
                  _DetailRow(
                    label: 'Sample Rate',
                    value: liveTrack.formattedSampleRate,
                  ),
                  _DetailRow(
                    label: 'Bitrate',
                    value: '${liveTrack.bitrateKbps} kbps',
                  ),
                  _DetailRow(
                    label: 'Channels',
                    value: liveTrack.channels == 1 ? 'Mono (1.0)' : 'Stereo (2.0)',
                  ),
                  _DetailRow(
                    label: 'Exact Duration',
                    value: _formatDuration(liveTrack.durationMs),
                  ),
                  _DetailRow(
                    label: 'File Size',
                    value: _formatFileSize(liveTrack.sizeBytes),
                  ),
                ],
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 4. Cloud Storage & Offline Caching
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _DetailSectionCard(
                title: 'Cloud Storage & Caching',
                icon: Icons.cloud_done_rounded,
                children: [
                  _DetailRow(
                    label: 'Provider Source',
                    value: liveTrack.providerType.displayName,
                  ),
                  _DetailRow(
                    label: 'Stream Mode',
                    value: isCached
                        ? 'Cached Offline (Zero Data Usage)'
                        : 'Direct Cloud Stream (Drive API)',
                    badge: isCached ? 'OFFLINE' : 'ONLINE',
                    badgeColor: isCached ? Colors.green : Colors.orange,
                  ),
                  _DetailRow(
                    label: 'Remote Path / ID',
                    value: liveTrack.remotePathOrId.isNotEmpty
                        ? liveTrack.remotePathOrId
                        : 'Local File',
                  ),
                  if (liveTrack.localCachePath != null &&
                      liveTrack.localCachePath!.isNotEmpty)
                    _DetailRow(
                      label: 'Local File Path',
                      value: liveTrack.localCachePath!,
                    ),
                  if (liveTrack.artworkUrl != null &&
                      liveTrack.artworkUrl!.isNotEmpty)
                    _DetailRow(
                      label: 'Album Art Source',
                      value: liveTrack.artworkUrl!,
                    ),
                ],
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 5. Signal Path & Output Route
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: _DetailSectionCard(
                title: 'Audio Output & DSP',
                icon: Icons.speaker_group_rounded,
                children: [
                  _DetailRow(
                    label: 'Active Output',
                    value: routeInfo.deviceName,
                  ),
                  _DetailRow(
                    label: 'Bluetooth Codec',
                    value: routeInfo.isBluetooth
                        ? routeInfo.bluetoothCodecName
                        : 'Direct Hardware Line / Speaker',
                  ),
                  _DetailRow(
                    label: 'Poweramp DSP EQ',
                    value: '10-Band Graphic & Tone Active',
                  ),
                ],
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 6. Lyrics Preview
          // ─────────────────────────────────────────────────────────────────
          if (liveTrack.syncedLyrics.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
                child: _DetailSectionCard(
                  title: 'Time-Synced Lyrics',
                  icon: Icons.lyrics_rounded,
                  children: [
                    Text(
                      liveTrack.syncedLyrics.take(3).map((l) => l.text).join('\n'),
                      style: textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        PixelHaptics.tick();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FullscreenLyricsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.fullscreen_rounded, size: 18),
                      label: const Text('View Full Lyrics'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

class _DetailSectionCard extends StatelessWidget {
  const _DetailSectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.badge,
    this.badgeColor,
  });

  final String label;
  final String value;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? cs.primary).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (badgeColor ?? cs.primary).withValues(alpha: 0.35),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: badgeColor ?? cs.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
