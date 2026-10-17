import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'nav_pill.dart';

/// Shows the Material 3 Expressive A-B Loop Repeater modal sheet.
Future<void> showABLoopModal(BuildContext context) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const ABLoopModal(),
  );
}

/// M3 Expressive A-B Loop Repeater Modal.
class ABLoopModal extends ConsumerWidget {
  const ABLoopModal({super.key});

  String _formatMs(int ms) {
    if (ms < 0) ms = 0;
    final totalSeconds = ms ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    final millis = ((ms % 1000) ~/ 100).toString();
    return '$minutes:$seconds.$millis';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    final trackDuration = playback.currentTrack.durationMs > 0
        ? playback.currentTrack.durationMs
        : 1;
    final currentPos = playback.positionMs;
    final loopA = playback.loopPointA;
    final loopB = playback.loopPointB;
    final isLoopActive = playback.isLoopActive;

    final double normA = loopA != null ? (loopA / trackDuration).clamp(0.0, 1.0) : 0.0;
    final double normB = loopB != null ? (loopB / trackDuration).clamp(0.0, 1.0) : 1.0;
    final double normCurrent = (currentPos / trackDuration).clamp(0.0, 1.0);

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

              // Title Header & Clear Button
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isLoopActive ? cs.primaryContainer : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.repeat_on_rounded,
                      size: 24,
                      color: isLoopActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'A-B Loop Repeater',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isLoopActive
                              ? 'Repeating ${_formatMs(loopA!)} → ${_formatMs(loopB!)}'
                              : 'Set start (A) and end (B) points to loop',
                          style: TextStyle(
                            fontSize: 12,
                            color: isLoopActive ? cs.primary : cs.onSurfaceVariant,
                            fontWeight: isLoopActive ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (loopA != null || loopB != null)
                    TextButton.icon(
                      onPressed: () {
                        PixelHaptics.tick();
                        notifier.clearLoop();
                      },
                      icon: const Icon(Icons.clear_all_rounded, size: 16),
                      label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),

              // ─────────────────────────────────────────────────────────────
              // Timeline Visualizer
              // ─────────────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Now: ${_formatMs(currentPos)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Total: ${_formatMs(trackDuration)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final totalWidth = constraints.maxWidth;
                        final leftA = loopA != null ? normA * totalWidth : 0.0;
                        final rightB = loopB != null ? normB * totalWidth : totalWidth;
                        final activeWidth = (rightB - leftA).clamp(0.0, totalWidth);
                        final currentX = (normCurrent * totalWidth).clamp(0.0, totalWidth);

                        return SizedBox(
                          height: 28,
                          child: Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              // Background track
                              Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: cs.outlineVariant.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),

                              // Active Loop Range Highlight
                              if (loopA != null && loopB != null)
                                Positioned(
                                  left: leftA,
                                  width: activeWidth,
                                  child: Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),

                              // Point A Marker
                              if (loopA != null)
                                Positioned(
                                  left: (leftA - 10).clamp(0.0, totalWidth - 20),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cs.surface, width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'A',
                                        style: TextStyle(
                                          color: cs.onPrimary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Point B Marker
                              if (loopB != null)
                                Positioned(
                                  left: (rightB - 10).clamp(0.0, totalWidth - 20),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: cs.tertiary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cs.surface, width: 2),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'B',
                                        style: TextStyle(
                                          color: cs.onTertiary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // Current Position Thumb
                              Positioned(
                                left: (currentX - 4).clamp(0.0, totalWidth - 8),
                                child: Container(
                                  width: 8,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: cs.onSurface,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ─────────────────────────────────────────────────────────────
              // Point A Controls
              // ─────────────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: loopA != null
                        ? cs.primary.withValues(alpha: 0.5)
                        : cs.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Start Point [A]',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            loopA != null ? _formatMs(loopA) : 'Not Set',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: loopA != null ? cs.primary : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        PixelHaptics.hifiConfirm();
                        notifier.setLoopPointA(currentPos);
                      },
                      icon: const Icon(Icons.bookmark_add_rounded, size: 16),
                      label: const Text('Set at Current'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ─────────────────────────────────────────────────────────────
              // Point B Controls
              // ─────────────────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: loopB != null
                        ? cs.tertiary.withValues(alpha: 0.5)
                        : cs.outlineVariant.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          'B',
                          style: TextStyle(
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'End Point [B]',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            loopB != null ? _formatMs(loopB) : 'Not Set',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: loopB != null ? cs.tertiary : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        PixelHaptics.hifiConfirm();
                        notifier.setLoopPointB(currentPos);
                      },
                      icon: const Icon(Icons.bookmark_added_rounded, size: 16),
                      label: const Text('Set at Current'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Quick Actions: Jump to A
              if (loopA != null)
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      PixelHaptics.tick();
                      notifier.seekToMs(loopA);
                    },
                    icon: const Icon(Icons.replay_rounded, size: 16),
                    label: Text('Jump to Point A (${_formatMs(loopA)})'),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
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
