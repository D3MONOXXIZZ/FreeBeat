import 'package:flutter/material.dart';

/// Exact replication of the stock Google Pixel Settings app (`OverScroller.SplineOverScroller`)
/// 120Hz scroll physics.
///
/// Why `11.mp4` paused for 1-2 frames on finger lift whereas `000.mp4` (Pixel Settings) did not:
/// - In Flutter's `BallisticScrollActivity`, `AnimationController._startSimulation` calls `simulation.x(0.0)`
///   synchronously on `PointerUpEvent`, and then on the first VSYNC frame (`handleBeginFrame`),
///   `Ticker._tick` passes `elapsed = Duration.zero` (`0.0s`), calling `simulation.x(0.0)` a second time!
///   Because `ClampingScrollSimulation.x(0.0)` returns `position.pixels` (`0.0px` change), Flutter wastes
///   an entire 120Hz VSYNC frame at `dy = 0.00px` right when your thumb leaves the glass.
/// - [_PixelZeroLagClampingSimulation] detects the initial `_startSimulation` call vs the first VSYNC
///   `_tick(Duration.zero)` call and advances the simulation time by +1 VSYNC (`1 / 120s = 8.333ms`),
///   matching Android `OverScroller`'s `mStartTime = currentAnimationTimeMillis()` handoff with zero dead frames!
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
    return _PixelZeroLagClampingSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.015, // Exact AOSP ViewConfiguration.getScrollFriction() used by Pixel Settings
      tolerance: tolerance,
    );
  }
}

/// Wraps [ClampingScrollSimulation] to eliminate Flutter's 1-frame `Ticker` `Duration.zero` stall
/// when transitioning from finger drag (`DragScrollActivity`) to ballistic fling (`BallisticScrollActivity`).
class _PixelZeroLagClampingSimulation extends ClampingScrollSimulation {
  _PixelZeroLagClampingSimulation({
    required super.position,
    required super.velocity,
    super.friction = 0.015,
    super.tolerance,
  });

  int _zeroTimeCallCount = 0;

  // One 120Hz VSYNC interval (8.333ms) lead compensation after _startSimulation's initial x(0.0) read
  static const double _kVsyncLeadSeconds = 1.0 / 120.0;

  double _effectiveTime(double time) {
    if (time == 0.0) {
      _zeroTimeCallCount++;
      // Call #1 is inside AnimationController._startSimulation (before VSYNC 1).
      // Call #2 is inside AnimationController._tick(Duration.zero) on VSYNC 1.
      if (_zeroTimeCallCount == 1) {
        return 0.0;
      }
    }
    return time + _kVsyncLeadSeconds;
  }

  @override
  double x(double time) => super.x(_effectiveTime(time));

  @override
  double dx(double time) => super.dx(_effectiveTime(time));

  @override
  bool isDone(double time) => super.isDone(_effectiveTime(time));
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
