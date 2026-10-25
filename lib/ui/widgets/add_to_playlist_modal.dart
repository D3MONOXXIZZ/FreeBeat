import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'generative_playlist_cover.dart';
import 'ultra_free_scroll_physics.dart';

/// Shows the Material 3 Expressive "Add to Playlist" bottom sheet modal.
Future<void> showAddToPlaylistModal(
  BuildContext context, [
  Track? track,
  List<Track>? tracks,
]) {
  final targetTracks = tracks ?? (track != null ? [track] : <Track>[]);
  if (targetTracks.isEmpty) return Future.value();
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddToPlaylistSheet(tracks: targetTracks),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.tracks});

  final List<Track> tracks;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  void _showCreatePlaylistDialog() {
    PixelHaptics.tick();
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text(
            'New Playlist',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Playlist Name',
                  hintText: 'e.g. Chill Beats, Gym Heavy',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  final playlist = await ref
                      .read(playlistsProvider.notifier)
                      .createPlaylist(
                        title,
                        description: descController.text.trim(),
                      );
                  // Automatically add tracks to the newly created playlist
                  await ref
                      .read(playlistsProvider.notifier)
                      .addTracksToPlaylist(
                        playlist.id,
                        widget.tracks.map((t) => t.id).toList(),
                      );
                  await PixelHaptics.hifiConfirm();
                  if (mounted) {
                    final msg = widget.tracks.length == 1
                        ? 'Added to "$title"'
                        : 'Added ${widget.tracks.length} tracks to "$title"';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(msg),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final playlists = ref.watch(playlistsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Grab handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header: Title & Track info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.playlist_add_rounded,
                      color: cs.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.tracks.length == 1
                              ? 'Add to Playlist'
                              : 'Add ${widget.tracks.length} Tracks to Playlist',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.tracks.length == 1
                              ? '${widget.tracks.first.title} • ${widget.tracks.first.artist}'
                              : '${widget.tracks.length} selected tracks from library',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _showCreatePlaylistDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.25),
            ),

            // Playlist List
            Flexible(
              child: playlists.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.queue_music_rounded,
                                size: 32,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Playlists Yet',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Create a custom playlist to start curating your lossless library.',
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _showCreatePlaylistDialog,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Create First Playlist'),
                              style: FilledButton.styleFrom(
                                shape: const StadiumBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      physics: const UltraFreeScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      itemCount: playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, idx) {
                        final playlist = playlists[idx];
                        final targetTrackIds =
                            widget.tracks.map((t) => t.id).toList();
                        final isSingle = widget.tracks.length == 1;
                        final allPresent = targetTrackIds.isNotEmpty &&
                            targetTrackIds.every(
                                (id) => playlist.trackIds.contains(id));
                        final somePresent = targetTrackIds.any(
                            (id) => playlist.trackIds.contains(id));
                        final isInPlaylist =
                            isSingle ? playlist.trackIds.contains(widget.tracks.first.id) : allPresent;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            final notifier =
                                ref.read(playlistsProvider.notifier);
                            if (isInPlaylist) {
                              if (isSingle) {
                                await notifier.removeTrackFromPlaylist(
                                  playlist.id,
                                  widget.tracks.first.id,
                                );
                              } else {
                                await notifier.removeTracksFromPlaylist(
                                  playlist.id,
                                  targetTrackIds,
                                );
                              }
                              await PixelHaptics.tick();
                              if (context.mounted) {
                                final msg = isSingle
                                    ? 'Removed from "${playlist.title}"'
                                    : 'Removed ${widget.tracks.length} tracks from "${playlist.title}"';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),
                                  ),
                                );
                              }
                            } else {
                              if (isSingle) {
                                await notifier.addTrackToPlaylist(
                                  playlist.id,
                                  widget.tracks.first.id,
                                );
                              } else {
                                await notifier.addTracksToPlaylist(
                                  playlist.id,
                                  targetTrackIds,
                                );
                              }
                              await PixelHaptics.hifiConfirm();
                              if (context.mounted) {
                                final msg = isSingle
                                    ? 'Added to "${playlist.title}"'
                                    : 'Added ${widget.tracks.length} tracks to "${playlist.title}"';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(msg),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isInPlaylist
                                  ? cs.primaryContainer.withValues(alpha: 0.28)
                                  : (somePresent && !isSingle)
                                      ? cs.secondaryContainer
                                          .withValues(alpha: 0.15)
                                      : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: GenerativePlaylistCover(
                                playlist: playlist,
                                size: 48,
                                borderRadius: 12,
                                showBadge: false,
                              ),
                              title: Text(
                                playlist.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: (isInPlaylist || somePresent)
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: (isInPlaylist || somePresent)
                                      ? cs.primary
                                      : cs.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                '${playlist.trackCount} ${playlist.trackCount == 1 ? "track" : "tracks"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              trailing: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: isInPlaylist
                                      ? cs.primary
                                      : (somePresent && !isSingle)
                                          ? cs.primary.withValues(alpha: 0.2)
                                          : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (isInPlaylist || somePresent)
                                        ? cs.primary
                                        : cs.outlineVariant,
                                    width: 1.5,
                                  ),
                                ),
                                child: isInPlaylist
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 18,
                                        color: cs.onPrimary,
                                      )
                                    : (somePresent && !isSingle)
                                        ? Icon(
                                            Icons.remove_rounded,
                                            size: 16,
                                            color: cs.primary,
                                          )
                                        : null,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
