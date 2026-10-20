import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/playlist/playlist_missing_tracks_sync_service.dart';

/// Expressive Material 3 banner that displays live progress when missing
/// playlist tracks are being resolved, downloaded, and uploaded to the user's cloud.
class CloudSyncProgressBanner extends ConsumerWidget {
  const CloudSyncProgressBanner({
    super.key,
    this.playlistId,
    this.margin = const EdgeInsets.fromLTRB(20, 8, 20, 8),
  });

  final String? playlistId;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(playlistMissingTracksSyncProvider);

    if (!syncState.isSyncing) return const SizedBox.shrink();
    if (playlistId != null && syncState.activePlaylistId != playlistId) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final account = syncState.activeCloudAccount;
    final accentColor = account?.providerType.accentColor ?? cs.primary;
    final progress = syncState.overallProgress.clamp(0.0, 1.0);
    final percentInt = (progress * 100).toInt();

    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: accentColor.withValues(alpha: 0.18),
                  child: Icon(
                    account?.providerType.icon ?? Icons.cloud_sync_rounded,
                    size: 16,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cloud Sync • ${account?.displayName ?? "Cloud Drive"}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        syncState.activePlaylistTitle != null
                            ? 'Playlist: ${syncState.activePlaylistTitle}'
                            : 'Syncing missing songs',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${syncState.completedCount}/${syncState.totalCount} ($percentInt%)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Cancel Cloud Sync',
                  onPressed: () {
                    PixelHaptics.tick();
                    ref.read(playlistMissingTracksSyncProvider.notifier).cancelSync();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: accentColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            ),
            if (syncState.currentStatusText.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                syncState.currentStatusText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
