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
import 'settings/settings_screen.dart';
import 'track_details_screen.dart';
import '../../core/models/playlist.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/generative_playlist_cover.dart';
import '../widgets/material_you_download_button.dart';
import '../widgets/swipe_to_queue_wrapper.dart';

/// Stock Google Pixel Material 3 Expressive Library Screen.
/// Strictly implements Screen 5 ("# Your Library") in Figma inspiration:
/// 1. Top App Bar with Search, Profile/Settings icon
/// 2. Stadium-pill filter chips (All Tracks, Hi-Res, Offline, Liked)
/// 3. Artists Avatar Row: horizontal scroll of artist circular avatars (Alexter, Teritona, etc.)
/// 4. Playlists 2-Column Curated Cards (Organic Playlists, Daily Mix, Add Music)
/// 5. Grouped 28dp Surface Card for Track List
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _segment = 'all'; // 'all', 'hires', 'offline', 'favorites'
  String? _selectedArtist;

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
      onFilesSelected: (filenames) {
        progressNotifier.startWithFiles(filenames);
      },
      onProgress: (current, total, track) {
        progressNotifier.update(
          current: current,
          total: total,
          name: track?.title ?? '',
          track: track,
        );
        if (track != null) {
          ref.read(tracksCatalogProvider.notifier).addIndexedTracks([track]);
        }
      },
    );
    progressNotifier.complete();
    if (picked.isNotEmpty) {
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
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                ],
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

    // Extract unique artists
    final artists = allTracks
        .map((t) => t.artist)
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList();

    final filtered = allTracks.where((t) {
      if (_selectedArtist != null && t.artist != _selectedArtist) {
        return false;
      }
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

    final hasActiveTrack = activeTrackId.isNotEmpty;
    final bottomFabPadding = MediaQuery.of(context).padding.bottom +
        (hasActiveTrack ? 156.0 : 88.0);

    return Scaffold(
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: bottomFabPadding, right: 8),
        child: FloatingActionButton(
          shape: const CircleBorder(),
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          tooltip: _segment == 'playlists' ? 'New Playlist' : 'Add Music',
          onPressed: _segment == 'playlists'
              ? _showCreatePlaylistDialog
              : _pickLocalFiles,
          child: Icon(
            _segment == 'playlists'
                ? Icons.playlist_add_rounded
                : Icons.add_rounded,
            size: 28,
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
                fontWeight: FontWeight.w800,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: _segment == 'playlists' ? 'New Playlist' : 'Add Music',
                onPressed: () {
                  PixelHaptics.tick();
                  if (_segment == 'playlists') {
                    _showCreatePlaylistDialog();
                  } else {
                    _pickLocalFiles();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded),
                tooltip: 'Search Library',
                onPressed: () {
                  PixelHaptics.tick();
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () {
                  PixelHaptics.tick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
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
            // ─────────────────────────────────────────────────────────────────
            // Curated & Smart Playlists 2-Column Responsive Grid
            // ─────────────────────────────────────────────────────────────────
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
                    if (index == 0) {
                      return _NewPlaylistCard(
                        onTap: _showCreatePlaylistDialog,
                      );
                    }
                    final playlist = allPlaylists[index - 1];
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
                  },
                  childCount: allPlaylists.length + 1,
                ),
              ),
            ),
          ] else ...[
            // ─────────────────────────────────────────────────────────────────
            // 3. Figma Screen 5: Artists Avatars Horizontal Row (when available)
            // ─────────────────────────────────────────────────────────────────
          if (artists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Artists',
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
                  itemCount: artists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
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
          // 4. Edge-to-Edge Surface Card for Track List
          // ───────────────────────────────────────────────────────────────────
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
                child: allTracks.isEmpty && importProgress.pendingTracks.isEmpty
                    ? Padding(
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
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. Pending Import Songs (all show up together, greyed out with filling circle indicators)
                          if (importProgress.pendingTracks.isNotEmpty) ...[
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
                                    'Importing ${importProgress.pendingTracks.length} Songs (${importProgress.current}/${importProgress.total})',
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
                              _PendingImportTrackTile(
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

                          // 2. Existing tracks in view
                          if (filtered.isEmpty &&
                              importProgress.pendingTracks.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(28),
                              child: Center(
                                child: Column(
                                  children: [
                                    Icon(Icons.filter_list_off_rounded,
                                        size: 32, color: cs.onSurfaceVariant),
                                    const SizedBox(height: 8),
                                    Text('No tracks in this view',
                                        style: textTheme.titleMedium),
                                    const SizedBox(height: 8),
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
                            )
                          else
                            for (int i = 0; i < filtered.length; i++) ...[
                              if (i > 0 &&
                                  importProgress.pendingTracks.isEmpty)
                                Divider(
                                  height: 1,
                                  indent: 74,
                                  endIndent: 16,
                                  color: cs.outlineVariant
                                      .withValues(alpha: 0.25),
                                ),
                              SwipeToQueueWrapper(
                                track: filtered[i],
                                child: _LibraryTrackTile(
                                  track: filtered[i],
                                  isCurrent:
                                      activeTrackId == filtered[i].id,
                                  isPlaying:
                                      activeTrackId == filtered[i].id &&
                                          isPlaybackActive,
                                  durationText: _formatTrackDuration(
                                      filtered[i].durationMs),
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
                                  onOptionsTap: () =>
                                      _showTrackOptions(filtered[i]),
                                ),
                              ),
                            ],
                        ],
                      ),
              ),
            ),
          ),
        ],
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
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTogglePin;
  final VoidCallback onOptionsTap;

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
                            PixelHaptics.tick();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ArtistDetailsScreen(artistName: track.artist),
                              ),
                            );
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

class _PendingImportTrackTile extends StatelessWidget {
  const _PendingImportTrackTile({required this.item});

  final PendingImportTrack item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Opacity(
      opacity: item.isCompleted ? 0.95 : 0.60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Album art container with circular progress indicator
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.isCompleted
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Center(
                child: item.isCompleted
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: cs.onPrimaryContainer,
                        size: 26,
                      )
                    : SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: item.progress > 0 ? item.progress : null,
                          strokeWidth: 2.8,
                          color: cs.primary,
                          backgroundColor:
                              cs.outlineVariant.withValues(alpha: 0.30),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: item.isCompleted
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isCompleted ? '${item.artist} • Ready' : item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.isCompleted ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: item.isCompleted
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.isCompleted)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ready',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              )
            else if (item.progress > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${(item.progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

