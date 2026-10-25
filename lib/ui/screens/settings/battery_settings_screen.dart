import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/haptics/pixel_haptics.dart';
import '../../../state/app_providers.dart';

/// Dedicated Material 3 Battery & Power Saver Settings Screen.
/// Styled after Google Pixel System Battery Settings.
class BatterySettingsScreen extends ConsumerWidget {
  const BatterySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final powerSaver = ref.watch(powerSaverProvider);
    final notifier = ref.read(powerSaverProvider.notifier);
    final battery = ref.watch(deviceBatteryStatusProvider);
    final isEffectiveActive = ref.watch(effectivePowerSaverActiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Battery & Power Saver',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Live Device Battery Status Hero Card
          Card(
            color: isEffectiveActive
                ? cs.primaryContainer.withValues(alpha: 0.7)
                : cs.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isEffectiveActive
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          battery.isCharging
                              ? Icons.battery_charging_full_rounded
                              : (isEffectiveActive
                                  ? Icons.battery_saver_rounded
                                  : Icons.battery_std_rounded),
                          color: isEffectiveActive ? cs.onPrimary : cs.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${battery.batteryLevel}%',
                                  style: textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: isEffectiveActive
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface,
                                  ),
                                ),
                                if (battery.isCharging) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.secondaryContainer,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      'CHARGING',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSecondaryContainer,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isEffectiveActive
                                  ? 'Power Saver is currently active'
                                  : 'Standard performance mode',
                              style: textTheme.bodySmall?.copyWith(
                                color: isEffectiveActive
                                    ? cs.onPrimaryContainer.withValues(alpha: 0.85)
                                    : cs.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  // Master Switch Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Use Power Saver',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              powerSaver.isEnabled
                                  ? 'Manually enabled'
                                  : (isEffectiveActive
                                      ? 'Active automatically via triggers'
                                      : 'Off • Tap to enable manually'),
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: powerSaver.isEnabled,
                        onChanged: (val) {
                          PixelHaptics.tick();
                          notifier.setEnabled(val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Auto-Activation Triggers Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_mode_rounded, color: cs.primary, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Automatic Triggers',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Follow Android Battery Saver',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      battery.isPowerSaveMode
                          ? 'Android Battery Saver is currently ON'
                          : 'Activates automatically when device Battery Saver turns on',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.autoOnSystemSaver,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setAutoOnSystemSaver(val);
                    },
                  ),
                  const Divider(height: 20),
                  Text(
                    'Turn on at low battery',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    powerSaver.autoBelowBatteryPercent > 0
                        ? 'Activates automatically when battery drops below ${powerSaver.autoBelowBatteryPercent}%'
                        : 'Never activate based on battery percentage alone',
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [0, 15, 20, 30].map((pct) {
                      final isSelected = powerSaver.autoBelowBatteryPercent == pct;
                      return ChoiceChip(
                        label: Text(pct == 0 ? 'Off' : '$pct%'),
                        selected: isSelected,
                        onSelected: (_) {
                          PixelHaptics.tick();
                          notifier.setAutoBelowBatteryPercent(pct);
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. Foreground & Display Optimizations Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.smartphone_rounded, color: cs.primary, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Display & Visual Optimizations',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'AMOLED Pitch Black (#000000)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Pure dark surfaces turn off OLED display pixels to save up to 40% screen power.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.amoledPitchBlack,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setAmoledPitchBlack(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Bypass 38-Sigma Blur & Aura',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Disables heavy Gaussian blur shaders and continuous animations on Now Playing screen.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.disableBlurAndAura,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setDisableBlurAndAura(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Pause Spectrum Visualizers',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Freezes 60/120fps wave animations in Smart EQ Studio while preserving the static EQ curve.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.pauseVisualizers,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setPauseVisualizers(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Cap Refresh Rate to 60Hz',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Prevents the display from drawing at 120Hz/90Hz, saving ~30% display power.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.capRefreshRate60Hz,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setCapRefreshRate60Hz(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Suppress Slider Micro-Haptics',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Mutes high-frequency vibration motor clicks on EQ sliders and seekbars to prevent current spikes.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.disableHaptics,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setDisableHaptics(val);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 4. Background & Audio Radio Optimizations Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi_tethering_off_rounded,
                          color: cs.primary, size: 22),
                      const SizedBox(width: 12),
                      Text(
                        'Audio & Background Radio Optimizations',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Smart Wi-Fi Radio Sleep',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Drops Wi-Fi wake lock completely when playing locally cached or offline tracks.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.smartWifiLock,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setSmartWifiLock(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Single-Track Preload Scaling',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Preloads 1 upcoming song instead of 5, slashing 80% of background network requests while retaining gapless playback.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.reducePreloadCount,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setReducePreloadCount(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Throttle Background State Updates',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Updates playback progress once per second instead of every 200ms when screen is off.',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                    ),
                    value: powerSaver.throttleBackgroundTicks,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      notifier.setThrottleBackgroundTicks(val);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
