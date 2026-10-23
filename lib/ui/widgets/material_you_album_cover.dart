import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/models/track.dart';
import 'expressive_shapes.dart';

/// Stock Google Pixel Material 3 Expressive Album Cover.
/// Wraps artwork in a vibrant, dynamic Material You container with tonal elevation,
/// smooth corner radii (24dp+), high-res codec badges, cloud source indicators,
/// and responsive spring-press scaling with Pixel LRA haptics.
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isStaleGreen = track.dominantColorValue == 0xFF3DDC84 ||
        track.dominantColorValue == 0xFF1DB954;
    final trackColor = (!isStaleGreen && track.dominantColorValue != 0)
        ? Color(track.dominantColorValue)
        : cs.primary;

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
                // Ambient M3 Surface Tint / Tonal glow for large hero artwork
                BoxShadow(
                  color: trackColor.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ]
            : size > 52
                ? [
                    // Crisp, hardware-accelerated elevation for 120Hz carousels
                    BoxShadow(
                      color: trackColor.withValues(alpha: 0.14),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [
                    // Lightweight elevation for fast 120Hz scrolling list thumbnails
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Artwork / Procedural Material You Cover (isolated raster layer)
            RepaintBoundary(
              child: _buildCoverImage(context, trackColor, cs),
            ),

            // 2. Subtle Bottom Gradient Scrim for Contrast
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

            // 3. Top-Left: Quality / Codec Badge (FLAC, Hi-Res, 320k)
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

            // 4. Top-Right: Cloud Provider / Source Badge
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

            // 5. Centered Playing Animation on Album Art (without dark shadow)
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
                child: SpringPressScale(
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
      return SpringPressScale(
        onTap: onPlayTap,
        child: coverContent,
      );
    }

    return coverContent;
  }

  Widget _buildCoverImage(BuildContext context, Color trackColor, ColorScheme cs) {
    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      final art = track.artworkUrl!;
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.5;
      final int targetCache = size.isFinite
          ? (size * dpr).round().clamp(96, 720)
          : 512;

      if (art.startsWith('http://') || art.startsWith('https://')) {
        return Image.network(
          art,
          fit: BoxFit.cover,
          cacheWidth: targetCache,
          cacheHeight: targetCache,
          errorBuilder: (_, __, ___) => _buildProceduralMaterialYouArt(context, trackColor, cs),
        );
      } else {
        return Image.file(
          File(art),
          fit: BoxFit.cover,
          cacheWidth: targetCache,
          cacheHeight: targetCache,
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
    // Generate initials
    final titleInitial = track.title.trim().isNotEmpty
        ? track.title.trim()[0].toUpperCase()
        : '♪';
    final artistInitial = track.artist.trim().isNotEmpty
        ? track.artist.trim()[0].toUpperCase()
        : '';
    final effectiveSize = size.isFinite ? size : 280.0;

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
          // Vinyl record grooves custom painter
          CustomPaint(
            painter: _VinylGroovesPainter(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),

          // Central Monogram / Musical Motif
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
    for (double r = size.width * 0.18; r < maxRadius; r += 9.0) {
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) => false;
}

/// Dynamic, hardware-accelerated 3-bar playing equalizer animation.
/// Visually indicates playback across album covers and mini-player.
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(widget.barCount, (i) {
            final factor = staticFactors[i % staticFactors.length];
            return Container(
              width: barWidth,
              height: (width * factor).clamp(3.0, width),
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(100),
              ),
            );
          }),
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value * 2 * pi;
          return SizedBox(
            width: width,
            height: width,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(widget.barCount, (i) {
                final phase = i * 1.45;
                final heightFactor = (0.25 + 0.70 * (0.5 + 0.5 * sin(t + phase))).clamp(0.2, 1.0);
                return Container(
                  width: barWidth,
                  height: (width * heightFactor).clamp(3.0, width),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(100),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
