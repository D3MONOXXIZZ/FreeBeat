import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';
import 'package:freebeat/ui/widgets/ultra_free_scroll_physics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LenisScrollPhysics Unit & Inertia Tests', () {
    test('Responsive null motion threshold and direct in-range 1:1 motion', () {
      const physics = LenisScrollPhysics();

      // Motion threshold is null for instantaneous Lenis-style subpixel touch response
      expect(physics.dragStartDistanceMotionThreshold, isNull);

      // User offset is returned 1:1 without dampening when within range
      final position = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10000,
        pixels: 500,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      expect(physics.applyPhysicsToUserOffset(position, 45.0), 45.0);
      expect(physics.applyPhysicsToUserOffset(position, -120.0), -120.0);
    });

    test('Balanced velocity cap and responsive min fling speed', () {
      const physics = LenisScrollPhysics();

      // Capped maximum velocity (8,000 px/s) guarantees locked 120Hz/60Hz frame budgets
      expect(physics.maxFlingVelocity, 8000.0);

      // Responsive min fling velocity
      expect(physics.minFlingVelocity, 50.0);

      // 1:1 continuous velocity handoff on finger release
      expect(physics.damping, 1.0);
    });

    test('Creates ClampingScrollSimulation in-range and ScrollSpringSimulation out-of-range', () {
      const physics = LenisScrollPhysics();

      final inRangePosition = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 50000,
        pixels: 1000,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Simulate an in-range fling of 2000 px/s -> ClampingScrollSimulation with tuned friction
      final inRangeSim = physics.createBallisticSimulation(inRangePosition, 2000.0);
      expect(inRangeSim, isNotNull);
      expect(inRangeSim, isA<ClampingScrollSimulation>());

      final outOfRangePosition = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 50000,
        pixels: -50,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Simulate an out-of-range boundary recovery -> ScrollSpringSimulation with spring
      final outOfRangeSim = physics.createBallisticSimulation(outOfRangePosition, -200.0);
      expect(outOfRangeSim, isNotNull);
      expect(outOfRangeSim, isA<ScrollSpringSimulation>());
    });

    test('Boundary motion pairs cleanly with Android StretchingOverscrollIndicator', () {
      const physics = LenisScrollPhysics();

      final atTopPosition = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10000,
        pixels: -50,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // In clamping physics, offset is passed cleanly to stretching indicator
      final offset = physics.applyPhysicsToUserOffset(atTopPosition, -50.0);
      expect(offset.abs(), 50.0);
    });
  });

  group('SmoothFreeScrollBehavior Integration Tests', () {
    testWidgets('SmoothFreeScrollBehavior provides UltraFreeScrollPhysics directly', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ));
      const behavior = SmoothFreeScrollBehavior();
      final element = tester.element(find.byType(SizedBox));

      final physics = behavior.getScrollPhysics(element);
      expect(physics, isA<UltraFreeScrollPhysics>());
      expect(physics.parent, isA<AlwaysScrollableScrollPhysics>());
    });
  });
}
