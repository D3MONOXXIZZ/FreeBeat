import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/cloud_account.dart';
import '../../providers/implementations/network_and_saf_connectors.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';

/// Unified Cloud & Offline Library Screen with Google Material 3 Expressive polish.
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
    final saf = AndroidSafConnector();
    final accounts = ref.read(cloudAccountsProvider);
    final safAccount = accounts.firstWhere(
      (a) => a.providerType == CloudProviderType.androidSaf,
      orElse: () => accounts.first,
    );
    final picked = await saf.pickSafAudioFiles(safAccount);
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
        // 1. Library Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Library',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: cs.onSurface,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _pickLocalFiles,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add Files'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. M3 Expressive Pill Filters
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            physics: const BouncingScrollPhysics(),
            children: [
              PixelFilterPill(
                label: 'All Tracks (${allTracks.length})',
                isSelected: _segment == 'all',
                icon: Icons.library_music_rounded,
                onTap: () => setState(() => _segment = 'all'),
              ),
              const SizedBox(width: 8),
              PixelFilterPill(
                label: 'Hi-Res 24-Bit',
                isSelected: _segment == 'hires',
                icon: Icons.high_quality_rounded,
                accentColor: const Color(0xFFC4F93B),
                onTap: () => setState(() => _segment = 'hires'),
              ),
              const SizedBox(width: 8),
              PixelFilterPill(
                label: 'Pinned Offline',
                isSelected: _segment == 'offline',
                icon: Icons.download_done_rounded,
                accentColor: cs.tertiary,
                onTap: () => setState(() => _segment = 'offline'),
              ),
              const SizedBox(width: 8),
              PixelFilterPill(
                label: 'Liked Songs',
                isSelected: _segment == 'favorites',
                icon: Icons.favorite_rounded,
                accentColor: const Color(0xFFFB7185),
                onTap: () => setState(() => _segment = 'favorites'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // 3. Track List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
            physics: const BouncingScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final track = filtered[index];
              final isCurrent = playback.currentTrack.id == track.id;
              final isPlaying = isCurrent && playback.isPlaying;

              return SpringPressScale(
                onTap: () {
                  ref.read(playbackProvider.notifier).playTrack(track);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? cs.surfaceContainerHigh
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: isCurrent
                        ? Border.all(color: cs.primary.withValues(alpha: 0.35))
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Squircle Thumbnail
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

                      // Title & Subtitle
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
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

                      // Duration
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          _formatTrackDuration(track.durationMs),
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
                          track.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: track.isFavorite
                              ? const Color(0xFFFB7185)
                              : cs.onSurfaceVariant,
                          size: 20,
                        ),
                        onPressed: () {
                          PixelHaptics.tick();
                          ref
                              .read(tracksCatalogProvider.notifier)
                              .toggleFavorite(track.id);
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
