import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';

/// Signature Android 13–15 Google Pixel Media Player Squiggly Seekbar.
/// Animates a continuous traveling sine wave along the active portion of the track
/// while playing, and smoothly morphs to a flat line when paused or actively dragged.
class SquigglySlider extends StatefulWidget {
  const SquigglySlider({
    super.key,
    required this.value,
    required this.bufferedValue,
    required this.isPlaying,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.waveAmplitude = 4.5,
    this.wavelength = 28.0,
  });

  final double value; // 0.0 to 1.0
  final double bufferedValue; // 0.0 to 1.0
  final bool isPlaying;
  final ValueChanged<double> onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final double waveAmplitude;
  final double wavelength;

  @override
  State<SquigglySlider> createState() => _SquigglySliderState();
}

class _SquigglySliderState extends State<SquigglySlider>
    with TickerProviderStateMixin {
  late final AnimationController _phaseController;
  late final AnimationController _amplitudeController;
  bool _isDragging = false;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.isPlaying) {
      _phaseController.repeat();
    }

    _amplitudeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant SquigglySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _phaseController.repeat();
      } else {
        _phaseController.stop();
      }
    }
    final shouldSquiggle = widget.isPlaying && !_isDragging;
    if (shouldSquiggle) {
      _amplitudeController.forward();
    } else {
      _amplitudeController.reverse();
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _amplitudeController.dispose();
    super.dispose();
  }

  void _handleDragUpdate(Offset localPosition, double width) {
    if (width <= 0) return;
    final nextVal = (localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragValue = nextVal;
    });
    PixelHaptics.lowTick(intensity: 0.35);
    widget.onChanged(nextVal);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.activeColor ?? cs.primary;
    final inactiveColor =
        widget.inactiveColor ?? cs.onSurfaceVariant.withValues(alpha: 0.28);
    final effectiveVal = (_dragValue ?? widget.value).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            setState(() => _isDragging = true);
            _amplitudeController.reverse();
            PixelHaptics.tick(intensity: 0.6);
            _handleDragUpdate(details.localPosition, width);
          },
          onHorizontalDragUpdate: (details) {
            _handleDragUpdate(details.localPosition, width);
          },
          onHorizontalDragEnd: (_) {
            setState(() {
              _isDragging = false;
              _dragValue = null;
            });
            if (widget.isPlaying) {
              _amplitudeController.forward();
            }
          },
          onTapDown: (details) {
            PixelHaptics.tick(intensity: 0.7);
            _handleDragUpdate(details.localPosition, width);
          },
          child: SizedBox(
            height: 36,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _phaseController,
                _amplitudeController,
              ]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _SquigglySliderPainter(
                    progress: effectiveVal,
                    bufferedProgress: widget.bufferedValue.clamp(0.0, 1.0),
                    phase: _phaseController.value * 2 * math.pi,
                    amplitude:
                        widget.waveAmplitude * _amplitudeController.value,
                    wavelength: widget.wavelength,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDragging: _isDragging,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SquigglySliderPainter extends CustomPainter {
  _SquigglySliderPainter({
    required this.progress,
    required this.bufferedProgress,
    required this.phase,
    required this.amplitude,
    required this.wavelength,
    required this.activeColor,
    required this.inactiveColor,
    required this.isDragging,
  });

  final double progress;
  final double bufferedProgress;
  final double phase;
  final double amplitude;
  final double wavelength;
  final Color activeColor;
  final Color inactiveColor;
  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final pad = 10.0;
    final usableWidth = (size.width - pad * 2).clamp(1.0, double.infinity);
    final activeEndX = pad + usableWidth * progress;
    final bufferedEndX = pad + usableWidth * bufferedProgress;

    // 1. Inactive Track Line
    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(activeEndX, cy),
      Offset(size.width - pad, cy),
      inactivePaint,
    );

    // 2. Buffered Track Segment
    if (bufferedEndX > activeEndX) {
      final bufferPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.25)
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(activeEndX, cy),
        Offset(bufferedEndX, cy),
        bufferPaint,
      );
    }

    // 3. Active Squiggly Sine Wave Segment
    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(pad, cy);
    for (double x = pad; x <= activeEndX; x += 2.0) {
      // Taper wave amplitude near ends for clean connection to thumb
      final distFromThumb = (activeEndX - x).clamp(0.0, 16.0) / 16.0;
      final y = cy +
          amplitude *
              distFromThumb *
              math.sin(((x - pad) / wavelength) * 2 * math.pi - phase);
      path.lineTo(x, y);
    }
    canvas.drawPath(path, activePaint);

    // 4. Pixel Pill Thumb Indicator
    final thumbHeight = isDragging ? 24.0 : 18.0;
    final thumbWidth = isDragging ? 8.0 : 6.0;
    final thumbRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(activeEndX, cy),
        width: thumbWidth,
        height: thumbHeight,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(thumbRect, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(covariant _SquigglySliderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.isDragging != isDragging;
  }
}
