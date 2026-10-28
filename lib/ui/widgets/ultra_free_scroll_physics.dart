import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Native-grade 120Hz Android scroll physics optimized for Pixel LTPO displays.
///
/// Features:
/// - Extends [ClampingScrollPhysics] so boundary conditions pair properly with
///   Android's [StretchingOverscrollIndicator] (preventing conflicting overscroll simulations).
/// - Tuned low friction (0.0080) for silky, effortless Lenis-style momentum gliding.
/// - Critically damped spring boundary recovery (zeta = 1.0) for zero oscillation.
/// - Deduplication in [applyTo] to prevent double friction chaining.
class LenisScrollPhysics extends ClampingScrollPhysics {
  const LenisScrollPhysics({
    super.parent,
    this.damping = 1.0,
    this.mass = 0.5,
    this.stiffness = 100.0,
    this.friction = 0.0080,
  });

  final double damping;
  final double mass;
  final double stiffness;
  final double friction;

  @override
  SpringDescription get spring => SpringDescription(
        mass: mass,
        stiffness: stiffness,
        damping: 2.0 * math.sqrt(mass * stiffness),
      );

  @override
  LenisScrollPhysics applyTo(ScrollPhysics? ancestor) {
    // Avoid chaining duplicate LenisScrollPhysics instances if already present in ScrollBehavior
    ScrollPhysics? cleanAncestor = ancestor;
    if (cleanAncestor is LenisScrollPhysics) {
      cleanAncestor = cleanAncestor.parent;
    }
    return LenisScrollPhysics(
      parent: buildParent(cleanAncestor),
      damping: damping,
      mass: mass,
      stiffness: stiffness,
      friction: friction,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final Tolerance tolerance = toleranceFor(position);
    if (position.outOfRange) {
      if (position.pixels > position.maxScrollExtent) {
        return ScrollSpringSimulation(
          spring,
          position.pixels,
          position.maxScrollExtent,
          velocity,
          tolerance: tolerance,
        );
      }
      if (position.pixels < position.minScrollExtent) {
        return ScrollSpringSimulation(
          spring,
          position.pixels,
          position.minScrollExtent,
          velocity,
          tolerance: tolerance,
        );
      }
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
      velocity: velocity * damping,
      friction: friction,
      tolerance: tolerance,
    );
  }
}

/// Backward compatibility alias for [LenisScrollPhysics].
typedef UltraFreeScrollPhysics = LenisScrollPhysics;

/// Convenience builder returning [LenisScrollPhysics].
ScrollPhysics buildSuperSmoothScrollPhysics({
  ScrollPhysics? parent,
  double damping = 1.0,
  double friction = 0.0080,
}) {
  return LenisScrollPhysics(
    parent: parent ?? const AlwaysScrollableScrollPhysics(),
    damping: damping,
    friction: friction,
  );
}
