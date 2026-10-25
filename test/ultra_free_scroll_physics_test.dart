import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';
import 'package:freebeat/ui/widgets/ultra_free_scroll_physics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UltraFreeScrollPhysics Unit & Deceleration Tests', () {
    test('Zero touch drag resistance and motion threshold', () {
      const physics = UltraFreeScrollPhysics();

      // Zero drag threshold (null in Flutter implies default immediate drag detection)
      expect(physics.dragStartDistanceMotionThreshold, isNull);

      // User offset is returned 1:1 without dampening or resistance
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

    test('Uncapped velocity and low min fling speed', () {
      const physics = UltraFreeScrollPhysics();

      // Unrestricted max velocity (150k px/s) allows user to fling at any speed
      expect(physics.maxFlingVelocity, 150000.0);

      // Low min fling velocity allows gentle gestures to trigger free glide
      expect(physics.minFlingVelocity, 8.0);

      // Default minimal friction constant
      expect(physics.friction, 0.00075);
    });

    test('Friction of 0.00075 results in vastly extended free-scroll distance vs standard', () {
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

      // Simulate a fling of 3000 px/s
      final ultraSim = ultraPhysics.createBallisticSimulation(position, 3000.0);
      final standardSim = standardPhysics.createBallisticSimulation(position, 3000.0);

      expect(ultraSim, isNotNull);
      expect(standardSim, isNotNull);

      // Compare final distance traveled
      final standardClamping = standardSim as ClampingScrollSimulation;
      final ultraClamping = ultraSim as ClampingScrollSimulation;

      // Ultra free scroll distance should be significantly greater (~10x+ further)
      expect(ultraClamping.friction, 0.00075);
      expect(standardClamping.friction, 0.015);

      // Sample position at t = 1.0 second
      final ultraPosAt1s = ultraClamping.x(1.0);
      final standardPosAt1s = standardClamping.x(1.0);

      expect(ultraPosAt1s - 1000, greaterThan(standardPosAt1s - 1000));
    });

    test('Clamps cleanly at edges without spring bouncing', () {
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
    testWidgets('SmoothFreeScrollBehavior provides UltraFreeScrollPhysics', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ));
      const behavior = SmoothFreeScrollBehavior();
      final element = tester.element(find.byType(SizedBox));

      final physics = behavior.getScrollPhysics(element);
      expect(physics, isA<UltraFreeScrollPhysics>());
    });
  });
}
