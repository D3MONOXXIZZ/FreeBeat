import 'dart:io';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/models/playlist.dart';
import '../../core/models/track.dart';

/// Stock Google Pixel Material 3 Expressive Generative Playlist Cover Art.
/// Features:
/// 1. Custom artwork loader if `customArtworkUrl` is present.
/// 2. 4-quadrant dynamic mosaic if tracks contain artwork.
/// 3. Procedural generative art: Concentric vinyl soundwave grooves, organic bezier
///    blobs, and dynamic gradients derived from the playlist title and Monet theme color seed.
class GenerativePlaylistCover extends StatelessWidget {
  const GenerativePlaylistCover({
    super.key,
    required this.playlist,
    this.tracks = const [],
    this.size = 140.0,
    this.borderRadius = 24.0,
    this.showBadge = true,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final double size;
  final double borderRadius;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primarySeed = playlist.colorSeed;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: cs.surfaceContainerHigh,
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: primarySeed.withValues(alpha: 0.22),
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
            // Base artwork or generative canvas
            _buildContent(context, primarySeed, cs),

            // Top-Right Smart Badge
            if (showBadge && playlist.isSmart)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.60),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getSmartIcon(playlist.smartType),
                        size: 10,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      const Text(
                        'SMART',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Track count pill bottom-left
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${playlist.trackCount} ${playlist.trackCount == 1 ? 'track' : 'tracks'}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color seed, ColorScheme cs) {
    if (playlist.customArtworkUrl != null &&
        playlist.customArtworkUrl!.isNotEmpty) {
      final art = playlist.customArtworkUrl!;
      if (art.startsWith('http://') || art.startsWith('https://')) {
        return CachedNetworkImage(
          imageUrl: art,
          fit: BoxFit.cover,
          memCacheWidth: size.isFinite ? (size * 2).round().clamp(128, 512) : 512,
          memCacheHeight: size.isFinite ? (size * 2).round().clamp(128, 512) : 512,
          maxWidthDiskCache: 512,
          maxHeightDiskCache: 512,
          fadeInDuration: const Duration(milliseconds: 150),
          errorWidget: (_, __, ___) => _buildTileOrGenerative(context, seed, cs),
        );
      }
      final file = File(art);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    return _buildTileOrGenerative(context, seed, cs);
  }

  Widget _buildTileOrGenerative(BuildContext context, Color seed, ColorScheme cs) {
    final tracksWithArt = tracks
        .where((t) => t.artworkUrl != null && t.artworkUrl!.isNotEmpty)
        .toList();

    // Check distinct artwork URLs across tracks
    final uniqueArtworkUrls = tracksWithArt.map((t) => t.artworkUrl!).toSet().toList();

    // Only render 4-quadrant mosaic if there are at least 4 DIFFERENT album artworks.
    // If tracks share the same artwork (e.g. an album or single artist collection),
    // render the single full-bleed cover rather than duplicating it 4 times!
    if (uniqueArtworkUrls.length >= 4 && size >= 100) {
      final distinctTracks = <Track>[];
      final seen = <String>{};
      for (final t in tracksWithArt) {
        if (seen.add(t.artworkUrl!)) {
          distinctTracks.add(t);
          if (distinctTracks.length == 4) break;
        }
      }
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildTile(distinctTracks[0])),
                Expanded(child: _buildTile(distinctTracks[1])),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _buildTile(distinctTracks[2])),
                Expanded(child: _buildTile(distinctTracks[3])),
              ],
            ),
          ),
        ],
      );
    } else if (tracksWithArt.isNotEmpty) {
      return _buildTile(tracksWithArt.first);
    }

    // Generative procedural art
    return CustomPaint(
      painter: _GenerativeProceduralPainter(
        seed: seed,
        title: playlist.title,
        smartType: playlist.smartType,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Icon(
            _getSmartIcon(playlist.smartType),
            color: Colors.white,
            size: size.isFinite ? size * 0.28 : 42.0,
          ),
        ),
      ),
    );
  }

  Widget _buildTile(Track track) {
    final art = track.artworkUrl!;
    if (art.startsWith('http://') || art.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: art,
        fit: BoxFit.cover,
        memCacheWidth: 256,
        memCacheHeight: 256,
        maxWidthDiskCache: 256,
        maxHeightDiskCache: 256,
        fadeInDuration: const Duration(milliseconds: 150),
        errorWidget: (_, __, ___) => Container(
          color: track.dominantColor,
          child: const Center(
            child: Icon(Icons.music_note_rounded, color: Colors.white70, size: 16),
          ),
        ),
      );
    }
    final file = File(art);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Container(
      color: track.dominantColor,
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white70, size: 16),
      ),
    );
  }

  IconData _getSmartIcon(String? smartType) {
    switch (smartType) {
      case 'hires':
        return Icons.auto_awesome_rounded;
      case 'offline':
        return Icons.download_done_rounded;
      case 'favorites':
        return Icons.favorite_rounded;
      case 'heavy_rotation':
        return Icons.local_fire_department_rounded;
      case 'recently_added':
        return Icons.schedule_rounded;
      case 'energy':
        return Icons.bolt_rounded;
      case 'chill':
        return Icons.spa_rounded;
      case 'focus':
        return Icons.psychology_rounded;
      default:
        return Icons.queue_music_rounded;
    }
  }
}

/// CustomPainter that renders organic fluid bezier blobs and concentric vinyl soundwave grooves.
class _GenerativeProceduralPainter extends CustomPainter {
  _GenerativeProceduralPainter({
    required this.seed,
    required this.title,
    this.smartType,
  });

  final Color seed;
  final String title;
  final String? smartType;

  @override
  void paint(Canvas canvas, Size size) {
    final hash = title.hashCode.abs();
    final rng = Random(hash);

    final hsl = HSLColor.fromColor(seed);
    final color1 = hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor();
    final color2 = hsl.withLightness((hsl.lightness - 0.20).clamp(0.0, 1.0)).toColor();
    final accentHue = (hsl.hue + 45.0) % 360.0;
    final color3 = HSLColor.fromAHSL(1.0, accentHue, 0.65, 0.50).toColor();

    // 1. Base Gradient
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [color1, color2, color3],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    // 2. Fluid Bezier Blobs
    final blobPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.35 + (rng.nextDouble() * 20 - 10),
      size.height * 0.15,
      size.width * 0.8,
      size.height * 0.45,
    );
    path.quadraticBezierTo(
      size.width * 1.1,
      size.height * 0.65,
      size.width * 0.6,
      size.height,
    );
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, blobPaint);

    // 3. Concentric Vinyl Soundwave Grooves
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 6; i++) {
      final radius = (size.width * 0.14) * i;
      ringPaint.color = Colors.white.withValues(alpha: (0.16 - (i * 0.02)).clamp(0.03, 0.16));
      canvas.drawCircle(center, radius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GenerativeProceduralPainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.title != title;
  }
}
