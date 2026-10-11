import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/signal_path_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onOpenNowPlaying,
    required this.onNavigateToTab,
  });

  final VoidCallback onOpenNowPlaying;
  final ValueChanged<int> onNavigateToTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tracks = ref.watch(filteredTracksProvider);
    final allTracks = ref.watch(tracksCatalogProvider);
    final accounts = ref.watch(cloudAccountsProvider);
    final selectedFilter = ref.watch(selectedCloudFilterProvider);
    final playback = ref.watch(playbackProvider);
    final quality = ref.watch(audioQualityProvider).effectiveStreamingTier;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 1. Pixel Top Header & Search Pill
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipPath(
                      clipper: ScallopedBadgeClipper(lobes: 10, depth: 0.09),
                      child: Container(
                        width: 42,
                        height: 42,
                        color: cs.primaryContainer,
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          color: cs.onPrimaryContainer,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FreeBeat',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: cs.onSurface,
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
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
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
                              quality.isLossless ? '24-BIT HI-FI' : '${quality.kbps}K',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Pixel Search Bar Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: TextField(
                    onChanged: (val) =>
                        ref.read(searchQueryProvider.notifier).state = val,
                    decoration: InputDecoration(
                      icon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
                      hintText: 'Search songs, FLAC masters, or cloud drives...',
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: Icon(Icons.tune_rounded, color: cs.primary),
                        tooltip: 'Open Poweramp 10-Band EQ Studio',
                        onPressed: () {
                          PixelHaptics.tick();
                          onNavigateToTab(2);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 2. Cloud Source Filter Strip
        SliverToBoxAdapter(
          child: SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              children: [
                PixelFilterPill(
                  label: 'All Clouds (${allTracks.length})',
                  isSelected: selectedFilter == 'all',
                  icon: Icons.cloud_done_rounded,
                  onTap: () =>
                      ref.read(selectedCloudFilterProvider.notifier).state = 'all',
                ),
                const SizedBox(width: 8),
                PixelFilterPill(
                  label: 'Pinned Offline',
                  isSelected: selectedFilter == 'offline',
                  icon: Icons.download_done_rounded,
                  onTap: () => ref
                      .read(selectedCloudFilterProvider.notifier)
                      .state = 'offline',
                ),
                const SizedBox(width: 8),
                for (final provider in [
                  CloudProviderType.googleDrive,
                  CloudProviderType.jellyfin,
                  CloudProviderType.s3,
                  CloudProviderType.oneDrive,
                  CloudProviderType.subsonic,
                  CloudProviderType.webdav,
                ]) ...[
                  PixelFilterPill(
                    label: provider.displayName,
                    isSelected: selectedFilter == provider.id,
                    icon: provider.icon,
                    accentColor: provider.accentColor,
                    onTap: () => ref
                        .read(selectedCloudFilterProvider.notifier)
                        .state = provider.id,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),

        // 3. Expressive Hero Carousel ("Jump Back In • Hi-Fi Cloud Masters")
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hi-Fi Cloud Masters',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    PixelHaptics.tick();
                    onNavigateToTab(3);
                  },
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text('Add Cloud'),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 215,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: allTracks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final track = allTracks[index];
                final isCurrent = playback.currentTrack.id == track.id;
                return _ExpressiveHeroCard(
                  track: track,
                  isCurrent: isCurrent,
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(track);
                    onOpenNowPlaying();
                  },
                );
              },
            ),
          ),
        ),

        // 4. Unified Cloud Stream List
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
            child: Text(
              'Instant Cloud Streams (${tracks.length})',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
          sliver: SliverList.separated(
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isPlayingThis = playback.currentTrack.id == track.id;
              return _CloudTrackTile(
                track: track,
                isActive: isPlayingThis,
                onTap: () {
                  ref.read(playbackProvider.notifier).playTrack(track);
                },
                onTogglePin: () {
                  ref
                      .read(tracksCatalogProvider.notifier)
                      .togglePinOffline(track.id);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExpressiveHeroCard extends StatelessWidget {
  const _ExpressiveHeroCard({
    required this.track,
    required this.isCurrent,
    required this.onTap,
  });

  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final seed = track.dominantColor;

    return SpringPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        width: 270,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              seed.withValues(alpha: 0.42),
              cs.surfaceContainerHighest,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isCurrent ? cs.primary : seed.withValues(alpha: 0.35),
            width: isCurrent ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipPath(
                  clipper: ScallopedBadgeClipper(lobes: 12, depth: 0.08),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: seed.withValues(alpha: 0.35),
                    child: Icon(
                      track.providerType.icon,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${track.bitDepth}-BIT/${(track.sampleRateHz / 1000).toInt()}k ${track.codec}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${track.artist} • ${track.providerType.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  track.isPinnedOffline
                      ? Icons.offline_pin_rounded
                      : Icons.cloud_queue_rounded,
                  size: 15,
                  color: cs.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    track.isPinnedOffline
                        ? 'Pinned Offline'
                        : '${track.bitrateKbps} kbps Direct',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
                Icon(
                  Icons.play_circle_fill_rounded,
                  color: cs.primary,
                  size: 28,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudTrackTile extends StatelessWidget {
  const _CloudTrackTile({
    required this.track,
    required this.isActive,
    required this.onTap,
    required this.onTogglePin,
  });

  final Track track;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SpringPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? cs.secondaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: track.dominantColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isActive ? Icons.equalizer_rounded : track.providerType.icon,
                color: isActive ? cs.primary : track.dominantColor,
              ),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${track.codec} ${track.bitDepth}/${(track.sampleRateHz / 1000).toInt()}k',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${track.artist} • ${track.providerType.displayName}',
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
            IconButton(
              icon: Icon(
                track.isPinnedOffline
                    ? Icons.download_done_rounded
                    : Icons.download_for_offline_outlined,
                color:
                    track.isPinnedOffline ? cs.primary : cs.onSurfaceVariant,
              ),
              tooltip: 'Pin Offline',
              onPressed: onTogglePin,
            ),
          ],
        ),
      ),
    );
  }
}
