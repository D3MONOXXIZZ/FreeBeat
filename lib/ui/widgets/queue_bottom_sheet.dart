import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'expressive_shapes.dart';
import 'material_you_album_cover.dart';
import 'sleep_timer_modal.dart';
import 'swipe_to_queue_wrapper.dart';

/// Shows the Material 3 Expressive Up Next Queue bottom sheet.
Future<void> showQueueBottomSheet(BuildContext context) =>
    QueueBottomSheet.show(context);

/// Full Interactive Up Next Queue & Session History Bottom Sheet (Material 3 Expressive).
/// Features:
/// 1. Currently Playing Hero card with live equalizer waves and timing.
/// 2. Drag-and-drop Up Next reordering via ReorderableListView with haptic feedback.
/// 3. Swipe gestures: swipe to dismiss/remove from queue.
/// 4. Quick actions: Shuffle Remaining, Clear Up Next, Sleep Timer launcher.
/// 5. Smart Autoplay toggle card.
/// 6. Session History tab of previously played tracks.
class QueueBottomSheet extends ConsumerStatefulWidget {
  const QueueBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    PixelHaptics.sheetExpand();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const QueueBottomSheet(),
    );
  }

  @override
  ConsumerState<QueueBottomSheet> createState() => _QueueBottomSheetState();
}

class _QueueBottomSheetState extends ConsumerState<QueueBottomSheet> {
  int _activeTab = 0; // 0: Up Next, 1: History

  String _formatMs(int ms) {
    final totalSeconds = (ms / 1000).floor().clamp(0, 86400);
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final playback = ref.watch(playbackProvider);
    final playbackNotifier = ref.read(playbackProvider.notifier);
    final current = playback.currentTrack;
    final upNext = playback.upNextQueue;
    final history = playback.sessionHistory;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
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
        children: [
          // ─────────────────────────────────────────────────────────────────
          // 1. Drag Handle
          // ─────────────────────────────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4.5,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 2. Header Bar with Actions & Sleep Timer Pill
          // ─────────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
            child: Row(
              children: [
                Text(
                  'Up Next Queue',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${upNext.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const Spacer(),

                // Sleep Timer Quick Button
                SpringPressScale(
                  onTap: () => SleepTimerModal.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: playback.isSleepTimerActive
                          ? cs.primary
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bedtime_rounded,
                          size: 14,
                          color: playback.isSleepTimerActive
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
                        if (playback.isSleepTimerActive) ...[
                          const SizedBox(width: 5),
                          Text(
                            playback.formattedSleepTimerRemaining,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // 3-Dots Queue Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onSelected: (val) {
                    if (val == 'shuffle') {
                      playbackNotifier.shuffleRemaining();
                    } else if (val == 'clear') {
                      playbackNotifier.clearUpNext();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'shuffle',
                      enabled: upNext.isNotEmpty,
                      child: const Row(
                        children: [
                          Icon(Icons.shuffle_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Shuffle Remaining'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'clear',
                      enabled: upNext.isNotEmpty,
                      child: const Row(
                        children: [
                          Icon(Icons.clear_all_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Clear Up Next'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // 3. Tab Filter Chips (Up Next / History)
          // ─────────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                _QueueTabPill(
                  label: 'Up Next (${upNext.length})',
                  icon: Icons.queue_music_rounded,
                  isSelected: _activeTab == 0,
                  onTap: () => setState(() => _activeTab = 0),
                ),
                const SizedBox(width: 8),
                _QueueTabPill(
                  label: 'History (${history.length})',
                  icon: Icons.history_rounded,
                  isSelected: _activeTab == 1,
                  onTap: () => setState(() => _activeTab = 1),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─────────────────────────────────────────────────────────────────
          // 4. Currently Playing Card
          // ─────────────────────────────────────────────────────────────────
          if (current.id.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    MaterialYouAlbumCover(
                      track: current,
                      size: 48,
                      borderRadius: 14,
                      showQualityBadge: false,
                      showSourceBadge: false,
                      isPlaying: playback.isPlaying,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'NOW PLAYING',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: cs.onPrimary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${current.codec} • ${current.bitDepth}-BIT',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            current.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 24,
                      ),
                      onPressed: () => playbackNotifier.togglePlayPause(),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ─────────────────────────────────────────────────────────────────
          // 5. Main Content: Reorderable Up Next OR History List
          // ─────────────────────────────────────────────────────────────────
          Expanded(
            child: _activeTab == 0
                ? _buildUpNextView(
                    context,
                    cs,
                    textTheme,
                    upNext,
                    playback,
                    playbackNotifier,
                  )
                : _buildHistoryView(
                    context,
                    cs,
                    textTheme,
                    history,
                    playbackNotifier,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpNextView(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    List<Track> upNext,
    PlaybackViewState playback,
    PlaybackNotifier playbackNotifier,
  ) {
    if (upNext.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.playlist_play_rounded,
                  size: 28,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Up Next is Empty',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                playback.isAutoplay
                    ? 'Smart Autoplay is ON — FreeBeat will seamlessly continue with similar tracks.'
                    : 'Turn on Smart Autoplay below or add tracks to continue listening.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // Smart Autoplay Card
              _buildAutoplayCard(cs, playback, playbackNotifier),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Reorderable list
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemCount: upNext.length,
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) {
              playbackNotifier.reorderUpNext(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final track = upNext[index];
              return SwipeToQueueWrapper(
                key: ValueKey('queue_item_${track.id}_$index'),
                track: track,
                borderRadius: BorderRadius.circular(18),
                primaryActionTitle: 'Play Next',
                primaryActionIcon: Icons.playlist_play_rounded,
                dismissOnPrimaryAction: true,
                onPrimaryAction: () {
                  playbackNotifier.playNext(track);
                },
                enableSecondaryAction: true,
                secondaryActionTitle: 'Remove',
                secondaryActionIcon: Icons.delete_outline_rounded,
                dismissOnSecondaryAction: true,
                onSecondaryAction: () {
                  playbackNotifier.removeFromQueue(track.id);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Drag Handle
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      MaterialYouAlbumCover(
                        track: track,
                        size: 40,
                        borderRadius: 10,
                        showQualityBadge: false,
                        showSourceBadge: false,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            PixelHaptics.tick();
                            playbackNotifier.playTrack(track);
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${track.artist} • ${_formatMs(track.durationMs)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        tooltip: 'Remove from Queue',
                        color: cs.onSurfaceVariant,
                        onPressed: () =>
                            playbackNotifier.removeFromQueue(track.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Autoplay switch footer
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: _buildAutoplayCard(cs, playback, playbackNotifier),
        ),
      ],
    );
  }

  Widget _buildHistoryView(
    BuildContext context,
    ColorScheme cs,
    TextTheme textTheme,
    List<Track> history,
    PlaybackNotifier playbackNotifier,
  ) {
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 28,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No Session History',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tracks played during this listening session will appear here.',
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      physics: const ClampingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final track = history[index];
        return SwipeToQueueWrapper(
          track: track,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                MaterialYouAlbumCover(
                  track: track,
                  size: 40,
                  borderRadius: 10,
                  showQualityBadge: false,
                  showSourceBadge: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${track.artist} • ${_formatMs(track.durationMs)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    PixelHaptics.tick();
                    playbackNotifier.playTrack(track);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAutoplayCard(
    ColorScheme cs,
    PlaybackViewState playback,
    PlaybackNotifier playbackNotifier,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.autorenew_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Smart Autoplay',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Continuous music from library when queue ends',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: playback.isAutoplay,
            onChanged: (_) => playbackNotifier.toggleAutoplay(),
          ),
        ],
      ),
    );
  }
}

class _QueueTabPill extends StatelessWidget {
  const _QueueTabPill({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.4)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
