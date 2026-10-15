import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/signal_path_sheet.dart';

/// Spotify-Style + Google Material 3 Expressive Home Screen.
/// Matches the user's reference images:
/// - Top Bar with user avatar, dynamic time-of-day greeting, and quick actions
/// - M3 Expressive Pill Filters ("All", "Lossless Hi-Fi", "Google Drive", "Jellyfin", "Offline", "Liked")
/// - Spotify-style 6-item Quick Access 2-Column Grid (Liked Songs, 24-Bit FLAC, etc.)
/// - "Your Mix" Editorial Hero Carousel with circular Play button (Direct match with Image 5)
/// - "Jump Back In" / "Recently Played" vertical track list with song durations ("2:34", "3:34", etc.)
/// - "Browse Clouds & Hi-Fi Formats" cards
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpenNowPlaying,
    required this.onNavigateToTab,
  });

  final VoidCallback onOpenNowPlaying;
  final ValueChanged<int> onNavigateToTab;

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

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
        // 1. Top Header: User Profile Avatar, Greeting, and Quick Actions
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(
              children: [
                // User Profile Avatar with M3 Expressive scalloped border
                SpringPressScale(
                  onTap: () {
                    PixelHaptics.tick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('FreeBeat Audiophile Profile • ${accounts.length} Clouds Connected'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    );
                  },
                  child: Stack(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [cs.primary, cs.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person_rounded,
                            color: cs.onPrimary,
                            size: 26,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC4F93B), // Neon Lime online dot
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Greeting & Hi-Fi Status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getTimeGreeting(),
                        style: textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        '${accounts.length} Clouds Mounted • ${quality.shortBadge}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                // High-Quality Signal Path Badge
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.high_quality_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          quality.isLossless ? 'HI-FI' : '${quality.kbps}K',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Poweramp 10-Band EQ Quick Launch Button
                IconButton(
                  icon: Icon(Icons.tune_rounded, color: cs.onSurface),
                  tooltip: 'Poweramp 10-Band EQ',
                  onPressed: () {
                    PixelHaptics.tick();
                    onNavigateToTab(2);
                  },
                ),
              ],
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 2. M3 Expressive Pill Filters Row (Spotify Style)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              physics: const BouncingScrollPhysics(),
              children: [
                PixelFilterPill(
                  label: 'All Tracks',
                  isSelected: selectedFilter == 'all',
                  icon: Icons.all_inclusive_rounded,
                  onTap: () =>
                      ref.read(selectedCloudFilterProvider.notifier).state = 'all',
                ),
                const SizedBox(width: 8),
                PixelFilterPill(
                  label: 'Lossless Hi-Fi',
                  isSelected: selectedFilter == 'hifi',
                  icon: Icons.graphic_eq_rounded,
                  accentColor: const Color(0xFFC4F93B),
                  onTap: () => ref
                      .read(selectedCloudFilterProvider.notifier)
                      .state = selectedFilter == 'hifi' ? 'all' : 'hifi',
                ),
                const SizedBox(width: 8),
                PixelFilterPill(
                  label: 'Pinned Offline',
                  isSelected: selectedFilter == 'offline',
                  icon: Icons.download_done_rounded,
                  accentColor: cs.tertiary,
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
                  PixelFilterPill(
                    label: provider.displayName,
                    isSelected: selectedFilter == provider.id,
                    icon: provider.icon,
                    accentColor: provider.accentColor,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = selectedFilter == provider.id ? 'all' : provider.id,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 3. Spotify-Style 2-Column Quick-Access Grid (6 cards)
        // ─────────────────────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 60,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildListDelegate([
              // 1. Liked Songs
              SpotifyQuickCard(
                title: 'Liked Songs',
                subtitle: '${allTracks.where((t) => t.isFavorite).length} favorites',
                icon: Icons.favorite_rounded,
                accentColor: const Color(0xFF7C3AED),
                onTap: () {
                  final fav = allTracks.firstWhere(
                    (t) => t.isFavorite,
                    orElse: () => allTracks.first,
                  );
                  ref.read(playbackProvider.notifier).playTrack(fav);
                  onOpenNowPlaying();
                },
              ),
              // 2. Astral Meadow (First Track)
              if (allTracks.isNotEmpty)
                SpotifyQuickCard(
                  title: allTracks[0].title,
                  subtitle: allTracks[0].artist,
                  icon: Icons.music_note_rounded,
                  accentColor: allTracks[0].dominantColor,
                  isPlaying: playback.currentTrack.id == allTracks[0].id && playback.isPlaying,
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(allTracks[0]);
                  },
                ),
              // 3. Blue Crane (Second Track)
              if (allTracks.length > 1)
                SpotifyQuickCard(
                  title: allTracks[1].title,
                  subtitle: allTracks[1].artist,
                  icon: Icons.album_rounded,
                  accentColor: allTracks[1].dominantColor,
                  isPlaying: playback.currentTrack.id == allTracks[1].id && playback.isPlaying,
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(allTracks[1]);
                  },
                ),
              // 4. Google Drive Masters
              SpotifyQuickCard(
                title: 'Google Drive',
                subtitle: '24-Bit FLAC Vault',
                icon: Icons.add_to_drive_rounded,
                accentColor: const Color(0xFF0F9D58),
                onTap: () {
                  ref.read(selectedCloudFilterProvider.notifier).state =
                      CloudProviderType.googleDrive.id;
                },
              ),
              // 5. Jellyfin Hi-Res
              SpotifyQuickCard(
                title: 'Jellyfin Server',
                subtitle: 'Direct Play • 192k',
                icon: Icons.dns_rounded,
                accentColor: const Color(0xFF00A4DC),
                onTap: () {
                  ref.read(selectedCloudFilterProvider.notifier).state =
                      CloudProviderType.jellyfin.id;
                },
              ),
              // 6. Poweramp 10-Band EQ
              SpotifyQuickCard(
                title: 'Poweramp EQ',
                subtitle: '10-Band DSP Studio',
                icon: Icons.graphic_eq_rounded,
                accentColor: const Color(0xFFC4F93B),
                onTap: () => onNavigateToTab(2),
              ),
            ]),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 4. "Your Mix" Section (Direct visual match to Image 5)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Your Mix',
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC4F93B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Hi-Fi',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC4F93B),
                        ),
                      ),
                    ),
                  ],
                ),
                // Circular Play Button (as seen in Image 5)
                SpringPressScale(
                  onTap: () {
                    if (allTracks.isNotEmpty) {
                      ref.read(playbackProvider.notifier).playTrack(allTracks.first);
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
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

        // Horizontal Square Cards Carousel ("Astral Meadow", "Blue Crane", "Ladder to the Moon")
        SliverToBoxAdapter(
          child: SizedBox(
            height: 230,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: allTracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final track = allTracks[index];
                final isCurrent = playback.currentTrack.id == track.id;
                return _SpotifyMixCard(
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
        // 5. "Jump Back In" / "Recently Played" Track List (As in Image 5)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Jump back in',
                  style: textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  '${tracks.length} tracks',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Vertical List with Song Durations ("2:34", "3:34", "3:46", etc.)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
          sliver: SliverList.separated(
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isCurrent = playback.currentTrack.id == track.id;
              final isPlayingThis = isCurrent && playback.isPlaying;
              return _SpotifyTrackRow(
                track: track,
                isCurrent: isCurrent,
                isPlaying: isPlayingThis,
                durationText: _formatTrackDuration(track.durationMs),
                onTap: () {
                  ref.read(playbackProvider.notifier).playTrack(track);
                },
                onToggleFavorite: () {
                  ref.read(tracksCatalogProvider.notifier).toggleFavorite(track.id);
                },
                onTogglePin: () {
                  ref.read(tracksCatalogProvider.notifier).togglePinOffline(track.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Spotify-style Large Square Album Card with M3 Expressive Gradient and Tags.
class _SpotifyMixCard extends StatelessWidget {
  const _SpotifyMixCard({
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
    final seed = track.dominantColor;

    return SpringPressScale(
      onTap: onTap,
      child: SizedBox(
        width: 155,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square Artwork Container with 20dp corners
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 155,
              height: 155,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [
                    seed.withValues(alpha: 0.8),
                    seed.withValues(alpha: 0.35),
                    cs.surfaceContainerHighest,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: isCurrent ? cs.primary : Colors.white.withValues(alpha: 0.08),
                  width: isCurrent ? 2.0 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: seed.withValues(alpha: isCurrent ? 0.35 : 0.15),
                    blurRadius: isCurrent ? 16 : 8,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Center Icon / Scalloped Accent
                  Center(
                    child: ClipPath(
                      clipper: ScallopedBadgeClipper(lobes: 10, depth: 0.08),
                      child: Container(
                        width: 58,
                        height: 58,
                        color: Colors.black.withValues(alpha: 0.3),
                        child: Icon(
                          track.providerType.icon,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),

                  // Top-Right Hi-Fi Chip
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${track.bitDepth}-BIT',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  // Bottom-Right Floating Play Button
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPlaying ? cs.primary : Colors.black.withValues(alpha: 0.55),
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Track Title
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isCurrent ? cs.primary : cs.onSurface,
              ),
            ),
            const SizedBox(height: 2),

            // Artist & Album
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spotify Track Row with Duration, Artwork Thumbnail, and Material 3 Expressive state.
class _SpotifyTrackRow extends StatelessWidget {
  const _SpotifyTrackRow({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationText,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onTogglePin,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent ? cs.surfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isCurrent
              ? Border.all(color: cs.primary.withValues(alpha: 0.35))
              : null,
        ),
        child: Row(
          children: [
            // Artwork Thumbnail (48x48) with squircle corners
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: track.dominantColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: isPlaying
                    ? Icon(
                        Icons.equalizer_rounded,
                        color: cs.primary,
                        size: 24,
                      )
                    : Icon(
                        track.providerType.icon,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
            const SizedBox(width: 14),

            // Track Title & Metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          track.codec,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${track.artist} • ${track.album}',
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

            // Duration (e.g. "2:34", "3:34") as seen in Image 5
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                durationText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),

            // Favorite Button
            IconButton(
              icon: Icon(
                track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: track.isFavorite ? const Color(0xFFFB7185) : cs.onSurfaceVariant,
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
