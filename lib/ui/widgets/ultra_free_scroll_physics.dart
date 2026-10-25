import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Ultra-smooth, frictionless free scroll physics for horizontal and vertical scrolling.
///
/// Features:
/// - Zero touch drag resistance: direct 1:1 finger tracking without dampening.
/// - Zero motion start threshold: starts moving instantaneously on finger touch.
/// - Uncapped maximum fling velocity (150,000 px/s): users can free scroll at any speed.
/// - Extremely minimal gradual slow down (friction: 0.00075 vs standard Android 0.015, ~20x less friction):
///   allows effortless free-gliding across hundreds or thousands of items on a single flick.
/// - Clean boundary clamping without spring bounces.
class UltraFreeScrollPhysics extends ClampingScrollPhysics {
  const UltraFreeScrollPhysics({
    super.parent,
    this.friction = 0.00075,
  });

  /// The deceleration friction constant. Default is 0.00075 (standard Android is 0.015).
  final double friction;

  @override
  UltraFreeScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return UltraFreeScrollPhysics(
      parent: buildParent(ancestor),
      friction: friction,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // Zero drag resistance during user touch: direct 1:1 motion
    return offset;
  }

  @override
  double? get dragStartDistanceMotionThreshold => null;

  @override
  double get minFlingVelocity => 8.0;

  @override
  double get maxFlingVelocity => 150000.0;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      double? end;
      if (position.pixels > position.maxScrollExtent) {
        end = position.maxScrollExtent;
      }
      if (position.pixels < position.minScrollExtent) {
        end = position.minScrollExtent;
      }
      assert(end != null);
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        end!,
        math.min(0.0, velocity),
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
      return null;
    }
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
      return null;
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: friction,
      tolerance: tolerance,
    );
  }
}
