import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/haptics/pixel_haptics.dart';
import '../../../state/app_providers.dart';
import 'about_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'audio_quality_settings_screen.dart';
import 'bluetooth_settings_screen.dart';
import 'cloud_sync_settings_screen.dart';
import 'playback_settings_screen.dart';

/// Master Settings Hub for FreeBeat (Styled after Google Pixel Settings).
/// Clean, categorized entry point where each configurable setting has its own dedicated screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final themeMode = ref.watch(themeModeProvider);
    final quality = ref.watch(audioQualityProvider);
    final route = ref.watch(audioRouteInfoProvider);
    final playback = ref.watch(playbackProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Category 1: Preferences (Appearance & Audio Quality)
          Card(
            child: Column(
              children: [
                _SettingsNavTile(
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: themeMode == ThemeMode.system
                      ? 'System Default • Material You'
                      : (themeMode == ThemeMode.dark ? 'Dark Theme' : 'Light Theme'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
                  ),
                ),
                const Divider(height: 1),
                _SettingsNavTile(
                  icon: Icons.high_quality_rounded,
                  title: 'Audio Quality',
                  subtitle: 'Wi-Fi: ${quality.wifiTier.label} • Cellular: ${quality.cellularTier.label}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AudioQualitySettingsScreen()),
                  ),
                ),
                const Divider(height: 1),
                _SettingsNavTile(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Playback & Transitions',
                  subtitle: playback.crossfadeSeconds == 0
                      ? 'Gapless • Autoplay ${playback.isAutoplay ? "On" : "Off"}'
                      : 'Crossfade ${playback.crossfadeSeconds}s • Autoplay ${playback.isAutoplay ? "On" : "Off"}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PlaybackSettingsScreen()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Category 2: Hardware & Connections
          Card(
            child: Column(
              children: [
                _SettingsNavTile(
                  icon: Icons.bluetooth_audio_rounded,
                  title: 'Bluetooth & Output',
                  subtitle: '${route.deviceName} (${route.bluetoothCodecName})',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BluetoothSettingsScreen()),
                  ),
                ),
                const Divider(height: 1),
                _SettingsNavTile(
                  icon: Icons.cloud_sync_outlined,
                  title: 'Storage & Sync',
                  subtitle: 'Offline downloads, storage breakdown, and cache limits',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CloudSyncSettingsScreen()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Category 3: System & Info
          Card(
            child: Column(
              children: [
                _SettingsNavTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About FreeBeat',
                  subtitle: 'Version 1.0.0 • 100% Serverless • Open Source',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutSettingsScreen()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: cs.primary, size: 22),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
    );
  }
}
