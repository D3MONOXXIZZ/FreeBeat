import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/haptics/pixel_haptics.dart';
import '../../../state/app_providers.dart';

/// Dedicated Bluetooth & Audio Output Settings Screen.
/// Clean, concise M3 Pixel layout for inspecting connected route and tuning audio output protections.
class BluetoothSettingsScreen extends ConsumerWidget {
  const BluetoothSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final route = ref.watch(audioRouteInfoProvider);
    final quality = ref.watch(audioQualityProvider);
    final qualityNotifier = ref.read(audioQualityProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Bluetooth & Output',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Current Output Device & Codec
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bluetooth_audio_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Current Output Device',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          route.deviceName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                route.bluetoothCodecName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              route.isBluetooth ? 'Wireless Audio' : 'Direct Audio',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Protections & Hardware DSP Limiter
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_rounded, color: cs.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Audio Output Protections',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Inter-Sample Peak Limiter (-0.5 dBFS)',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Prevents clipping and digital crackle during Bluetooth compression (LDAC, aptX, AAC, SBC).',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: quality.bluetoothIspProtection,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      qualityNotifier.toggleBluetoothIspProtection(val);
                    },
                  ),
                  const Divider(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Direct Volume Control (DVC)',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Applies 64-bit software gain scaling for wider dynamic range on supported headphones.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: quality.disableDvcOnBluetoothAbsoluteVolume,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      qualityNotifier.toggleDisableDvcOnBluetooth(val);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
