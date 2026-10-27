import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';
import 'package:freebeat/ui/widgets/ultra_free_scroll_physics.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UltraFreeScrollPhysics Unit & Deceleration Tests', () {
    test('Standard touch slop motion threshold and direct in-range 1:1 motion', () {
      const physics = UltraFreeScrollPhysics();

      // Motion threshold delegates to standard kTouchSlop to prevent micro-jitters
      expect(physics.dragStartDistanceMotionThreshold, kTouchSlop);

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
      const physics = UltraFreeScrollPhysics();

      // Capped maximum velocity (8,000 px/s) guarantees locked 120Hz/60Hz frame budgets
      expect(physics.maxFlingVelocity, 8000.0);

      // Responsive min fling velocity allows gentle gestures to trigger fluid glide
      expect(physics.minFlingVelocity, 35.0);

      // Default smooth fluid friction constant (0.012 vs standard Android 0.015)
      expect(physics.friction, 0.012);
    });

    test('Fluid friction of 0.012 glides further than stock Android without runaway speeds', () {
      const ultraPhysics = UltraFreeScrollPhysics();
      const standardPhysics = ClampingScrollPhysics();

      final position = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 50000,
        pixels: 1000,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Simulate a normal fling of 2000 px/s
      final ultraSim = ultraPhysics.createBallisticSimulation(position, 2000.0);
      final standardSim = standardPhysics.createBallisticSimulation(position, 2000.0);

      expect(ultraSim, isNotNull);
      expect(standardSim, isNotNull);

      final standardClamping = standardSim as ClampingScrollSimulation;
      final ultraClamping = ultraSim as ClampingScrollSimulation;

      expect(ultraClamping.friction, 0.012);
      expect(standardClamping.friction, 0.015);

      // Sample position at t = 1.0 second: 0.012 glides slightly further and smoother
      final ultraPosAt1s = ultraClamping.x(1.0);
      final standardPosAt1s = standardClamping.x(1.0);

      expect(ultraPosAt1s - 1000, greaterThan(standardPosAt1s - 1000));
    });

    test('Clamps cleanly at edges without spring bouncing when in bounds', () {
      const physics = UltraFreeScrollPhysics();

      final atTopPosition = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10000,
        pixels: 0,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Scrolling up past minScrollExtent clamps
      final boundaryTop = physics.applyBoundaryConditions(atTopPosition, -50.0);
      expect(boundaryTop, -50.0);

      // Moving inward is allowed (returns 0.0)
      final inwardMove = physics.applyBoundaryConditions(atTopPosition, 50.0);
      expect(inwardMove, 0.0);

      // Negative velocity when already at min extent creates no simulation
      final noSim = physics.createBallisticSimulation(atTopPosition, -500.0);
      expect(noSim, isNull);
    });
  });

  group('SmoothFreeScrollBehavior Integration Tests', () {
    testWidgets('SmoothFreeScrollBehavior provides SuperRangeMaintainingScrollPhysics wrapping UltraFreeScrollPhysics', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ));
      const behavior = SmoothFreeScrollBehavior();
      final element = tester.element(find.byType(SizedBox));

      final physics = behavior.getScrollPhysics(element);
      expect(physics, isA<SuperRangeMaintainingScrollPhysics>());
      final superPhysics = physics as SuperRangeMaintainingScrollPhysics;
      expect(superPhysics.parent, isA<UltraFreeScrollPhysics>());
    });
  });
}
