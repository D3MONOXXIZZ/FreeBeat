import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/metadata/artwork_and_lyrics_service.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/track_metadata_editor_modal.dart';

/// Fullscreen Synchronized Karaoke Lyrics Screen (Google Pixel Material You Style).
/// Strictly mirrors Screen 6 in Figma inspiration with:
/// - Edge-to-edge ambient gradient aura derived from current album art
/// - Karaoke-style progress typography with active line magnification
/// - Instant tap-to-seek timestamp alignment with tactile tick haptics
/// - Real-time timing offset calibration slider (±0.1s to ±3.0s)
/// - Integrated online synced lyrics search (LRCLIB) and LRC pasting fallback
/// - Floating bottom mini-controls dock for uninterrupted playback control
class FullscreenLyricsScreen extends ConsumerStatefulWidget {
  const FullscreenLyricsScreen({super.key});

  @override
  ConsumerState<FullscreenLyricsScreen> createState() =>
      _FullscreenLyricsScreenState();
}

class _FullscreenLyricsScreenState
    extends ConsumerState<FullscreenLyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLyric(int index, int totalCount) {
    if (index == _lastActiveIndex || !_scrollController.hasClients) return;
    _lastActiveIndex = index;

    // Smooth auto-scroll to center the active singing line
    const itemHeight = 76.0;
    final targetOffset = (index * itemHeight) - 180.0;
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  void _showLyricsCalibrationModal(BuildContext context, Track track) {
    PixelHaptics.sheetExpand();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LyricsCalibrationSheet(track: track),
    );
  }

  void _showOnlineLyricsSearchSheet(BuildContext context, Track track) {
    PixelHaptics.sheetExpand();
    final initialQuery = '${track.artist} ${track.title}'.trim();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OnlineLyricsSearchSheet(
        initialQuery: initialQuery.isNotEmpty ? initialQuery : track.title,
      ),
    );
  }

  void _showPasteLrcDialog(BuildContext context) {
    PixelHaptics.sheetExpand();
    showDialog<void>(
      context: context,
      builder: (ctx) => const _PasteLrcDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final track = playback.currentTrack;
    final lyrics = track.syncedLyrics;
    final activeIndex = playback.activeLyricIndex;
    final offsetMs = track.lyricsOffsetMs;

    // Trigger auto-scroll on lyric progress change
    if (lyrics.isNotEmpty && activeIndex >= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActiveLyric(activeIndex, lyrics.length);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Ambient Blurred Gradient Aura Background
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.0, -0.4),
                radius: 1.4,
                colors: [
                  track.dominantColor.withValues(alpha: 0.50),
                  cs.surface.withValues(alpha: 0.90),
                  cs.surface,
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 2. Top Header with Back button, Track Title & Calibration
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, size: 24),
                        onPressed: () {
                          PixelHaptics.tick();
                          Navigator.of(context).pop();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title.isEmpty ? 'Now Playing' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              track.artist.isEmpty ? 'FreeBeat' : track.artist,
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
                      // Timing Offset Calibration Pill
                      if (lyrics.isNotEmpty)
                        SpringPressScale(
                          onTap: () => _showLyricsCalibrationModal(context, track),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: offsetMs != 0
                                  ? cs.primaryContainer
                                  : cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: offsetMs != 0
                                    ? cs.primary.withValues(alpha: 0.5)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 13,
                                  color: offsetMs != 0
                                      ? cs.onPrimaryContainer
                                      : cs.onSecondaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  offsetMs == 0
                                      ? 'SYNCED'
                                      : '${offsetMs > 0 ? "+" : ""}${(offsetMs / 1000).toStringAsFixed(1)}s',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: offsetMs != 0
                                        ? cs.onPrimaryContainer
                                        : cs.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      // Options Menu
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        onSelected: (action) {
                          if (action == 'calibrate') {
                            _showLyricsCalibrationModal(context, track);
                          } else if (action == 'search') {
                            _showOnlineLyricsSearchSheet(context, track);
                          } else if (action == 'paste') {
                            _showPasteLrcDialog(context);
                          } else if (action == 'edit_metadata') {
                            showTrackMetadataEditorModal(context, track);
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (lyrics.isNotEmpty)
                            const PopupMenuItem(
                              value: 'calibrate',
                              child: Row(
                                children: [
                                  Icon(Icons.tune_rounded, size: 18),
                                  SizedBox(width: 12),
                                  Text('Calibrate Timing Offset'),
                                ],
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'search',
                            child: Row(
                              children: [
                                Icon(Icons.travel_explore_rounded, size: 18),
                                SizedBox(width: 12),
                                Text('Search Online Lyrics (LRCLIB)'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'paste',
                            child: Row(
                              children: [
                                Icon(Icons.paste_rounded, size: 18),
                                SizedBox(width: 12),
                                Text('Paste .LRC Lyrics'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'edit_metadata',
                            child: Row(
                              children: [
                                Icon(Icons.edit_note_rounded, size: 18),
                                SizedBox(width: 12),
                                Text('Edit Track Info & Artwork'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // 3. Lyrics Scroll Area
                Expanded(
                  child: lyrics.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHigh,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.lyrics_outlined,
                                    size: 34,
                                    color: cs.primary,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  'No Time-Synced Lyrics Found',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Search the LRCLIB online library or paste timestamped LRC lyrics to activate real-time karaoke mode.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _showOnlineLyricsSearchSheet(
                                              context, track),
                                      icon: const Icon(
                                          Icons.travel_explore_rounded,
                                          size: 18),
                                      label: const Text('Search LRCLIB'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          _showPasteLrcDialog(context),
                                      icon: const Icon(Icons.paste_rounded,
                                          size: 18),
                                      label: const Text('Paste .LRC'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          physics: const ClampingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(24, 40, 24, 140),
                          itemCount: lyrics.length,
                          itemBuilder: (context, index) {
                            final line = lyrics[index];
                            final isActive = index == activeIndex;
                            final isPassed = index < activeIndex;

                            return InkWell(
                              onTap: () {
                                PixelHaptics.tick();
                                ref
                                    .read(playbackProvider.notifier)
                                    .seekToMs(line.timestampMs);
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? cs.primaryContainer
                                          .withValues(alpha: 0.35)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  line.text,
                                  style: TextStyle(
                                    fontSize: isActive ? 24 : 18,
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                    height: 1.35,
                                    color: isActive
                                        ? cs.onSurface
                                        : (isPassed
                                            ? cs.onSurfaceVariant
                                                .withValues(alpha: 0.40)
                                            : cs.onSurfaceVariant
                                                .withValues(alpha: 0.65)),
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

          // 4. Floating Mini-Dock at Bottom
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: SpringPressScale(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    MaterialYouAlbumCover(
                      track: track,
                      size: 42,
                      borderRadius: 12,
                      showQualityBadge: false,
                      showSourceBadge: false,
                      showPlayingAnimation: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title.isEmpty ? 'FreeBeat' : track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            track.artist.isEmpty
                                ? 'Lossless Stream'
                                : track.artist,
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
                    IconButton(
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 36,
                        color: cs.primary,
                      ),
                      onPressed: () {
                        PixelHaptics.playPauseToggle();
                        ref.read(playbackProvider.notifier).togglePlayPause();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Real-time lyrics timing calibration sheet with stepper pills and slider.
class _LyricsCalibrationSheet extends ConsumerWidget {
  const _LyricsCalibrationSheet({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final liveTrack = ref.watch(playbackProvider.select((p) => p.currentTrack));
    final offsetMs = liveTrack.lyricsOffsetMs;

    void updateOffset(int newOffset) {
      PixelHaptics.tick();
      final clamped = newOffset.clamp(-5000, 5000);
      ref.read(playbackProvider.notifier).setLyricsOffsetMs(clamped);
    }

    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
        ),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.tune_rounded,
                      size: 20, color: cs.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lyrics Timing Calibration',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Calibrate synced lines in real time during playback',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Digital Offset Readout
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: offsetMs != 0
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    offsetMs == 0
                        ? '0.0s (In-Sync)'
                        : '${offsetMs > 0 ? "+" : ""}${(offsetMs / 1000).toStringAsFixed(2)}s',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: offsetMs != 0 ? cs.primary : cs.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (offsetMs != 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${offsetMs > 0 ? "+" : ""}$offsetMs ms)',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Slider
            Slider(
              value: offsetMs.toDouble().clamp(-3000.0, 3000.0),
              min: -3000.0,
              max: 3000.0,
              divisions: 120,
              label: '${offsetMs > 0 ? "+" : ""}${(offsetMs / 1000).toStringAsFixed(2)}s',
              onChanged: (val) => updateOffset(val.round()),
            ),
            const SizedBox(height: 12),
            // Stepper Chips
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('-0.5s'),
                  onPressed: () => updateOffset(offsetMs - 500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                ActionChip(
                  label: const Text('-0.1s'),
                  onPressed: () => updateOffset(offsetMs - 100),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                ActionChip(
                  label: const Text('Reset (0s)'),
                  onPressed: () => updateOffset(0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                ActionChip(
                  label: const Text('+0.1s'),
                  onPressed: () => updateOffset(offsetMs + 100),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
                ActionChip(
                  label: const Text('+0.5s'),
                  onPressed: () => updateOffset(offsetMs + 500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                PixelHaptics.tick();
                Navigator.of(context).pop();
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// In-sheet online lyrics search connecting to LRCLIB database.
class _OnlineLyricsSearchSheet extends ConsumerStatefulWidget {
  const _OnlineLyricsSearchSheet({required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<_OnlineLyricsSearchSheet> createState() =>
      _OnlineLyricsSearchSheetState();
}

class _OnlineLyricsSearchSheetState
    extends ConsumerState<_OnlineLyricsSearchSheet> {
  late final TextEditingController _searchController;
  List<OnlineLyricResult> _results = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialQuery);
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final service = ref.read(artworkAndLyricsServiceProvider);
      final res = await service.searchOnlineLyrics(query: query);
      if (mounted) {
        setState(() {
          _results = res;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyLyrics(OnlineLyricResult item) {
    PixelHaptics.hifiConfirm();
    final parsed = item.parsedSyncedLyrics;
    if (parsed.isNotEmpty) {
      ref.read(playbackProvider.notifier).updateCurrentTrackLyrics(parsed);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied synced lyrics (${parsed.length} lines)'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This result only contains plain text lyrics without timestamps.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
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
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search Online Lyrics (LRCLIB)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Search Input
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
              decoration: InputDecoration(
                hintText: 'Song title or artist name...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: _performSearch,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'No lyrics found. Try refining your search query.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          physics: const ClampingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final hasSynced = item.hasSyncedLyrics;

                            return ListTile(
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: hasSynced
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  hasSynced
                                      ? Icons.lyrics_rounded
                                      : Icons.text_snippet_outlined,
                                  color: hasSynced
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                item.trackName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                '${item.artistName} • ${item.albumName.isNotEmpty ? item.albumName : "Single"}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: hasSynced
                                      ? cs.primaryContainer
                                      : cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  hasSynced ? 'SYNCED' : 'PLAIN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: hasSynced
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              onTap: () => _applyLyrics(item),
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

/// Dialog allowing users to paste raw .LRC timestamped text directly.
class _PasteLrcDialog extends ConsumerStatefulWidget {
  const _PasteLrcDialog();

  @override
  ConsumerState<_PasteLrcDialog> createState() => _PasteLrcDialogState();
}

class _PasteLrcDialogState extends ConsumerState<_PasteLrcDialog> {
  final TextEditingController _lrcController = TextEditingController();

  @override
  void dispose() {
    _lrcController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      _lrcController.text = data.text!;
      PixelHaptics.tick();
    }
  }

  void _submit() {
    final text = _lrcController.text.trim();
    if (text.isEmpty) return;

    final parsed = ArtworkAndLyricsService.parseLrcContent(text);
    if (parsed.isNotEmpty) {
      PixelHaptics.hifiConfirm();
      ref.read(playbackProvider.notifier).updateCurrentTrackLyrics(parsed);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${parsed.length} synced lyric lines!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'No valid [mm:ss.xx] timestamps found. Ensure standard LRC format is used.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.paste_rounded),
          SizedBox(width: 10),
          Text('Paste .LRC Lyrics'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste timestamped lines in standard [mm:ss.xx] format:',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lrcController,
              maxLines: 7,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: '[00:12.30] First verse line...\n[00:15.80] Second verse line...',
                filled: true,
                fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_go_rounded, size: 16),
                label: const Text('Paste from Clipboard'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Apply Lyrics'),
        ),
      ],
    );
  }
}
