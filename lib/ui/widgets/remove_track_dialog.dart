import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// Shows a Stock Google Pixel Material 3 Expressive confirmation dialog
/// to remove a track from the FreeBeat library, clean up its cache,
/// and remove it from all playlists.
Future<bool> showRemoveTrackConfirmationDialog(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  VoidCallback? onRemoved,
}) async {
  final cs = Theme.of(context).colorScheme;
  unawaited(PixelHaptics.sheetExpand());

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        icon: Icon(Icons.delete_outline_rounded, size: 28, color: cs.error),
        title: const Text('Remove from Library?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove "${track.title}" by ${track.artist} from your FreeBeat library?',
              style: TextStyle(
                fontSize: 14.5,
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.error.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This will remove the song from your library, offline downloads, and playlists.',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );

  if (confirmed == true) {
    unawaited(PixelHaptics.hifiConfirm());
    await ref.read(tracksCatalogProvider.notifier).removeTracks([track.id]);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${track.title}" from library'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    onRemoved?.call();
    return true;
  }
  return false;
}
