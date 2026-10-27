import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';

/// 120Hz Material 3 Expressive press-scale spring wrapper for cards, buttons, and pills.
class SpringPressScale extends StatefulWidget {
  const SpringPressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.95,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;

  @override
  State<SpringPressScale> createState() => _SpringPressScaleState();
}

class _SpringPressScaleState extends State<SpringPressScale> {
  bool _pressed = false;
  Timer? _pressTimer;

  @override
  void dispose() {
    _pressTimer?.cancel();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _pressTimer?.cancel();
    // 100ms standard Material press timeout: lets vertical scroll gestures claim the arena
    // without triggering premature setState re-renders or haptic ticks on items during scrolls
    _pressTimer = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _pressed = true);
        PixelHaptics.tick(intensity: 0.35);
      }
    });
  }

  void _onTapUp(TapUpDetails details) {
    final wasPending = _pressTimer?.isActive ?? false;
    _pressTimer?.cancel();
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    } else if (wasPending && mounted) {
      // For quick deliberate taps, show a brief spring-press response
      setState(() => _pressed = true);
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) {
          setState(() => _pressed = false);
        }
      });
    }
    widget.onTap?.call();
  }

  void _onTapCancel() {
    _pressTimer?.cancel();
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    }
  }

  void _onLongPress() {
    _pressTimer?.cancel();
    if (_pressed && mounted) {
      setState(() => _pressed = false);
    }
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) {
      return widget.child;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onLongPress: _onLongPress,
      onTapCancel: _onTapCancel,
      child: AnimatedScale(
        scale: _pressed ? widget.scaleDown : 1.0,
        duration: _pressed
            ? const Duration(milliseconds: 90)
            : const Duration(milliseconds: 180),
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Google Pixel Material 3 Expressive Morphing Play/Pause Button.
/// Smoothly morphs border radius from a circle (paused) into a squircle pill (playing)
/// with custom Pixel LRA haptics, using pure M3 tonal elevation (no drop shadow).
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
          borderRadius: BorderRadius.circular(isPlaying ? 28 : size / 2),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.35),
            width: 1.5,
          ),
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

/// Interactive Cloud Provider Filter Pill with Pixel Stadium Border and Haptics.
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
          borderRadius: BorderRadius.circular(100), // Strict stadium pill
          border: Border.all(
            color: isSelected
                ? (accentColor ?? cs.secondary)
                : cs.outlineVariant.withValues(alpha: 0.25),
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
                    ? (accentColor ?? cs.onSecondaryContainer)
                    : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (accentColor != null ? cs.onSurface : cs.onSecondaryContainer)
                    : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spotify-style 2-column Quick Access Card with Material 3 Expressive 20-28dp rounded polish.
class SpotifyQuickCard extends StatelessWidget {
  const SpotifyQuickCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    this.isPlaying = false,
    this.artworkUrl,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;
  final bool isPlaying;
  final String? artworkUrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 60,
        decoration: BoxDecoration(
          color: isPlaying ? cs.surfaceContainerHighest : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isPlaying
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.25),
            width: isPlaying ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(19),
              ),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.8),
                      accentColor.withValues(alpha: 0.4),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(
                    isPlaying ? Icons.equalizer_rounded : icon,
                    color: cs.onPrimary,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isPlaying ? cs.primary : cs.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPlaying
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20,
                  color: isPlaying ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google Material 3 Expressive Cloud Shape Clipper.
class CloudShapeClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    path.moveTo(w * 0.25, h * 0.75);
    path.cubicTo(w * 0.05, h * 0.75, 0, h * 0.55, w * 0.15, h * 0.40);
    path.cubicTo(w * 0.10, h * 0.20, w * 0.30, h * 0.05, w * 0.48, h * 0.18);
    path.cubicTo(w * 0.62, h * 0.02, w * 0.85, h * 0.10, w * 0.88, h * 0.35);
    path.cubicTo(w * 1.02, h * 0.45, w * 1.0, h * 0.70, w * 0.82, h * 0.75);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
