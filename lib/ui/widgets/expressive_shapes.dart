import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';

/// 120Hz Material 3 Expressive press-scale spring wrapper for cards, buttons, and pills.
class SpringPressScale extends StatefulWidget {
  const SpringPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.95,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  @override
  State<SpringPressScale> createState() => _SpringPressScaleState();
}

class _SpringPressScaleState extends State<SpringPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Google Pixel Material 3 Expressive Morphing Play/Pause Button.
/// Smoothly morphs border radius from a circle (paused) into a squircle pill (playing)
/// with custom Pixel LRA haptics.
class MorphingPlayPauseButton extends StatelessWidget {
  const MorphingPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.size = 72.0,
  });

  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SpringPressScale(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutBack,
        width: isPlaying ? size * 1.18 : size,
        height: size,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(isPlaying ? 24 : size / 2),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.28),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey<bool>(isPlaying),
              size: size * 0.5,
              color: cs.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// 12-Lobe Scalloped / Cookie Clipper used in Google Pixel Material 3 Expressive badges & artwork.
class ScallopedBadgeClipper extends CustomClipper<Path> {
  ScallopedBadgeClipper({this.lobes = 12, this.depth = 0.08});

  final int lobes;
  final double depth;

  @override
  Path getClip(Size size) {
    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseRadius = math.min(cx, cy) * (1.0 - depth);
    final amp = math.min(cx, cy) * depth;

    const steps = 120;
    for (int i = 0; i <= steps; i++) {
      final theta = (i / steps) * 2 * math.pi;
      final r = baseRadius + amp * math.cos(lobes * theta);
      final x = cx + r * math.cos(theta);
      final y = cy + r * math.sin(theta);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant ScallopedBadgeClipper oldClipper) => false;
}

/// Interactive Cloud Provider Filter Pill with Pixel Haptics.
class PixelFilterPill extends StatelessWidget {
  const PixelFilterPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.accentColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeBg = accentColor != null
        ? accentColor!.withValues(alpha: 0.25)
        : cs.secondaryContainer;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(isSelected ? 16 : 24),
          border: Border.all(
            color: isSelected
                ? (accentColor ?? cs.primary)
                : cs.outlineVariant.withValues(alpha: 0.35),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: isSelected
                    ? (accentColor ?? cs.primary)
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
