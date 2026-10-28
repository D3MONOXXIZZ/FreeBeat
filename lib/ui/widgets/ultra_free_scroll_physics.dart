import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ultra-smooth 120Hz scroll physics designed for high-refresh-rate Android displays.
///
/// Key fixes over previous implementation:
/// - Eliminates the double velocity damping penalty (previously `velocity * 0.82 * 0.91 = 0.746x`),
///   preserving 100% of finger release velocity on ballistic handoff so there is zero lurch when lifting your thumb.
/// - Uses [ClampingScrollSimulation] with a tuned low-friction spline (`friction: 0.0115`) for in-range
///   scrolling, matching native Android high-refresh-rate frame pacing.
/// - Replaces the 50.0 mass boundary spring (100x heavier than default) with a responsive,
///   critically damped spring (`mass: 0.8, stiffness: 180.0, ratio: 1.0`).
/// - Removes the redundant [SuperRangeMaintainingScrollPhysics] wrapper that conflicted with
///   [SliverFixedExtentList] during fast flings.
class LenisScrollPhysics extends ScrollPhysics {
  const LenisScrollPhysics({
    super.parent,
    this.damping = 1.0,
    this.mass = 0.8,
    this.stiffness = 180.0,
  });

  /// Velocity transfer multiplier. Default is 1.0 for 1:1 continuous velocity handoff on finger release.
  final double damping;

  /// Spring mass for boundary cushioning.
  final double mass;

  /// Spring stiffness for smooth boundary absorption.
  final double stiffness;

  @override
  LenisScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return LenisScrollPhysics(
      parent: buildParent(ancestor),
      damping: damping,
      mass: mass,
      stiffness: stiffness,
    );
  }

  @override
  double get minFlingVelocity => 50.0;

  @override
  double get maxFlingVelocity => 8000.0;

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: mass,
        stiffness: stiffness,
        ratio: 1.0,
      );

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
          1.0 - (overscrollPast / position.viewportDimension).clamp(0.0, 0.65);
      return offset * easing;
    }
    return offset;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      return BouncingScrollSimulation(
        spring: spring,
        position: position.pixels,
        velocity: velocity * damping,
        leadingExtent: position.minScrollExtent,
        trailingExtent: position.maxScrollExtent,
        tolerance: tolerance,
      );
    }
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    if ((velocity > 0.0 && position.pixels >= position.maxScrollExtent) ||
        (velocity < 0.0 && position.pixels <= position.minScrollExtent)) {
      return null;
    }
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity * damping,
      friction: 0.0115,
      tolerance: tolerance,
    );
  }
}

/// Backward compatibility alias for [LenisScrollPhysics].
typedef UltraFreeScrollPhysics = LenisScrollPhysics;

/// Convenience builder returning [LenisScrollPhysics] with 1:1 velocity handoff.
ScrollPhysics buildSuperSmoothScrollPhysics({
  ScrollPhysics? parent,
  double damping = 1.0,
}) {
  return LenisScrollPhysics(
    parent: parent ?? const AlwaysScrollableScrollPhysics(),
    damping: damping,
  );
}
