import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/audio/cloud_audio_cache_service.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'expressive_shapes.dart';

/// Material You Expressive Download Action Button.
/// Displays clear visual states:
/// - Not Downloaded: Outline download icon.
/// - Downloading: Animated circular progress indicator with pulsating download indicator.
/// - Downloaded: Filled primary checkmark / offline badge.
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
    final cacheSvc = ref.watch(cloudAudioCacheServiceProvider);
    final isCached = track.isPinnedOffline || cacheSvc.isTrackCached(track);
    final progress = cacheSvc.getProgress(track.id);
    final isDownloading = progress.state == CacheState.caching;

    Widget iconWidget;
    Color buttonColor = color ?? cs.onSurfaceVariant;

    if (isDownloading) {
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
    } else if (isCached) {
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

    final button = SpringPressScale(
      onTap: () async {
        PixelHaptics.tick();
        if (track.id.isEmpty) return;

        final willPin = !isCached;
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
      child: Tooltip(
        message: isDownloading
            ? 'Downloading ${(progress.progress * 100).round()}%'
            : (isCached ? 'Downloaded Offline' : 'Download Song Locally'),
        child: showBackground
            ? Container(
                width: size + 16,
                height: size + 16,
                decoration: BoxDecoration(
                  color: isCached
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
      ),
    );

    return button;
  }
}
