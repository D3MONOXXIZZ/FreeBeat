import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Official Circular App Icon for Spotify.
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
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1ED760).withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: ClipOval(
          child: Center(
            child: CustomPaint(
              size: Size(size * 0.64, size * 0.64),
              painter: const _SpotifyWavePainter(),
            ),
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
    canvas.rotate(-0.174); // -10 degrees official tilt
    canvas.translate(-w / 2, -h / 2);

    // Top arc: thickest and widest
    paint.strokeWidth = w * 0.16;
    final topPath = Path();
    topPath.moveTo(w * 0.10, h * 0.36);
    topPath.quadraticBezierTo(w * 0.50, h * 0.14, w * 0.90, h * 0.38);
    canvas.drawPath(topPath, paint);

    // Middle arc
    paint.strokeWidth = w * 0.135;
    final midPath = Path();
    midPath.moveTo(w * 0.18, h * 0.54);
    midPath.quadraticBezierTo(w * 0.50, h * 0.35, w * 0.82, h * 0.56);
    canvas.drawPath(midPath, paint);

    // Bottom arc: thinnest and shortest
    paint.strokeWidth = w * 0.11;
    final botPath = Path();
    botPath.moveTo(w * 0.27, h * 0.72);
    botPath.quadraticBezierTo(w * 0.50, h * 0.56, w * 0.73, h * 0.73);
    canvas.drawPath(botPath, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official Circular App Icon for Apple Music.
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
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFC3C44), Color(0xFFFA233B), Color(0xFFE0115F)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFC3C44).withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: ClipOval(
          child: Center(
            child: Icon(
              CupertinoIcons.music_note_2,
              color: Colors.white,
              size: size * 0.56,
            ),
          ),
        ),
      ),
    );
  }
}

/// Official Circular App Icon for YouTube & YouTube Music.
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
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF0000).withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: ClipOval(
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(left: size * 0.05),
              child: CustomPaint(
                size: Size(size * 0.40, size * 0.40),
                painter: const _YouTubeTrianglePainter(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YouTubeTrianglePainter extends CustomPainter {
  const _YouTubeTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, h / 2)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official Circular App Icon for Deezer.
class DeezerAppIcon extends StatelessWidget {
  const DeezerAppIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Deezer',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFA238FF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFA238FF).withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: ClipOval(
          child: Center(
            child: Icon(
              Icons.graphic_eq_rounded,
              color: Colors.white,
              size: size * 0.60,
            ),
          ),
        ),
      ),
    );
  }
}

/// Composite row of official circular platform app icons for import banners and cards.
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
        SizedBox(width: spacing),
        DeezerAppIcon(size: size),
      ],
    );
  }
}
