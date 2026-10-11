import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';

/// Tactile Poweramp-style Rotary Knob for Bass, Treble, and Stereo X (Width).
/// Features glowing Material You arc progress, tick marks, pointer drag rotation,
/// double-tap reset, and custom Google Pixel LRA micro-tick & rail-thud haptics.
class PowerampRotaryKnob extends StatefulWidget {
  const PowerampRotaryKnob({
    super.key,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.accentColor,
    this.size = 104.0,
  });

  final String label;
  final String subtitle;
  final double value; // 0.0 to 1.0
  final ValueChanged<double> onChanged;
  final Color? accentColor;
  final double size;

  @override
  State<PowerampRotaryKnob> createState() => _PowerampRotaryKnobState();
}

class _PowerampRotaryKnobState extends State<PowerampRotaryKnob> {
  double _lastHapticStep = 0.0;

  void _updateFromDelta(double dy) {
    final delta = -dy / 130.0;
    final next = (widget.value + delta).clamp(0.0, 1.0);
    if ((next - widget.value).abs() < 0.001) return;

    if ((next == 0.0 || next == 1.0) &&
        widget.value > 0.01 &&
        widget.value < 0.99) {
      PixelHaptics.railLimitThud();
    } else if ((next - _lastHapticStep).abs() >= 0.03) {
      _lastHapticStep = next;
      PixelHaptics.lowTick(intensity: 0.35 + next * 0.55);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.accentColor ?? cs.primary;
    final pct = (widget.value * 100).round();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => _updateFromDelta(details.delta.dy),
      onHorizontalDragUpdate: (details) => _updateFromDelta(-details.delta.dx),
      onDoubleTap: () {
        PixelHaptics.centerDetentSnap();
        widget.onChanged(0.0);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _RotaryKnobPainter(
                value: widget.value,
                activeColor: activeColor,
                surfaceColor: cs.surfaceContainerHighest,
                tickColor: cs.onSurfaceVariant.withValues(alpha: 0.35),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$pct%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      '+${(widget.value * 12.0).toStringAsFixed(1)}dB',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: activeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          Text(
            widget.subtitle,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RotaryKnobPainter extends CustomPainter {
  _RotaryKnobPainter({
    required this.value,
    required this.activeColor,
    required this.surfaceColor,
    required this.tickColor,
  });

  final double value;
  final Color activeColor;
  final Color surfaceColor;
  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 6;
    final knobRadius = outerRadius - 10;

    const startAngle = 0.75 * math.pi; // 135 deg
    const sweepTotal = 1.5 * math.pi; // 270 deg

    // 1. Background Arc Track
    final bgArcPaint = Paint()
      ..color = tickColor
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startAngle,
      sweepTotal,
      false,
      bgArcPaint,
    );

    // 2. Active Glowing Arc
    if (value > 0.005) {
      final activeArcPaint = Paint()
        ..color = activeColor
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        startAngle,
        sweepTotal * value,
        false,
        activeArcPaint,
      );
    }

    // 3. Rotary Dial Body
    final bodyPaint = Paint()
      ..color = surfaceColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, knobRadius, bodyPaint);

    final rimPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, knobRadius, rimPaint);

    // 4. Indicator Notch Dot on Dial
    final currentAngle = startAngle + sweepTotal * value;
    final notchRadius = knobRadius - 8;
    final notchOffset = Offset(
      center.dx + notchRadius * math.cos(currentAngle),
      center.dy + notchRadius * math.sin(currentAngle),
    );
    canvas.drawCircle(notchOffset, 3.8, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(covariant _RotaryKnobPainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.activeColor != activeColor;
  }
}
