import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/metadata/artist_helper.dart';
import '../../services/search/audiophile_search_engine.dart';
import '../../services/search/search_history_service.dart';
import '../../state/app_providers.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/generative_playlist_cover.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/material_you_download_button.dart';
import '../widgets/remove_track_dialog.dart';
import '../widgets/swipe_to_queue_wrapper.dart';
import '../widgets/track_metadata_editor_modal.dart';
import 'artist_details_screen.dart';
import 'playlist_details_screen.dart';
import 'track_details_screen.dart';
import '../widgets/ultra_free_scroll_physics.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Stock Google Pixel Material 3 Expressive Global Search & Audiophile Filtering Screen.
/// Provides real-time instant search across all connected clouds and local storage with
/// codec filters (FLAC, WMA, M4A, WAV), Hi-Res 24-bit filtering, and persistent search history.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    this.initialQuery,
    this.initialFilter = SearchFilterType.all,
  });

  final String? initialQuery;
  final SearchFilterType initialFilter;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late SearchFilterType _activeFilter;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    _focusNode = FocusNode();
    _activeFilter = widget.initialFilter;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQuerySubmitted(String query) {
    if (query.trim().isNotEmpty) {
      ref.read(searchHistoryServiceProvider).addQuery(query);
    }
  }

  void _applyRecentQuery(String query) {
    PixelHaptics.tick();
    _controller.text = query;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );
    setState(() {});
    ref.read(searchHistoryServiceProvider).addQuery(query);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allTracks = ref.watch(tracksCatalogProvider);
    final allPlaylists = ref.watch(playlistsProvider);
    final historyService = ref.watch(searchHistoryServiceProvider);
    final currentTrackId =
        ref.watch(playbackProvider.select((p) => p.currentTrack.id));
    final isPlaying =
        ref.watch(playbackProvider.select((p) => p.isPlaying));

    final query = _controller.text;
    final results = AudiophileSearchEngine.search(
      query: query,
      allTracks: allTracks,
      allPlaylists: allPlaylists,
      filter: _activeFilter,
    );

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: buildSuperSmoothScrollPhysics(),
          scrollCacheExtent: const ScrollCacheExtent.pixels(450),
          slivers: [
            // 1. Search Bar Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back',
                      onPressed: () {
                        PixelHaptics.tick();
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Container(
                        height: 52,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus: widget.initialQuery == null,
                          textInputAction: TextInputAction.search,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _onQuerySubmitted,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            fillColor: Colors.transparent,
                            hintText: 'Search songs, artists, FLAC, WMA...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: cs.primary,
                              size: 22,
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 18),
                                    onPressed: () {
                                      PixelHaptics.tick();
                                      _controller.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Horizontally Scrollable Filter Chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: SuperListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  physics: buildSuperSmoothScrollPhysics(),
                  itemCount: SearchFilterType.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final filter = SearchFilterType.values[idx];
                    final isSelected = _activeFilter == filter;

                    IconData? chipIcon;
                    switch (filter) {
                      case SearchFilterType.hiRes:
                        chipIcon = Icons.auto_awesome_rounded;
                        break;
                      case SearchFilterType.offline:
                        chipIcon = Icons.download_done_rounded;
                        break;
                      case SearchFilterType.flac:
                      case SearchFilterType.wma:
                      case SearchFilterType.m4a:
                      case SearchFilterType.wav:
                      case SearchFilterType.mp3:
                        chipIcon = Icons.audio_file_rounded;
                        break;
                      case SearchFilterType.artists:
                        chipIcon = Icons.person_rounded;
                        break;
                      case SearchFilterType.albums:
                        chipIcon = Icons.album_rounded;
                        break;
                      case SearchFilterType.playlists:
                        chipIcon = Icons.queue_music_rounded;
                        break;
                      case SearchFilterType.all:
                        chipIcon = Icons.all_inclusive_rounded;
                        break;
                    }

                    return FilterChip(
                      selected: isSelected,
                      showCheckmark: false,
                      avatar: Icon(
                        chipIcon,
                        size: 16,
                        color: isSelected
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                      label: Text(
                        filter.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      backgroundColor: cs.surfaceContainerHigh,
                      selectedColor: cs.primaryContainer,
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: isSelected
                              ? cs.primary
                              : cs.outlineVariant.withValues(alpha: 0.3),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      onSelected: (_) {
                        PixelHaptics.tick();
                        setState(() {
                          _activeFilter = filter;
                        });
                      },
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // 3. Content Area
            if (query.trim().isEmpty && _activeFilter == SearchFilterType.all) ...[
              // Recent Searches
              if (historyService.history.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Searches',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            PixelHaptics.tick();
                            historyService.clearHistory();
                          },
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: historyService.history.map((q) {
                        return InputChip(
                          avatar: Icon(
                            Icons.history_rounded,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          label: Text(q,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                          backgroundColor: cs.surfaceContainerHigh,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          onPressed: () => _applyRecentQuery(q),
                          onDeleted: () {
                            PixelHaptics.tick();
                            historyService.removeQuery(q);
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],

              // Quick Audiophile Shortcuts
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Text(
                    'Explore Audiophile Audio',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.2,
                  ),
                  delegate: SliverChildListDelegate([
                    _ExploreCard(
                      title: 'Hi-Res Lossless',
                      subtitle: '24-bit / 96kHz+',
                      icon: Icons.auto_awesome_rounded,
                      color: cs.primary,
                      onTap: () {
                        PixelHaptics.tick();
                        setState(() => _activeFilter = SearchFilterType.hiRes);
                      },
                    ),
                    _ExploreCard(
                      title: 'Downloaded',
                      subtitle: 'Offline listening',
                      icon: Icons.download_done_rounded,
                      color: cs.tertiary,
                      onTap: () {
                        PixelHaptics.tick();
                        setState(
                            () => _activeFilter = SearchFilterType.offline);
                      },
                    ),
                    _ExploreCard(
                      title: 'FLAC Master',
                      subtitle: 'Studio master audio',
                      icon: Icons.audio_file_rounded,
                      color: cs.secondary,
                      onTap: () {
                        PixelHaptics.tick();
                        setState(() => _activeFilter = SearchFilterType.flac);
                      },
                    ),
                    _ExploreCard(
                      title: 'WMA & M4A',
                      subtitle: 'All format playback',
                      icon: Icons.graphic_eq_rounded,
                      color: cs.error,
                      onTap: () {
                        PixelHaptics.tick();
                        setState(() => _activeFilter = SearchFilterType.wma);
                      },
                    ),
                  ]),
                ),
              ),
            ] else if (results.isEmpty) ...[
              // No Results Found State
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          query.isNotEmpty
                              ? 'No matches for "$query"'
                              : 'No tracks match ${_activeFilter.label}',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Try checking for spelling or switching your filter chips.',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (_activeFilter != SearchFilterType.all) ...[
                          const SizedBox(height: 16),
                          FilledButton.tonal(
                            onPressed: () {
                              PixelHaptics.tick();
                              setState(() {
                                _activeFilter = SearchFilterType.all;
                              });
                            },
                            child: const Text('Show All Formats'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              // 4. Search Results Content

              // Top Result Card (if applicable)
              if (results.topMatch != null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Text(
                      'Top Result',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _TopResultCard(
                      track: results.topMatch!,
                      isCurrent: currentTrackId == results.topMatch!.id,
                      isPlaying: isPlaying,
                      onTap: () {
                        _onQuerySubmitted(query);
                        ref
                            .read(playbackProvider.notifier)
                            .playTrack(results.topMatch!,
                                newQueue: results.tracks);
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],

              // Matching Artists Carousel
              if (results.artists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Text(
                      'Artists (${results.artists.length})',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 104,
                    child: SuperListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      physics: buildSuperSmoothScrollPhysics(),
                      itemCount: results.artists.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, idx) {
                        final artist = results.artists[idx];
                        return _ArtistAvatarBubble(
                          artistName: artist,
                          onTap: () {
                            _onQuerySubmitted(query);
                            PixelHaptics.tick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ArtistDetailsScreen(artistName: artist),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],

              // Matching Playlists
              if (results.playlists.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Text(
                      'Playlists (${results.playlists.length})',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 140,
                    child: SuperListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      physics: buildSuperSmoothScrollPhysics(),
                      itemCount: results.playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, idx) {
                        final pl = results.playlists[idx];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            _onQuerySubmitted(query);
                            PixelHaptics.tick();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlaylistDetailsScreen(playlist: pl),
                              ),
                            );
                          },
                          child: SizedBox(
                            width: 100,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GenerativePlaylistCover(
                                  playlist: pl,
                                  size: 100,
                                  borderRadius: 16,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  pl.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
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
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],

              // Matching Songs List
              if (results.tracks.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Songs (${results.tracks.length})',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _onQuerySubmitted(query);
                            PixelHaptics.playPauseToggle();
                            final shuffled = List<Track>.from(results.tracks)
                              ..shuffle();
                            ref
                                .read(playbackProvider.notifier)
                                .playTrack(
                                  shuffled.first,
                                  newQueue: shuffled,
                                  isShuffle: true,
                                );
                          },
                          icon: const Icon(Icons.shuffle_rounded, size: 16),
                          label: const Text('Shuffle'),
                        ),
                      ],
                    ),
                  ),
                ),
                SuperSliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, idx) {
                      final track = results.tracks[idx];
                      final isCurrent = currentTrackId == track.id;

                      return SwipeToQueueWrapper(
                        track: track,
                        child: _SearchResultTrackTile(
                          track: track,
                          isCurrent: isCurrent,
                          isPlaying: isCurrent && isPlaying,
                          onTap: () {
                            _onQuerySubmitted(query);
                            ref
                                .read(playbackProvider.notifier)
                                .playTrack(track, newQueue: results.tracks);
                          },
                          onOptions: () => _showTrackOptions(context, track),
                        ),
                      );
                    },
                    childCount: results.tracks.length,
                  ),
                ),
              ],
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  void _showTrackOptions(BuildContext context, Track track) {
    PixelHaptics.tick();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHigh,
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
                            borderRadius: 12,
                            showQualityBadge: false,
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
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
                          leading: const Icon(Icons.playlist_add_rounded),
                          title: const Text('Add to Playlist',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.pop(ctx);
                            showAddToPlaylistModal(context, track);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.edit_note_rounded),
                          title: const Text('Edit Metadata & Artwork',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                              'Title, artist, album, genre, year & cover art'),
                          onTap: () {
                            Navigator.pop(ctx);
                            showTrackMetadataEditorModal(context, track);
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            track.isPinnedOffline
                                ? Icons.download_done_rounded
                                : Icons.download_for_offline_outlined,
                            color: track.isPinnedOffline ? cs.primary : null,
                          ),
                          title: Text(
                            track.isPinnedOffline
                                ? 'Remove Offline Download'
                                : 'Download Offline',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: track.isPinnedOffline ? cs.primary : null,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .togglePinOffline(track.id);
                          },
                        ),
                        ...() {
                          final trackArtists = ArtistHelper.extractArtists(track.artist, track.title);
                          if (trackArtists.length > 1) {
                            return trackArtists.map((a) => ListTile(
                              leading: const Icon(Icons.person_rounded),
                              title: Text('View Artist ($a)',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
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
                              title: Text('View Artist ($aName)',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ArtistDetailsScreen(artistName: aName),
                                  ),
                                );
                              },
                            ),
                          ];
                        }(),
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded),
                          title: const Text('Audio Track Details',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TrackDetailsScreen(track: track),
                              ),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.delete_outline_rounded,
                              color: cs.error),
                          title: Text(
                            'Remove from Library',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.error,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
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
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _TopResultCard extends StatelessWidget {
  const _TopResultCard({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCurrent
              ? cs.primaryContainer.withValues(alpha: 0.4)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isCurrent ? cs.primary : cs.outlineVariant.withValues(alpha: 0.3),
            width: isCurrent ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            MaterialYouAlbumCover(
              track: track,
              size: 72,
              borderRadius: 18,
              isPlaying: isPlaying,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isCurrent ? cs.primary : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: track.isHiRes
                          ? cs.primary.withValues(alpha: 0.15)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${track.codec.toUpperCase()}${track.isHiRes ? " • 24-bit Hi-Res" : ""}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: track.isHiRes ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: () {
                PixelHaptics.playPauseToggle();
                onTap();
              },
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistAvatarBubble extends StatelessWidget {
  const _ArtistAvatarBubble({
    required this.artistName,
    required this.onTap,
  });

  final String artistName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: cs.secondaryContainer,
              child: Icon(
                Icons.person_rounded,
                size: 28,
                color: cs.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              artistName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultTrackTile extends StatelessWidget {
  const _SearchResultTrackTile({
    required this.track,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.onOptions,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: MaterialYouAlbumCover(
        track: track,
        size: 48,
        borderRadius: 14,
        showQualityBadge: false,
        isPlaying: isPlaying,
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
          fontSize: 13.5,
          color: isCurrent ? cs.primary : null,
        ),
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: track.isHiRes
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              track.codec.toUpperCase(),
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: track.isHiRes ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MaterialYouDownloadButton(track: track, size: 20),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onPressed: onOptions,
          ),
        ],
      ),
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
    );
  }
}
