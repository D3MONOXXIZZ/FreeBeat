import 'dart:io';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/metadata/artwork_palette_extractor.dart';
import '../../services/metadata/artist_helper.dart';
import '../../state/app_providers.dart';
import '../widgets/ab_loop_modal.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/material_you_album_cover.dart';
import '../widgets/material_you_download_button.dart';
import '../widgets/playback_speed_modal.dart';
import '../widgets/queue_bottom_sheet.dart';
import '../widgets/remove_track_dialog.dart';
import '../widgets/signal_path_sheet.dart';
import '../widgets/sleep_timer_modal.dart';
import '../widgets/waveform_seekbar.dart';
import 'artist_details_screen.dart';
import 'fullscreen_lyrics_screen.dart';
import 'track_details_screen.dart';
import '../widgets/add_to_playlist_modal.dart';
import '../widgets/track_metadata_editor_modal.dart';
import '../widgets/ultra_free_scroll_physics.dart';

/// Full-Screen Google Pixel Material 3 Expressive Now Playing Screen.
/// Strictly implements Screen 2 in Figma inspiration:
/// 1. Ambient blurred colored aura derived from current track artwork
/// 2. Top Bar: Collapse chevron, Connected Output Chip (`Pixel Buds Optimized`), and EQ icon
/// 3. Hero 32dp Squircle Artwork with ambient colored drop glow
/// 4. Track title & artist in bold Google Sans with favorite toggle
/// 5. Dynamic Multi-Bar Waveform Seekbar with micro-haptic scrubbing
/// 6. Large circular Play/Pause button with spring scale & tactile pulses
/// 7. Bottom Peekable Lyrics Drawer expanding into Fullscreen Karaoke Lyrics
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({
    super.key,
    required this.onOpenDspStudio,
  });

  final VoidCallback onOpenDspStudio;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen>
    with TickerProviderStateMixin {
  ArtworkPalette? _palette;
  String? _lastArtworkKey;
  late final AnimationController _auraAnimController;
  late final AnimationController _springResetController;
  late final AnimationController _dismissController;
  Animation<double>? _springResetAnim;
  Animation<double>? _artSpringAnim;
  Animation<double>? _dismissAnim;
  double _dragOffsetY = 0.0;
  double _artDragX = 0.0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _auraAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _springResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _springResetController.addListener(() {
      if (_springResetAnim != null) {
        setState(() => _dragOffsetY = _springResetAnim!.value);
      }
      if (_artSpringAnim != null) {
        setState(() => _artDragX = _artSpringAnim!.value);
      }
    });

    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
    );
    _dismissController.addListener(() {
      if (_dismissAnim != null) {
        setState(() => _dragOffsetY = _dismissAnim!.value);
      }
    });
  }

  @override
  void dispose() {
    _auraAnimController.dispose();
    _springResetController.dispose();
    _dismissController.dispose();
    super.dispose();
  }

  void _collapsePlayer() {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    PixelHaptics.tick();
    final screenHeight = MediaQuery.of(context).size.height;
    final remaining = (screenHeight - _dragOffsetY).clamp(0.0, screenHeight);
    final durationMs = (remaining / screenHeight * 460).round().clamp(360, 480);

    _dismissController.duration = Duration(milliseconds: durationMs);
    _dismissAnim = Tween<double>(
      begin: _dragOffsetY,
      end: screenHeight,
    ).animate(CurvedAnimation(
      parent: _dismissController,
      curve: Curves.easeOutCubic,
    ));

    _dismissController.forward(from: 0.0).then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    final dy = details.delta.dy;
    if (_dragOffsetY + dy >= 0) {
      setState(() {
        _dragOffsetY += dy;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    final vy = details.primaryVelocity ?? 0.0;
    if (_dragOffsetY > 110 || vy > 400) {
      _collapsePlayer();
    } else if (_dragOffsetY > 0) {
      _springResetAnim = Tween<double>(
        begin: _dragOffsetY,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _springResetController,
        curve: Curves.easeOutCubic,
      ));
      _springResetController.forward(from: 0.0);
    }
  }

  void _onArtHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _artDragX += details.delta.dx;
    });
    PixelHaptics.swipeLoadTick(
      progress: (_artDragX.abs() / 120.0).clamp(0.0, 1.0),
    );
  }

  void _onArtHorizontalDragEnd(DragEndDetails details) {
    final vx = details.primaryVelocity ?? 0.0;
    if (_artDragX < -55 || vx < -400) {
      PixelHaptics.swipeClick();
      ref.read(playbackProvider.notifier).skipNext();
    } else if (_artDragX > 55 || vx > 400) {
      PixelHaptics.swipeClick();
      ref.read(playbackProvider.notifier).skipPrevious();
    }

    _artSpringAnim = Tween<double>(
      begin: _artDragX,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _springResetController,
      curve: Curves.easeOutBack,
    ));
    _springResetController.forward(from: 0.0);
  }

  void _resolvePalette(Track track) {
    final artKey = '${track.id}_${track.artworkUrl}';
    if (_lastArtworkKey == artKey) return;
    _lastArtworkKey = artKey;

    final cached = ArtworkPaletteExtractor.getCached(track.artworkUrl);
    if (cached != null) {
      _palette = cached;
      return;
    }

    ArtworkPaletteExtractor.extractPalette(track.artworkUrl).then((pal) {
      if (mounted) {
        setState(() {
          _palette = pal;
        });
      }
    });
  }

  Widget _buildArtworkBackdrop(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 256,
        memCacheHeight: 256,
        maxWidthDiskCache: 512,
        maxHeightDiskCache: 512,
        fadeInDuration: const Duration(milliseconds: 200),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    final file = File(url);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }

  void _openFullscreenLyrics() {
    PixelHaptics.sheetExpand();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const FullscreenLyricsScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final track = ref.watch(playbackProvider.select((p) => p.currentTrack));
    final isPlaying = ref.watch(playbackProvider.select((p) => p.isPlaying));
    final bassGain = ref.watch(powerampDspProvider.select((p) => p.bassGain));
    final isShuffle = ref.watch(playbackProvider.select((p) => p.isShuffle));
    final repeatMode = ref.watch(playbackProvider.select((p) => p.repeatMode));
    final hasUserQueuedTracks =
        ref.watch(playbackProvider.select((p) => p.hasUserQueuedTracks));
    final userQueueCount =
        ref.watch(playbackProvider.select((p) => p.userQueueCount));
    final hasActiveOptions = ref.watch(playbackProvider.select((p) =>
        p.isSleepTimerActive ||
        p.playbackSpeed != 1.0 ||
        p.pitch != 1.0 ||
        p.isLoopActive));
    final lyrics = track.syncedLyrics;
    final isPowerSaver = ref.watch(effectivePowerSaverActiveProvider);
    final powerSaver = ref.watch(powerSaverProvider);
    final shouldDisableAura = isPowerSaver && powerSaver.disableBlurAndAura;
    _resolvePalette(track);

    if (isPlaying && !shouldDisableAura) {
      if (!_auraAnimController.isAnimating) {
        _auraAnimController.repeat(reverse: true);
      }
    } else {
      if (_auraAnimController.isAnimating) {
        _auraAnimController.stop();
      }
    }

    final isStaleGreen = track.dominantColorValue == 0xFF3DDC84 ||
        track.dominantColorValue == 0xFF1DB954;
    final effectiveDominant = (_palette != null && _palette!.isExtracted)
        ? _palette!.dominantColor
        : (!isStaleGreen && track.dominantColorValue != 0
            ? track.dominantColor
            : cs.primary);
    final effectiveEdge = (_palette != null && _palette!.isExtracted)
        ? _palette!.edgeColor
        : effectiveDominant;
    final effectiveTopEdge = (_palette != null && _palette!.isExtracted)
        ? _palette!.topEdgeColor
        : effectiveDominant;
    final effectiveBottomEdge = (_palette != null && _palette!.isExtracted)
        ? _palette!.bottomEdgeColor
        : effectiveEdge;
    final effectiveLeftEdge = (_palette != null && _palette!.isExtracted)
        ? _palette!.leftEdgeColor
        : effectiveDominant;
    final effectiveRightEdge = (_palette != null && _palette!.isExtracted)
        ? _palette!.rightEdgeColor
        : effectiveDominant;

    final topPadding = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;
    final cardTopMargin = topPadding > 0 ? topPadding + 6.0 : 16.0;

    final dismissFraction = (screenHeight > 0)
        ? (_dragOffsetY / screenHeight).clamp(0.0, 1.0)
        : 0.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _collapsePlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Dynamic Fullscreen Backdrop Blur & Scrim (GPU-cached static blur with alpha modulation)
            if (dismissFraction < 0.99)
              Positioned.fill(
                child: Opacity(
                  opacity: (1.0 - dismissFraction).clamp(0.0, 1.0),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.54),
                    ),
                  ),
                ),
              ),

            // 2. Backdrop Tap Target to dismiss card
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _collapsePlayer,
                child: const SizedBox.expand(),
              ),
            ),

            // 3. Interactive Dismissible Now Playing Card Sheet (Matching "More" Card Architecture)
            Positioned(
              top: cardTopMargin,
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: Transform.translate(
                  offset: Offset(0, _dragOffsetY),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLowest,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: const Offset(0, -6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      child: Stack(
                        children: [
                          // 1. Ambient Dynamic Gradient Background
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0.0, -0.42),
                                radius: 1.45,
                                colors: [
                                  effectiveDominant.withValues(alpha: 0.42),
                                  effectiveEdge.withValues(alpha: 0.22),
                                  cs.surface.withValues(alpha: 0.95),
                                  cs.surfaceContainerLowest,
                                ],
                                stops: const [0.0, 0.40, 0.78, 1.0],
                              ),
                            ),
                          ),

                          SafeArea(
                            top: false,
                            bottom: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                              child: Column(
                                children: [
                                  // Drag Handle Pill (Matching "More" Card)
                                  Center(
                                    child: Container(
                                      width: 38,
                                      height: 4.5,
                                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                                      decoration: BoxDecoration(
                                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(2.5),
                                      ),
                                    ),
                                  ),

                                  // 2. Top Bar: Collapse, Connected Output Chip, EQ Action
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 32,
                                        ),
                                        onPressed: _collapsePlayer,
                                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.info_outline_rounded, size: 24),
                            tooltip: 'Track Details',
                            onPressed: () {
                              PixelHaptics.tick();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TrackDetailsScreen(track: track),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.tune_rounded, size: 24),
                            tooltip: 'Smart EQ',
                            onPressed: () {
                              PixelHaptics.sheetExpand();
                              Navigator.of(context).pop();
                              widget.onOpenDspStudio();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(flex: 1),

                  // 3. Hero Album Artwork Card with Ambient Edge-Matched Glow
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Ambient Edge-Matched Glow & Gaussian Blur Backdrop
                          // Wrapped in RepaintBoundary to cache rasterization and avoid GPU lag
                          if (!shouldDisableAura)
                            Positioned.fill(
                              child: AnimatedBuilder(
                              animation: _auraAnimController,
                              builder: (context, child) {
                                final auraVal = _auraAnimController.value;
                                final dynamicOpacity =
                                    (0.70 + (auraVal * (0.15 + bassGain * 0.05))).clamp(0.0, 1.0);

                                return Opacity(
                                  opacity: isPlaying ? dynamicOpacity : 0.65,
                                  child: child,
                                );
                              },
                              child: RepaintBoundary(
                                child: Stack(
                                  alignment: Alignment.center,
                                  clipBehavior: Clip.none,
                                  children: [
                                    // 3a. Directional Edge Lighting Aura: Top, Bottom, Left, Right Blooms
                                    Positioned.fill(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(36),
                                          boxShadow: [
                                            // Top edge glow
                                            BoxShadow(
                                              color: effectiveTopEdge
                                                  .withValues(alpha: 0.45),
                                              blurRadius: 52,
                                              spreadRadius: 10,
                                              offset: const Offset(0, -14),
                                            ),
                                            // Bottom edge glow
                                            BoxShadow(
                                              color: effectiveBottomEdge
                                                  .withValues(alpha: 0.50),
                                              blurRadius: 56,
                                              spreadRadius: 12,
                                              offset: const Offset(0, 16),
                                            ),
                                            // Left edge glow
                                            BoxShadow(
                                              color: effectiveLeftEdge
                                                  .withValues(alpha: 0.40),
                                              blurRadius: 46,
                                              spreadRadius: 8,
                                              offset: const Offset(-12, 0),
                                            ),
                                            // Right edge glow
                                            BoxShadow(
                                              color: effectiveRightEdge
                                                  .withValues(alpha: 0.40),
                                              blurRadius: 46,
                                              spreadRadius: 8,
                                              offset: const Offset(12, 0),
                                            ),
                                            // Deep center dominant ambient bloom
                                            BoxShadow(
                                              color: effectiveDominant
                                                  .withValues(alpha: 0.55),
                                              blurRadius: 68,
                                              spreadRadius: 16,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // 3b. Blurred scaled duplicate of actual artwork
                                    if (track.artworkUrl != null &&
                                        track.artworkUrl!.isNotEmpty)
                                      Positioned.fill(
                                        child: Transform.scale(
                                          scale: 1.14,
                                          child: ImageFiltered(
                                            imageFilter: ui.ImageFilter.blur(
                                                sigmaX: 38, sigmaY: 38),
                                            child: Opacity(
                                              opacity: 0.75,
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(32),
                                                child: _buildArtworkBackdrop(
                                                    track.artworkUrl!),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 3c. Crisp Hero Album Artwork Card with horizontal swipe-to-skip & tilt
                          Transform.translate(
                            offset: Offset(_artDragX, 0),
                            child: Transform.rotate(
                              angle: (_artDragX / 1400.0).clamp(-0.1, 0.1),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: _onArtHorizontalDragUpdate,
                                onHorizontalDragEnd: _onArtHorizontalDragEnd,
                                onTap: () {
                                  PixelHaptics.tick();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TrackDetailsScreen(track: track),
                                    ),
                                  );
                                },
                                child: Hero(
                                  tag: 'album_art_${track.id}',
                                  child: MaterialYouAlbumCover(
                                    track: track,
                                    size: double.infinity,
                                    borderRadius: 32,
                                    showQualityBadge: true,
                                    showSourceBadge: true,
                                    isPlaying: isPlaying,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 3),

                  // 4. Track Title, Artist & Actions
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title.isEmpty ? 'Ready to Stream' : track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                if (track.artist.isNotEmpty &&
                                    track.artist !=
                                        'Connect cloud storage or import songs') {
                                  PixelHaptics.tick();
                                  final artists = ArtistHelper.extractArtists(track.artist, track.title);
                                  if (artists.length > 1) {
                                    showModalBottomSheet<void>(
                                      context: context,
                                      backgroundColor: cs.surfaceContainerLow,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                                      ),
                                      builder: (ctx) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(height: 12),
                                            Container(
                                              width: 36,
                                              height: 4,
                                              decoration: BoxDecoration(
                                                color: cs.outlineVariant,
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 20),
                                              child: Text('Artists on this Track',
                                                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                            ),
                                            const SizedBox(height: 8),
                                            for (final a in artists)
                                              ListTile(
                                                leading: const Icon(Icons.person_rounded),
                                                title: Text(a, style: const TextStyle(fontWeight: FontWeight.w700)),
                                                onTap: () {
                                                  Navigator.of(ctx).pop();
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(builder: (_) => ArtistDetailsScreen(artistName: a)),
                                                  );
                                                },
                                              ),
                                            const SizedBox(height: 12),
                                          ],
                                        ),
                                      ),
                                    );
                                  } else {
                                    final aName = artists.isNotEmpty ? artists.first : track.artist;
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ArtistDetailsScreen(
                                          artistName: aName,
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      track.artist.isEmpty
                                          ? 'Connect cloud storage or import songs'
                                          : track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (track.artist.isNotEmpty &&
                                      track.artist !=
                                          'Connect cloud storage or import songs') ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (track.id.isNotEmpty) ...[
                        MaterialYouDownloadButton(
                          track: track,
                          size: 24,
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        icon: Icon(
                          track.isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: track.isFavorite ? cs.error : cs.onSurfaceVariant,
                          size: 26,
                        ),
                        onPressed: () {
                          PixelHaptics.tick();
                          if (track.id.isNotEmpty) {
                            ref
                                .read(tracksCatalogProvider.notifier)
                                .toggleFavorite(track.id);
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 5. Dynamic Audio Waveform Seekbar (Isolated to eliminate background blur repaints)
                  _NowPlayingSeekSection(track: track),

                  const SizedBox(height: 14),

                  // 6. Expressive Transport Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: isShuffle
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).toggleShuffle(),
                      ),
                      IconButton(
                        iconSize: 42,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).skipPrevious(),
                      ),
                      // Large Circular Play/Pause Button (72dp)
                      SpringPressScale(
                        onTap: () =>
                            ref.read(playbackProvider.notifier).togglePlayPause(),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cs.primaryContainer,
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.25),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              key: ValueKey<bool>(isPlaying),
                              size: 38,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        iconSize: 42,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).skipNext(),
                      ),
                      IconButton(
                        icon: Icon(
                          repeatMode == 2
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: repeatMode > 0
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        onPressed: () =>
                            ref.read(playbackProvider.notifier).cycleRepeatMode(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Secondary Action Bar (Queue, Lyrics Button, Hamburger Menu) - Equally spaced out
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionPill(
                          context: context,
                          icon: Icons.queue_music_rounded,
                          label: hasUserQueuedTracks
                              ? (userQueueCount > 0
                                  ? 'Queue ($userQueueCount)'
                                  : 'Queue')
                              : 'Up Next',
                          isActive: hasUserQueuedTracks,
                          onTap: () => showQueueBottomSheet(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionPill(
                          context: context,
                          icon: Icons.lyrics_rounded,
                          label: 'Lyrics',
                          isActive: lyrics.isNotEmpty,
                          onTap: _openFullscreenLyrics,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildActionPill(
                          context: context,
                          icon: Icons.menu_rounded,
                          label: 'More',
                          isActive: hasActiveOptions,
                          onTap: () => _showPlaybackOptionsMenu(context),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(
                    height: MediaQuery.of(context).padding.bottom > 0
                        ? MediaQuery.of(context).padding.bottom + 8
                        : 24,
                  ),
                ],
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
],
),
),
);
  }

  void _showPlaybackOptionsMenu(BuildContext context) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;
    final playback = ref.read(playbackProvider);
    final track = playback.currentTrack;

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
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.tune_rounded,
                              color: cs.onPrimaryContainer,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Playback Options',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    physics: buildSuperSmoothScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: Icon(
                            playback.isSleepTimerActive
                                ? Icons.bedtime_rounded
                                : Icons.bedtime_outlined,
                            color: playback.isSleepTimerActive ? cs.primary : null,
                          ),
                          title: const Text('Sleep Timer',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            playback.isSleepTimerActive
                                ? 'Remaining: ${playback.formattedSleepTimerRemaining}'
                                : 'Turn off playback automatically',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: playback.isSleepTimerActive
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              playback.isSleepTimerActive
                                  ? playback.formattedSleepTimerRemaining
                                  : 'Off',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: playback.isSleepTimerActive
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showSleepTimerModal(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.speed_rounded,
                            color: (playback.playbackSpeed != 1.0 ||
                                    playback.pitch != 1.0)
                                ? cs.primary
                                : null,
                          ),
                          title: const Text('Playback Speed & Pitch',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Fine-grained tempo & pitch shifting'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: (playback.playbackSpeed != 1.0 ||
                                      playback.pitch != 1.0)
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '${playback.playbackSpeed.toStringAsFixed(playback.playbackSpeed % 1 == 0 ? 0 : 2)}x',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: (playback.playbackSpeed != 1.0 ||
                                        playback.pitch != 1.0)
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showPlaybackSpeedModal(context);
                          },
                        ),
                        ListTile(
                          leading: Icon(
                            playback.isLoopActive
                                ? Icons.repeat_on_rounded
                                : Icons.all_inclusive_rounded,
                            color: playback.isLoopActive ? cs.primary : null,
                          ),
                          title: const Text('A-B Repeat Loop',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Loop a specific section seamlessly'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: playback.isLoopActive
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              playback.isLoopActive ? 'Active' : 'Off',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: playback.isLoopActive
                                    ? cs.onPrimaryContainer
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showABLoopModal(context);
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.graphic_eq_rounded),
                          title: const Text('Audio Signal Path & Specs',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${track.codec} • ${track.bitDepth}-Bit • ${track.formattedSampleRate}'),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => const SignalPathSheet(),
                            );
                          },
                        ),
                        if (track.id.isNotEmpty) ...[
                          ListTile(
                            leading: Icon(
                              track.isPinnedOffline
                                  ? Icons.check_circle_rounded
                                  : Icons.download_for_offline_rounded,
                              color: track.isPinnedOffline ? cs.primary : null,
                            ),
                            title: Text(
                              track.isPinnedOffline
                                  ? 'Downloaded to Device'
                                  : 'Download Track',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              track.isPinnedOffline
                                  ? 'Available offline • Tap to remove'
                                  : 'Save locally for offline high-fidelity playback',
                            ),
                            trailing: track.isPinnedOffline
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      'Saved',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  )
                                : null,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              ref
                                  .read(tracksCatalogProvider.notifier)
                                  .togglePinOffline(track.id);
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.playlist_add_rounded),
                            title: const Text('Add to Playlist',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('Save to a custom or new playlist'),
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
                            subtitle:
                                const Text('Remove this track from your collection'),
                            onTap: () {
                              Navigator.of(ctx).pop();
                              showRemoveTrackConfirmationDialog(
                                context,
                                ref,
                                track,
                                onRemoved: () {
                                  Navigator.of(context).maybePop();
                                },
                              );
                            },
                          ),
                        ],
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

  Widget _buildActionPill({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return SpringPressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: isActive
              ? cs.primaryContainer
              : cs.surfaceContainerHigh.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isActive
                ? cs.primary.withValues(alpha: 0.6)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic Audio Waveform Seekbar extracted into an isolated ConsumerWidget.
/// Re-evaluates ONLY on position/progress ticks so heavy background blurs & box shadows
/// are NEVER re-blurred during playback.
class _NowPlayingSeekSection extends ConsumerWidget {
  const _NowPlayingSeekSection({
    required this.track,
  });

  final Track track;

  static String _formatDuration(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final progressFraction =
        ref.watch(playbackProvider.select((p) => p.progressFraction));
    final bufferedPositionMs =
        ref.watch(playbackProvider.select((p) => p.bufferedPositionMs));
    final positionMs =
        ref.watch(playbackProvider.select((p) => p.positionMs));
    final isPlaying =
        ref.watch(playbackProvider.select((p) => p.isPlaying));

    final bufferedProgress = track.durationMs > 0
        ? (bufferedPositionMs / track.durationMs).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: WaveformSeekbar(
            progress: progressFraction,
            bufferedProgress: bufferedProgress,
            isPlaying: isPlaying,
            primaryColor: cs.primary,
            onSeek: (frac) {
              if (track.durationMs > 0) {
                final targetMs = (frac * track.durationMs).round();
                ref.read(playbackProvider.notifier).seekToMs(targetMs);
              }
            },
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(positionMs),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                _formatDuration(track.durationMs),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
