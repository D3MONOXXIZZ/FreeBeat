import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/haptics/pixel_haptics.dart';
import '../../../state/app_providers.dart';
import '../../widgets/playback_speed_modal.dart';
import '../../widgets/sleep_timer_modal.dart';

/// Dedicated Playback & Transitions Settings Screen (Material 3 Expressive).
/// Configures Crossfade, Gapless playback, Smart Autoplay, and Sleep Timer.
class PlaybackSettingsScreen extends ConsumerWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final playback = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Playback & Transitions',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Crossfade & Gapless Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.waves_rounded, color: cs.onPrimaryContainer, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Crossfade',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              playback.crossfadeSeconds == 0
                                  ? 'Off (True Gapless Playback)'
                                  : '${playback.crossfadeSeconds}s audio cross-overlap',
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          playback.crossfadeSeconds == 0
                              ? 'GAPLESS'
                              : '${playback.crossfadeSeconds}s',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 6,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.3),
                      thumbColor: cs.primary,
                    ),
                    child: Slider(
                      value: playback.crossfadeSeconds.toDouble(),
                      min: 0,
                      max: 12,
                      divisions: 12,
                      label: playback.crossfadeSeconds == 0
                          ? 'Gapless'
                          : '${playback.crossfadeSeconds}s',
                      onChanged: (val) {
                        PixelHaptics.lowTick();
                        notifier.setCrossfadeSeconds(val.round());
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0s (Gapless)',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      Text(
                        '12s (Max)',
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Smart Autoplay Card
          Card(
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.all_inclusive_rounded, color: cs.onSecondaryContainer, size: 20),
              ),
              title: Text(
                'Smart Autoplay',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                'Keep playing similar tracks from your library when your queue finishes.',
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              value: playback.isAutoplay,
              onChanged: (_) {
                notifier.toggleAutoplay();
              },
            ),
          ),

          const SizedBox(height: 16),

          // 3. Speed & Pitch Quick Launcher
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.speed_rounded, color: cs.onTertiaryContainer, size: 20),
              ),
              title: Text(
                'Speed & Pitch Shifter',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                'Current: ${playback.playbackSpeed.toStringAsFixed(2)}x tempo',
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                showPlaybackSpeedModal(context);
              },
            ),
          ),

          const SizedBox(height: 16),

          // 4. Sleep Timer Quick Launcher
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  playback.isSleepTimerActive
                      ? Icons.bedtime_rounded
                      : Icons.bedtime_outlined,
                  color: playback.isSleepTimerActive ? cs.primary : cs.onSurfaceVariant,
                  size: 20,
                ),
              ),
              title: Text(
                'Sleep Timer',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                playback.isSleepTimerActive
                    ? 'Active • ${playback.formattedSleepTimerRemaining} remaining'
                    : 'Turn off playback automatically with 30s gentle volume fade',
                style: textTheme.bodySmall?.copyWith(
                  color: playback.isSleepTimerActive ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                showSleepTimerModal(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}
