import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/power_saver_settings.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/settings/battery_settings_screen.dart';
import 'package:freebeat/ui/screens/settings/settings_screen.dart';
import 'package:freebeat/ui/theme/pixel_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getBatteryStatus') {
          return {
            'batteryLevel': 85,
            'isCharging': false,
            'isPowerSaveMode': false,
          };
        }
        return true;
      },
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PowerSaverSettings Model & Serialization Tests', () {
    test('Default values are correctly configured', () {
      const settings = PowerSaverSettings();
      expect(settings.isEnabled, isFalse);
      expect(settings.autoOnSystemSaver, isTrue);
      expect(settings.autoBelowBatteryPercent, equals(20));
      expect(settings.amoledPitchBlack, isTrue);
      expect(settings.disableBlurAndAura, isTrue);
      expect(settings.pauseVisualizers, isTrue);
      expect(settings.capRefreshRate60Hz, isTrue);
      expect(settings.smartWifiLock, isTrue);
      expect(settings.reducePreloadCount, isTrue);
      expect(settings.disableHaptics, isTrue);
      expect(settings.throttleBackgroundTicks, isTrue);
    });

    test('copyWith updates fields cleanly', () {
      const original = PowerSaverSettings();
      final updated = original.copyWith(
        isEnabled: true,
        autoBelowBatteryPercent: 15,
        amoledPitchBlack: false,
      );
      expect(updated.isEnabled, isTrue);
      expect(updated.autoBelowBatteryPercent, equals(15));
      expect(updated.amoledPitchBlack, isFalse);
      expect(updated.autoOnSystemSaver, isTrue); // Unchanged
    });

    test('Serialization to/from Map and JSON round-trips losslessly', () {
      const settings = PowerSaverSettings(
        isEnabled: true,
        autoOnSystemSaver: false,
        autoBelowBatteryPercent: 30,
        amoledPitchBlack: true,
        disableBlurAndAura: false,
        pauseVisualizers: true,
        capRefreshRate60Hz: false,
        smartWifiLock: true,
        reducePreloadCount: false,
        disableHaptics: true,
        throttleBackgroundTicks: false,
      );

      final jsonStr = settings.toJson();
      final restored = PowerSaverSettings.fromJson(jsonStr);

      expect(restored, equals(settings));
      expect(restored.autoBelowBatteryPercent, equals(30));
      expect(restored.isEnabled, isTrue);
      expect(restored.autoOnSystemSaver, isFalse);
    });
  });

  group('effectivePowerSaverActiveProvider Logic Tests', () {
    test('Returns true when isEnabled is manually toggled on', () {
      final container = ProviderContainer(
        overrides: [
          powerSaverProvider.overrideWith(
            (ref) => PowerSaverNotifier()
              ..setEnabled(true),
          ),
          deviceBatteryStatusProvider.overrideWith(
            (ref) => DeviceBatteryStatusNotifier()
              ..updateMockState(const DeviceBatteryStatus(
                batteryLevel: 95,
                isCharging: true,
                isPowerSaveMode: false,
              )),
          ),
        ],
      );
      addTearDown(container.dispose);

      final isActive = container.read(effectivePowerSaverActiveProvider);
      expect(isActive, isTrue);
    });

    test('Returns true when Android system battery saver is on', () {
      final container = ProviderContainer(
        overrides: [
          powerSaverProvider.overrideWith(
            (ref) => PowerSaverNotifier()
              ..setEnabled(false)
              ..setAutoOnSystemSaver(true),
          ),
          deviceBatteryStatusProvider.overrideWith(
            (ref) => DeviceBatteryStatusNotifier()
              ..updateMockState(const DeviceBatteryStatus(
                batteryLevel: 70,
                isCharging: false,
                isPowerSaveMode: true,
              )),
          ),
        ],
      );
      addTearDown(container.dispose);

      final isActive = container.read(effectivePowerSaverActiveProvider);
      expect(isActive, isTrue);
    });

    test('Returns true when battery drops below threshold and not charging', () {
      final container = ProviderContainer(
        overrides: [
          powerSaverProvider.overrideWith(
            (ref) => PowerSaverNotifier()
              ..setEnabled(false)
              ..setAutoOnSystemSaver(false)
              ..setAutoBelowBatteryPercent(20),
          ),
          deviceBatteryStatusProvider.overrideWith(
            (ref) => DeviceBatteryStatusNotifier()
              ..updateMockState(const DeviceBatteryStatus(
                batteryLevel: 18,
                isCharging: false,
                isPowerSaveMode: false,
              )),
          ),
        ],
      );
      addTearDown(container.dispose);

      final isActive = container.read(effectivePowerSaverActiveProvider);
      expect(isActive, isTrue);
    });

    test('Returns false when battery is below threshold but device is charging', () {
      final container = ProviderContainer(
        overrides: [
          powerSaverProvider.overrideWith(
            (ref) => PowerSaverNotifier()
              ..setEnabled(false)
              ..setAutoOnSystemSaver(false)
              ..setAutoBelowBatteryPercent(20),
          ),
          deviceBatteryStatusProvider.overrideWith(
            (ref) => DeviceBatteryStatusNotifier()
              ..updateMockState(const DeviceBatteryStatus(
                batteryLevel: 15,
                isCharging: true,
                isPowerSaveMode: false,
              )),
          ),
        ],
      );
      addTearDown(container.dispose);

      final isActive = container.read(effectivePowerSaverActiveProvider);
      expect(isActive, isFalse);
    });
  });

  group('AMOLED Pitch Black Theme & UI Tests', () {
    test('PixelTheme generates true #000000 surface in amoledPitchBlack mode', () {
      final normalDark = PixelTheme.buildDarkColorScheme(amoledPitchBlack: false);
      final amoledDark = PixelTheme.buildDarkColorScheme(amoledPitchBlack: true);

      expect(normalDark.surface, isNot(equals(Colors.black)));
      expect(amoledDark.surface, equals(Colors.black));
      expect(amoledDark.surfaceContainerLowest, equals(Colors.black));
    });

    testWidgets('BatterySettingsScreen renders live battery status and switches', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: BatterySettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Battery & Power Saver'), findsOneWidget);
      expect(find.text('Use Power Saver'), findsOneWidget);
      expect(find.text('Automatic Triggers'), findsOneWidget);
      expect(find.text('Follow Android Battery Saver'), findsOneWidget);
      expect(find.text('AMOLED Pitch Black (#000000)'), findsOneWidget);
      expect(find.text('Bypass 38-Sigma Blur & Aura'), findsOneWidget);
      expect(find.text('Pause Spectrum Visualizers'), findsOneWidget);
      expect(find.text('Cap Refresh Rate to 60Hz'), findsOneWidget);
      expect(find.text('Smart Wi-Fi Radio Sleep'), findsOneWidget);
      expect(find.text('Single-Track Preload Scaling'), findsOneWidget);
    });

    testWidgets('SettingsScreen navigates to BatterySettingsScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Battery & Power Saver'), findsOneWidget);
      await tester.tap(find.text('Battery & Power Saver'));
      await tester.pumpAndSettle();

      expect(find.byType(BatterySettingsScreen), findsOneWidget);
    });
  });
}
