import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// Material You Expressive Download Action Button.
///
/// Optimized to match Pixel Settings (`000.mp4`) 120Hz scrolling:
/// - For list rows (`size <= 24` and `!showBackground`), renders as a lightweight stateless icon
///   without attaching per-row Riverpod `.select()` subscriptions on all 592 rows during scroll!
/// - Tapping still triggers `togglePinOffline` via `ProviderScope.containerOf(context, listen: false)`.
class MaterialYouDownloadButton extends StatelessWidget {
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

  Future<void> _handleTap(BuildContext context) async {
    PixelHaptics.tick();
    if (track.id.isEmpty) return;

    final cs = Theme.of(context).colorScheme;
    final willPin = !track.isPinnedOffline;
    final container = ProviderScope.containerOf(context, listen: false);
    await container
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
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDownloadedOffline = track.isPinnedOffline;

    // Fast path for 592-track list rows: 0 Riverpod subscriptions per row during scroll!
    if (!showBackground && size <= 24) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleTap(context),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            isDownloadedOffline
                ? Icons.download_done_rounded
                : Icons.arrow_circle_down_rounded,
            size: size,
            color: isDownloadedOffline
                ? cs.primary
                : (color ?? cs.onSurfaceVariant),
          ),
        ),
      );
    }

    // Detail screens / larger buttons with background use Consumer for live progress spinner
    return Consumer(
      builder: (context, ref, _) {
        final inQueue = isDownloadedOffline
            ? false
            : ref.watch(downloadQueueManagerProvider.select(
                (mgr) => mgr.isTrackInQueue(track.id),
              ));

        Widget iconWidget;
        Color buttonColor = color ?? cs.onSurfaceVariant;

        if (inQueue) {
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
        } else {
          iconWidget = Icon(
            Icons.arrow_circle_down_rounded,
            size: size,
            color: buttonColor,
          );
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleTap(context),
          child: Container(
            width: size + 16,
            height: size + 16,
            decoration: BoxDecoration(
              color: isDownloadedOffline
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
        );
      },
    );
  }
}
