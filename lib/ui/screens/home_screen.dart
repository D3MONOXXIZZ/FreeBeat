import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/signal_path_sheet.dart';
import 'artist_details_screen.dart';
import 'settings/settings_screen.dart';
import 'track_details_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();
  _HomeCategoryFilter _categoryFilter = _HomeCategoryFilter.all;
  bool _showSearchBar = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTrackDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showTrackOptionsModal(Track track) {
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Added to queue: ${track.title}'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
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
        );
      },
    );
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
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
    final picked =
        await authService.pickFromInstalledCloudApp(account: driveAccount);
    if (picked.isNotEmpty) {
      await ref.read(cloudAccountsProvider.notifier).addAccount(driveAccount, {});
      await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(picked);
      await PixelHaptics.hifiConfirm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${picked.length} tracks from Google Drive!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
    final picked =
        await authService.pickFromInstalledCloudApp(account: safAccount);
    if (picked.isNotEmpty) {
      await ref.read(cloudAccountsProvider.notifier).addAccount(safAccount, {});
      await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(picked);
      await PixelHaptics.hifiConfirm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Imported ${picked.length} tracks from device storage!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
    final playback = ref.watch(playbackProvider);
    final quality = ref.watch(audioQualityProvider).effectiveStreamingTier;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ─────────────────────────────────────────────────────────────────────
        // 1. Collapsing M3 Large Top App Bar with Greeting & Quick Actions
        // ─────────────────────────────────────────────────────────────────────
        SliverAppBar.large(
          expandedHeight: 148,
          pinned: true,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: SpringPressScale(
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
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsetsDirectional.only(start: 64, bottom: 14),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_getTimeGreeting()}, Alex',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  selectedArtist ?? selectedAlbum ?? 'Your Mix',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Search toggle icon
            IconButton(
              icon: Icon(
                _showSearchBar ? Icons.search_off_rounded : Icons.search_rounded,
                color: cs.onSurface,
              ),
              tooltip: 'Search Library',
              onPressed: () {
                PixelHaptics.tick();
                setState(() => _showSearchBar = !_showSearchBar);
              },
            ),

            // Hi-Fi Lossless Status Pill
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: FilledButton.tonal(
                onPressed: () {
                  PixelHaptics.sheetExpand();
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const SignalPathSheet(),
                  );
                },
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: const StadiumBorder(),
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.high_quality_rounded,
                      size: 16,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      quality.isLossless ? 'HI-FI' : '${quality.kbps}K',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
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
        // 2. Search Bar (Animated Expand)
        // ─────────────────────────────────────────────────────────────────────
        if (_showSearchBar)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (q) {
                  ref.read(searchQueryProvider.notifier).state = q;
                },
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, albums, FLAC...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchQueryProvider.notifier).state = '';
                            PixelHaptics.tick();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
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
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: artists.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final artist = artists[idx];
                        final isSelected = selectedArtist == artist.name;
                        return ChoiceChip(
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
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: albums.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final album = albums[idx];
                        final isSelected = selectedAlbum == album.title;
                        return ChoiceChip(
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

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 112,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildListDelegate([
                _PixelPlaylistCard(
                  title: 'Daily Mix',
                  subtitle: 'Adaptive Flow',
                  icon: Icons.auto_awesome_rounded,
                  onTap: () {
                    if (topPicks.isNotEmpty) {
                      ref
                          .read(playbackProvider.notifier)
                          .playTrack(topPicks.first, newQueue: topPicks);
                      widget.onOpenNowPlaying();
                    }
                  },
                ),
                _PixelPlaylistCard(
                  title: 'Lossless Hi-Fi',
                  subtitle: 'FLAC 24-Bit Masters',
                  icon: Icons.high_quality_rounded,
                  onTap: () {
                    ref.read(selectedCloudFilterProvider.notifier).state = 'hifi';
                  },
                ),
                _PixelPlaylistCard(
                  title: 'Poweramp DSP',
                  subtitle: '10-Band EQ & Knobs',
                  icon: Icons.graphic_eq_rounded,
                  onTap: () => widget.onNavigateToTab(2),
                ),
                _PixelPlaylistCard(
                  title: 'Cloud Storage',
                  subtitle: 'Drive & Media Servers',
                  icon: Icons.cloud_rounded,
                  onTap: () => widget.onNavigateToTab(3),
                ),
              ]),
            ),
          ),
        ],

        // ─────────────────────────────────────────────────────────────────────
        // 5. "Top Picks for Today" Section with Material You Album Covers
        // ─────────────────────────────────────────────────────────────────────
        if (allTracks.isNotEmpty &&
            selectedArtist == null &&
            selectedAlbum == null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
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
                        Flexible(
                          child: Text(
                            'Top Picks for Today',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      PixelHaptics.playPauseToggle();
                      ref.read(topPicksSeedProvider.notifier).state++;
                    },
                    icon: const Icon(Icons.casino_rounded, size: 14),
                    label: const Text('Shuffle',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
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
              height: 228,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                itemCount: topPicks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, idx) {
                  final track = topPicks[idx];
                  final isCurrent = playback.currentTrack.id == track.id;
                  final isPlaying = isCurrent && playback.isPlaying;

                  return SizedBox(
                    width: 154,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MaterialYouAlbumCover(
                          track: track,
                          size: 154,
                          borderRadius: 24,
                          showQualityBadge: true,
                          showSourceBadge: true,
                          showPlayButton: true,
                          isPlaying: isPlaying,
                          onPlayTap: () {
                            ref
                                .read(playbackProvider.notifier)
                                .playTrack(track, newQueue: topPicks);
                            widget.onOpenNowPlaying();
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
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

        // ─────────────────────────────────────────────────────────────────────
        // 6. "Artists in Your Library" Row with Circular Avatars
        // ─────────────────────────────────────────────────────────────────────
        if (artists.length > 1 &&
            selectedArtist == null &&
            selectedAlbum == null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.person_rounded, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Artists in Your Library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
              height: 114,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                itemCount: artists.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, idx) {
                  final artist = artists[idx];
                  return SpringPressScale(
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
                        ref
                            .read(selectedArtistFilterProvider.notifier)
                            .state = artist.name;
                      }
                    },
                    onLongPress: () {
                      PixelHaptics.tick();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistDetailsScreen(
                            artistName: artist.name,
                          ),
                        ),
                      );
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
                          width: 74,
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
                          '${artist.trackCount} songs',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
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

        // ─────────────────────────────────────────────────────────────────────
        // 7. "Featured Albums" Row
        // ─────────────────────────────────────────────────────────────────────
        if (albums.length > 1 &&
            selectedArtist == null &&
            selectedAlbum == null) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.album_rounded, size: 20, color: cs.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Albums',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${albums.length} albums',
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
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                itemCount: albums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, idx) {
                  final album = albums[idx];
                  return SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MaterialYouAlbumCover(
                          track: album.representativeTrack,
                          size: 120,
                          borderRadius: 20,
                          showQualityBadge: false,
                          showSourceBadge: true,
                          onPlayTap: () {
                            PixelHaptics.tick();
                            ref
                                .read(selectedAlbumFilterProvider.notifier)
                                .state = album.title;
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${album.artist} • ${album.trackCount}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: cs.onSurfaceVariant,
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

        // ─────────────────────────────────────────────────────────────────────
        // 8. Hero Empty State OR "Jump Back In" Track List
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
                    const SizedBox(height: 16),
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
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Load Demo Showcase Tracks'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ] else ...[
          // "Jump Back In" Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    selectedArtist != null
                        ? 'Tracks by $selectedArtist'
                        : selectedAlbum != null
                            ? 'Tracks in $selectedAlbum'
                            : 'Jump back in',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
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

          // Grouped 28dp Surface Card for Track List
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
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
                  child: tracks.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(28),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.filter_list_off_rounded,
                                    color: cs.onSurfaceVariant, size: 36),
                                const SizedBox(height: 10),
                                Text('No tracks match this filter',
                                    style: textTheme.titleMedium),
                                const SizedBox(height: 8),
                                FilledButton.tonal(
                                  onPressed: () {
                                    PixelHaptics.tick();
                                    ref
                                        .read(
                                            selectedArtistFilterProvider.notifier)
                                        .state = null;
                                    ref
                                        .read(
                                            selectedAlbumFilterProvider.notifier)
                                        .state = null;
                                    ref
                                        .read(
                                            selectedCloudFilterProvider.notifier)
                                        .state = 'all';
                                    setState(() => _categoryFilter =
                                        _HomeCategoryFilter.all);
                                  },
                                  child: const Text('Reset All Filters'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (int i = 0; i < tracks.length; i++) ...[
                              if (i > 0)
                                Divider(
                                  height: 1,
                                  indent: 76,
                                  endIndent: 16,
                                  color: cs.outlineVariant
                                      .withValues(alpha: 0.25),
                                ),
                              _PixelTrackTile(
                                track: tracks[i],
                                isCurrent:
                                    playback.currentTrack.id == tracks[i].id,
                                isPlaying:
                                    playback.currentTrack.id == tracks[i].id &&
                                        playback.isPlaying,
                                durationText:
                                    _formatTrackDuration(tracks[i].durationMs),
                                onTap: () {
                                  ref
                                      .read(playbackProvider.notifier)
                                      .playTrack(tracks[i], newQueue: tracks);
                                },
                                onToggleFavorite: () {
                                  ref
                                      .read(tracksCatalogProvider.notifier)
                                      .toggleFavorite(tracks[i].id);
                                },
                                onOpenOptions: () {
                                  _showTrackOptionsModal(tracks[i]);
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

    return SpringPressScale(
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

class _PixelTrackTile extends StatelessWidget {
  const _PixelTrackTile({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.durationText,
    required this.onTap,
    required this.onToggleFavorite,
    required this.onOpenOptions,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final String durationText;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenOptions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Material You Album Cover Thumbnail with Equalizer State
            MaterialYouAlbumCover(
              track: track,
              size: 50,
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
            IconButton(
              icon: Icon(
                track.isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: track.isFavorite ? cs.error : cs.onSurfaceVariant,
                size: 20,
              ),
              onPressed: () {
                PixelHaptics.tick();
                onToggleFavorite();
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 20,
              ),
              tooltip: 'Track Options',
              onPressed: () {
                PixelHaptics.tick();
                onOpenOptions();
              },
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
