import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/metadata/artwork_and_lyrics_service.dart';
import '../../services/metadata/artwork_palette_extractor.dart';
import '../../state/app_providers.dart';
import 'material_you_album_cover.dart';
import 'ultra_free_scroll_physics.dart';

/// Shows the Pixel Material 3 in-app ID3 tag and album artwork editor modal.
Future<void> showTrackMetadataEditorModal(
  BuildContext context,
  Track track,
) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TrackMetadataEditorSheet(initialTrack: track),
  );
}

class _TrackMetadataEditorSheet extends ConsumerStatefulWidget {
  const _TrackMetadataEditorSheet({required this.initialTrack});

  final Track initialTrack;

  @override
  ConsumerState<_TrackMetadataEditorSheet> createState() =>
      _TrackMetadataEditorSheetState();
}

class _TrackMetadataEditorSheetState
    extends ConsumerState<_TrackMetadataEditorSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _genreController;
  late final TextEditingController _yearController;

  String? _currentArtworkUrl;
  int? _currentDominantColor;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTrack;
    _titleController = TextEditingController(text: t.title);
    _artistController = TextEditingController(text: t.artist);
    _albumController = TextEditingController(text: t.album);
    _genreController = TextEditingController(text: t.genre ?? '');
    _yearController =
        TextEditingController(text: t.year != null ? t.year.toString() : '');
    _currentArtworkUrl = t.artworkUrl;
    _currentDominantColor = t.dominantColorValue;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _genreController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _pickArtworkFromGallery() async {
    PixelHaptics.tick();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null && File(path).existsSync()) {
          final paletteSvc = await ArtworkPaletteExtractor.extractPalette(path);
          final service = ref.read(artworkAndLyricsServiceProvider);
          final permanentPath = await service.copyLocalImageToAppStorage(
            path,
            widget.initialTrack.id,
          );
          if (mounted) {
            setState(() {
              _currentArtworkUrl = permanentPath ?? path;
              _currentDominantColor = paletteSvc.dominantColor.toARGB32();
            });
            PixelHaptics.hifiConfirm();
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking artwork: $e');
    }
  }

  Future<void> _searchOnlineArtwork() async {
    PixelHaptics.tick();
    final query =
        '${_artistController.text.trim()} ${_titleController.text.trim()}'.trim();
    final selectedArt = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OnlineArtworkSearchSheet(
        initialQuery: query.isNotEmpty ? query : widget.initialTrack.title,
        trackId: widget.initialTrack.id,
      ),
    );

    if (selectedArt != null && mounted) {
      final paletteSvc =
          await ArtworkPaletteExtractor.extractPalette(selectedArt);
      setState(() {
        _currentArtworkUrl = selectedArt;
        _currentDominantColor = paletteSvc.dominantColor.toARGB32();
      });
      PixelHaptics.hifiConfirm();
    }
  }

  void _removeArtwork() {
    PixelHaptics.tick();
    setState(() {
      _currentArtworkUrl = null;
      _currentDominantColor = 0xFF1E293B;
    });
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    PixelHaptics.hifiConfirm();

    try {
      final newTitle = _titleController.text.trim().isEmpty
          ? widget.initialTrack.title
          : _titleController.text.trim();
      final newArtist = _artistController.text.trim().isEmpty
          ? widget.initialTrack.artist
          : _artistController.text.trim();
      final newAlbum = _albumController.text.trim().isEmpty
          ? widget.initialTrack.album
          : _albumController.text.trim();
      final newGenre = _genreController.text.trim().isEmpty
          ? null
          : _genreController.text.trim();
      final parsedYear = int.tryParse(_yearController.text.trim());

      final updatedTrack = widget.initialTrack.copyWith(
        title: newTitle,
        artist: newArtist,
        album: newAlbum,
        genre: newGenre,
        year: parsedYear,
        artworkUrl: _currentArtworkUrl,
        dominantColorValue: _currentDominantColor ?? widget.initialTrack.dominantColorValue,
      );

      // 1. Update Database & Riverpod State
      await ref.read(tracksCatalogProvider.notifier).updateTrack(updatedTrack);

      // 2. Physical File ID3 Tagging if local file exists
      final localPath = updatedTrack.localCachePath ??
          (File(updatedTrack.streamUrl).existsSync()
              ? updatedTrack.streamUrl
              : null);

      if (localPath != null && File(localPath).existsSync()) {
        try {
          final tagWriter = ref.read(trackTagWriterServiceProvider);
          await tagWriter.writeTagsToLocalFile(
            filePath: localPath,
            title: newTitle,
            artist: newArtist,
            album: newAlbum,
            genre: newGenre,
            year: parsedYear,
            artworkPath: _currentArtworkUrl,
          );
        } catch (_) {}
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated metadata for "$newTitle"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keyboardBottom = MediaQuery.of(context).viewInsets.bottom;

    // Temporary track for album cover preview
    final previewTrack = widget.initialTrack.copyWith(
      artworkUrl: _currentArtworkUrl,
      dominantColorValue: _currentDominantColor ?? widget.initialTrack.dominantColorValue,
    );

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
            padding: EdgeInsets.only(bottom: keyboardBottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              physics: buildSuperSmoothScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Handle
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

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.edit_note_rounded,
                            size: 20, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Edit Metadata & Artwork',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Cover Art Section
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: previewTrack.dominantColor
                                    .withValues(alpha: 0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: MaterialYouAlbumCover(
                            track: previewTrack,
                            size: 130,
                            borderRadius: 24,
                            showQualityBadge: false,
                            showSourceBadge: false,
                            showPlayingAnimation: false,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(color: cs.surface, width: 2),
                          ),
                          child: Icon(Icons.camera_alt_rounded,
                              size: 18, color: cs.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Artwork action buttons
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.photo_library_outlined, size: 16),
                        label: const Text('Pick Gallery'),
                        onPressed: _pickArtworkFromGallery,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.travel_explore_rounded, size: 16),
                        label: const Text('Search Online'),
                        onPressed: _searchOnlineArtwork,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                      if (_currentArtworkUrl != null)
                        ActionChip(
                          avatar: Icon(Icons.close_rounded,
                              size: 16, color: cs.error),
                          label: Text('Remove',
                              style: TextStyle(color: cs.error)),
                          onPressed: _removeArtwork,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Title Field
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Track Title',
                      prefixIcon: const Icon(Icons.music_note_rounded),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Artist Field
                  TextFormField(
                    controller: _artistController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Artist',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Album Field
                  TextFormField(
                    controller: _albumController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Album',
                      prefixIcon: const Icon(Icons.album_outlined),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Row: Genre & Year
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _genreController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Genre',
                            prefixIcon: const Icon(Icons.category_outlined),
                            filled: true,
                            fillColor: cs.surfaceContainerHigh
                                .withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          controller: _yearController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Year',
                            prefixIcon:
                                const Icon(Icons.calendar_today_outlined),
                            filled: true,
                            fillColor: cs.surfaceContainerHigh
                                .withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            PixelHaptics.tick();
                            Navigator.of(context).pop();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSaving ? null : _saveChanges,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-sheet online artwork search utilizing high-resolution Apple Music / iTunes CDN.
class _OnlineArtworkSearchSheet extends ConsumerStatefulWidget {
  const _OnlineArtworkSearchSheet({
    required this.initialQuery,
    required this.trackId,
  });

  final String initialQuery;
  final String trackId;

  @override
  ConsumerState<_OnlineArtworkSearchSheet> createState() =>
      _OnlineArtworkSearchSheetState();
}

class _OnlineArtworkSearchSheetState
    extends ConsumerState<_OnlineArtworkSearchSheet> {
  late final TextEditingController _searchController;
  List<OnlineArtworkResult> _results = [];
  bool _isLoading = false;
  String? _downloadingUrl;

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
      final res = await service.searchOnlineArtwork(query: query, limit: 18);
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

  Future<void> _selectArtwork(OnlineArtworkResult item) async {
    setState(() => _downloadingUrl = item.artworkUrl);
    PixelHaptics.tick();
    try {
      final service = ref.read(artworkAndLyricsServiceProvider);
      final localPath = await service.downloadAndCacheArtwork(
        item.artworkUrl,
        widget.trackId,
      );
      if (mounted) {
        Navigator.of(context).pop(localPath ?? item.artworkUrl);
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context).pop(item.artworkUrl);
      }
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
                    'Search Album Covers Online',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Search Bar
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
              decoration: InputDecoration(
                hintText: 'Search artist or album title...',
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
            // Results Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'No album covers found. Try a different query.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : GridView.builder(
                          physics: buildSuperSmoothScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final item = _results[index];
                            final isDownloading =
                                _downloadingUrl == item.artworkUrl;

                            return InkWell(
                              onTap: isDownloading
                                  ? null
                                  : () => _selectArtwork(item),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cs.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(
                                            item.artworkUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: cs.surfaceContainerHighest,
                                              child: const Icon(
                                                  Icons.broken_image_rounded),
                                            ),
                                          ),
                                          if (isDownloading)
                                            Container(
                                              color: Colors.black45,
                                              child: const Center(
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.album.isNotEmpty
                                                ? item.album
                                                : item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            item.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 9,
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
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
