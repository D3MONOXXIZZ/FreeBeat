import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/metadata/artist_helper.dart';
import '../../state/app_providers.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/material_you_download_button.dart';
import 'artist_details_screen.dart';
import 'settings/settings_screen.dart';
import 'track_details_screen.dart';
import 'search_screen.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/cloud_sync_progress_banner.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/remove_track_dialog.dart';
import '../widgets/track_metadata_editor_modal.dart';
import '../widgets/ultra_free_scroll_physics.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

enum _HomeCategoryFilter {
  all('All', Icons.grid_view_rounded),
  topPicks('Top Picks', Icons.auto_awesome_rounded),
  artists('Artists', Icons.person_rounded),
  albums('Albums', Icons.album_rounded),
  hifi('Hi-Fi 24-Bit', Icons.high_quality_rounded),
  offline('Offline', Icons.download_done_rounded);

  const _HomeCategoryFilter(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Stock Google Pixel Material 3 Expressive Home Screen.
/// Features:
/// 1. Time-aware header with user profile avatar, greeting, weather badge, and Hi-Fi pill
/// 2. Expressive Category & Filter Hub (All, Top Picks, Artists, Albums, Hi-Fi, Offline)
/// 3. Dynamic Artist & Album selector filter chips
/// 4. "Top Picks for Today" section featuring Material You container album covers
/// 5. "Artists in Your Library" circular avatar row with track counts
/// 6. "Featured Albums" row with Material You styled artwork
/// 7. "Jump back in" track collection in unified 28dp surface container with Pixel LRA haptics
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenNowPlaying,
    required this.onNavigateToTab,
  });

  final VoidCallback onOpenNowPlaying;
  final ValueChanged<int> onNavigateToTab;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeCategoryFilter _categoryFilter = _HomeCategoryFilter.all;

  void _showTrackOptionsModal(Track track) {
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
                            size: 52,
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
                                  '${track.artist} • ${track.album}',
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
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Added to queue: ${track.title}'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.playlist_add_rounded),
                          title: const Text('Add to Playlist',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Add to custom or new playlist'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showAddToPlaylistModal(context, track);
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
                        ...() {
                          final trackArtists = ArtistHelper.extractArtists(track.artist, track.title);
                          if (trackArtists.length > 1) {
                            return trackArtists.map((a) => ListTile(
                              leading: const Icon(Icons.person_rounded),
                              title: Text('View Artist: $a',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ArtistDetailsScreen(artistName: a),
                                  ),
                                );
                              },
                            ));
                          }
                          final aName = trackArtists.isNotEmpty ? trackArtists.first : track.artist;
                          return [
                            ListTile(
                              leading: const Icon(Icons.person_rounded),
                              title: Text('View Artist: $aName',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              onTap: () {
                                Navigator.of(ctx).pop();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ArtistDetailsScreen(artistName: aName),
                                  ),
                                );
                              },
                            ),
                          ];
                        }(),
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

  Future<void> _pickGoogleDriveMusic() async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    const driveAccount = CloudAccount(
      id: 'gdrive_quick',
      providerType: CloudProviderType.googleDrive,
      displayName: 'Google Drive',
      endpointOrFolder: 'Google Drive App Storage',
    );
    final progressNotifier = ref.read(importProgressProvider.notifier);
    final picked = await authService.pickFromInstalledCloudApp(
      account: driveAccount,
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
      await ref.read(cloudAccountsProvider.notifier).addAccount(driveAccount, {});
      await PixelHaptics.hifiConfirm();
      progressNotifier.complete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${picked.length} tracks from Google Drive!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      progressNotifier.clearPending();
    }
  }

  Future<void> _pickLocalAudio() async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    const safAccount = CloudAccount(
      id: 'local_storage',
      providerType: CloudProviderType.androidSaf,
      displayName: 'Device Storage',
      endpointOrFolder: 'Local Music Files',
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
      await ref.read(cloudAccountsProvider.notifier).addAccount(safAccount, {});
      await PixelHaptics.hifiConfirm();
      progressNotifier.complete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Imported ${picked.length} tracks from device storage!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      progressNotifier.clearPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tracks = ref.watch(filteredTracksProvider);
    final allTracks = ref.watch(tracksCatalogProvider);
    final topPicks = ref.watch(topPicksProvider);
    final artists = ref.watch(availableArtistsProvider);
    final albums = ref.watch(availableAlbumsProvider);
    final selectedArtist = ref.watch(selectedArtistFilterProvider);
    final selectedAlbum = ref.watch(selectedAlbumFilterProvider);
    final currentTrackId =
        ref.watch(playbackProvider.select((p) => p.currentTrack.id));
    final isPlaying =
        ref.watch(playbackProvider.select((p) => p.isPlaying));
    final importProgress = ref.watch(importProgressProvider);

    return CustomScrollView(
      physics: buildSuperSmoothScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.viewport(1.5),
      slivers: [
        // ─────────────────────────────────────────────────────────────────────
        // 1. Collapsing M3 Large Top App Bar with Greeting & Quick Actions
        // ─────────────────────────────────────────────────────────────────────
        SliverAppBar.large(
          expandedHeight: 120,
          pinned: true,
          flexibleSpace: const FlexibleSpaceBar(),
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  PixelHaptics.tick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.person_rounded,
                    color: cs.onPrimaryContainer,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          title: Text(
            selectedArtist ?? selectedAlbum ?? 'Your Mix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          actions: [
            // Search button
            IconButton(
              icon: Icon(
                Icons.search_rounded,
                color: cs.onSurface,
              ),
              tooltip: 'Search Library',
              onPressed: () {
                PixelHaptics.tick();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchScreen()),
                );
              },
            ),

            // Settings Screen Button
            IconButton(
              icon: Icon(Icons.settings_outlined, color: cs.onSurface),
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

        // ─────────────────────────────────────────────────────────────────────
        // Import Progress Bar (Real-Time Loading Bar)
        // ─────────────────────────────────────────────────────────────────────
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

        // ─────────────────────────────────────────────────────────────────────
        // Cloud Missing Track Sync Progress Banner
        // ─────────────────────────────────────────────────────────────────────
        const SliverToBoxAdapter(
          child: CloudSyncProgressBanner(),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 2. Pixel M3 Expressive Search Bar
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Material(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(100),
              child: InkWell(
                borderRadius: BorderRadius.circular(100),
                onTap: () {
                  PixelHaptics.tick();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchScreen()),
                  );
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: cs.onSurfaceVariant,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search songs, artists, FLAC, Hi-Res...',
                          style: TextStyle(
                            fontSize: 14,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Hi-Fi',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: cs.onSecondaryContainer,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 3. Category Filter Pills Row (All, Top Picks, Artists, Albums, Hi-Fi, Offline)
        // ─────────────────────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: SizedBox(
              height: 46,
              child: SuperListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: buildSuperSmoothScrollPhysics(),
                cacheExtent: 300,
                children: [
                  for (final cat in _HomeCategoryFilter.values) ...[
                    _PixelCategoryPill(
                      label: cat.label,
                      icon: cat.icon,
                      isSelected: _categoryFilter == cat,
                      onTap: () {
                        PixelHaptics.tick();
                        setState(() => _categoryFilter = cat);

                        if (cat == _HomeCategoryFilter.hifi) {
                          ref.read(selectedCloudFilterProvider.notifier).state =
                              'hifi';
                        } else if (cat == _HomeCategoryFilter.offline) {
                          ref.read(selectedCloudFilterProvider.notifier).state =
                              'offline';
                        } else {
                          ref.read(selectedCloudFilterProvider.notifier).state =
                              'all';
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────────────
        // 4. Dynamic Artist / Album Filter Carousel
        // ─────────────────────────────────────────────────────────────────────
        if (_categoryFilter == _HomeCategoryFilter.artists && artists.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.25),
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
                          Icon(Icons.person_pin_rounded,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Filter by Artist (${artists.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (selectedArtist != null)
                        TextButton(
                          onPressed: () {
                            PixelHaptics.tick();
                            ref
                                .read(selectedArtistFilterProvider.notifier)
                                .state = null;
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Show All',
                              style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: SuperListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: buildSuperSmoothScrollPhysics(),
                      cacheExtent: 300,
                      itemCount: artists.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final artist = artists[idx];
                        final isSelected = selectedArtist == artist.name;
                        return ChoiceChip(
                          key: ValueKey('filter_chip_artist_${artist.name}'),
                          label: Text('${artist.name} (${artist.trackCount})'),
                          selected: isSelected,
                          onSelected: (selected) {
                            PixelHaptics.tick();
                            ref
                                .read(selectedArtistFilterProvider.notifier)
                                .state = selected ? artist.name : null;
                          },
                          shape: const StadiumBorder(),
                          avatar: isSelected
                              ? const Icon(Icons.check_rounded, size: 14)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_categoryFilter == _HomeCategoryFilter.albums &&
            albums.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.25),
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
                          Icon(Icons.album_rounded,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Filter by Album (${albums.length})',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (selectedAlbum != null)
                        TextButton(
                          onPressed: () {
                            PixelHaptics.tick();
                            ref
                                .read(selectedAlbumFilterProvider.notifier)
                                .state = null;
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Show All',
                              style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: SuperListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: buildSuperSmoothScrollPhysics(),
                      cacheExtent: 300,
                      itemCount: albums.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final album = albums[idx];
                        final isSelected = selectedAlbum == album.title;
                        return ChoiceChip(
                          key: ValueKey('filter_chip_album_${album.title}'),
                          label: Text(album.title),
                          selected: isSelected,
                          onSelected: (selected) {
                            PixelHaptics.tick();
                            ref
                                .read(selectedAlbumFilterProvider.notifier)
                                .state = selected ? album.title : null;
                          },
                          shape: const StadiumBorder(),
                          avatar: isSelected
                              ? const Icon(Icons.check_rounded, size: 14)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Active Filter Banner (if an artist or album is active)
        if (selectedArtist != null || selectedAlbum != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      selectedArtist != null
                          ? Icons.person_rounded
                          : Icons.album_rounded,
                      size: 16,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedArtist != null
                            ? 'Artist: $selectedArtist (${tracks.length} tracks)'
                            : 'Album: $selectedAlbum (${tracks.length} tracks)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        PixelHaptics.tick();
                        ref
                            .read(selectedArtistFilterProvider.notifier)
                            .state = null;
                        ref
                            .read(selectedAlbumFilterProvider.notifier)
                            .state = null;
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // ─────────────────────────────────────────────────────────────────────
        // "Pixel Playlists" Curated Shortcuts Grid
        // ─────────────────────────────────────────────────────────────────────
        if (selectedArtist == null && selectedAlbum == null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pixel Playlists',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onNavigateToTab(1),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _PixelPlaylistCard(
                title: 'Daily Mix',
                subtitle:
                    'Adaptive Flow • ${topPicks.isNotEmpty ? topPicks.length : allTracks.length} tracks',
                icon: Icons.auto_awesome_rounded,
                onTap: () {
                  if (topPicks.isNotEmpty) {
                    ref
                        .read(playbackProvider.notifier)
                        .playTrack(topPicks.first, newQueue: topPicks);
                    widget.onOpenNowPlaying();
                  } else if (allTracks.isNotEmpty) {
                    ref
                        .read(playbackProvider.notifier)
                        .playTrack(allTracks.first, newQueue: allTracks);
                    widget.onOpenNowPlaying();
                  }
                },
              ),
            ),
          ),
        ],

        // ─────────────────────────────────────────────────────────────────────
        // 5. Hero Empty State (when no tracks exist in catalog)
        // ─────────────────────────────────────────────────────────────────────
        if (allTracks.isEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 140),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        size: 38,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your Music, Everywhere',
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import your music directly from Google Drive or device storage to stream lossless audio anywhere with zero subscriptions.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () {
                        PixelHaptics.tick();
                        widget.onNavigateToTab(3);
                      },
                      icon: const Icon(Icons.cloud_sync_rounded, size: 20),
                      label: const Text('Connect Cloud Storage'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _pickGoogleDriveMusic,
                      icon: const Icon(Icons.add_to_drive_rounded, size: 20),
                      label: const Text('Pick from Google Drive'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _pickLocalAudio,
                      icon: const Icon(Icons.folder_open_rounded, size: 20),
                      label: const Text('Import from Device Storage'),
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else if (selectedArtist != null || selectedAlbum != null) ...[
          // ─────────────────────────────────────────────────────────────────
          // Filtered Tracks Section (Pure Cover Art Horizontal Carousel)
          // ─────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      selectedArtist != null
                          ? 'Tracks by $selectedArtist'
                          : 'Tracks in $selectedAlbum',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Text(
                    '${tracks.length} tracks',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 254,
              child: SuperListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: buildSuperSmoothScrollPhysics(),
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
                cacheExtent: 500,
                itemCount: tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, idx) {
                  final track = tracks[idx];
                  final isCurrent = currentTrackId == track.id;
                  return _PixelCoverCard(
                    key: ValueKey('home_filtered_${track.id}'),
                    track: track,
                    isCurrent: isCurrent,
                    isPlaying: isCurrent && isPlaying,
                    onTap: () {
                      ref
                          .read(playbackProvider.notifier)
                          .playTrack(track, newQueue: tracks);
                      widget.onOpenNowPlaying();
                    },
                    onToggleFavorite: () {
                      ref
                          .read(tracksCatalogProvider.notifier)
                          .toggleFavorite(track.id);
                    },
                    onOpenOptions: () => _showTrackOptionsModal(track),
                  );
                },
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
        ] else ...[
          // ─────────────────────────────────────────────────────────────────
          // 6. "New Albums" Section (Horizontally Scrollable Cover Art)
          // ─────────────────────────────────────────────────────────────────
          if (albums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.album_rounded,
                            size: 18,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'New Albums',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        PixelHaptics.tick();
                        setState(() => _categoryFilter = _HomeCategoryFilter.albums);
                      },
                      child: Text('${albums.length} albums'),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 216,
                child: SuperListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: buildSuperSmoothScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  cacheExtent: 500,
                  itemCount: albums.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final album = albums[idx];
                    return _PixelAlbumCoverCard(
                      key: ValueKey('home_album_${album.title}'),
                      album: album,
                      onTap: () {
                        PixelHaptics.tick();
                        ref.read(selectedAlbumFilterProvider.notifier).state =
                            album.title;
                      },
                      onPlay: () {
                        final albumTracks = allTracks
                            .where((t) => t.album == album.title)
                            .toList();
                        if (albumTracks.isNotEmpty) {
                          ref
                              .read(playbackProvider.notifier)
                              .playTrack(albumTracks.first, newQueue: albumTracks);
                          widget.onOpenNowPlaying();
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ],

          // ─────────────────────────────────────────────────────────────────
          // 7. "Recently Added" Section (Horizontally Scrollable Cover Art)
          // ─────────────────────────────────────────────────────────────────
          if (allTracks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.schedule_rounded,
                            size: 18,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Recently Added',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${allTracks.length} tracks',
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 254,
                child: SuperListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: buildSuperSmoothScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  cacheExtent: 500,
                  itemCount: allTracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final track = allTracks[allTracks.length - 1 - idx];
                    final isCurrent = currentTrackId == track.id;
                    return _PixelCoverCard(
                      key: ValueKey('home_recent_${track.id}'),
                      track: track,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && isPlaying,
                      onTap: () {
                        ref
                            .read(playbackProvider.notifier)
                            .playTrack(track, newQueue: allTracks);
                        widget.onOpenNowPlaying();
                      },
                      onToggleFavorite: () {
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .toggleFavorite(track.id);
                      },
                      onOpenOptions: () => _showTrackOptionsModal(track),
                    );
                  },
                ),
              ),
            ),
          ],

          // ─────────────────────────────────────────────────────────────────
          // 8. "Top Picks for Today" Section (Horizontally Scrollable Cover Art)
          // ─────────────────────────────────────────────────────────────────
          if (topPicks.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Top Picks for Today',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        PixelHaptics.playPauseToggle();
                        ref.read(topPicksSeedProvider.notifier).state++;
                      },
                      icon: const Icon(Icons.casino_rounded, size: 14),
                      label: const Text('Shuffle',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 32),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 254,
                child: SuperListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: buildSuperSmoothScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  cacheExtent: 500,
                  itemCount: topPicks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final track = topPicks[idx];
                    final isCurrent = currentTrackId == track.id;
                    return _PixelCoverCard(
                      key: ValueKey('home_top_picks_${track.id}'),
                      track: track,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && isPlaying,
                      onTap: () {
                        ref
                            .read(playbackProvider.notifier)
                            .playTrack(track, newQueue: topPicks);
                        widget.onOpenNowPlaying();
                      },
                      onToggleFavorite: () {
                        ref
                            .read(tracksCatalogProvider.notifier)
                            .toggleFavorite(track.id);
                      },
                      onOpenOptions: () => _showTrackOptionsModal(track),
                    );
                  },
                ),
              ),
            ),
          ],

          // ─────────────────────────────────────────────────────────────────
          // 9. "Artists in Your Library" Section (Horizontally Scrollable Avatars)
          // ─────────────────────────────────────────────────────────────────
          if (artists.length > 1) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: cs.tertiaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.person_rounded,
                            size: 18,
                            color: cs.onTertiaryContainer,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Artists in Your Library',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${artists.length} artists',
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 124,
                child: SuperListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: buildSuperSmoothScrollPhysics(),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  cacheExtent: 500,
                  itemCount: artists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, idx) {
                    final artist = artists[idx];
                    return RepaintBoundary(
                      key: ValueKey('home_artist_${artist.name}'),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          PixelHaptics.tick();
                          if (ref.read(selectedArtistFilterProvider) == artist.name) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ArtistDetailsScreen(
                                  artistName: artist.name,
                                ),
                              ),
                            );
                          } else {
                            ref.read(selectedArtistFilterProvider.notifier).state =
                                artist.name;
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cs.surfaceContainerHigh,
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                              ),
                              child: ClipOval(
                                child: MaterialYouAlbumCover(
                                  track: artist.representativeTrack,
                                  size: 68,
                                  borderRadius: 34,
                                  showQualityBadge: false,
                                  showSourceBadge: false,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 78,
                              child: Text(
                                artist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${artist.trackCount} ${artist.trackCount == 1 ? "track" : "tracks"}',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subcomponents
// ─────────────────────────────────────────────────────────────────────────────

class _PixelCategoryPill extends StatelessWidget {
  const _PixelCategoryPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelPlaylistCard extends StatelessWidget {
  const _PixelPlaylistCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      scaleDown: 0.97,
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: cs.onPrimary,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Squircle Cover Art Card for tracks with Material You play button & download button.
/// Strictly horizontally scrollable with spring press scale physics.
class _PixelCoverCard extends StatelessWidget {
  const _PixelCoverCard({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onOpenOptions,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenOptions;

  static const double cardWidth = 154;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SpringPressScale(
              scaleDown: 0.96,
              onTap: onTap,
              onLongPress: onOpenOptions,
              child: MaterialYouAlbumCover(
                track: track,
                size: cardWidth,
                borderRadius: 24,
                showQualityBadge: true,
                showSourceBadge: true,
                showPlayButton: true,
                isPlaying: isPlaying,
                onPlayTap: onTap,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
                      color: isCurrent ? cs.primary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MaterialYouDownloadButton(
                  track: track,
                  size: 22,
                ),
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: Icon(
                    track.isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: track.isFavorite ? cs.error : cs.onSurfaceVariant,
                  ),
                  onPressed: () {
                    PixelHaptics.tick();
                    onToggleFavorite();
                  },
                ),
                IconButton(
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(Icons.more_vert_rounded),
                  color: cs.onSurfaceVariant,
                  onPressed: () {
                    PixelHaptics.tick();
                    onOpenOptions();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Squircle Album Cover Card for New Albums section with spring press physics.
class _PixelAlbumCoverCard extends StatelessWidget {
  const _PixelAlbumCoverCard({
    super.key,
    required this.album,
    required this.onTap,
    required this.onPlay,
  });

  final AlbumInfo album;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  static const double cardWidth = 154;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SpringPressScale(
              scaleDown: 0.96,
              onTap: onTap,
              child: MaterialYouAlbumCover(
                track: album.representativeTrack,
                size: cardWidth,
                borderRadius: 24,
                showQualityBadge: false,
                showSourceBadge: true,
                showPlayButton: true,
                onPlayTap: onPlay,
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${album.artist} • ${album.trackCount} ${album.trackCount == 1 ? "track" : "tracks"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}


