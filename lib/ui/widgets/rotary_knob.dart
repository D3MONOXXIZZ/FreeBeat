import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';

/// Tactile Smart EQ Rotary Knob for Bass, Treble, and Stereo X (Width).
/// Features glowing Material You arc progress, tick marks, pointer drag rotation,
/// double-tap reset, and custom Google Pixel LRA micro-tick & rail-thud haptics.
typedef SmartEqRotaryKnob = PowerampRotaryKnob;

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
  late double _localValue;
  bool _isDragging = false;
  double _lastHapticStep = 0.0;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
    _lastHapticStep = widget.value;
  }

  @override
  void didUpdateWidget(PowerampRotaryKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.value != widget.value) {
      _localValue = widget.value;
      _lastHapticStep = widget.value;
    }
  }

  void _onPanStart(DragStartDetails details) {
    _isDragging = true;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Both vertical (upward = increase) and horizontal (rightward = increase) drag supported smoothly
    final delta = (-details.delta.dy + details.delta.dx) / 140.0;
    final next = (_localValue + delta).clamp(0.0, 1.0);
    if ((next - _localValue).abs() < 0.001) return;

    setState(() {
      _localValue = next;
    });

    if ((next == 0.0 || next == 1.0) &&
        _localValue > 0.01 &&
        _localValue < 0.99) {
      PixelHaptics.railLimitThud();
    } else if ((next - _lastHapticStep).abs() >= 0.035) {
      _lastHapticStep = next;
      PixelHaptics.lowTick(intensity: 0.35 + next * 0.55);
    }
    widget.onChanged(next);
  }

  void _onPanEnd(DragEndDetails details) {
    _isDragging = false;
    widget.onChanged(_localValue);
  }

  void _onPanCancel() {
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = widget.accentColor ?? cs.primary;
    final pct = (_localValue * 100).round();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      onDoubleTap: () {
        PixelHaptics.centerDetentSnap();
        setState(() {
          _localValue = 0.0;
          _lastHapticStep = 0.0;
        });
        widget.onChanged(0.0);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RotaryKnobPainter(
                  value: _localValue,
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
                        '+${(_localValue * 12.0).toStringAsFixed(1)}dB',
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
