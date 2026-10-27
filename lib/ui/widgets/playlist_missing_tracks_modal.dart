import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../../services/engine/track_resolution_gateway.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/metadata/artist_helper.dart';
import '../../services/playlist/playlist_import_service.dart';
import '../../services/playlist/playlist_missing_tracks_sync_service.dart';
import '../../state/app_providers.dart';
import '../screens/search_screen.dart';
import 'ultra_free_scroll_physics.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Opens the Material 3 Expressive Missing & Skipped Tracks inspector modal.
Future<void> showPlaylistMissingTracksModal(
  BuildContext context, {
  required Playlist playlist,
  required List<Track> currentTracks,
}) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PlaylistMissingTracksSheet(
      playlist: playlist,
      currentTracks: currentTracks,
    ),
  );
}

class _DiscoveredMissingTrack {
  _DiscoveredMissingTrack({
    required this.sourceIndex,
    required this.title,
    required this.artist,
    this.album,
    this.durationMs,
    this.sourceUrl,
    this.artworkUrl,
    required this.reason,
    required this.isDuplicate,
  });

  final int sourceIndex;
  final String title;
  final String artist;
  final String? album;
  final int? durationMs;
  final String? sourceUrl;
  final String? artworkUrl;
  final String reason;
  final bool isDuplicate;
  bool isResolving = false;
  bool isAdded = false;
}

class _PlaylistMissingTracksSheet extends ConsumerStatefulWidget {
  const _PlaylistMissingTracksSheet({
    required this.playlist,
    required this.currentTracks,
  });

  final Playlist playlist;
  final List<Track> currentTracks;

  @override
  ConsumerState<_PlaylistMissingTracksSheet> createState() =>
      _PlaylistMissingTracksSheetState();
}

class _PlaylistMissingTracksSheetState
    extends ConsumerState<_PlaylistMissingTracksSheet> {
  final TextEditingController _urlController = TextEditingController();
  final PlaylistImportService _importService = const PlaylistImportService();

  bool _isLoading = false;
  String? _errorMessage;
  int _totalSourceCount = 0;
  List<_DiscoveredMissingTrack> _missingItems = [];
  String _activeFilter = 'all'; // 'all', 'missing', 'duplicates'

  @override
  void initState() {
    super.initState();
    final sourceUrl = widget.playlist.syncSourceUrl;
    if (sourceUrl != null && sourceUrl.isNotEmpty) {
      _urlController.text = sourceUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _analyzeSource(sourceUrl);
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _canonicalTitle(String s) {
    var clean = s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
        .replaceAll(RegExp(r'\s+[-–—:]\s+.*$'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const fluffWords = [
      'studio version',
      'single version',
      'album version',
      'radio edit',
      'original mix',
      'remastered',
      'remaster',
      'official audio',
      'official video',
      'lyric video',
    ];
    for (final fw in fluffWords) {
      if (clean.endsWith(fw)) {
        clean = clean.substring(0, clean.length - fw.length).trim();
      }
    }
    return clean;
  }

  static bool _areSameSong(
    String title1,
    String artist1,
    String title2,
    String artist2,
  ) {
    final canon1 = _canonicalTitle(title1);
    final canon2 = _canonicalTitle(title2);
    if (canon1 != canon2) return false;

    final cleanA1 = _normalize(artist1);
    final cleanA2 = _normalize(artist2);
    if (cleanA1.isEmpty || cleanA2.isEmpty || cleanA1 == cleanA2) return true;

    final artists1 = ArtistHelper.extractArtists(artist1, title1)
        .map((a) => _normalize(a))
        .where((a) => a.isNotEmpty)
        .toSet();
    final artists2 = ArtistHelper.extractArtists(artist2, title2)
        .map((a) => _normalize(a))
        .where((a) => a.isNotEmpty)
        .toSet();

    if (artists1.isNotEmpty && artists2.isNotEmpty) {
      final overlap = artists1.intersection(artists2);
      if (overlap.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _analyzeSource(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid playlist link.');
      return;
    }

    PixelHaptics.tick();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch raw tracks from the remote source without filtering
      final importResult = await _importService.importFromUrl(
        cleanUrl,
        [], // empty library to inspect ALL source tracks
      );

      final sourceTracks = importResult.rawSourceTracks.isNotEmpty
          ? importResult.rawSourceTracks
          : importResult.missingTracks;

      _totalSourceCount = importResult.totalParsed > 0
          ? importResult.totalParsed
          : sourceTracks.length;

      // 2. Track seen items in source to detect intra-source duplicates
      final seenSourceItems = <MissingTrackItem>[];
      final seenSourceIndices = <int>[];
      final missing = <_DiscoveredMissingTrack>[];

      for (int i = 0; i < sourceTracks.length; i++) {
        final item = sourceTracks[i];
        final int firstSeenIdx = seenSourceItems.indexWhere(
          (seen) => _areSameSong(
            seen.title,
            seen.artist,
            item.title,
            item.artist,
          ),
        );

        final bool isAlreadyInPlaylist = PlaylistImportService.findBestMatch(
              item.title,
              item.artist,
              widget.currentTracks,
            ) !=
            null;

        if (firstSeenIdx != -1) {
          final originalPos = seenSourceIndices[firstSeenIdx];
          missing.add(
            _DiscoveredMissingTrack(
              sourceIndex: i + 1,
              title: item.title,
              artist: item.artist,
              album: item.album,
              durationMs: item.expectedDurationMs,
              sourceUrl: item.sourceUrl,
              artworkUrl: item.preferredArtworkUrl,
              reason: isAlreadyInPlaylist
                  ? 'Duplicate in source playlist (already in your playlist; duplicate of #$originalPos)'
                  : 'Duplicate entry in source playlist (duplicate of #$originalPos)',
              isDuplicate: true,
            ),
          );
        } else {
          seenSourceItems.add(item);
          seenSourceIndices.add(i + 1);

          if (!isAlreadyInPlaylist) {
            String reason = 'Stream not found or below confidence threshold';
            final lower = '${item.title} ${item.artist}'.toLowerCase();
            if (lower.contains('acoustic') ||
                lower.contains('unplugged') ||
                lower.contains('akustik')) {
              reason = 'Acoustic / Unplugged cut (no authentic stream match)';
            } else if (lower.contains('reprise') || lower.contains('remix')) {
              reason = 'Special version / Reprise mismatch';
            } else if (lower.contains('live')) {
              reason = 'Live version (rejected by studio audio filter)';
            }

            missing.add(
              _DiscoveredMissingTrack(
                sourceIndex: i + 1,
                title: item.title,
                artist: item.artist,
                album: item.album,
                durationMs: item.expectedDurationMs,
                sourceUrl: item.sourceUrl,
                artworkUrl: item.preferredArtworkUrl,
                reason: reason,
                isDuplicate: false,
              ),
            );
          }
        }
      }

      // Save syncSourceUrl to playlist if not already linked
      if (widget.playlist.syncSourceUrl == null) {
        await ref
            .read(playlistsProvider.notifier)
            .updatePlaylistSyncSource(widget.playlist.id, cleanUrl);
      }

      if (mounted) {
        setState(() {
          _missingItems = missing;
          _isLoading = false;
        });
        await PixelHaptics.hifiConfirm();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _copyMissingListToClipboard() async {
    PixelHaptics.tick();
    final buffer = StringBuffer();
    buffer.writeln(
        'Missing Tracks from "${widget.playlist.title}" (${_missingItems.length} tracks):');
    buffer.writeln('Source: ${_urlController.text.trim()}');
    buffer.writeln('---');
    for (int i = 0; i < _missingItems.length; i++) {
      final item = _missingItems[i];
      final tag = item.isDuplicate ? ' [Duplicate]' : '';
      buffer.writeln(
          '${i + 1}. "${item.title}" by "${item.artist}"$tag - Reason: ${item.reason}');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Copied ${_missingItems.length} missing tracks to clipboard',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
    }
  }

  Future<void> _resolveAndAddTrack(_DiscoveredMissingTrack item) async {
    PixelHaptics.tick();
    setState(() => item.isResolving = true);

    try {
      final gateway = TrackResolutionGateway();
      final bundle = await gateway.resolveAudioBundle(
        title: item.title,
        artist: item.artist,
        expectedDurationMs: item.durationMs,
        spotifyUrlOrUri: item.sourceUrl,
        preferredArtworkUrl: item.artworkUrl,
        preferredAlbum: item.album,
      );

      if (bundle != null) {
        final newTrack = Track(
          id: 'resolved_${DateTime.now().microsecondsSinceEpoch}',
          accountId: 'stream_resolver',
          providerType: CloudProviderType.androidSaf,
          title: bundle.title,
          artist: bundle.artist,
          album: bundle.album.isNotEmpty ? bundle.album : 'Single',
          durationMs: bundle.candidate.durationMs,
          streamUrl: bundle.candidate.streamUrl,
          remotePathOrId: bundle.candidate.sourceId,
          artworkUrl: bundle.artworkUrl ?? item.artworkUrl,
          codec: bundle.audioCodec,
          bitrateKbps: bundle.bitrateKbps,
        );

        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks([newTrack]);
        await ref
            .read(playlistsProvider.notifier)
            .addTracksToPlaylist(widget.playlist.id, [newTrack.id]);

        if (mounted) {
          setState(() {
            item.isResolving = false;
            item.isAdded = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "${item.title}" to ${widget.playlist.title}!'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
          await PixelHaptics.hifiConfirm();
        }
      } else {
        if (mounted) {
          setState(() => item.isResolving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not resolve stream for "${item.title}". Try searching manually.',
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => item.isResolving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resolution error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _searchTrackInFreeBeat(_DiscoveredMissingTrack item) {
    PixelHaptics.tick();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          initialQuery: '${item.artist} ${item.title}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final filteredItems = _missingItems.where((it) {
      if (_activeFilter == 'missing') return !it.isDuplicate;
      if (_activeFilter == 'duplicates') return it.isDuplicate;
      return true;
    }).toList();

    final duplicateCount = _missingItems.where((it) => it.isDuplicate).length;
    final missingCount = _missingItems.where((it) => !it.isDuplicate).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle Bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(
                        Icons.playlist_remove_rounded,
                        color: cs.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Missing & Skipped Tracks',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Playlist: ${widget.playlist.title}',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Search / URL input bar if needed
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText:
                              'Spotify, YouTube, or Apple Music link...',
                          prefixIcon: const Icon(Icons.link_rounded, size: 20),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _analyzeSource(_urlController.text),
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.radar_rounded, size: 18),
                      label: Text(_isLoading ? 'Scanning' : 'Scan'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_errorMessage != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: cs.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: cs.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Summary Stats & Action Pills
              if (_missingItems.isNotEmpty || _totalSourceCount > 0) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Source: $_totalSourceCount • Playlist: ${widget.currentTracks.length}${duplicateCount > 0 ? " • Duplicates: $duplicateCount" : ""}${missingCount > 0 ? " • Missing: $missingCount" : ""}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_missingItems.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: _copyMissingListToClipboard,
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: const Text(
                            'Copy List',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            shape: const StadiumBorder(),
                          ),
                        ),
                    ],
                  ),
                ),

                // Filter Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text('All (${_missingItems.length})'),
                        selected: _activeFilter == 'all',
                        onSelected: (val) {
                          if (val) setState(() => _activeFilter = 'all');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Missing Audio ($missingCount)'),
                        selected: _activeFilter == 'missing',
                        onSelected: (val) {
                          if (val) setState(() => _activeFilter = 'missing');
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text('Duplicates ($duplicateCount)'),
                        selected: _activeFilter == 'duplicates',
                        onSelected: (val) {
                          if (val) setState(() => _activeFilter = 'duplicates');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // Content Area
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Comparing source tracks against playlist...',
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : filteredItems.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 48,
                                    color: Colors.green.shade400,
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    missingCount == 0 && duplicateCount > 0
                                        ? 'All unique songs present!'
                                        : (_missingItems.isEmpty
                                            ? 'No missing tracks detected.'
                                            : 'No tracks match this filter.'),
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    missingCount == 0 && duplicateCount > 0
                                        ? 'All unique songs are already in your playlist. The $duplicateCount additional entries on the source playlist are duplicate tracks.'
                                        : 'All parsed songs are present in this playlist.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SuperListView.builder(
                            controller: scrollController,
                            physics: buildSuperSmoothScrollPhysics(),
                            cacheExtent: 1500,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                            itemCount: filteredItems.length,
                            itemBuilder: (ctx, idx) {
                              final it = filteredItems[idx];
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                elevation: 0,
                                color: it.isAdded
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : cs.surfaceContainerHighest
                                        .withValues(alpha: 0.6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: it.isAdded
                                        ? Colors.green.withValues(alpha: 0.4)
                                        : cs.outlineVariant
                                            .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: it.isDuplicate
                                                  ? Colors.indigo
                                                      .withValues(alpha: 0.15)
                                                  : cs.primaryContainer,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              '${it.sourceIndex}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: it.isDuplicate
                                                    ? Colors.indigo.shade300
                                                    : cs.onPrimaryContainer,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  it.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  it.artist,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: cs.onSurfaceVariant,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (it.isAdded) ...[
                                            const Chip(
                                              avatar: Icon(Icons.check,
                                                  size: 14,
                                                  color: Colors.green),
                                              label: Text('Added',
                                                  style:
                                                      TextStyle(fontSize: 11)),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ),
                                          ] else ...[
                                            IconButton(
                                              icon: const Icon(
                                                Icons.search_rounded,
                                                size: 20,
                                              ),
                                              tooltip: 'Search in FreeBeat',
                                              onPressed: () =>
                                                  _searchTrackInFreeBeat(it),
                                            ),
                                            if (!it.isDuplicate) ...[
                                              IconButton(
                                                icon: it.isResolving
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .cloud_download_outlined,
                                                        size: 20,
                                                      ),
                                                tooltip:
                                                    'Retry Stream Resolve',
                                                onPressed: it.isResolving
                                                    ? null
                                                    : () =>
                                                        _resolveAndAddTrack(it),
                                              ),
                                            ],
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: it.isDuplicate
                                              ? Colors.indigo
                                                  .withValues(alpha: 0.12)
                                              : cs.errorContainer
                                                  .withValues(alpha: 0.25),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          it.reason,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: it.isDuplicate
                                                ? Colors.indigo.shade200
                                                : cs.error,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }
}
