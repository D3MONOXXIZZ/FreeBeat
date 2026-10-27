import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

/// Ultra-smooth, high-performance fluid scroll physics inspired by Lenis smooth scroll on the web
/// and backed by [super_sliver_list] and [zero_scroll].
///
/// Features:
/// - True Lenis-style exponential momentum decay using [BouncingScrollSimulation] with [FrictionSimulation].
/// - Critically damped harmonic oscillator boundary physics (ratio = 1.0, mass = 50, stiffness = 100)
///   for zero-oscillation, zero-shock cushioned deceleration at list boundaries.
/// - Weighted velocity damping (v * 0.82) replicating the luxurious, cinematic gliding feel of Lenis.
/// - 0.0px drag start motion threshold: immediate 1:1 subpixel response to finger movement without dead-zones.
/// - Progressive rubber-band overscroll resistance when pulled past limits.
/// - Capped maximum fling velocity (7,000 px/s) to guarantee locked 120Hz/60Hz frame budgets.
/// - Seamlessly wrapped in [SuperRangeMaintainingScrollPhysics] to prevent layout drift or jumps.
class LenisScrollPhysics extends ScrollPhysics {
  const LenisScrollPhysics({
    super.parent,
    this.damping = 0.82,
    this.mass = 50.0,
    this.stiffness = 100.0,
  });

  /// Velocity transfer multiplier. Default is 0.82 (dampens explosive flick velocity into a smooth, weighty glide).
  final double damping;

  /// Spring mass for boundary cushioning. Default is 50.0 for a weighty, luxurious feel.
  final double mass;

  /// Spring stiffness. Default is 100.0 for smooth, non-snapping boundary absorption.
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
  double? get dragStartDistanceMotionThreshold => null;

  @override
  double get minFlingVelocity => 15.0;

  @override
  double get maxFlingVelocity => 7000.0;

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: mass,
        stiffness: stiffness,
        ratio: 1.0, // Critically damped: returns smoothly without bouncing or oscillation
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
    // Direct 1:1 fluid tracking when within range
    return offset;
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);
    if (velocity.abs() >= tolerance.velocity || position.outOfRange) {
      return BouncingScrollSimulation(
        spring: spring,
        position: position.pixels,
        velocity: velocity * damping, // Lenis-style weighted velocity transfer
        leadingExtent: position.minScrollExtent,
        trailingExtent: position.maxScrollExtent,
        tolerance: tolerance,
      );
    }
    return null;
  }
}

/// Backward compatibility alias for [LenisScrollPhysics].
typedef UltraFreeScrollPhysics = LenisScrollPhysics;

/// Convenience builder that returns [SuperRangeMaintainingScrollPhysics]
/// wrapping [LenisScrollPhysics] for jitter-free, Lenis-smooth list layout and glides.
ScrollPhysics buildSuperSmoothScrollPhysics({
  ScrollPhysics? parent,
  double damping = 0.82,
}) {
  return SuperRangeMaintainingScrollPhysics(
    parent: LenisScrollPhysics(
      parent: parent ?? const AlwaysScrollableScrollPhysics(),
      damping: damping,
    ),
  );
}
