import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// A Material You wrapper that allows swiping right on any track list item
/// to append the track to the playback queue with tactile haptics and a confirmation toast.
///
/// Automatically snaps back into position so the track remains in the list view.
class SwipeToQueueWrapper extends ConsumerWidget {
  const SwipeToQueueWrapper({
    super.key,
    required this.track,
    required this.child,
    this.borderRadius,
    this.onQueued,
  });

  final Track track;
  final Widget child;
  final BorderRadius? borderRadius;
  final VoidCallback? onQueued;

  /// Shows a unified Material You floating confirmation SnackBar when a track is queued.
  static void showQueuedSnackBar(BuildContext context, String trackTitle) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.onPrimaryContainer.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.queue_music_rounded,
                color: cs.onPrimaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Added "$trackTitle" to queue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cs.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey('swipe_queue_${track.id}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.28,
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          ref.read(playbackProvider.notifier).addToQueue(track);
          await PixelHaptics.hifiConfirm();
          if (context.mounted) {
            showQueuedSnackBar(context, track.title);
          }
          onQueued?.call();
        }
        // Always return false to snap back into place
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: borderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.onPrimaryContainer.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.queue_music_rounded,
                color: cs.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Add to Queue',
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      child: child,
    );
  }
}
