import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'nav_pill.dart';

/// Shows the Material 3 Expressive Playback Speed & Pitch Shifter modal sheet.
Future<void> showPlaybackSpeedModal(BuildContext context) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const PlaybackSpeedModal(),
  );
}

/// M3 Expressive Speed (0.5x - 2.0x) and Pitch Shifter Modal.
class PlaybackSpeedModal extends ConsumerWidget {
  const PlaybackSpeedModal({super.key});

  static const List<double> _speedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    final currentSpeed = playback.playbackSpeed;
    final currentPitch = playback.pitch;

    // Calculate approximate semitones: 12 * log2(pitch)
    final semitones = (12 * (log(currentPitch) / ln2)).round();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title Header & Reset Button
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.speed_rounded,
                      size: 24,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Speed & Pitch',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Variable tempo and semitone pitch shifting',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      PixelHaptics.hifiConfirm();
                      notifier.setPlaybackSpeed(1.0);
                      notifier.setPitch(1.0);
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(
                      foregroundColor: cs.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ─────────────────────────────────────────────────────────────
              // 1. Playback Speed Section
              // ─────────────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PLAYBACK SPEED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '${currentSpeed.toStringAsFixed(2)}x',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Preset Speed Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: Row(
                  children: _speedPresets.map((speed) {
                    final isSelected = (currentSpeed - speed).abs() < 0.02;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}x',
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        selectedColor: cs.primaryContainer,
                        backgroundColor: cs.surfaceContainerHigh,
                        checkmarkColor: cs.onPrimaryContainer,
                        side: BorderSide(
                          color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        onSelected: (_) {
                          PixelHaptics.tick();
                          notifier.setPlaybackSpeed(speed);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 6),

              // Continuous Speed Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  activeTrackColor: cs.primary,
                  inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.3),
                  thumbColor: cs.primary,
                ),
                child: Slider(
                  value: currentSpeed.clamp(0.5, 2.0),
                  min: 0.5,
                  max: 2.0,
                  divisions: 30, // 0.05 increments
                  label: '${currentSpeed.toStringAsFixed(2)}x',
                  onChanged: (val) {
                    PixelHaptics.lowTick();
                    notifier.setPlaybackSpeed(val);
                  },
                ),
              ),

              const SizedBox(height: 14),

              // ─────────────────────────────────────────────────────────────
              // 2. Pitch Shifter Section
              // ─────────────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'PITCH SHIFT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      semitones == 0
                          ? 'Standard (±0 st)'
                          : '${semitones > 0 ? "+$semitones" : "$semitones"} semitones',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Style Presets (Nightcore, Slowed & Reverb, Standard)
              Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('Nightcore'),
                    backgroundColor: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    onPressed: () {
                      PixelHaptics.hifiConfirm();
                      // 1.25x speed, +2 semitones
                      notifier.setPlaybackSpeed(1.25);
                      notifier.setPitch(pow(2, 2 / 12).toDouble());
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.waves_rounded, size: 16),
                    label: const Text('Slowed'),
                    backgroundColor: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    onPressed: () {
                      PixelHaptics.hifiConfirm();
                      // 0.85x speed, -2 semitones
                      notifier.setPlaybackSpeed(0.85);
                      notifier.setPitch(pow(2, -2 / 12).toDouble());
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.music_note_rounded, size: 16),
                    label: const Text('Normal (1.0)'),
                    backgroundColor: cs.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    onPressed: () {
                      PixelHaptics.tick();
                      notifier.setPitch(1.0);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Pitch Slider (-6 to +6 semitones, mapped to ratio 2^(n/12))
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  activeTrackColor: cs.tertiary,
                  inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.3),
                  thumbColor: cs.tertiary,
                ),
                child: Slider(
                  value: semitones.toDouble().clamp(-6.0, 6.0),
                  min: -6.0,
                  max: 6.0,
                  divisions: 12, // 1 semitone steps
                  label: '${semitones > 0 ? "+$semitones" : "$semitones"} st',
                  onChanged: (val) {
                    PixelHaptics.lowTick();
                    final targetSemitone = val.round();
                    final ratio = pow(2, targetSemitone / 12).toDouble();
                    notifier.setPitch(ratio);
                  },
                ),
              ),

              const SizedBox(height: 12),
              const AndroidGestureHandle(margin: EdgeInsets.only(top: 4, bottom: 4)),
            ],
          ),
        ),
      ),
    );
  }
}
