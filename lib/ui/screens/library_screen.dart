import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _segment = 'all'; // 'all', 'hires', 'offline', 'favorites'

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Text(
            'Unified Cloud Library',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            children: [
              PixelFilterPill(
                label: 'All Songs (${allTracks.length})',
                isSelected: _segment == 'all',
                icon: Icons.library_music_rounded,
                onTap: () => setState(() => _segment = 'all'),
              ),
              const SizedBox(width: 8),
              PixelFilterPill(
                label: 'Hi-Res 24-Bit',
                isSelected: _segment == 'hires',
                icon: Icons.high_quality_rounded,
                onTap: () => setState(() => _segment = 'hires'),
              ),
              const SizedBox(width: 8),
              PixelFilterPill(
                label: 'Pinned Offline',
                isSelected: _segment == 'offline',
                icon: Icons.offline_pin_rounded,
                onTap: () => setState(() => _segment = 'offline'),
              ),
              const SizedBox(width: 8),
              PixelFilterPill(
                label: 'Favorites',
                isSelected: _segment == 'favorites',
                icon: Icons.favorite_rounded,
                onTap: () => setState(() => _segment = 'favorites'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
            physics: const BouncingScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final track = filtered[index];
              final isPlaying = playback.currentTrack.id == track.id;
              return SpringPressScale(
                onTap: () {
                  ref.read(playbackProvider.notifier).playTrack(track);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? cs.secondaryContainer
                        : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            track.dominantColor.withValues(alpha: 0.22),
                        child: Icon(
                          track.providerType.icon,
                          color: track.dominantColor,
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
                            Text(
                              '${track.artist} • ${track.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${track.qualityBadgeText} • ${track.providerType.displayName}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
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
                          color: track.isFavorite
                              ? Colors.pinkAccent
                              : cs.onSurfaceVariant,
                        ),
                        onPressed: () {
                          PixelHaptics.tick();
                          ref
                              .read(tracksCatalogProvider.notifier)
                              .toggleFavorite(track.id);
                        },
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
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
