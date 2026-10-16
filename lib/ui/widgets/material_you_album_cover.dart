import 'dart:io';
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
    this.onPlayTap,
  });

  final Track track;
  final double size;
  final double borderRadius;
  final bool showQualityBadge;
  final bool showSourceBadge;
  final bool showPlayButton;
  final bool isPlaying;
  final VoidCallback? onPlayTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trackColor = track.dominantColorValue != 0
        ? Color(track.dominantColorValue)
        : cs.primary;

    return SpringPressScale(
      onTap: onPlayTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: cs.surfaceContainerHigh,
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1.0,
          ),
          boxShadow: [
            // M3 Surface Tint / Tonal Elevation glow
            BoxShadow(
              color: trackColor.withValues(alpha: 0.18),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Artwork / Procedural Material You Cover
              _buildCoverImage(context, trackColor, cs),

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

              // 5. Center / Bottom: Play Button or Equalizer Animation
              if (showPlayButton || isPlaying)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isPlaying ? cs.primary : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        isPlaying ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                        color: isPlaying ? cs.onPrimary : Colors.black,
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, Color trackColor, ColorScheme cs) {
    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      final art = track.artworkUrl!;
      if (art.startsWith('http://') || art.startsWith('https://')) {
        return Image.network(
          art,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildProceduralMaterialYouArt(context, trackColor, cs),
        );
      } else {
        final file = File(art);
        if (file.existsSync()) {
          return Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildProceduralMaterialYouArt(context, trackColor, cs),
          );
        }
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
                  width: size * 0.38,
                  height: size * 0.38,
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
                        fontSize: size * 0.16,
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
