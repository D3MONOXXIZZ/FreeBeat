import 'package:flutter/material.dart';

/// Art styles matching Google Pixel Material You inspiration designs.
enum PixelArtStyle {
  desertSun,
  organicWaves,
  dailySoundtrack,
  aiDjMesh,
  minimalBlobs,
}

/// Procedural vector artwork widget that renders fluid, organic, pastel
/// Material You abstract art (desert dunes, sunrise, wavy topography, gradient meshes).
/// Eliminates network dependencies and renders crisp, vibrant artwork at any screen scale.
class PixelOrganicArtwork extends StatelessWidget {
  const PixelOrganicArtwork({
    super.key,
    required this.style,
    this.borderRadius = 28.0,
    this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
    this.showGlow = false,
  });

  final PixelArtStyle style;
  final double borderRadius;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? tertiaryColor;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pColor = primaryColor ?? cs.primary;
    final sColor = secondaryColor ?? cs.secondary;
    final tColor = tertiaryColor ?? cs.tertiary;

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CustomPaint(
        size: Size.infinite,
        painter: _OrganicArtPainter(
          style: style,
          colorScheme: cs,
          primaryColor: pColor,
          secondaryColor: sColor,
          tertiaryColor: tColor,
        ),
      ),
    );

    if (!showGlow) return content;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: pColor.withValues(alpha: 0.35),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: content,
    );
  }
}

class _OrganicArtPainter extends CustomPainter {
  _OrganicArtPainter({
    required this.style,
    required this.colorScheme,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
  });

  final PixelArtStyle style;
  final ColorScheme colorScheme;
  final Color primaryColor;
  final Color secondaryColor;
  final Color tertiaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case PixelArtStyle.desertSun:
        _paintDesertSun(canvas, size);
        break;
      case PixelArtStyle.organicWaves:
        _paintOrganicWaves(canvas, size);
        break;
      case PixelArtStyle.dailySoundtrack:
        _paintDailySoundtrack(canvas, size);
        break;
      case PixelArtStyle.aiDjMesh:
        _paintAiDjMesh(canvas, size);
        break;
      case PixelArtStyle.minimalBlobs:
        _paintMinimalBlobs(canvas, size);
        break;
    }
  }

  /// Screen 2 in Figma: "Desert Sun" — warm terracotta dunes with a glowing golden sun
  void _paintDesertSun(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Sky gradient
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF4A7C85),
          Color(0xFF88B3BA),
          Color(0xFFE8D0B3),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    // Golden Sun
    final sunCenter = Offset(size.width * 0.55, size.height * 0.38);
    final sunRadius = size.width * 0.22;
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFF7C2),
          const Color(0xFFFFD57A).withValues(alpha: 0.95),
          const Color(0xFFFF9E43).withValues(alpha: 0.2),
        ],
        stops: const [0.0, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius * 1.5));
    canvas.drawCircle(sunCenter, sunRadius, sunPaint);

    // Dune 1 (Back mountain)
    final dune1Path = Path();
    dune1Path.moveTo(0, size.height * 0.52);
    dune1Path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.42,
      size.width * 0.55,
      size.height * 0.46,
    );
    dune1Path.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.50,
      size.width,
      size.height * 0.40,
    );
    dune1Path.lineTo(size.width, size.height);
    dune1Path.lineTo(0, size.height);
    dune1Path.close();

    final dune1Paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF7A3E4E), Color(0xFF9E4B56)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawPath(dune1Path, dune1Paint);

    // Dune 2 (Middle dune)
    final dune2Path = Path();
    dune2Path.moveTo(0, size.height * 0.62);
    dune2Path.quadraticBezierTo(
      size.width * 0.35,
      size.height * 0.54,
      size.width * 0.70,
      size.height * 0.60,
    );
    dune2Path.quadraticBezierTo(
      size.width * 0.90,
      size.height * 0.64,
      size.width,
      size.height * 0.58,
    );
    dune2Path.lineTo(size.width, size.height);
    dune2Path.lineTo(0, size.height);
    dune2Path.close();

    final dune2Paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFE27341), Color(0xFFC75135)],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect);
    canvas.drawPath(dune2Path, dune2Paint);

    // Dune 3 (Front warm dune)
    final dune3Path = Path();
    dune3Path.moveTo(0, size.height * 0.76);
    dune3Path.quadraticBezierTo(
      size.width * 0.30,
      size.height * 0.66,
      size.width * 0.65,
      size.height * 0.78,
    );
    dune3Path.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.84,
      size.width,
      size.height * 0.72,
    );
    dune3Path.lineTo(size.width, size.height);
    dune3Path.lineTo(0, size.height);
    dune3Path.close();

    final dune3Paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFF3A752), Color(0xFFD66336)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(rect);
    canvas.drawPath(dune3Path, dune3Paint);

    // Foreground Dark Valley
    final dune4Path = Path();
    dune4Path.moveTo(0, size.height * 0.90);
    dune4Path.quadraticBezierTo(
      size.width * 0.45,
      size.height * 0.80,
      size.width,
      size.height * 0.88,
    );
    dune4Path.lineTo(size.width, size.height);
    dune4Path.lineTo(0, size.height);
    dune4Path.close();

    final dune4Paint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF384358), Color(0xFF2A3245)],
      ).createShader(rect);
    canvas.drawPath(dune4Path, dune4Paint);
  }

  /// Screen 1 in Figma: "Organic Playlists" — soothing sage, olive, cream, terracotta waves
  void _paintOrganicWaves(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base background
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFE5DECE),
    );

    // Top Olive Blob
    final path1 = Path();
    path1.moveTo(0, 0);
    path1.lineTo(size.width * 0.75, 0);
    path1.cubicTo(
      size.width * 0.65,
      size.height * 0.35,
      size.width * 0.25,
      size.height * 0.25,
      0,
      size.height * 0.50,
    );
    path1.close();
    canvas.drawPath(
      path1,
      Paint()..color = const Color(0xFFC77958),
    );

    // Center undulating wave
    final path2 = Path();
    path2.moveTo(0, size.height * 0.40);
    path2.cubicTo(
      size.width * 0.40,
      size.height * 0.20,
      size.width * 0.70,
      size.height * 0.65,
      size.width,
      size.height * 0.35,
    );
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    canvas.drawPath(
      path2,
      Paint()..color = const Color(0xFF6B7B50),
    );

    // Bottom Sage Arc
    final path3 = Path();
    path3.moveTo(0, size.height * 0.65);
    path3.cubicTo(
      size.width * 0.35,
      size.height * 0.85,
      size.width * 0.75,
      size.height * 0.60,
      size.width,
      size.height * 0.75,
    );
    path3.lineTo(size.width, size.height);
    path3.lineTo(0, size.height);
    path3.close();
    canvas.drawPath(
      path3,
      Paint()..color = const Color(0xFF9AA77C),
    );
  }

  /// Screen 1 in Figma: "Your Daily Soundtrack" — pastel lavender, violet, sunset butter
  void _paintDailySoundtrack(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Soft butter background
    canvas.drawRect(
      rect,
      Paint()..color = const Color(0xFFF9D58E),
    );

    // Fluid purple/violet curves
    final path1 = Path();
    path1.moveTo(0, size.height * 0.15);
    path1.cubicTo(
      size.width * 0.30,
      size.height * 0.45,
      size.width * 0.70,
      -size.height * 0.10,
      size.width,
      size.height * 0.25,
    );
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();

    final paint1 = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF9885D2), Color(0xFF5D7CE2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawPath(path1, paint1);

    // Blush pink middle blob
    final path2 = Path();
    path2.moveTo(size.width * 0.35, size.height);
    path2.cubicTo(
      size.width * 0.40,
      size.height * 0.55,
      size.width * 0.80,
      size.height * 0.60,
      size.width,
      size.height * 0.70,
    );
    path2.lineTo(size.width, size.height);
    path2.close();

    final paint2 = Paint()..color = const Color(0xFFE9969F);
    canvas.drawPath(path2, paint2);

    // Cream white top fluid corner
    final path3 = Path();
    path3.moveTo(0, 0);
    path3.lineTo(size.width * 0.45, 0);
    path3.cubicTo(
      size.width * 0.35,
      size.height * 0.20,
      size.width * 0.15,
      size.height * 0.25,
      0,
      size.height * 0.15,
    );
    path3.close();
    canvas.drawPath(path3, Paint()..color = const Color(0xFFFFF8EC));
  }

  /// Screen 3 in Figma: "AI DJ" — vibrant energetic mesh gradient
  void _paintAiDjMesh(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final basePaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.6, -0.6),
        radius: 1.2,
        colors: [
          Color(0xFF5B69F2),
          Color(0xFFE55D87),
          Color(0xFF5FC3E4),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    // Glowing orb
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.45),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.75, size.height * 0.25),
          radius: size.width * 0.35,
        ),
      );
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.25),
      size.width * 0.35,
      glowPaint,
    );
  }

  /// Minimalist Material You geometric blobs
  void _paintMinimalBlobs(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = colorScheme.surfaceContainerHighest,
    );

    final p1 = Path();
    p1.addOval(Rect.fromCenter(
      center: Offset(size.width * 0.3, size.height * 0.4),
      width: size.width * 0.7,
      height: size.height * 0.7,
    ));
    canvas.drawPath(
      p1,
      Paint()..color = primaryColor.withValues(alpha: 0.35),
    );

    final p2 = Path();
    p2.addOval(Rect.fromCenter(
      center: Offset(size.width * 0.75, size.height * 0.7),
      width: size.width * 0.6,
      height: size.height * 0.6,
    ));
    canvas.drawPath(
      p2,
      Paint()..color = secondaryColor.withValues(alpha: 0.30),
    );
  }

  @override
  bool shouldRepaint(covariant _OrganicArtPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
