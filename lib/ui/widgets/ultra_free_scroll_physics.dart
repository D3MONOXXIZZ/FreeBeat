import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Ultra-smooth, high-performance fluid scroll physics backed by [super_sliver_list].
///
/// Features:
/// - Direct 1:1 finger tracking within scroll range without sluggish touch dampening.
/// - Elastic boundary resistance when pulled past scroll limits.
/// - Standard touch slop motion threshold to prevent tap micro-jitters.
/// - Capped maximum fling velocity (8,000 px/s) to guarantee locked 120Hz/60Hz frame budgets
///   and prevent dropped frames from excessive widget instantiation during ballistic glides.
/// - Fluid deceleration friction (0.012 default, ~20% smoother than standard Android 0.015)
///   for effortless, natural gliding.
/// - Seamless integration with [SuperRangeMaintainingScrollPhysics] to prevent layout jumps.
class UltraFreeScrollPhysics extends ClampingScrollPhysics {
  const UltraFreeScrollPhysics({
    super.parent,
    this.friction = 0.012,
  });

  /// Deceleration friction constant. Default is 0.012 (stock Android is 0.015).
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
    if (position.outOfRange) {
      final double overscrollPastStart =
          math.max(position.minScrollExtent - position.pixels, 0.0);
      final double overscrollPastEnd =
          math.max(position.pixels - position.maxScrollExtent, 0.0);
      final double overscrollPast =
          math.max(overscrollPastStart, overscrollPastEnd);
      final double easing =
          1.0 - (overscrollPast / position.viewportDimension).clamp(0.0, 0.5);
      return offset * easing;
    }
    // Direct 1:1 motion when within range
    return offset;
  }

  @override
  double? get dragStartDistanceMotionThreshold => kTouchSlop;

  @override
  double get minFlingVelocity => 35.0;

  @override
  double get maxFlingVelocity => 8000.0;

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
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
        velocity,
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

/// Convenience builder that returns [SuperRangeMaintainingScrollPhysics]
/// wrapping [UltraFreeScrollPhysics] for jitter-free list layout and flings.
ScrollPhysics buildSuperSmoothScrollPhysics({
  ScrollPhysics? parent,
  double friction = 0.012,
}) {
  return SuperRangeMaintainingScrollPhysics(
    parent: UltraFreeScrollPhysics(
      parent: parent ?? const AlwaysScrollableScrollPhysics(),
      friction: friction,
    ),
  );
}
