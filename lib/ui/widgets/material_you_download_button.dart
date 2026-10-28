import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/audio/cloud_audio_cache_service.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// Material You Expressive Download Action Button.
/// Optimized for 120Hz scrolling:
/// - Skips watching download progress/queue providers when a track is already pinned offline.
/// - Removes per-row [Tooltip] long-press gesture detector overhead inside dense track lists.
class MaterialYouDownloadButton extends ConsumerWidget {
  const MaterialYouDownloadButton({
    super.key,
    required this.track,
    this.size = 22,
    this.color,
    this.showBackground = false,
  });

  final Track track;
  final double size;
  final Color? color;
  final bool showBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isPinned = track.isPinnedOffline;

    // Only subscribe to active download progress/queue providers if the track is not already offline
    bool isDownloading = false;
    if (!isPinned) {
      final progress = ref.watch(cloudAudioCacheServiceProvider.select(
        (svc) => svc.getProgress(track.id),
      ));
      final inQueue = ref.watch(downloadQueueManagerProvider.select(
        (mgr) => mgr.isTrackInQueue(track.id),
      ));
      isDownloading = progress.state == CacheState.caching || inQueue;
    }

    final isDownloadedOffline = isPinned;

    Widget iconWidget;
    Color buttonColor = color ?? cs.onSurfaceVariant;

    if (isDownloading) {
      final progress = ref.watch(cloudAudioCacheServiceProvider.select(
        (svc) => svc.getProgress(track.id),
      ));
      iconWidget = SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress.progress > 0.05 ? progress.progress : null,
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              backgroundColor: cs.primary.withValues(alpha: 0.2),
            ),
            Icon(
              Icons.arrow_downward_rounded,
              size: size * 0.55,
              color: cs.primary,
            ),
          ],
        ),
      );
    } else if (isDownloadedOffline) {
      iconWidget = Icon(
        Icons.download_done_rounded,
        size: size,
        color: cs.primary,
      );
      buttonColor = cs.primary;
    } else {
      iconWidget = Icon(
        Icons.arrow_circle_down_rounded,
        size: size,
        color: buttonColor,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        PixelHaptics.tick();
        if (track.id.isEmpty) return;

        final willPin = !isDownloadedOffline;
        await ref
            .read(tracksCatalogProvider.notifier)
            .togglePinOffline(track.id);

        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    willPin
                        ? Icons.downloading_rounded
                        : Icons.delete_outline_rounded,
                    color: cs.onInverseSurface,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      willPin
                          ? 'Downloading "${track.title}" locally...'
                          : 'Removed "${track.title}" from offline cache',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          );
        }
      },
      child: showBackground
          ? Container(
              width: size + 16,
              height: size + 16,
              decoration: BoxDecoration(
                color: isDownloadedOffline
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Center(child: iconWidget),
            )
          : Padding(
              padding: const EdgeInsets.all(6),
              child: iconWidget,
            ),
    );
  }
}
