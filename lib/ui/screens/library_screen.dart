import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'search_screen.dart';
import 'settings/cloud_sync_settings_screen.dart';
import 'settings/settings_screen.dart';
import 'track_details_screen.dart';
import '../../core/models/playlist.dart';
import '../widgets/add_to_library_modal.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/cloud_sync_progress_banner.dart';
import '../widgets/generative_playlist_cover.dart';
import '../widgets/material_you_download_button.dart';
import '../widgets/pending_import_track_tile.dart';
import '../widgets/platform_app_icons.dart';
import '../widgets/playlist_import_modal.dart';
import '../widgets/remove_track_dialog.dart';
import '../widgets/swipe_to_queue_wrapper.dart';
import '../widgets/track_metadata_editor_modal.dart';

/// Stock Google Pixel Material 3 Expressive Library Screen.
/// Strictly implements Screen 5 ("# Your Library") in Figma inspiration:
/// 1. Top App Bar with Search, Profile/Settings icon
/// 2. Stadium-pill filter chips (All Tracks, Hi-Res, Offline, Liked)
/// 3. Artists Avatar Row: horizontal scroll of artist circular avatars (Alexter, Teritona, etc.)
/// 4. Playlists 2-Column Curated Cards (Organic Playlists, Daily Mix, Add Music)
/// 5. Grouped 28dp Surface Card for Track List
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.showFab = true});

  final bool showFab;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _segment = 'all'; // 'all', 'hires', 'offline', 'favorites'
  String? _selectedArtist;

  bool _isMultiSelect = false;
  final Set<String> _selectedTrackIds = <String>{};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  void _onSearchFocusChanged() {
    if (mounted) {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _focusSearch() {
    PixelHaptics.tick();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    _searchFocusNode.requestFocus();
  }

  void _enterMultiSelect([String? initialTrackId]) {
    setState(() {
      _isMultiSelect = true;
      if (initialTrackId != null) {
        _selectedTrackIds.add(initialTrackId);
      }
    });
    PixelHaptics.sheetExpand();
  }

  void _exitMultiSelect() {
    setState(() {
      _isMultiSelect = false;
      _selectedTrackIds.clear();
    });
    PixelHaptics.tick();
  }

  void _toggleSelectTrack(String trackId) {
    setState(() {
      if (_selectedTrackIds.contains(trackId)) {
        _selectedTrackIds.remove(trackId);
      } else {
        _selectedTrackIds.add(trackId);
      }
    });
    PixelHaptics.tick();
  }

  void _toggleSelectAll(List<Track> filtered) {
    setState(() {
      final filteredIds = filtered.map((t) => t.id).toSet();
      final allSelected = filteredIds.isNotEmpty &&
          filteredIds.every((id) => _selectedTrackIds.contains(id));
      if (allSelected) {
        _selectedTrackIds.removeAll(filteredIds);
      } else {
        _selectedTrackIds.addAll(filteredIds);
        _isMultiSelect = true;
      }
    });
    PixelHaptics.tick();
  }

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
      orElse: () => const CloudAccount(
        id: 'local_storage_saf',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Local Storage',
        endpointOrFolder: 'Local Music Files',
      ),
    );
    final progressNotifier = ref.read(importProgressProvider.notifier);
    final picked = await authService.pickFromInstalledCloudApp(
      account: safAccount,
      batchSize: 10,
      onBatchStarted: (batchFilenames, batchStartIndex, totalFiles) {
        progressNotifier.startBatch(
          batchFilenames: batchFilenames,
          batchStartIndex: batchStartIndex,
          totalFiles: totalFiles,
        );
      },
      onProgress: (current, total, track) {
        progressNotifier.update(
          current: current,
          total: total,
          name: track?.title ?? '',
          track: track,
        );
      },
      onBatchCompleted: (batchTracks) async {
        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(batchTracks);
      },
    );
    if (picked.isNotEmpty) {
      await PixelHaptics.hifiConfirm();
      progressNotifier.complete();
      ref.read(tracksCatalogProvider.notifier).enrichLibraryArtwork(picked);
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
    } else {
      progressNotifier.clearPending();
    }
  }

  void _showAddMusicOptionsSheet() {
    showAddToLibraryModal(context, ref);
  }

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
                  hintText: 'e.g. Late Night Drives, Chill Lofi',
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
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showPlaylistImportModal(context);
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Or import from Spotify, Apple, or YouTube'),
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
                  await PixelHaptics.hifiConfirm();
                  if (mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaylistDetailsScreen(playlist: playlist),
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

  void _showDeduplicateDialog(Map<String, List<Track>> duplicateMap) {
    PixelHaptics.tick();
    final totalRedundant = duplicateMap.values.fold<int>(
      0,
      (sum, list) => sum + (list.length - 1),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_fix_high_rounded,
                  color: cs.onTertiaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '1-Tap Deduplicate',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Found $totalRedundant duplicate tracks across ${duplicateMap.length} titles.\n\nFreeBeat will keep the highest quality version (Hi-Res / highest sample rate) and safely remove redundant copies from your library.',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final idsToRemove = <String>[];
                for (final group in duplicateMap.values) {
                  // Sort by bit depth and sample rate descending
                  final sorted = List<Track>.from(group)
                    ..sort((a, b) {
                      final scoreA = (a.isHiRes ? 1000 : 0) +
                          (a.bitDepth * 10) +
                          (a.sampleRateHz / 1000).round();
                      final scoreB = (b.isHiRes ? 1000 : 0) +
                          (b.bitDepth * 10) +
                          (b.sampleRateHz / 1000).round();
                      return scoreB.compareTo(scoreA);
                    });
                  // Keep first (highest quality), remove the rest
                  for (int i = 1; i < sorted.length; i++) {
                    idsToRemove.add(sorted[i].id);
                  }
                }

                if (idsToRemove.isNotEmpty) {
                  await ref
                      .read(tracksCatalogProvider.notifier)
                      .removeTracks(idsToRemove);
                  await PixelHaptics.hifiConfirm();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Cleaned up ${idsToRemove.length} duplicate tracks! Library optimized.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    );
                  }
                }
              },
              child: Text('Clean $totalRedundant Duplicates'),
            ),
          ],
        );
      },
    );
  }

  void _showTrackOptions(Track track) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Material(
          color: cs.surfaceContainerLowest,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        MaterialYouAlbumCover(
                          track: track,
                          size: 52,
                          borderRadius: 14,
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
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.checklist_rounded),
                    title: const Text('Select Track',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Enter multi-selection mode'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _enterMultiSelect(track.id);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.playlist_play_rounded),
                    title: const Text('Play Next',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle:
                        const Text('Insert immediately after current track'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref.read(playbackProvider.notifier).playNext(track);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Playing next: ${track.title}'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: const Text('Add to Queue',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Append to the end of Up Next queue'),
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
                  ListTile(
                    leading: const Icon(Icons.playlist_add_rounded),
                    title: const Text('Add to Playlist',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Save to custom or new playlist'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showAddToPlaylistModal(context, track);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: const Text('Edit Metadata & Artwork',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Title, artist, album, genre, year & cover art'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showTrackMetadataEditorModal(context, track);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('View Track Details',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${track.codec} • ${track.bitDepth}-Bit • ${track.formattedSampleRate}'),
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
                    leading: const Icon(Icons.person_rounded),
                    title: Text('View Artist: ${track.artist}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ArtistDetailsScreen(artistName: track.artist),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      track.isPinnedOffline
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                    ),
                    title: Text(
                      track.isPinnedOffline
                          ? 'Cached Offline (Tap to Remove)'
                          : 'Download / Cache Offline',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(tracksCatalogProvider.notifier)
                          .togglePinOffline(track.id);
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
                      'Remove from library, offline cache, and playlists',
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showRemoveTrackConfirmationDialog(context, ref, track);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

  void _showBatchTrackOptions(List<Track> tracks) {
    if (tracks.isEmpty) return;
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;
    final totalDurationMs = tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final totalSeconds = (totalDurationMs / 1000).floor();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final formattedDuration =
        hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
    final artistCount = tracks
        .map((t) => t.artist)
        .where((a) => a.isNotEmpty)
        .toSet()
        .length;

    final allPinned = tracks.every((t) => t.isPinnedOffline);
    final unpinnedCount = tracks.where((t) => !t.isPinnedOffline).length;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Material(
          color: cs.surfaceContainerLowest,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                color: cs.onPrimaryContainer,
                                size: 28,
                              ),
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${tracks.length}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: cs.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${tracks.length} Selected ${tracks.length == 1 ? "Track" : "Tracks"}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$formattedDuration • $artistCount ${artistCount == 1 ? "artist" : "artists"}',
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
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.playlist_play_rounded),
                    title: const Text('Play Next',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'Insert ${tracks.length} tracks immediately after current track'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(playbackProvider.notifier)
                          .playNextMultiple(tracks);
                      _exitMultiSelect();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Playing next: ${tracks.length} tracks',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.queue_music_rounded),
                    title: const Text('Add to Queue',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'Append ${tracks.length} tracks to Up Next queue'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      ref
                          .read(playbackProvider.notifier)
                          .addToQueueMultiple(tracks);
                      _exitMultiSelect();
                      PixelHaptics.hifiConfirm();
                      SwipeToQueueWrapper.showQueuedSnackBar(
                        context,
                        '${tracks.length} tracks',
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.playlist_add_rounded),
                    title: const Text('Add to Playlist',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        'Save ${tracks.length} tracks to custom or new playlist'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showAddToPlaylistModal(context, null, tracks);
                      _exitMultiSelect();
                    },
                  ),
                  if (tracks.length == 1) ...[
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded),
                      title: const Text('View Track Details',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(
                          '${tracks.first.codec} • ${tracks.first.bitDepth}-Bit • ${tracks.first.formattedSampleRate}'),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                TrackDetailsScreen(track: tracks.first),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: Text('View Artist: ${tracks.first.artist}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArtistDetailsScreen(
                              artistName: tracks.first.artist,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(
                      allPinned
                          ? Icons.download_done_rounded
                          : Icons.download_rounded,
                    ),
                    title: Text(
                      allPinned
                          ? 'Remove from Offline Cache (${tracks.length} tracks)'
                          : 'Download / Cache Offline ($unpinnedCount new)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      allPinned
                          ? 'Delete local cached files to free device space'
                          : 'Download and pin for offline lossless playback',
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      if (allPinned) {
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .unpinTracksOffline(
                              tracks.map((t) => t.id).toList(),
                            );
                      } else {
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .pinTracksOffline(
                              tracks.map((t) => t.id).toList(),
                            );
                      }
                      _exitMultiSelect();
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
                    subtitle: Text(
                      'Remove ${tracks.length} tracks from library, offline cache, and playlists',
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      showRemoveTracksConfirmationDialog(
                        context,
                        ref,
                        tracks,
                        onRemoved: _exitMultiSelect,
                      );
                    },
                  ),
                ],
              ),
            ),
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
    final activeTrackId =
        ref.watch(playbackProvider.select((p) => p.currentTrack.id));
    final isPlaybackActive =
        ref.watch(playbackProvider.select((p) => p.isPlaying));
    final importProgress = ref.watch(importProgressProvider);
    final allPlaylists = ref.watch(smartPlaylistsProvider);
    final duplicateMap = ref.watch(duplicateTracksProvider);
    final artists = ref.watch(allArtistsProvider);

    final query = _searchQuery.trim().toLowerCase();

    final filtered = allTracks.where((t) {
      if (_selectedArtist != null && t.artist != _selectedArtist) {
        return false;
      }
      switch (_segment) {
        case 'hires':
          if (!t.isHiRes) return false;
          break;
        case 'offline':
          if (!t.isPinnedOffline) return false;
          break;
        case 'favorites':
          if (!t.isFavorite) return false;
          break;
        default:
          break;
      }
      if (query.isNotEmpty) {
        final matches = t.title.toLowerCase().contains(query) ||
            t.artist.toLowerCase().contains(query) ||
            t.album.toLowerCase().contains(query) ||
            t.codec.toLowerCase().contains(query);
        if (!matches) return false;
      }
      return true;
    }).toList();

    final filteredPlaylists = query.isEmpty
        ? allPlaylists
        : allPlaylists.where((p) {
            return p.title.toLowerCase().contains(query) ||
                p.description.toLowerCase().contains(query);
          }).toList();

    final filteredArtists = query.isEmpty
        ? artists
        : artists.where((a) => a.toLowerCase().contains(query)).toList();

    final isAllFilteredSelected = filtered.isNotEmpty &&
        filtered.every((t) => _selectedTrackIds.contains(t.id));
    final selectedTracks = allTracks
        .where((t) => _selectedTrackIds.contains(t.id))
        .toList();

    final hasActiveTrack = ref.watch(
      playbackProvider.select(
        (p) => p.currentTrack.id.isNotEmpty && p.queue.isNotEmpty,
      ),
    );
    // Align with mini player when music is active (58.0 + Scaffold's 16.0 margin = 74.0dp, exactly matching the mini player from 74-124dp above screen bottom)
    // When no track is active, sit comfortably above the navigation pill (8.0 + 16.0 = 24.0dp)
    final bottomFabPadding = hasActiveTrack ? 58.0 : 8.0;

    return PopScope(
      canPop: !_isMultiSelect,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isMultiSelect) {
          _exitMultiSelect();
        }
      },
      child: Scaffold(
        floatingActionButtonLocation: _isMultiSelect
            ? FloatingActionButtonLocation.centerFloat
            : FloatingActionButtonLocation.endFloat,
        floatingActionButton: _isMultiSelect
            ? Padding(
                padding: EdgeInsets.only(bottom: bottomFabPadding),
                child: _BatchActionsFloatingBar(
                  selectedCount: _selectedTrackIds.length,
                  onPlayNext: _selectedTrackIds.isEmpty
                      ? null
                      : () {
                          ref
                              .read(playbackProvider.notifier)
                              .playNextMultiple(selectedTracks);
                          _exitMultiSelect();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Playing next: ${selectedTracks.length} tracks',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  onAddToQueue: _selectedTrackIds.isEmpty
                      ? null
                      : () {
                          ref
                              .read(playbackProvider.notifier)
                              .addToQueueMultiple(selectedTracks);
                          _exitMultiSelect();
                          SwipeToQueueWrapper.showQueuedSnackBar(
                            context,
                            '${selectedTracks.length} tracks',
                          );
                        },
                  onAddToPlaylist: _selectedTrackIds.isEmpty
                      ? null
                      : () {
                          showAddToPlaylistModal(context, null, selectedTracks);
                          _exitMultiSelect();
                        },
                  onToggleOffline: _selectedTrackIds.isEmpty
                      ? null
                      : () {
                          final allPinned = selectedTracks
                              .every((t) => t.isPinnedOffline);
                          if (allPinned) {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .unpinTracksOffline(
                                  selectedTracks.map((t) => t.id).toList(),
                                );
                          } else {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .pinTracksOffline(
                                  selectedTracks.map((t) => t.id).toList(),
                                );
                          }
                          _exitMultiSelect();
                        },
                  onRemove: _selectedTrackIds.isEmpty
                      ? null
                      : () {
                          showRemoveTracksConfirmationDialog(
                            context,
                            ref,
                            selectedTracks,
                            onRemoved: _exitMultiSelect,
                          );
                        },
                  onOptions: _selectedTrackIds.isEmpty
                      ? null
                      : () => _showBatchTrackOptions(selectedTracks),
                ),
              )
            : (widget.showFab
                ? Padding(
                    padding: EdgeInsets.only(bottom: bottomFabPadding),
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: FloatingActionButton(
                        shape: const CircleBorder(),
                        elevation: 4,
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                        tooltip: 'Add to Library',
                        onPressed: _showAddMusicOptionsSheet,
                        child: const Icon(
                          Icons.add_rounded,
                          size: 26,
                        ),
                      ),
                    ),
                  )
                : null),
        body: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ─────────────────────────────────────────────────────────────────
            // 1. M3 Top App Bar
            // ─────────────────────────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              leading: _isMultiSelect
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Exit Selection',
                      onPressed: _exitMultiSelect,
                    )
                  : null,
              title: Text(
                _isMultiSelect
                    ? (_selectedTrackIds.isEmpty
                        ? 'Select Tracks'
                        : '${_selectedTrackIds.length} Selected')
                    : 'Your Library',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: _isMultiSelect ? 20 : null,
                ),
              ),
              actions: [
                if (_isMultiSelect) ...[
                  IconButton(
                    icon: Icon(
                      isAllFilteredSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    tooltip:
                        isAllFilteredSelected ? 'Deselect All' : 'Select All',
                    onPressed: () => _toggleSelectAll(filtered),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: 'Batch Options',
                    onPressed: _selectedTrackIds.isEmpty
                        ? null
                        : () => _showBatchTrackOptions(selectedTracks),
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search Library',
                    onPressed: _focusSearch,
                  ),
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
                      tooltip: 'Menu',
                      onSelected: (value) {
                        PixelHaptics.tick();
                        switch (value) {
                          case 'play_all':
                            if (filtered.isNotEmpty) {
                              PixelHaptics.playPauseToggle();
                              ref.read(playbackProvider.notifier).playTrack(
                                    filtered.first,
                                    newQueue: filtered,
                                  );
                            }
                            break;
                          case 'search':
                            _focusSearch();
                            break;
                          case 'search_global':
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    SearchScreen(initialQuery: _searchQuery),
                              ),
                            );
                            break;
                          case 'add':
                            _showAddMusicOptionsSheet();
                            break;
                          case 'import_playlist':
                            showPlaylistImportModal(context);
                            break;
                          case 'select':
                            _enterMultiSelect();
                            break;
                          case 'settings':
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                            break;
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'play_all',
                          child: Row(
                            children: [
                              Icon(Icons.play_circle_fill_rounded,
                                  color: cs.primary, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Play All Tracks',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'search',
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded,
                                  color: cs.primary, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Search in Library',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'search_global',
                          child: Row(
                            children: [
                              Icon(Icons.travel_explore_rounded,
                                  color: cs.primary, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Search Global Catalog',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'add',
                          child: Row(
                            children: [
                              Icon(Icons.add_rounded,
                                  color: cs.primary, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Add to Library',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'import_playlist',
                          child: Row(
                            children: [
                              Icon(
                                Icons.playlist_add_check_circle_outlined,
                                color: cs.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Import Playlist',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'select',
                          child: Row(
                            children: [
                              Icon(Icons.checklist_rounded,
                                  color: cs.primary, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Select Tracks',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'settings',
                          child: Row(
                            children: [
                              Icon(Icons.settings_outlined,
                                  color: cs.onSurfaceVariant, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Settings',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 8),
              ],
            ),

            // ─────────────────────────────────────────────────────────────────
            // 2. Material You Library Search Bar (Zero Sharp Corners)
            // ─────────────────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Container(
                  height: 48,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.70),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: _isSearchFocused
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha: 0.35),
                      width: _isSearchFocused ? 1.5 : 1.0,
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintText: _segment == 'playlists'
                          ? 'Search playlists in library...'
                          : 'Search songs, artists, albums, codecs...',
                      hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: _isSearchFocused
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              color: cs.onSurfaceVariant,
                              tooltip: 'Clear search',
                              onPressed: () {
                                PixelHaptics.tick();
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),

          // Real-Time Import Progress Loading Bar
          if (importProgress.isImporting)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Importing Music...',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${importProgress.current} / ${importProgress.total} (${importProgress.progressPercentage})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      if (importProgress.currentItemName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          importProgress.currentItemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: LinearProgressIndicator(
                          value: importProgress.total > 0
                              ? importProgress.progressFraction
                              : null,
                          minHeight: 5,
                          backgroundColor:
                              cs.onPrimaryContainer.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ───────────────────────────────────────────────────────────────────
          // Cloud Missing Track Sync Progress Banner
          // ───────────────────────────────────────────────────────────────────
          const SliverToBoxAdapter(
            child: CloudSyncProgressBanner(),
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
                    isSelected: _segment == 'all' && _selectedArtist == null,
                    icon: Icons.library_music_rounded,
                    onTap: () => setState(() {
                      _segment = 'all';
                      _selectedArtist = null;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _LibraryPillFilter(
                    label: 'Playlists (${allPlaylists.length})',
                    isSelected: _segment == 'playlists',
                    icon: Icons.playlist_play_rounded,
                    onTap: () => setState(() {
                      _segment = 'playlists';
                      _selectedArtist = null;
                    }),
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

          // ───────────────────────────────────────────────────────────────────
          // Duplicate Tracks Detector Banner (1-Tap Deduplication)
          // ───────────────────────────────────────────────────────────────────
          if (duplicateMap.isNotEmpty && _segment != 'playlists')
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.tertiary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.tertiaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.auto_fix_high_rounded,
                          color: cs.onTertiaryContainer,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${duplicateMap.length} Duplicate ${duplicateMap.length == 1 ? "Track" : "Tracks"} Found',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: cs.onTertiaryContainer,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Keep highest audio fidelity & deduplicate',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onTertiaryContainer
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _showDeduplicateDialog(duplicateMap),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiary,
                          foregroundColor: cs.onTertiary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: const StadiumBorder(),
                        ),
                        child: const Text(
                          'Clean Up',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_segment == 'playlists') ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                child: _SpotifyAppleImportBanner(
                  onTap: () => showPlaylistImportModal(context),
                ),
              ),
            ),
            // ─────────────────────────────────────────────────────────────────
            // Curated & Smart Playlists 2-Column Responsive Grid
            // ─────────────────────────────────────────────────────────────────
            if (query.isNotEmpty && filteredPlaylists.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 40,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No playlists matching "$_searchQuery"',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Check your search query or create a new playlist.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          label: const Text('Clear Search'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 160),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.74,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (query.isEmpty) {
                        if (index == 0) {
                          return _NewPlaylistCard(
                            onTap: _showCreatePlaylistDialog,
                          );
                        }
                        if (index == 1) {
                          return _ImportPlaylistCard(
                            onTap: () => showPlaylistImportModal(context),
                          );
                        }
                        final playlist = filteredPlaylists[index - 2];
                        final pTracks = allTracks
                            .where((t) => playlist.trackIds.contains(t.id))
                            .toList();
                        return _PlaylistGridCard(
                          playlist: playlist,
                          tracks: pTracks,
                          onTap: () {
                            PixelHaptics.tick();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlaylistDetailsScreen(playlist: playlist),
                              ),
                            );
                          },
                        );
                      } else {
                        final playlist = filteredPlaylists[index];
                        final pTracks = allTracks
                            .where((t) => playlist.trackIds.contains(t.id))
                            .toList();
                        return _PlaylistGridCard(
                          playlist: playlist,
                          tracks: pTracks,
                          onTap: () {
                            PixelHaptics.tick();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlaylistDetailsScreen(playlist: playlist),
                              ),
                            );
                          },
                        );
                      }
                    },
                    childCount: query.isEmpty
                        ? filteredPlaylists.length + 2
                        : filteredPlaylists.length,
                  ),
                ),
              ),
          ] else ...[
            // ─────────────────────────────────────────────────────────────────
            // 3. Figma Screen 5: Artists Avatars Horizontal Row (when available)
            // ─────────────────────────────────────────────────────────────────
          if (filteredArtists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      query.isNotEmpty ? 'Matching Artists' : 'Artists',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_selectedArtist != null)
                      TextButton.icon(
                        onPressed: () {
                          PixelHaptics.tick();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ArtistDetailsScreen(
                                artistName: _selectedArtist!,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: Text('View $_selectedArtist'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemCount: filteredArtists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final artist = filteredArtists[index];
                    final isSelected = _selectedArtist == artist;
                    return GestureDetector(
                      onTap: () {
                        PixelHaptics.tick();
                        setState(() {
                          _selectedArtist = isSelected ? null : artist;
                        });
                      },
                      onLongPress: () {
                        PixelHaptics.medium();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ArtistDetailsScreen(artistName: artist),
                          ),
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: cs.primaryContainer,
                              border: Border.all(
                                color: isSelected
                                    ? cs.primary
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                artist.isNotEmpty ? artist[0].toUpperCase() : 'A',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 64,
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isSelected ? cs.primary : cs.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ───────────────────────────────────────────────────────────────────
          // 4. Edge-to-Edge Surface Card for Track List (Virtualized 120Hz Slivers)
          // ───────────────────────────────────────────────────────────────────
          if (allTracks.isEmpty && importProgress.pendingTracks.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 160),
              sliver: SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                        width: 1,
                      ),
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.queue_music_rounded,
                              size: 32,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Your Library is Empty',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add music files from your device or connect cloud storage to start listening.',
                            textAlign: TextAlign.center,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _pickLocalFiles,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Music from Device'),
                            style: FilledButton.styleFrom(
                              shape: const StadiumBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: () {
                              PixelHaptics.tick();
                              ref
                                  .read(cloudAccountsProvider.notifier)
                                  .loadSampleDemoAccounts();
                              ref
                                  .read(tracksCatalogProvider.notifier)
                                  .loadSampleDemoTracks();
                            },
                            icon: const Icon(Icons.auto_awesome_rounded,
                                size: 16),
                            label: const Text('Load Demo Showcase'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            )
          else ...[
            // 1. Pending Import Songs (all show up together, greyed out with filling circle indicators)
            if (importProgress.pendingTracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    border: Border(
                      top: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                        width: 1,
                      ),
                      bottom: filtered.isEmpty
                          ? BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.25),
                              width: 1,
                            )
                          : BorderSide.none,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              importProgress.total > 10
                                  ? 'Importing Batch ${((importProgress.batchIndex ~/ 10) + 1)} of ${((importProgress.total + 9) ~/ 10)} (${importProgress.current}/${importProgress.total})'
                                  : 'Importing ${importProgress.total} Songs (${importProgress.current}/${importProgress.total})',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (int p = 0;
                          p < importProgress.pendingTracks.length;
                          p++) ...[
                        PendingImportTrackTile(
                          item: importProgress.pendingTracks[p],
                        ),
                        Divider(
                          height: 1,
                          indent: 74,
                          endIndent: 16,
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // 2. Existing tracks empty filter view
            if (filtered.isEmpty && importProgress.pendingTracks.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 160),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      border: Border(
                        top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                          width: 1,
                        ),
                        bottom: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              query.isNotEmpty
                                  ? Icons.search_off_rounded
                                  : (_segment == 'offline'
                                      ? Icons.download_for_offline_outlined
                                      : Icons.filter_list_off_rounded),
                              size: 36,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              query.isNotEmpty
                                  ? 'No tracks matching "$_searchQuery"'
                                  : (_segment == 'offline'
                                      ? 'No Pinned Offline Tracks'
                                      : 'No tracks in this view'),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              query.isNotEmpty
                                  ? 'Check your spelling or search our online and cloud streaming engine.'
                                  : (_segment == 'offline'
                                      ? 'Pin any song, playlist, or artist to listen without an internet connection.'
                                      : 'Try selecting a different filter or adding music to your library.'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (query.isNotEmpty) ...[
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 16),
                                    label: const Text('Clear Search'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => SearchScreen(
                                            initialQuery: _searchQuery,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                        Icons.travel_explore_rounded,
                                        size: 16),
                                    label: const Text('Search Online'),
                                  ),
                                ],
                              ),
                            ] else if (_segment == 'offline')
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  PixelHaptics.tick();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const CloudSyncSettingsScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.storage_rounded,
                                  size: 18,
                                ),
                                label: const Text('Manage Downloads'),
                              )
                            else
                              TextButton(
                                onPressed: () => setState(() {
                                  _segment = 'all';
                                  _selectedArtist = null;
                                }),
                                child: const Text('View All Tracks'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (filtered.isNotEmpty) ...[
              // Track List Header with Play / Select controls on the Left and Track Counter on the Right
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 20, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isMultiSelect) ...[
                        TextButton.icon(
                          onPressed: () => _toggleSelectAll(filtered),
                          icon: Icon(
                            isAllFilteredSelected
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                            size: 18,
                          ),
                          label: Text(
                            isAllFilteredSelected
                                ? 'Deselect All'
                                : 'Select All',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                      ] else ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              onPressed: () {
                                if (filtered.isNotEmpty) {
                                  PixelHaptics.playPauseToggle();
                                  ref.read(playbackProvider.notifier).playTrack(
                                        filtered.first,
                                        newQueue: filtered,
                                      );
                                }
                              },
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Play All',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: () => _enterMultiSelect(),
                              icon: const Icon(
                                Icons.checklist_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Select',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _isMultiSelect
                              ? '${_selectedTrackIds.length} of ${filtered.length} selected'
                              : (query.isNotEmpty
                                  ? 'Found ${filtered.length} ${filtered.length == 1 ? "track" : "tracks"}'
                                  : '${filtered.length} ${filtered.length == 1 ? "track" : "tracks"}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: query.isNotEmpty
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 3. Fully Virtualized Track List with RepaintBoundary per item for smooth 120Hz scrolling
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 160),
                sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    border: Border(
                      top: importProgress.pendingTracks.isEmpty
                          ? BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.25),
                              width: 1,
                            )
                          : BorderSide.none,
                      bottom: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                  ),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 74,
                      endIndent: 16,
                      color: cs.outlineVariant.withValues(alpha: 0.25),
                    ),
                    itemBuilder: (context, i) {
                      final track = filtered[i];
                      final isCurrent = activeTrackId == track.id;
                      final isPlaying = isCurrent && isPlaybackActive;

                      return SwipeToQueueWrapper(
                        key: ValueKey(track.id),
                        track: track,
                        enabled: !_isMultiSelect,
                        child: _LibraryTrackTile(
                          track: track,
                          isCurrent: isCurrent,
                          isPlaying: isPlaying,
                          durationText:
                              _formatTrackDuration(track.durationMs),
                          isMultiSelect: _isMultiSelect,
                          isSelected: _selectedTrackIds.contains(track.id),
                          onSelectToggle: () => _toggleSelectTrack(track.id),
                          onTap: () {
                            if (_isMultiSelect) {
                              _toggleSelectTrack(track.id);
                            } else {
                              ref
                                  .read(playbackProvider.notifier)
                                  .playTrack(track);
                            }
                          },
                          onLongPress: () {
                            if (_isMultiSelect) {
                              _toggleSelectTrack(track.id);
                            } else {
                              _enterMultiSelect(track.id);
                            }
                          },
                          onToggleFavorite: () {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .toggleFavorite(track.id);
                          },
                          onTogglePin: () {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .togglePinOffline(track.id);
                          },
                          onOptionsTap: () => _showTrackOptions(track),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ] else if (importProgress.pendingTracks.isNotEmpty)
              const SliverToBoxAdapter(
                child: SizedBox(height: 160),
              ),
          ],
        ],
      ],
      ),
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

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
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
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
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
    required this.onOptionsTap,
    this.isMultiSelect = false,
    this.isSelected = false,
    this.onSelectToggle,
    this.onLongPress,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePin;
  final VoidCallback onOptionsTap;
  final bool isMultiSelect;
  final bool isSelected;
  final VoidCallback? onSelectToggle;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        if (isMultiSelect) {
          onSelectToggle?.call();
        } else {
          onTap();
        }
      },
      onLongPress: () {
        PixelHaptics.sheetExpand();
        if (onLongPress != null) {
          onLongPress!();
        } else {
          onOptionsTap();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isMultiSelect) ...[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? cs.primary : cs.outlineVariant,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check_rounded, size: 16, color: cs.onPrimary)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
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
                          horizontal: 5,
                          vertical: 1.5,
                        ),
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
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (isMultiSelect) {
                              onSelectToggle?.call();
                            } else {
                              PixelHaptics.tick();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ArtistDetailsScreen(artistName: track.artist),
                                ),
                              );
                            }
                          },
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
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isMultiSelect) ...[
              MaterialYouDownloadButton(
                track: track,
                size: 20,
              ),
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
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                tooltip: 'Track Options',
                onPressed: () {
                  PixelHaptics.tick();
                  onOptionsTap();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BatchActionsFloatingBar extends StatelessWidget {
  const _BatchActionsFloatingBar({
    required this.selectedCount,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onToggleOffline,
    required this.onRemove,
    required this.onOptions,
  });

  final int selectedCount;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;
  final VoidCallback? onToggleOffline;
  final VoidCallback? onRemove;
  final VoidCallback? onOptions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = selectedCount > 0;

    return Center(
      child: Material(
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(32),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 350),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.playlist_play_rounded),
                tooltip: 'Play Next',
                onPressed: isEnabled ? onPlayNext : null,
              ),
              IconButton(
                icon: const Icon(Icons.queue_music_rounded),
                tooltip: 'Add to Queue',
                onPressed: isEnabled ? onAddToQueue : null,
              ),
              IconButton(
                icon: const Icon(Icons.playlist_add_rounded),
                tooltip: 'Add to Playlist',
                onPressed: isEnabled ? onAddToPlaylist : null,
              ),
              IconButton(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Download / Offline',
                onPressed: isEnabled ? onToggleOffline : null,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: isEnabled ? cs.error : null,
                ),
                tooltip: 'Remove from Library',
                onPressed: isEnabled ? onRemove : null,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded),
                tooltip: 'More Options',
                onPressed: isEnabled ? onOptions : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewPlaylistCard extends StatelessWidget {
  const _NewPlaylistCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_rounded,
                color: cs.onPrimaryContainer,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'New Playlist',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Custom curation',
              style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportPlaylistCard extends StatelessWidget {
  const _ImportPlaylistCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.secondary.withValues(alpha: 0.45),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.file_download_outlined,
                color: cs.onSecondaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Import Playlist',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Spotify, Apple, YouTube, .M3U',
              style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotifyAppleImportBanner extends StatelessWidget {
  const _SpotifyAppleImportBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PlatformAppIconGroup(size: 28, spacing: 8),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onTap,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Import'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Import Playlists & Tracks',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Paste Spotify, Apple Music, or YouTube links, tracklists, or .M3U8',
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

class _PlaylistGridCard extends StatelessWidget {
  const _PlaylistGridCard({
    required this.playlist,
    required this.tracks,
    required this.onTap,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: GenerativePlaylistCover(
                  playlist: playlist,
                  tracks: tracks,
                  size: double.infinity,
                  borderRadius: 18,
                  showBadge: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  if (playlist.isSmart) ...[
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 11,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      playlist.isSmart
                          ? '${playlist.trackCount} tracks • Smart'
                          : '${playlist.trackCount} tracks',
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
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

