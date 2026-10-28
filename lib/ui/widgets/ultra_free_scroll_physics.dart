import 'package:flutter/material.dart';

/// Native-grade 120Hz Android scroll physics optimized for Pixel LTPO displays.
///
/// Extends [ClampingScrollPhysics] so boundary conditions pair properly with
/// Android's [StretchingOverscrollIndicator] (preventing conflicting overscroll simulations),
/// and prevents duplicate chaining when applied at both [ScrollBehavior] and [ScrollView] levels.
class LenisScrollPhysics extends ClampingScrollPhysics {
  const LenisScrollPhysics({
    super.parent,
    this.damping = 1.0,
    this.mass = 0.5,
    this.stiffness = 100.0,
  });

  final double damping;
  final double mass;
  final double stiffness;

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
      velocity: velocity,
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
}) {
  return LenisScrollPhysics(
    parent: parent ?? const AlwaysScrollableScrollPhysics(),
    damping: damping,
  );
}
