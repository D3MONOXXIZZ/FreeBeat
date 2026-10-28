import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/models/track.dart';

/// Stock Google Pixel Material 3 Expressive Album Cover.
///
/// Engineered to match the Pixel Settings app (`000.mp4`) zero-drop 120Hz scrolling:
/// 1. **Zero `ClipRRectLayer` Stencil Pass on List Thumbnails**:
///    For list thumbnails (`size <= 56`), uses `DecoratedBox` with `BoxDecoration(borderRadius: ..., image: DecorationImage(...))`
///    instead of `ClipRRect` + `Image`. Impeller draws rounded `DecorationImage` quads in a single GPU draw call
///    with zero offscreen stencil buffer allocations!
/// 2. **Background RAM Pre-Warming ([prewarmLibraryThumbnails])**:
///    Pre-decodes all local track thumbnails (`144px` width) into `PaintingBinding.instance.imageCache`
///    so scrolling into unvisited rows (`rows 15..500+`) never reads or decodes JPEGs from flash storage mid-fling!
/// 3. **Fling-Aware Deferred Loading**:
///    If a thumbnail is not yet in `imageCache` while the list is flinging at high velocity
///    (`Scrollable.recommendDeferredLoadingForContext(context) == true`), defers disk decoding until the fling slows down.
class MaterialYouAlbumCover extends StatelessWidget {
  const MaterialYouAlbumCover({
    super.key,
    required this.track,
    this.size = 140.0,
    this.borderRadius = 24.0,
    this.showQualityBadge = true,
    this.showSourceBadge = true,
    this.showPlayButton = false,
    this.isPlaying = false,
    this.showPlayingAnimation = true,
    this.onPlayTap,
  });

  final Track track;
  final double size;
  final double borderRadius;
  final bool showQualityBadge;
  final bool showSourceBadge;
  final bool showPlayButton;
  final bool isPlaying;
  final bool showPlayingAnimation;
  final VoidCallback? onPlayTap;

  static final Map<String, ImageProvider> _providerCache = <String, ImageProvider>{};
  static final Set<String> _prewarmedPaths = <String>{};
  static bool _isPrewarming = false;

  static ImageProvider getCachedFileProvider(String path, [int targetCache = 144]) {
    final key = '$path|$targetCache';
    final existing = _providerCache[key];
    if (existing != null) return existing;
    if (_providerCache.length > 2000) {
      _providerCache.clear();
    }
    final provider = ResizeImage(
      FileImage(File(path)),
      width: targetCache,
      policy: ResizeImagePolicy.fit,
    );
    _providerCache[key] = provider;
    return provider;
  }

  /// Pre-decodes local library thumbnails into Flutter's [ImageCache] during idle frames
  /// so scrolling into unvisited rows has 0 disk I/O and 0 JPEG decoding spikes.
  static void prewarmLibraryThumbnails(BuildContext context, List<Track> tracks) {
    if (_isPrewarming || tracks.isEmpty) return;
    _isPrewarming = true;
    unawaited(() async {
      try {
        for (final t in tracks) {
          if (!context.mounted) break;
          final art = t.artworkUrl;
          if (art == null || art.isEmpty || art.startsWith('http')) continue;
          if (_prewarmedPaths.contains(art)) continue;
          _prewarmedPaths.add(art);

          final provider = getCachedFileProvider(art, 144);
          final status = PaintingBinding.instance.imageCache.statusForKey(provider);
          if (status.keepAlive || status.live) continue;

          // Yield until the scheduler is idle / between frames
          await SchedulerBinding.instance.endOfFrame;
          if (!context.mounted) break;
          try {
            await precacheImage(provider, context);
          } catch (_) {}
        }
      } finally {
        _isPrewarming = false;
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isStaleGreen = track.dominantColorValue == 0xFF3DDC84 ||
        track.dominantColorValue == 0xFF1DB954;
    final trackColor = (!isStaleGreen && track.dominantColorValue != 0)
        ? Color(track.dominantColorValue)
        : cs.primary;

    // ULTRA-FAST PATH FOR 48dp LIST THUMBNAILS (0 ClipRRect layers, 0 Stacks, 0 BoxShadows):
    if (size <= 56 &&
        !showQualityBadge &&
        !showSourceBadge &&
        !showPlayButton &&
        !(isPlaying && showPlayingAnimation) &&
        onPlayTap == null) {
      return _buildFastListThumbnail(context, trackColor, cs);
    }

    final coverContent = Container(
      width: size.isFinite ? size : null,
      height: size.isFinite ? size : null,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: cs.surfaceContainerHigh,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1.0,
        ),
        boxShadow: size > 160
            ? [
                BoxShadow(
                  color: trackColor.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ]
            : size > 52
                ? [
                    BoxShadow(
                      color: trackColor.withValues(alpha: 0.14),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            size > 120
                ? RepaintBoundary(
                    child: _buildCoverImage(context, trackColor, cs),
                  )
                : _buildCoverImage(context, trackColor, cs),

            if (size > 52 || showQualityBadge || showSourceBadge)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

            if (showQualityBadge)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (track.isHiRes)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            size: 10,
                            color: cs.primaryContainer,
                          ),
                        ),
                      Text(
                        track.isHiRes
                            ? 'HI-RES'
                            : track.isLossless
                                ? track.codec.toUpperCase()
                                : '${track.bitrateKbps}K',
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (showSourceBadge)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      track.providerType.icon,
                      size: 12,
                      color: track.providerType.accentColor,
                    ),
                  ),
                ),
              ),

            if (isPlaying && showPlayingAnimation)
              Center(
                child: RepaintBoundary(
                  child: PixelPlayingEqualizerAnimation(
                    size: (size * 0.36).clamp(16.0, 32.0),
                    color: Colors.white,
                  ),
                ),
              )
            else if (showPlayButton)
              Positioned(
                bottom: 8,
                right: 8,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPlayTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (onPlayTap != null && !showPlayButton) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPlayTap,
        child: coverContent,
      );
    }

    return coverContent;
  }

  /// Renders a 48dp list thumbnail using [DecoratedBox] + [DecorationImage] instead of [ClipRRect],
  /// eliminating GPU stencil-clip render passes and deferring uncached disk decodes during fast flings.
  Widget _buildFastListThumbnail(
    BuildContext context,
    Color trackColor,
    ColorScheme cs,
  ) {
    final art = track.artworkUrl;
    if (art != null && art.isNotEmpty) {
      if (!art.startsWith('http://') && !art.startsWith('https://')) {
        final provider = getCachedFileProvider(art, 144);
        final cacheStatus =
            PaintingBinding.instance.imageCache.statusForKey(provider);
        // If already in ImageCache, draw immediately with DecorationImage (0 ClipRRect layers!).
        // If not yet in ImageCache and user is flinging fast, defer disk decode until fling slows down!
        if (!cacheStatus.keepAlive &&
            !cacheStatus.live &&
            Scrollable.recommendDeferredLoadingForContext(context)) {
          return SizedBox(
            width: size,
            height: size,
            child: _buildFastMonogramBox(trackColor, cs),
          );
        }
        return SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: trackColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(borderRadius),
              image: DecorationImage(
                image: provider,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                onError: (_, __) {},
              ),
            ),
          ),
        );
      } else {
        if (Scrollable.recommendDeferredLoadingForContext(context)) {
          return SizedBox(
            width: size,
            height: size,
            child: _buildFastMonogramBox(trackColor, cs),
          );
        }
        return SizedBox(
          width: size,
          height: size,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: CachedNetworkImage(
              imageUrl: art,
              fit: BoxFit.cover,
              memCacheWidth: 144,
              maxWidthDiskCache: 512,
              maxHeightDiskCache: 512,
              useOldImageOnUrlChange: true,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => _buildProceduralMaterialYouArt(context, trackColor, cs),
              errorWidget: (_, __, ___) => _buildProceduralMaterialYouArt(context, trackColor, cs),
            ),
          ),
        );
      }
    }

    return SizedBox(
      width: size,
      height: size,
      child: _buildFastMonogramBox(trackColor, cs),
    );
  }

  Widget _buildFastMonogramBox(Color trackColor, ColorScheme cs) {
    final titleInitial = track.title.trim().isNotEmpty
        ? track.title.trim()[0].toUpperCase()
        : '♪';
    final artistInitial = track.artist.trim().isNotEmpty
        ? track.artist.trim()[0].toUpperCase()
        : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: trackColor.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Text(
          '$titleInitial$artistInitial',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, Color trackColor, ColorScheme cs) {
    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      final art = track.artworkUrl!;
      final bool isListThumbnail = size <= 64;
      final int targetCache = isListThumbnail
          ? 144
          : (size.isFinite ? (size * 2.75).round().clamp(144, 512) : 512);

      if (art.startsWith('http://') || art.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: art,
          fit: BoxFit.cover,
          memCacheWidth: targetCache,
          maxWidthDiskCache: 512,
          maxHeightDiskCache: 512,
          useOldImageOnUrlChange: true,
          fadeInDuration: isListThumbnail
              ? Duration.zero
              : const Duration(milliseconds: 150),
          fadeOutDuration: Duration.zero,
          placeholder: (_, __) => _buildProceduralMaterialYouArt(context, trackColor, cs),
          errorWidget: (_, __, ___) => _buildProceduralMaterialYouArt(context, trackColor, cs),
        );
      } else {
        return Image(
          image: getCachedFileProvider(art, targetCache),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, __, ___) =>
              _buildProceduralMaterialYouArt(context, trackColor, cs),
        );
      }
    }

    return _buildProceduralMaterialYouArt(context, trackColor, cs);
  }

  Widget _buildProceduralMaterialYouArt(
    BuildContext context,
    Color trackColor,
    ColorScheme cs,
  ) {
    final titleInitial = track.title.trim().isNotEmpty
        ? track.title.trim()[0].toUpperCase()
        : '♪';
    final artistInitial = track.artist.trim().isNotEmpty
        ? track.artist.trim()[0].toUpperCase()
        : '';
    final effectiveSize = size.isFinite ? size : 280.0;

    if (size <= 56) {
      return _buildFastMonogramBox(trackColor, cs);
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            trackColor.withValues(alpha: 0.85),
            cs.secondaryContainer,
            cs.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _VinylGroovesPainter(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: effectiveSize * 0.38,
                  height: effectiveSize * 0.38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$titleInitial$artistInitial',
                      style: TextStyle(
                        fontFamily: 'GoogleSans',
                        fontSize: effectiveSize * 0.16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  _VinylGroovesPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final maxRadius = size.width * 0.65;
    final step = size.width > 80 ? 9.0 : 16.0;
    for (double r = size.width * 0.18; r < maxRadius; r += step) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) => false;
}

class PixelPlayingEqualizerAnimation extends StatefulWidget {
  const PixelPlayingEqualizerAnimation({
    super.key,
    this.color,
    this.size = 20,
    this.barCount = 3,
    this.isStatic = false,
  });

  final Color? color;
  final double size;
  final int barCount;
  final bool isStatic;

  @override
  State<PixelPlayingEqualizerAnimation> createState() =>
      _PixelPlayingEqualizerAnimationState();
}

class _PixelPlayingEqualizerAnimationState
    extends State<PixelPlayingEqualizerAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    if (!widget.isStatic) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(PixelPlayingEqualizerAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStatic != oldWidget.isStatic) {
      if (widget.isStatic) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.color ?? Colors.white;
    final width = widget.size;
    final barWidth = (width / (widget.barCount * 2.2)).clamp(2.0, 4.0);

    if (widget.isStatic) {
      const staticFactors = [0.45, 0.95, 0.65, 0.80, 0.50];
      return SizedBox(
        width: width,
        height: width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(widget.barCount, (i) {
            final factor = staticFactors[i % staticFactors.length];
            return Container(
              width: barWidth,
              height: width * factor,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(100),
              ),
            );
          }),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: width,
          height: width,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(widget.barCount, (i) {
              final phase = (i * 0.35);
              final rawVal = sin((_controller.value * 2 * pi) + phase);
              final factor = 0.25 + (0.75 * ((rawVal + 1) / 2));
              return Container(
                width: barWidth,
                height: width * factor,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(100),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
