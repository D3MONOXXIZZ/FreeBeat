import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/add_to_playlist_modal.dart';
import 'track_details_screen.dart';

/// Stock Google Pixel Material 3 Expressive Artist Details Page.
/// Features:
/// - Hero Artist Avatar with tonal elevation and vinyl grooves
/// - "Play All" and "Shuffle" M3 stadium buttons with Pixel haptics
/// - Horizontal carousel of albums by this artist
/// - Grouped track list with Material You album covers and 3-dots options
/// - Format and quality profile card
class ArtistDetailsScreen extends ConsumerWidget {
  const ArtistDetailsScreen({
    super.key,
    required this.artistName,
  });

  final String artistName;

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = (totalSec % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final allTracks = ref.watch(tracksCatalogProvider);
    final artistTracks = allTracks.where((t) {
      return t.artist.trim().toLowerCase() == artistName.trim().toLowerCase();
    }).toList();

    // Unique albums by this artist
    final albumMap = <String, List<Track>>{};
    for (final t in artistTracks) {
      final alb = t.album.trim().isEmpty ? 'Single / Unknown' : t.album.trim();
      albumMap.putIfAbsent(alb, () => []).add(t);
    }

    final playback = ref.watch(playbackProvider);

    // Audio format counts
    final hiResCount = artistTracks.where((t) => t.isHiRes).length;
    final losslessCount =
        artistTracks.where((t) => t.isLossless && !t.isHiRes).length;
    final lossyCount = artistTracks.where((t) => !t.isLossless).length;

    final repTrack = artistTracks.isNotEmpty
        ? artistTracks.first
        : PlaybackViewState.emptyTrack;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ─────────────────────────────────────────────────────────────────
          // 1. M3 Large Collapsing App Bar
          // ─────────────────────────────────────────────────────────────────
          SliverAppBar.large(
            title: Text(artistName),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: 'Share Artist',
                onPressed: () {
                  PixelHaptics.tick();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ─────────────────────────────────────────────────────────────────
          // 2. Hero Artist Banner & Stats
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Large circular artist avatar
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.surfaceContainerHigh,
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.35),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.2),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: MaterialYouAlbumCover(
                        track: repTrack,
                        size: 104,
                        borderRadius: 52,
                        showQualityBadge: false,
                        showSourceBadge: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    artistName,
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${artistTracks.length} Songs • ${albumMap.length} Albums',
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Play All & Shuffle Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: artistTracks.isEmpty
                            ? null
                            : () {
                                PixelHaptics.playPauseToggle();
                                ref
                                    .read(playbackProvider.notifier)
                                    .playTrack(artistTracks.first,
                                        newQueue: artistTracks);
                              },
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text('Play All'),
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
                        onPressed: artistTracks.isEmpty
                            ? null
                            : () {
                                PixelHaptics.tick();
                                final shuffled = List<Track>.from(artistTracks)
                                  ..shuffle();
                                ref
                                    .read(playbackProvider.notifier)
                                    .playTrack(shuffled.first,
                                        newQueue: shuffled);
                              },
                        icon: const Icon(Icons.shuffle_rounded, size: 20),
                        label: const Text('Shuffle'),
                        style: FilledButton.styleFrom(
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
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
          // 3. Albums by this Artist
          // ─────────────────────────────────────────────────────────────────
          if (albumMap.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.album_rounded, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Albums',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${albumMap.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: albumMap.entries.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final entry = albumMap.entries.elementAt(idx);
                    final albumName = entry.key;
                    final albumTracks = entry.value;
                    final firstTrack = albumTracks.first;

                    return SpringPressScale(
                      onTap: () {
                        PixelHaptics.tick();
                        ref
                            .read(playbackProvider.notifier)
                            .playTrack(firstTrack, newQueue: albumTracks);
                      },
                      child: SizedBox(
                        width: 116,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MaterialYouAlbumCover(
                              track: firstTrack,
                              size: 116,
                              borderRadius: 20,
                              showQualityBadge: false,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              albumName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${albumTracks.length} songs',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          // ─────────────────────────────────────────────────────────────────
          // 4. Grouped Tracks List
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Songs',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${artistTracks.length} tracks',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    children: [
                      for (int i = 0; i < artistTracks.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 74,
                            endIndent: 16,
                            color: cs.outlineVariant.withValues(alpha: 0.25),
                          ),
                        _ArtistTrackTile(
                          track: artistTracks[i],
                          isCurrent: playback.currentTrack.id == artistTracks[i].id,
                          isPlaying:
                              playback.currentTrack.id == artistTracks[i].id &&
                                  playback.isPlaying,
                          durationText:
                              _formatDuration(artistTracks[i].durationMs),
                          onTap: () {
                            ref
                                .read(playbackProvider.notifier)
                                .playTrack(artistTracks[i], newQueue: artistTracks);
                          },
                          onOpenDetails: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TrackDetailsScreen(
                                  track: artistTracks[i],
                                ),
                              ),
                            );
                          },
                          onAddToPlaylist: () {
                            showAddToPlaylistModal(context, artistTracks[i]);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 5. Audio Quality Profile Card
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.high_quality_rounded,
                            size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Library Audio Profile',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _FormatPill(
                          label: '$hiResCount Hi-Res 24-Bit',
                          isHighlighted: hiResCount > 0,
                        ),
                        const SizedBox(width: 8),
                        _FormatPill(
                          label: '$losslessCount 16-Bit FLAC',
                          isHighlighted: losslessCount > 0,
                        ),
                        if (lossyCount > 0) ...[
                          const SizedBox(width: 8),
                          _FormatPill(
                            label: '$lossyCount Standard Audio',
                            isHighlighted: false,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

class _ArtistTrackTile extends StatelessWidget {
  const _ArtistTrackTile({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationText,
    required this.onTap,
    required this.onOpenDetails,
    required this.onAddToPlaylist,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onOpenDetails;
  final VoidCallback onAddToPlaylist;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            MaterialYouAlbumCover(
              track: track,
              size: 48,
              borderRadius: 14,
              showQualityBadge: false,
              showSourceBadge: false,
              isPlaying: isPlaying,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          track.codec,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${track.album} • $durationText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.playlist_add_rounded, size: 22),
              tooltip: 'Add to Playlist',
              onPressed: () {
                PixelHaptics.tick();
                onAddToPlaylist();
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline_rounded, size: 20),
              tooltip: 'Track Details',
              onPressed: () {
                PixelHaptics.tick();
                onOpenDetails();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatPill extends StatelessWidget {
  const _FormatPill({
    required this.label,
    required this.isHighlighted,
  });

  final String label;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isHighlighted
            ? cs.primaryContainer
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isHighlighted ? FontWeight.w800 : FontWeight.w600,
          color: isHighlighted
              ? cs.onPrimaryContainer
              : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
