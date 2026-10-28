import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../services/audio/download_queue_manager.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/playlist/playlist_missing_tracks_sync_service.dart';
import '../../services/playlist/playlist_sync_service.dart';
import '../../state/app_providers.dart';
import '../widgets/cloud_sync_progress_banner.dart';
import '../widgets/generative_playlist_cover.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/mini_player_dock.dart';
import '../widgets/playlist_import_modal.dart';
import '../widgets/playlist_missing_tracks_modal.dart';
import '../widgets/playlist_qr_modal.dart';
import '../widgets/remove_track_dialog.dart';
import '../widgets/swipe_to_queue_wrapper.dart';
import '../widgets/track_metadata_editor_modal.dart';
import '../widgets/ultra_free_scroll_physics.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
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
  bool _isSyncing = false;

  String _formatLastSynced(DateTime? dt) {
    if (dt == null) return 'Never synced';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _handleSyncPlaylist(Playlist current) {
    PixelHaptics.tick();
    if (current.syncSourceUrl == null || current.syncSourceUrl!.isEmpty) {
      _showLinkSourceDialog(current);
    } else {
      _performSync(current, current.syncSourceUrl!);
    }
  }

  void _showLinkSourceDialog(Playlist current) {
    PixelHaptics.tick();
    final urlController = TextEditingController(text: current.syncSourceUrl ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          icon: Icon(Icons.sync_rounded, color: cs.primary, size: 28),
          title: const Text(
            'Sync with Spotify',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Link a public Spotify or Apple Music playlist to automatically import newly added songs with 1 tap.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Playlist Link',
                  hintText: 'https://open.spotify.com/playlist/...',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
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
            FilledButton.icon(
              onPressed: () {
                final text = urlController.text.trim();
                Navigator.of(ctx).pop();
                if (text.isNotEmpty) {
                  ref.read(playlistsProvider.notifier).updatePlaylistSyncSource(current.id, text);
                  _performSync(current, text);
                }
              },
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('Save & Sync'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performSync(Playlist current, String url) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    await PixelHaptics.tick();

    final allTracks = ref.read(tracksCatalogProvider);
    final cloudAccounts = ref.read(cloudAccountsProvider);
    final playlistsNotifier = ref.read(playlistsProvider.notifier);
    final missingTracksNotifier = ref.read(playlistMissingTracksSyncProvider.notifier);

    final outcome = await ref.read(playlistSyncServiceProvider).syncPlaylist(
      playlist: current,
      sourceUrl: url,
      allLibraryTracks: allTracks,
      playlistsNotifier: playlistsNotifier,
      missingTracksNotifier: missingTracksNotifier,
      cloudAccounts: cloudAccounts,
    );

    if (mounted) {
      setState(() => _isSyncing = false);

      if (outcome.isSuccess && outcome.totalNewTracksCount > 0) {
        await PixelHaptics.hifiConfirm();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(outcome.message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
  }
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

  Widget _buildActionPillsRow(
    BuildContext context,
    ColorScheme cs,
    Playlist livePlaylist,
    List<Track> playlistTracks,
  ) {
    final queueMgr = ref.watch(downloadQueueManagerProvider);
    final pinnedCount = playlistTracks.where((t) => t.isPinnedOffline).length;
    final allPinned = playlistTracks.isNotEmpty && pinnedCount == playlistTracks.length;
    final anyInQueue = playlistTracks.any((t) =>
        queueMgr.queue.any((q) =>
            q.track.id == t.id &&
            (q.status == DownloadStatus.downloading ||
                q.status == DownloadStatus.queued)));

    // 1. Download Pill
    final Widget downloadPill;
    if (allPinned) {
      downloadPill = _SmallActionPill(
        icon: Icon(Icons.download_done_rounded, color: cs.primary, size: 16),
        label: 'Downloaded',
        tooltip: 'Downloaded Offline ($pinnedCount tracks). Tap to remove.',
        isActive: true,
        activeColor: cs.primary,
        onPressed: () {
          PixelHaptics.tick();
          _showRemoveDownloadsDialog(playlistTracks);
        },
      );
    } else if (anyInQueue) {
      downloadPill = _SmallActionPill(
        icon: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
        label: '$pinnedCount/${playlistTracks.length}',
        tooltip: 'Downloading ($pinnedCount / ${playlistTracks.length}). Tap to cancel.',
        isActive: true,
        activeColor: cs.secondary,
        onPressed: () {
          PixelHaptics.tick();
          for (final t in playlistTracks) {
            queueMgr.cancel(t.id);
          }
        },
      );
    } else {
      downloadPill = _SmallActionPill(
        icon: Icon(Icons.download_rounded, color: cs.onSurfaceVariant, size: 16),
        label: 'Download',
        tooltip: 'Download Playlist (${playlistTracks.length} tracks)',
        onPressed: playlistTracks.isEmpty
            ? null
            : () {
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
      );
    }

    // 2. Import Pill
    final importPill = _SmallActionPill(
      icon: Icon(Icons.playlist_add_rounded, color: cs.onSurfaceVariant, size: 17),
      label: 'Import',
      tooltip: 'Import Songs (Spotify, Apple Music, YouTube, M3U)',
      onPressed: livePlaylist.isSmart
          ? null
          : () {
              PixelHaptics.tick();
              showPlaylistImportModal(
                context,
                targetPlaylist: livePlaylist,
              );
            },
    );

    // 3. Sync Pill
    final Widget syncPill;
    if (_isSyncing) {
      syncPill = _SmallActionPill(
        icon: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
          ),
        ),
        label: 'Syncing',
        tooltip: 'Syncing playlist tracks...',
        isActive: true,
        activeColor: cs.primary,
        onPressed: null,
      );
    } else if (livePlaylist.syncSourceUrl != null) {
      final isSpotify = livePlaylist.syncSourceUrl!.contains('spotify');
      syncPill = _SmallActionPill(
        icon: Icon(
          Icons.sync_rounded,
          color: isSpotify ? const Color(0xFF1DB954) : cs.primary,
          size: 16,
        ),
        label: 'Sync',
        tooltip: 'Sync with ${isSpotify ? 'Spotify' : 'Source'} • ${_formatLastSynced(livePlaylist.lastSyncedAt)}',
        isActive: true,
        activeColor: isSpotify ? const Color(0xFF1DB954) : cs.primary,
        onPressed: () => _handleSyncPlaylist(livePlaylist),
      );
    } else {
      syncPill = _SmallActionPill(
        icon: Icon(Icons.sync_rounded, color: cs.onSurfaceVariant, size: 16),
        label: 'Sync',
        tooltip: 'Link to Spotify or streaming source for 1-Tap Sync',
        onPressed: livePlaylist.isSmart ? null : () => _handleSyncPlaylist(livePlaylist),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(child: downloadPill),
          const SizedBox(width: 8),
          Expanded(child: importPill),
          const SizedBox(width: 8),
          Expanded(child: syncPill),
        ],
      ),
    );
  }

  void _showRemoveDownloadsDialog(List<Track> playlistTracks) {
    final cs = Theme.of(context).colorScheme;
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
  }

  void _showRenameDialog(Playlist current) {
    PixelHaptics.tick();
    final titleController = TextEditingController(text: current.title);
    final descController = TextEditingController(text: current.description);
    final urlController = TextEditingController(text: current.syncSourceUrl ?? '');

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
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: InputDecoration(
                  labelText: 'Spotify / Source URL (Optional)',
                  hintText: 'https://open.spotify.com/playlist/...',
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
                  final newUrl = urlController.text.trim();
                  ref.read(playlistsProvider.notifier).renamePlaylist(
                        current.id,
                        newTitle,
                        description: descController.text.trim(),
                        syncSourceUrl: newUrl.isEmpty ? null : newUrl,
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
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    physics: buildSuperSmoothScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                        ListTile(
                          leading: const Icon(Icons.edit_note_rounded),
                          title: const Text('Edit Metadata & Artwork',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text(
                              'Title, artist, album, genre, year & cover art'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showTrackMetadataEditorModal(context, track);
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading:
                              Icon(Icons.delete_outline_rounded, color: cs.error),
                          title: Text(
                            'Remove from Library',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.error,
                            ),
                          ),
                          subtitle: const Text(
                            'Delete completely from FreeBeat and all playlists',
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showRemoveTrackConfirmationDialog(
                                context, ref, track);
                          },
                        ),
                      ],
                    ),
                  ),
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

    final hasActiveTrack = currentTrackId.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(450),
            physics: buildSuperSmoothScrollPhysics(),
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
              Theme(
                data: Theme.of(context).copyWith(
                  popupMenuTheme: PopupMenuThemeData(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 6,
                    color: cs.surfaceContainerHigh,
                  ),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.menu_rounded, size: 26),
                  tooltip: 'Playlist Options',
                  onSelected: (value) {
                    PixelHaptics.tick();
                    switch (value) {
                      case 'sync':
                        _handleSyncPlaylist(livePlaylist);
                        break;
                      case 'import':
                        showPlaylistImportModal(
                          context,
                          targetPlaylist: livePlaylist,
                        );
                        break;
                      case 'missing_tracks':
                        showPlaylistMissingTracksModal(
                          context,
                          playlist: livePlaylist,
                          currentTracks: playlistTracks,
                        );
                        break;
                      case 'edit':
                        _showRenameDialog(livePlaylist);
                        break;
                      case 'qr':
                        showPlaylistQrModal(
                          context,
                          livePlaylist,
                          playlistTracks,
                        );
                        break;
                      case 'export_m3u8':
                        _exportM3u8(livePlaylist, playlistTracks);
                        break;
                      case 'delete':
                        _confirmDeletePlaylist(livePlaylist);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (!livePlaylist.isSmart) ...[
                      PopupMenuItem(
                        value: 'sync',
                        enabled: !_isSyncing,
                        child: Row(
                          children: [
                            Icon(Icons.sync_rounded, color: cs.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                livePlaylist.syncSourceUrl != null
                                    ? 'Sync (${livePlaylist.syncSourceUrl!.contains('spotify') ? 'Spotify' : 'Source'})'
                                    : 'Link & Sync with Spotify',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'import',
                        child: Row(
                          children: [
                            Icon(Icons.playlist_add_rounded, color: cs.primary, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Import Songs',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'missing_tracks',
                        child: Row(
                          children: [
                            Icon(Icons.playlist_remove_rounded, color: cs.primary, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Show Missing Tracks',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, color: cs.primary, size: 20),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Edit Playlist',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    PopupMenuItem(
                      value: 'qr',
                      child: Row(
                        children: [
                          Icon(Icons.qr_code_2_rounded, color: cs.primary, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Share & QR Code',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export_m3u8',
                      child: Row(
                        children: [
                          Icon(Icons.file_download_outlined, color: cs.primary, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Export .M3U8',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!livePlaylist.isSmart) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: cs.error, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Delete Playlist',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: cs.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),

          // Cloud Sync Progress Banner (when actively syncing this playlist)
          SliverToBoxAdapter(
            child: CloudSyncProgressBanner(playlistId: livePlaylist.id),
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
                                        isShuffle: true,
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
                  // 4. Download, Import, and Sync Small Action Pills
                  _buildActionPillsRow(context, cs, livePlaylist, playlistTracks),
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
                        'Add songs from your library using the 3-dots menu on any track, or import from Spotify or Apple Music.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      if (!livePlaylist.isSmart) ...[
                        const SizedBox(height: 16),
                        if (livePlaylist.syncSourceUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FilledButton.icon(
                              onPressed: _isSyncing
                                  ? null
                                  : () => _handleSyncPlaylist(livePlaylist),
                              icon: _isSyncing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.sync_rounded, size: 18),
                              label: Text(_isSyncing
                                  ? 'Syncing with Spotify...'
                                  : 'Sync Tracks from Spotify'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            PixelHaptics.tick();
                            showPlaylistImportModal(
                              context,
                              targetPlaylist: livePlaylist,
                            );
                          },
                          icon: const Icon(Icons.playlist_add_rounded, size: 18),
                          label: const Text(
                            'Import Songs into Playlist',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else
            SuperSliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = playlistTracks[index];
                  final isCurrent = currentTrackId == track.id;
                  final isPlaying = isCurrent && isPlaybackPlaying;

                  return SwipeToQueueWrapper(
                    key: Key('pl_${livePlaylist.id}_${track.id}_$index'),
                    track: track,
                    enableSecondaryAction: false,
                    child: Material(
                      color: Colors.transparent,
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
                    ),
                  );
                },
                childCount: playlistTracks.length,
              ),
            ),

          SliverToBoxAdapter(
            child: SizedBox(height: hasActiveTrack ? 120 : 60),
          ),
        ],
      ),
      if (hasActiveTrack)
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 12,
          child: const Center(
            child: MiniPlayerDock(),
          ),
        ),
    ],
  ),
);
  }
}

/// Compact, uniform-size action pill for playlist download, import, and sync.
class _SmallActionPill extends StatelessWidget {
  const _SmallActionPill({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onPressed,
    this.isActive = false,
    this.activeColor,
  });

  final Widget icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isActive;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = activeColor ?? cs.primary;
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.45,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: onPressed,
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: isActive
                    ? effectiveColor.withValues(alpha: 0.14)
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: isActive
                      ? effectiveColor.withValues(alpha: 0.45)
                      : cs.outlineVariant.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isActive ? effectiveColor : cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
