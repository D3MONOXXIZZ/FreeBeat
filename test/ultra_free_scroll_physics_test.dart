import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/main.dart';
import 'package:freebeat/ui/widgets/ultra_free_scroll_physics.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

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

      // Capped maximum velocity (7,000 px/s) guarantees locked 120Hz/60Hz frame budgets
      expect(physics.maxFlingVelocity, 7000.0);

      // Responsive min fling velocity allows gentle gestures to trigger fluid glide
      expect(physics.minFlingVelocity, 15.0);

      // Default smooth velocity damping factor
      expect(physics.damping, 0.82);
    });

    test('Creates BouncingScrollSimulation with critically damped spring and weighted velocity', () {
      const physics = LenisScrollPhysics();

      final position = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 50000,
        pixels: 1000,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Simulate a normal fling of 2000 px/s
      final sim = physics.createBallisticSimulation(position, 2000.0);

      expect(sim, isNotNull);
      expect(sim, isA<BouncingScrollSimulation>());

      final bouncingSim = sim as BouncingScrollSimulation;
      // Critically damped spring damping coefficient c = 2 * ratio * sqrt(mass * stiffness)
      expect(bouncingSim.spring.damping, closeTo(141.42, 0.1));
    });

    test('Progressive rubber-band easing when pulled past boundaries', () {
      const physics = LenisScrollPhysics();

      final atTopPosition = FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: 10000,
        pixels: -50,
        viewportDimension: 800,
        axisDirection: AxisDirection.down,
        devicePixelRatio: 1.0,
      );

      // Pulling past boundary dampens offset
      final easedOffset = physics.applyPhysicsToUserOffset(atTopPosition, -50.0);
      expect(easedOffset.abs(), lessThan(50.0));
    });
  });

  group('SmoothFreeScrollBehavior Integration Tests', () {
    testWidgets('SmoothFreeScrollBehavior provides SuperRangeMaintainingScrollPhysics wrapping LenisScrollPhysics', (tester) async {
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(),
      ));
      const behavior = SmoothFreeScrollBehavior();
      final element = tester.element(find.byType(SizedBox));

      final physics = behavior.getScrollPhysics(element);
      expect(physics, isA<SuperRangeMaintainingScrollPhysics>());
      final superPhysics = physics as SuperRangeMaintainingScrollPhysics;
      expect(superPhysics.parent, isA<LenisScrollPhysics>());
    });
  });
}
