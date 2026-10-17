import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'expressive_shapes.dart';

/// Shows the Material 3 Expressive Sleep Timer modal sheet.
Future<void> showSleepTimerModal(BuildContext context) =>
    SleepTimerModal.show(context);

/// Google Pixel Material 3 Expressive Sleep Timer Modal Sheet.
/// Features:
/// - Quick preset chips (15m, 30m, 45m, 1h, 2h, End of Current Track).
/// - Custom duration slider (1 to 120 minutes).
/// - Live countdown with 1-tap cancellation.
/// - Gentle 30-second volume fade-out explanation badge.
class SleepTimerModal extends ConsumerStatefulWidget {
  const SleepTimerModal({super.key});

  static Future<void> show(BuildContext context) {
    PixelHaptics.sheetExpand();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SleepTimerModal(),
    );
  }

  @override
  ConsumerState<SleepTimerModal> createState() => _SleepTimerModalState();
}

class _SleepTimerModalState extends ConsumerState<SleepTimerModal> {
  double _customMinutes = 30;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final playback = ref.watch(playbackProvider);
    final playbackNotifier = ref.read(playbackProvider.notifier);
    final isActive = playback.isSleepTimerActive;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Grab Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 36,
              height: 4.5,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),

          // Title & Active Badge
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive ? cs.primary : cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bedtime_rounded,
                  size: 22,
                  color: isActive ? cs.onPrimary : cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sleep Timer',
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      isActive
                          ? 'Stopping in ${playback.formattedSleepTimerRemaining}'
                          : 'Music will stop automatically',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                FilledButton.tonal(
                  onPressed: () {
                    playbackNotifier.setSleepTimer(null);
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('Cancel'),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Gentle Fade-out Note Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.volume_down_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Music will smoothly fade out over the final 30 seconds so you aren’t startled awake.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Presets Grid
          Text(
            'Quick Presets',
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TimerPresetChip(
                label: '15 Minutes',
                duration: const Duration(minutes: 15),
                onTap: (d) {
                  playbackNotifier.setSleepTimer(d);
                  Navigator.of(context).pop();
                },
              ),
              _TimerPresetChip(
                label: '30 Minutes',
                duration: const Duration(minutes: 30),
                onTap: (d) {
                  playbackNotifier.setSleepTimer(d);
                  Navigator.of(context).pop();
                },
              ),
              _TimerPresetChip(
                label: '45 Minutes',
                duration: const Duration(minutes: 45),
                onTap: (d) {
                  playbackNotifier.setSleepTimer(d);
                  Navigator.of(context).pop();
                },
              ),
              _TimerPresetChip(
                label: '1 Hour',
                duration: const Duration(hours: 1),
                onTap: (d) {
                  playbackNotifier.setSleepTimer(d);
                  Navigator.of(context).pop();
                },
              ),
              _TimerPresetChip(
                label: '2 Hours',
                duration: const Duration(hours: 2),
                onTap: (d) {
                  playbackNotifier.setSleepTimer(d);
                  Navigator.of(context).pop();
                },
              ),
              SpringPressScale(
                onTap: () {
                  playbackNotifier.setSleepTimerAfterCurrentTrack();
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: cs.secondary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.skip_next_rounded,
                          size: 16, color: cs.onSecondaryContainer),
                      const SizedBox(width: 6),
                      Text(
                        'End of Current Track',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Custom Duration Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Custom Duration',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                '${_customMinutes.toInt()} minutes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: _customMinutes,
            min: 5,
            max: 120,
            divisions: 23,
            label: '${_customMinutes.toInt()}m',
            onChanged: (val) {
              PixelHaptics.lowTick();
              setState(() => _customMinutes = val);
            },
          ),
          const SizedBox(height: 8),

          // Set Custom Timer Button
          FilledButton.icon(
            onPressed: () {
              playbackNotifier.setSleepTimer(
                Duration(minutes: _customMinutes.toInt()),
              );
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.timer_rounded, size: 20),
            label: Text('Set Timer for ${_customMinutes.toInt()} Minutes'),
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerPresetChip extends StatelessWidget {
  const _TimerPresetChip({
    required this.label,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final Duration duration;
  final ValueChanged<Duration> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SpringPressScale(
      onTap: () {
        PixelHaptics.tick();
        onTap(duration);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
    );
  }
}
