import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../services/audio/download_queue_manager.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/generative_playlist_cover.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/playlist_qr_modal.dart';
import '../widgets/swipe_to_queue_wrapper.dart';
import 'track_details_screen.dart';

/// Stock Google Pixel Material 3 Playlist Details Screen.
/// Displays playlist cover (generative art or mosaic), metadata, playback controls (Play All / Shuffle),
/// drag-and-drop track reordering, track removal, and .m3u8 export.
class PlaylistDetailsScreen extends ConsumerStatefulWidget {
  const PlaylistDetailsScreen({
    super.key,
    required this.playlist,
  });

  final Playlist playlist;

  @override
  ConsumerState<PlaylistDetailsScreen> createState() =>
      _PlaylistDetailsScreenState();
}

class _PlaylistDetailsScreenState
    extends ConsumerState<PlaylistDetailsScreen> {
  String _formatTotalDuration(List<Track> tracks) {
    final totalMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final totalSeconds = (totalMs / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remMin = minutes % 60;
    return '${hours}h ${remMin}m';
  }

  String _formatTrackDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildDownloadRow(
    BuildContext context,
    ColorScheme cs,
    List<Track> playlistTracks,
  ) {
    if (playlistTracks.isEmpty) return const SizedBox.shrink();

    final queueMgr = ref.watch(downloadQueueManagerProvider);
    final pinnedCount = playlistTracks.where((t) => t.isPinnedOffline).length;
    final allPinned = pinnedCount == playlistTracks.length;
    final anyInQueue = playlistTracks.any((t) =>
        queueMgr.queue.any((q) =>
            q.track.id == t.id &&
            (q.status == DownloadStatus.downloading ||
                q.status == DownloadStatus.queued)));

    if (allPinned) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: () {
            PixelHaptics.tick();
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                title: const Text('Remove Downloads',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                content: Text(
                  'Remove all ${playlistTracks.length} offline tracks in "${widget.playlist.title}" from device storage? The songs will remain in your library.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Keep'),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref
                          .read(tracksCatalogProvider.notifier)
                          .unpinTracksOffline(
                            playlistTracks.map((t) => t.id).toList(),
                          );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Removed offline tracks.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Text('Remove'),
                  ),
                ],
              ),
            );
          },
          icon: Icon(Icons.download_done_rounded, color: cs.primary, size: 18),
          label: Text(
            'Downloaded Offline (${playlistTracks.length})',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
            side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    if (anyInQueue) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: cs.secondaryContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Downloading ($pinnedCount / ${playlistTracks.length})...',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.cancel_rounded, size: 18),
                onPressed: () {
                  PixelHaptics.tick();
                  for (final t in playlistTracks) {
                    queueMgr.cancel(t.id);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        onPressed: () {
          PixelHaptics.hifiConfirm();
          ref
              .read(tracksCatalogProvider.notifier)
              .pinTracksOffline(playlistTracks.map((t) => t.id).toList());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Downloading ${playlistTracks.length} tracks from "${widget.playlist.title}"...',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        icon: const Icon(Icons.download_for_offline_outlined, size: 18),
        label: Text(
          'Download Playlist (${playlistTracks.length} tracks)',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  void _showRenameDialog(Playlist current) {
    PixelHaptics.tick();
    final titleController = TextEditingController(text: current.title);
    final descController = TextEditingController(text: current.description);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text('Edit Playlist',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Playlist Name',
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
              onPressed: () {
                final newTitle = titleController.text.trim();
                if (newTitle.isNotEmpty) {
                  ref.read(playlistsProvider.notifier).renamePlaylist(
                        current.id,
                        newTitle,
                        description: descController.text.trim(),
                      );
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeletePlaylist(Playlist current) {
    PixelHaptics.tick();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          icon: Icon(Icons.delete_outline_rounded,
              color: cs.error, size: 28),
          title: const Text('Delete Playlist?',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Text(
            'Are you sure you want to delete "${current.title}"? Your audio files will not be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Keep'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () {
                ref
                    .read(playlistsProvider.notifier)
                    .deletePlaylist(current.id);
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${current.title}"'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _exportM3u8(Playlist current, List<Track> tracks) {
    PixelHaptics.hifiConfirm();
    final m3u8 = ref
        .read(playlistsProvider.notifier)
        .exportPlaylistM3u8(current, tracks);
    Clipboard.setData(ClipboardData(text: m3u8));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported M3U8 for "${current.title}" (Copied to Clipboard)'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  void _showTrackOptionsMenu(Track track, Playlist current) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    MaterialYouAlbumCover(
                      track: track,
                      size: 48,
                      borderRadius: 14,
                      showQualityBadge: false,
                      showSourceBadge: false,
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
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: const Text('Play Next',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref.read(playbackProvider.notifier).playNext(track);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: const Text('Add to Queue',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref.read(playbackProvider.notifier).addToQueue(track);
                    PixelHaptics.hifiConfirm();
                    SwipeToQueueWrapper.showQueuedSnackBar(
                      context,
                      track.title,
                    );
                  },
                ),
                if (!current.isSmart)
                  ListTile(
                    leading: Icon(Icons.remove_circle_outline_rounded,
                        color: cs.error),
                    title: Text(
                      'Remove from Playlist',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(playlistsProvider.notifier)
                          .removeTrackFromPlaylist(current.id, track.id);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('View Track Details',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TrackDetailsScreen(track: track),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allTracks = ref.watch(tracksCatalogProvider);
    final allPlaylists = ref.watch(smartPlaylistsProvider);
    final currentTrackId =
        ref.watch(playbackProvider.select((p) => p.currentTrack.id));
    final isPlaybackPlaying =
        ref.watch(playbackProvider.select((p) => p.isPlaying));

    // Find the latest live state of this playlist
    final livePlaylist = allPlaylists.firstWhere(
      (p) => p.id == widget.playlist.id,
      orElse: () => widget.playlist,
    );

    // Resolve tracks in order of playlist.trackIds
    final trackMap = {for (final t in allTracks) t.id: t};
    final playlistTracks = livePlaylist.trackIds
        .map((id) => trackMap[id])
        .whereType<Track>()
        .toList();

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Sleek App Bar
          SliverAppBar(
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () {
                PixelHaptics.tick();
                Navigator.of(context).pop();
              },
            ),
            actions: [
              if (!livePlaylist.isSmart)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit Playlist',
                  onPressed: () => _showRenameDialog(livePlaylist),
                ),
              IconButton(
                icon: const Icon(Icons.qr_code_2_rounded),
                tooltip: 'Share & QR Code',
                onPressed: () => showPlaylistQrModal(
                  context,
                  livePlaylist,
                  playlistTracks,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Export .M3U8',
                onPressed: () => _exportM3u8(livePlaylist, playlistTracks),
              ),
              if (!livePlaylist.isSmart)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Delete Playlist',
                  onPressed: () => _confirmDeletePlaylist(livePlaylist),
                ),
              const SizedBox(width: 8),
            ],
          ),

          // 2. Playlist Header & Cover Art
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  GenerativePlaylistCover(
                    playlist: livePlaylist,
                    tracks: playlistTracks,
                    size: 170,
                    borderRadius: 28,
                    showBadge: true,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    livePlaylist.title,
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (livePlaylist.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      livePlaylist.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    '${playlistTracks.length} tracks • ${_formatTotalDuration(playlistTracks)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. Play & Shuffle Buttons Row
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: playlistTracks.isNotEmpty
                              ? () {
                                  PixelHaptics.playPauseToggle();
                                  ref
                                      .read(playbackProvider.notifier)
                                      .playTrack(
                                        playlistTracks.first,
                                        newQueue: playlistTracks,
                                      );
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text(
                            'Play All',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: playlistTracks.isNotEmpty
                              ? () {
                                  PixelHaptics.playPauseToggle();
                                  final shuffled =
                                      List<Track>.from(playlistTracks)
                                        ..shuffle();
                                  ref
                                      .read(playbackProvider.notifier)
                                      .playTrack(
                                        shuffled.first,
                                        newQueue: shuffled,
                                      );
                                }
                              : null,
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          label: const Text(
                            'Shuffle',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildDownloadRow(context, cs, playlistTracks),
                ],
              ),
            ),
          ),

          // 4. Track List
          if (playlistTracks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 48),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.queue_music_rounded,
                          size: 48, color: cs.outlineVariant),
                      const SizedBox(height: 12),
                      const Text(
                        'This playlist is empty',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add songs from your library using the 3-dots menu on any track.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = playlistTracks[index];
                  final isCurrent = currentTrackId == track.id;
                  final isPlaying = isCurrent && isPlaybackPlaying;

                  return SwipeToQueueWrapper(
                    key: Key('pl_${livePlaylist.id}_${track.id}_$index'),
                    track: track,
                    enableSecondaryAction: !livePlaylist.isSmart,
                    secondaryActionTitle: 'Remove',
                    secondaryActionIcon: Icons.delete_outline_rounded,
                    dismissOnSecondaryAction: true,
                    onSecondaryAction: () {
                      ref
                          .read(playlistsProvider.notifier)
                          .removeTrackFromPlaylist(livePlaylist.id, track.id);
                    },
                    child: InkWell(
                      onTap: () {
                        PixelHaptics.tick();
                        ref.read(playbackProvider.notifier).playTrack(
                              track,
                              newQueue: playlistTracks,
                            );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            // Track index or play indicator
                            SizedBox(
                              width: 28,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: isCurrent
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isCurrent
                                          ? cs.primary
                                          : cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${track.artist} • ${_formatTrackDuration(track.durationMs)}',
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
                            IconButton(
                              icon: const Icon(Icons.more_vert_rounded),
                              color: cs.onSurfaceVariant,
                              onPressed: () =>
                                  _showTrackOptionsMenu(track, livePlaylist),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                childCount: playlistTracks.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
