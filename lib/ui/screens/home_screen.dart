import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/signal_path_sheet.dart';

/// Stock Google Pixel Material 3 Expressive Home Screen.
/// Strictly implements:
/// 1. M3 Large Top App Bar (`SliverAppBar.large`) that collapses and tints on scroll.
/// 2. Stadium-pill filter chips with Monet accent indicators.
/// 3. Spotify-style 2-column quick access grid with 28dp tonal cards.
/// 4. "Your Mix" editorial hero carousel with 28dp squircle curvature and tonal elevation.
/// 5. "Jump back in" track collection grouped inside a unified 28dp `surfaceContainerLow` card
///    (matching Google Pixel Settings / Clock grouped item layout).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpenNowPlaying,
    required this.onNavigateToTab,
  });

  final VoidCallback onOpenNowPlaying;
  final ValueChanged<int> onNavigateToTab;

  String _formatTrackDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tracks = ref.watch(filteredTracksProvider);
    final allTracks = ref.watch(tracksCatalogProvider);
    final accounts = ref.watch(cloudAccountsProvider);
    final selectedFilter = ref.watch(selectedCloudFilterProvider);
    final playback = ref.watch(playbackProvider);
    final quality = ref.watch(audioQualityProvider).effectiveStreamingTier;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ─────────────────────────────────────────────────────────────────────
        // 1. Collapsing M3 Large Top App Bar (Pixel System App Header)
        // ─────────────────────────────────────────────────────────────────────
        SliverAppBar.large(
          title: Text(
            'Your Mix',
            style: textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            // Hi-Fi Quality Status Tonal Pill
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.tonal(
                onPressed: () {
                  PixelHaptics.sheetExpand();
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const SignalPathSheet(),
                  );
                },
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: const StadiumBorder(),
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.high_quality_rounded,
                      size: 16,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      quality.isLossless ? 'HI-FI' : '${quality.kbps}K',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Poweramp EQ Quick Launch Button
            IconButton(
              icon: Icon(Icons.tune_rounded, color: cs.onSurface),
              tooltip: 'Poweramp 10-Band EQ',
              onPressed: () {
                PixelHaptics.tick();
                onNavigateToTab(2);
              },
            ),

            // Profile Avatar with dynamic Monet gradient
            Padding(
              padding: const EdgeInsets.only(right: 16, left: 4),
              child: SpringPressScale(
                onTap: () {
                  PixelHaptics.tick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'FreeBeat Audiophile Profile • ${accounts.length} Clouds Connected',
                      ),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 2. M3 Expressive Pill Filters Row (Stadium Shapes, Zero Shadows)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              physics: const BouncingScrollPhysics(),
              children: [
                _PixelPillFilter(
                  label: 'All Tracks',
                  isSelected: selectedFilter == 'all',
                  icon: Icons.all_inclusive_rounded,
                  onTap: () => ref
                      .read(selectedCloudFilterProvider.notifier)
                      .state = 'all',
                ),
                const SizedBox(width: 8),
                _PixelPillFilter(
                  label: 'Lossless Hi-Fi',
                  isSelected: selectedFilter == 'hifi',
                  icon: Icons.graphic_eq_rounded,
                  onTap: () => ref
                      .read(selectedCloudFilterProvider.notifier)
                      .state = selectedFilter == 'hifi' ? 'all' : 'hifi',
                ),
                const SizedBox(width: 8),
                _PixelPillFilter(
                  label: 'Pinned Offline',
                  isSelected: selectedFilter == 'offline',
                  icon: Icons.download_done_rounded,
                  onTap: () => ref
                      .read(selectedCloudFilterProvider.notifier)
                      .state = selectedFilter == 'offline' ? 'all' : 'offline',
                ),
                const SizedBox(width: 8),
                for (final provider in [
                  CloudProviderType.googleDrive,
                  CloudProviderType.jellyfin,
                  CloudProviderType.s3,
                  CloudProviderType.oneDrive,
                  CloudProviderType.subsonic,
                ]) ...[
                  _PixelPillFilter(
                    label: provider.displayName,
                    isSelected: selectedFilter == provider.id,
                    icon: provider.icon,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == provider.id
                            ? 'all'
                            : provider.id,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 3. Spotify-Style 2-Column Quick Access Grid (24-28dp Tonal Cards)
        // ─────────────────────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 64,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildListDelegate([
              // 1. Liked Songs
              _PixelQuickCard(
                title: 'Liked Songs',
                subtitle:
                    '${allTracks.where((t) => t.isFavorite).length} favorites',
                icon: Icons.favorite_rounded,
                accentColor: cs.tertiary,
                onTap: () {
                  final fav = allTracks.firstWhere(
                    (t) => t.isFavorite,
                    orElse: () => allTracks.first,
                  );
                  ref.read(playbackProvider.notifier).playTrack(fav);
                  onOpenNowPlaying();
                },
              ),
              // 2. Astral Meadow
              if (allTracks.isNotEmpty)
                _PixelQuickCard(
                  title: allTracks[0].title,
                  subtitle: allTracks[0].artist,
                  icon: Icons.music_note_rounded,
                  accentColor: cs.primary,
                  isPlaying: playback.currentTrack.id == allTracks[0].id &&
                      playback.isPlaying,
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(allTracks[0]);
                  },
                ),
              // 3. Blue Crane / Down My Limbs
              if (allTracks.length > 1)
                _PixelQuickCard(
                  title: allTracks[1].title,
                  subtitle: allTracks[1].artist,
                  icon: Icons.album_rounded,
                  accentColor: cs.secondary,
                  isPlaying: playback.currentTrack.id == allTracks[1].id &&
                      playback.isPlaying,
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(allTracks[1]);
                  },
                ),
              // 4. Google Drive Masters
              _PixelQuickCard(
                title: 'Google Drive',
                subtitle: '24-Bit FLAC Vault',
                icon: Icons.add_to_drive_rounded,
                accentColor: const Color(0xFF4285F4),
                onTap: () {
                  ref.read(selectedCloudFilterProvider.notifier).state =
                      CloudProviderType.googleDrive.id;
                },
              ),
              // 5. Jellyfin Server
              _PixelQuickCard(
                title: 'Jellyfin Server',
                subtitle: 'Direct Play • 192k',
                icon: Icons.dns_rounded,
                accentColor: const Color(0xFFAA5CC3),
                onTap: () {
                  ref.read(selectedCloudFilterProvider.notifier).state =
                      CloudProviderType.jellyfin.id;
                },
              ),
              // 6. Poweramp EQ
              _PixelQuickCard(
                title: 'Poweramp EQ',
                subtitle: '10-Band DSP Studio',
                icon: Icons.graphic_eq_rounded,
                accentColor: cs.primary,
                onTap: () => onNavigateToTab(2),
              ),
            ]),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 4. "Your Mix" Carousel Section (28dp Corner Radius, Tonal Elevation)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Your Mix',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Hi-Fi',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                // Circular Play Button
                SpringPressScale(
                  onTap: () {
                    if (allTracks.isNotEmpty) {
                      ref
                          .read(playbackProvider.notifier)
                          .playTrack(allTracks.first);
                    }
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                    ),
                    child: Icon(
                      playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: cs.onPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Horizontal Carousel of 28dp Rounded Mix Cards
        SliverToBoxAdapter(
          child: SizedBox(
            height: 236,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: allTracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final track = allTracks[index];
                final isCurrent = playback.currentTrack.id == track.id;
                return _PixelMixCard(
                  track: track,
                  isCurrent: isCurrent,
                  isPlaying: isCurrent && playback.isPlaying,
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(track);
                    onOpenNowPlaying();
                  },
                );
              },
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 5. "Jump Back In" Grouped Card (Stock Pixel Settings / Clock Style)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jump back in',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${tracks.length} tracks',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),

        // Grouped 28dp Surface Card for Track List
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
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
                    for (int i = 0; i < tracks.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 74,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                        ),
                      _PixelTrackTile(
                        track: tracks[i],
                        isCurrent: playback.currentTrack.id == tracks[i].id,
                        isPlaying: playback.currentTrack.id == tracks[i].id &&
                            playback.isPlaying,
                        durationText:
                            _formatTrackDuration(tracks[i].durationMs),
                        onTap: () {
                          ref
                              .read(playbackProvider.notifier)
                              .playTrack(tracks[i]);
                        },
                        onToggleFavorite: () {
                          ref
                              .read(tracksCatalogProvider.notifier)
                              .toggleFavorite(tracks[i].id);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-components: Strictly styled for Material 3 Expressive
// ─────────────────────────────────────────────────────────────────────────────

class _PixelPillFilter extends StatelessWidget {
  const _PixelPillFilter({
    required this.label,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.secondaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? cs.secondary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? cs.onSecondaryContainer
                  : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? cs.onSecondaryContainer
                    : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelQuickCard extends StatelessWidget {
  const _PixelQuickCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.isPlaying = false,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPlaying
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.35),
            width: isPlaying ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon squircle (14dp radius)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Icon(
                  isPlaying ? Icons.equalizer_rounded : icon,
                  color: accentColor,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
          ],
        ),
      ),
    );
  }
}

class _PixelMixCard extends StatelessWidget {
  const _PixelMixCard({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: SizedBox(
        width: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 28dp Rounded Card (Tonal Elevation, NO Black Drop Shadow)
            Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: cs.surfaceContainerHigh,
                border: Border.all(
                  color: isCurrent
                      ? cs.primary
                      : cs.outlineVariant.withValues(alpha: 0.4),
                  width: isCurrent ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.equalizer_rounded
                            : track.providerType.icon,
                        color: cs.onPrimaryContainer,
                        size: 30,
                      ),
                    ),
                  ),
                  // Hi-Res Badge
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${track.bitDepth}-BIT',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
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
    );
  }
}

class _PixelTrackTile extends StatelessWidget {
  const _PixelTrackTile({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationText,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Album art squircle (14dp radius)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: cs.surfaceContainerHighest,
              ),
              child: Center(
                child: Icon(
                  isPlaying ? Icons.equalizer_rounded : track.providerType.icon,
                  color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Title & Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
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
                          '${track.artist} • $durationText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Favorite Button
            IconButton(
              icon: Icon(
                track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: track.isFavorite ? cs.error : cs.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}
