import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/audio_quality_settings.dart';
import '../../../services/haptics/pixel_haptics.dart';
import '../../../state/app_providers.dart';

/// Dedicated Audio Quality & Streaming Bitrate Settings Screen.
/// Clean, concise M3 Pixel layout for configuring Wi-Fi, Cellular, and Download tiers.
class AudioQualitySettingsScreen extends ConsumerWidget {
  const AudioQualitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final quality = ref.watch(audioQualityProvider);
    final qualityNotifier = ref.read(audioQualityProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Audio Quality',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Wi-Fi Streaming Tier
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Wi-Fi Streaming',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _QualitySelectorTile(
                    title: 'Streaming Resolution',
                    subtitle: quality.wifiTier.subtitle,
                    currentTier: quality.wifiTier,
                    onChanged: (tier) {
                      if (tier != null) qualityNotifier.setWifiTier(tier);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Mobile Cellular Data Streaming Tier
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.signal_cellular_alt_rounded, color: cs.secondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Mobile Data Streaming',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _QualitySelectorTile(
                    title: 'Cellular Resolution',
                    subtitle: quality.cellularTier.subtitle,
                    currentTier: quality.cellularTier,
                    onChanged: (tier) {
                      if (tier != null) qualityNotifier.setCellularTier(tier);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. Offline Downloads Tier
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.download_done_rounded, color: cs.tertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Offline Downloads',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _QualitySelectorTile(
                    title: 'Cached Track Resolution',
                    subtitle: quality.offlineDownloadTier.subtitle,
                    currentTier: quality.offlineDownloadTier,
                    onChanged: (tier) {
                      if (tier != null) qualityNotifier.setOfflineDownloadTier(tier);
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

class _QualitySelectorTile extends StatelessWidget {
  const _QualitySelectorTile({
    required this.title,
    required this.subtitle,
    required this.currentTier,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final AudioQualityTier currentTier;
  final ValueChanged<AudioQualityTier?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<AudioQualityTier>(
          initialValue: currentTier,
          decoration: InputDecoration(
            labelText: title,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHigh,
          ),
          items: AudioQualityTier.values.map((tier) {
            return DropdownMenuItem(
              value: tier,
              child: Text(
                tier.label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            );
          }).toList(),
          onChanged: (tier) {
            PixelHaptics.tick();
            onChanged(tier);
          },
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
