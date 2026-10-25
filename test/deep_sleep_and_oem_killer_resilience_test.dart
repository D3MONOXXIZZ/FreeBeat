import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/power_saver_settings.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/settings/battery_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Deep Sleep & Battery Optimization Models & Notifier Tests', () {
    test('DeviceBatteryStatus supports isIgnoringBatteryOptimizations', () {
      const status = DeviceBatteryStatus(
        batteryLevel: 85,
        isCharging: false,
        isPowerSaveMode: false,
        isIgnoringBatteryOptimizations: false,
      );

      expect(status.batteryLevel, 85);
      expect(status.isIgnoringBatteryOptimizations, isFalse);

      final updated = status.copyWith(isIgnoringBatteryOptimizations: true);
      expect(updated.isIgnoringBatteryOptimizations, isTrue);
      expect(updated.batteryLevel, 85);
    });

    test('DeviceBatteryStatusNotifier invokes platform channel and updates state', () async {
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.freebeat.app/dsp'), (call) async {
        log.add(call);
        if (call.method == 'getBatteryStatus') {
          return {
            'batteryLevel': 78,
            'isCharging': true,
            'isPowerSaveMode': false,
          };
        }
        if (call.method == 'isIgnoringBatteryOptimizations') {
          return true;
        }
        if (call.method == 'requestIgnoreBatteryOptimizations') {
          return true;
        }
        return null;
      });

      final notifier = DeviceBatteryStatusNotifier();
      // Allow async platform calls
      await Future.delayed(const Duration(milliseconds: 30));

      expect(notifier.state.batteryLevel, 78);
      expect(notifier.state.isCharging, isTrue);
      expect(notifier.state.isIgnoringBatteryOptimizations, isTrue);

      final requested = await notifier.requestIgnoreBatteryOptimizations();
      expect(requested, isTrue);
      expect(notifier.state.isIgnoringBatteryOptimizations, isTrue);

      expect(log.any((c) => c.method == 'getBatteryStatus'), isTrue);
      expect(log.any((c) => c.method == 'isIgnoringBatteryOptimizations'), isTrue);
      expect(log.any((c) => c.method == 'requestIgnoreBatteryOptimizations'), isTrue);
    });
  });

  group('BatterySettingsScreen UI Widget Tests', () {
    testWidgets('Renders Deep Sleep Playback Protection Card with Unrestricted Status',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.freebeat.app/dsp'), (call) async {
        if (call.method == 'getBatteryStatus') {
          return {
            'batteryLevel': 90,
            'isCharging': false,
            'isPowerSaveMode': false,
          };
        }
        if (call.method == 'isIgnoringBatteryOptimizations') {
          return true;
        }
        return null;
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: BatterySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deep Sleep Protection Card Title
      expect(find.text('Deep Sleep Playback Protection'), findsOneWidget);
      expect(find.text('Unrestricted Background Playback'), findsOneWidget);
      expect(find.text('Protected from OEM deep sleep termination.'), findsOneWidget);
    });

    testWidgets('Renders Warning & Allow Button when Battery Optimizations are Active',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.freebeat.app/dsp'), (call) async {
        if (call.method == 'getBatteryStatus') {
          return {
            'batteryLevel': 50,
            'isCharging': false,
            'isPowerSaveMode': false,
          };
        }
        if (call.method == 'isIgnoringBatteryOptimizations') {
          return false;
        }
        if (call.method == 'requestIgnoreBatteryOptimizations') {
          return true;
        }
        return null;
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: BatterySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show warning state and Allow action button
      expect(find.text('Battery Optimizations Active'), findsOneWidget);
      expect(find.text('Tap to exempt FreeBeat from background sleep restrictions.'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);

      // Tap Allow button
      await tester.tap(find.text('Allow'));
      await tester.pump();
    });
  });
}
