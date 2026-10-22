import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Authentic Material / iOS squircle App Icon for Spotify.
class SpotifyAppIcon extends StatelessWidget {
  const SpotifyAppIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Spotify',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1ED760),
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1ED760).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: CustomPaint(
            size: Size(size * 0.65, size * 0.65),
            painter: const _SpotifyWavePainter(),
          ),
        ),
      ),
    );
  }
}

class _SpotifyWavePainter extends CustomPainter {
  const _SpotifyWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF121212)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-0.17); // ~ -10 degrees official tilt
    canvas.translate(-w / 2, -h / 2);

    // Top arc
    paint.strokeWidth = w * 0.16;
    final topRect = Rect.fromLTWH(0, h * 0.04, w, h * 0.72);
    canvas.drawArc(topRect, math.pi * 1.15, math.pi * 0.70, false, paint);

    // Middle arc
    paint.strokeWidth = w * 0.13;
    final midRect = Rect.fromLTWH(w * 0.14, h * 0.28, w * 0.72, h * 0.62);
    canvas.drawArc(midRect, math.pi * 1.15, math.pi * 0.70, false, paint);

    // Bottom arc
    paint.strokeWidth = w * 0.11;
    final botRect = Rect.fromLTWH(w * 0.26, h * 0.50, w * 0.48, h * 0.54);
    canvas.drawArc(botRect, math.pi * 1.15, math.pi * 0.70, false, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Authentic Material / iOS squircle App Icon for Apple Music.
class AppleMusicAppIcon extends StatelessWidget {
  const AppleMusicAppIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Apple Music',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFC3C44), Color(0xFFFA233B), Color(0xFFE0115F)],
          ),
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFC3C44).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            CupertinoIcons.music_note_2,
            color: Colors.white,
            size: size * 0.58,
          ),
        ),
      ),
    );
  }
}

/// Authentic Material / iOS squircle App Icon for YouTube & YouTube Music.
class YouTubeAppIcon extends StatelessWidget {
  const YouTubeAppIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'YouTube',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(size * 0.26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF0000).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(left: size * 0.06),
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: size * 0.68,
            ),
          ),
        ),
      ),
    );
  }
}

/// Composite row of platform app icons for import banners and cards.
class PlatformAppIconGroup extends StatelessWidget {
  const PlatformAppIconGroup({
    super.key,
    this.size = 28,
    this.spacing = 8,
  });

  final double size;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpotifyAppIcon(size: size),
        SizedBox(width: spacing),
        AppleMusicAppIcon(size: size),
        SizedBox(width: spacing),
        YouTubeAppIcon(size: size),
      ],
    );
  }
}
