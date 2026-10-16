import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';

/// Expressive Audio Waveform Seekbar (as shown in Google Pixel Now Playing Screen 2).
/// Renders an authentic multi-bar vertical audio spectrum that responds to scrubbing
/// with tactile micro-haptics and gentle dynamic breathing while playing.
class WaveformSeekbar extends StatefulWidget {
  const WaveformSeekbar({
    super.key,
    required this.progress,
    required this.bufferedProgress,
    required this.isPlaying,
    required this.onSeek,
    this.barCount = 38,
    this.height = 42.0,
    this.primaryColor,
    this.inactiveColor,
  });

  final double progress; // 0.0 to 1.0
  final double bufferedProgress; // 0.0 to 1.0
  final bool isPlaying;
  final ValueChanged<double> onSeek;
  final int barCount;
  final double height;
  final Color? primaryColor;
  final Color? inactiveColor;

  @override
  State<WaveformSeekbar> createState() => _WaveformSeekbarState();
}

class _WaveformSeekbarState extends State<WaveformSeekbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final List<double> _baseHeights;
  bool _isDragging = false;
  double _dragProgress = 0.0;
  int _lastHapticBar = -1;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isPlaying) {
      _animController.repeat(reverse: true);
    }

    // Deterministic procedural waveform pattern (peaks and valleys of real audio)
    final rng = math.Random(42);
    _baseHeights = List.generate(widget.barCount, (i) {
      final t = i / widget.barCount;
      // Multi-frequency wave formula creating realistic musical dynamics
      final wave = 0.45 * math.sin(t * math.pi * 3.5).abs() +
          0.30 * math.sin(t * math.pi * 7.2).abs() +
          0.25 * rng.nextDouble();
      return (wave * 0.85 + 0.15).clamp(0.18, 1.0);
    });
  }

  @override
  void didUpdateWidget(covariant WaveformSeekbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _animController.repeat(reverse: true);
      } else {
        _animController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleSeekUpdate(double localX, double width) {
    final frac = (localX / width).clamp(0.0, 1.0);
    final currentBar = (frac * widget.barCount).floor();
    if (currentBar != _lastHapticBar) {
      _lastHapticBar = currentBar;
      PixelHaptics.lowTick(intensity: 0.35);
    }
    setState(() {
      _dragProgress = frac;
    });
    widget.onSeek(frac);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveProgress = _isDragging ? _dragProgress : widget.progress;

    final activeColor = widget.primaryColor ?? cs.primary;
    final inactiveColor =
        widget.inactiveColor ?? cs.onSurfaceVariant.withValues(alpha: 0.28);
    final bufferedColor = cs.onSurfaceVariant.withValues(alpha: 0.45);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            _isDragging = true;
            PixelHaptics.tick();
            _handleSeekUpdate(details.localPosition.dx, totalWidth);
          },
          onHorizontalDragUpdate: (details) {
            _handleSeekUpdate(details.localPosition.dx, totalWidth);
          },
          onHorizontalDragEnd: (details) {
            setState(() => _isDragging = false);
            PixelHaptics.tick();
          },
          onTapDown: (details) {
            _handleSeekUpdate(details.localPosition.dx, totalWidth);
          },
          child: AnimatedBuilder(
            animation: _animController,
            builder: (context, _) {
              final animVal = widget.isPlaying ? _animController.value : 0.0;

              return SizedBox(
                height: widget.height,
                width: double.infinity,
                child: CustomPaint(
                  size: Size(totalWidth, widget.height),
                  painter: _WaveformSeekbarPainter(
                    baseHeights: _baseHeights,
                    progress: effectiveProgress,
                    bufferedProgress: widget.bufferedProgress,
                    animationValue: animVal,
                    activeColor: activeColor,
                    bufferedColor: bufferedColor,
                    inactiveColor: inactiveColor,
                    isDragging: _isDragging,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _WaveformSeekbarPainter extends CustomPainter {
  _WaveformSeekbarPainter({
    required this.baseHeights,
    required this.progress,
    required this.bufferedProgress,
    required this.animationValue,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
    required this.isDragging,
  });

  final List<double> baseHeights;
  final double progress;
  final double bufferedProgress;
  final double animationValue;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;
  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = baseHeights.length;
    final totalBarWidth = size.width / barCount;
    final barWidth = math.max(2.5, totalBarWidth * 0.65);
    final cornerRadius = Radius.circular(barWidth / 2);

    final activePaint = Paint()..color = activeColor;
    final bufferedPaint = Paint()..color = bufferedColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (int i = 0; i < barCount; i++) {
      final barProgress = i / barCount;
      final xCenter = (i + 0.5) * totalBarWidth;

      // Subtle dynamic flutter when playing
      final flutter = math.sin((i * 0.4) + (animationValue * math.pi * 2)) * 0.08;
      final normalizedHeight = (baseHeights[i] + flutter).clamp(0.15, 1.0);
      final barHeight = normalizedHeight * (size.height * 0.88);

      final yTop = (size.height - barHeight) / 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(xCenter - (barWidth / 2), yTop, barWidth, barHeight),
        cornerRadius,
      );

      if (barProgress <= progress) {
        canvas.drawRRect(rrect, activePaint);
      } else if (barProgress <= bufferedProgress) {
        canvas.drawRRect(rrect, bufferedPaint);
      } else {
        canvas.drawRRect(rrect, inactivePaint);
      }
    }

    // Thumb indicator line/pill when dragging
    if (isDragging) {
      final thumbX = (progress * size.width).clamp(0.0, size.width);
      final thumbPaint = Paint()
        ..color = activeColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(thumbX, 2),
        Offset(thumbX, size.height - 2),
        thumbPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformSeekbarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.activeColor != activeColor;
  }
}
