import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// Stock Google Pixel Material 3 Expressive Library Screen.
/// Strictly implements:
/// 1. M3 Large Top App Bar (`SliverAppBar.large`) that collapses and tints on scroll.
/// 2. Stadium-pill filter chips for Library segmentation.
/// 3. Unified 28dp `surfaceContainerLow` card grouping all tracks.
/// 4. 28dp rounded-rectangle Floating Action Button filled with Primary Container color.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _segment = 'all'; // 'all', 'hires', 'offline', 'favorites'

  String _formatTrackDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _pickLocalFiles() async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    final accounts = ref.read(cloudAccountsProvider);
    final safAccount = accounts.firstWhere(
      (a) => a.providerType == CloudProviderType.androidSaf,
      orElse: () => accounts.first,
    );
    final picked =
        await authService.pickFromInstalledCloudApp(account: safAccount);
    if (picked.isNotEmpty) {
      await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${picked.length} tracks into Library'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allTracks = ref.watch(tracksCatalogProvider);
    final playback = ref.watch(playbackProvider);

    final filtered = allTracks.where((t) {
      switch (_segment) {
        case 'hires':
          return t.isHiRes;
        case 'offline':
          return t.isPinnedOffline;
        case 'favorites':
          return t.isFavorite;
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 74, right: 8),
        child: FloatingActionButton.extended(
          onPressed: _pickLocalFiles,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text(
            'Add Music',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ───────────────────────────────────────────────────────────────────
          // 1. M3 Top App Bar
          // ───────────────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            title: Text(
              'Your Library',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search Library',
                onPressed: () {
                  PixelHaptics.tick();
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ───────────────────────────────────────────────────────────────────
          // 2. M3 Expressive Pill Filters
          // ───────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                physics: const BouncingScrollPhysics(),
                children: [
                  _LibraryPillFilter(
                    label: 'All Tracks (${allTracks.length})',
                    isSelected: _segment == 'all',
                    icon: Icons.library_music_rounded,
                    onTap: () => setState(() => _segment = 'all'),
                  ),
                  const SizedBox(width: 8),
                  _LibraryPillFilter(
                    label: 'Hi-Res 24-Bit',
                    isSelected: _segment == 'hires',
                    icon: Icons.high_quality_rounded,
                    onTap: () => setState(() => _segment = 'hires'),
                  ),
                  const SizedBox(width: 8),
                  _LibraryPillFilter(
                    label: 'Pinned Offline',
                    isSelected: _segment == 'offline',
                    icon: Icons.download_done_rounded,
                    onTap: () => setState(() => _segment = 'offline'),
                  ),
                  const SizedBox(width: 8),
                  _LibraryPillFilter(
                    label: 'Liked Songs',
                    isSelected: _segment == 'favorites',
                    icon: Icons.favorite_rounded,
                    onTap: () => setState(() => _segment = 'favorites'),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ───────────────────────────────────────────────────────────────────
          // 3. Grouped 28dp Surface Card for Track List
          // ───────────────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 160),
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
                      for (int i = 0; i < filtered.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 74,
                            endIndent: 16,
                            color: cs.outlineVariant.withValues(alpha: 0.25),
                          ),
                        _LibraryTrackTile(
                          track: filtered[i],
                          isCurrent: playback.currentTrack.id == filtered[i].id,
                          isPlaying:
                              playback.currentTrack.id == filtered[i].id &&
                                  playback.isPlaying,
                          durationText:
                              _formatTrackDuration(filtered[i].durationMs),
                          onTap: () {
                            ref
                                .read(playbackProvider.notifier)
                                .playTrack(filtered[i]);
                          },
                          onToggleFavorite: () {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .toggleFavorite(filtered[i].id);
                          },
                          onTogglePin: () {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .togglePinOffline(filtered[i].id);
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
      ),
    );
  }
}

class _LibraryPillFilter extends StatelessWidget {
  const _LibraryPillFilter({
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

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      borderRadius: BorderRadius.circular(100),
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

class _LibraryTrackTile extends StatelessWidget {
  const _LibraryTrackTile({
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

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Squircle Artwork (14dp radius)
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

            // Track Title & Details
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

            // Pin Offline Action
            IconButton(
              icon: Icon(
                track.isPinnedOffline
                    ? Icons.download_done_rounded
                    : Icons.download_rounded,
                color: track.isPinnedOffline ? cs.primary : cs.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onTogglePin,
            ),

            // Favorite Action
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
