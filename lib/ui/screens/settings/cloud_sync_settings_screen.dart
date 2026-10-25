import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/audio/cloud_audio_cache_service.dart';
import '../../../services/audio/download_queue_manager.dart';
import '../../../services/haptics/pixel_haptics.dart';
import '../../../state/app_providers.dart';

/// Dedicated Cloud Sync & Storage Settings Screen.
/// Clean, concise M3 Pixel layout for managing offline sync, download queue,
/// storage quotas, and cache maintenance.
class CloudSyncSettingsScreen extends ConsumerWidget {
  const CloudSyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accounts = ref.watch(cloudAccountsProvider);
    final tracks = ref.watch(tracksCatalogProvider);
    final usageAsync = ref.watch(storageUsageFutureProvider);
    final queueMgr = ref.watch(downloadQueueManagerProvider);
    final cacheSvc = ref.watch(cloudAudioCacheServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Storage & Downloads',
          style: textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        physics: const ClampingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Library Overview & Storage Breakdown Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.pie_chart_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Storage Breakdown',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'Refresh Storage Stats',
                        onPressed: () {
                          PixelHaptics.tick();
                          ref.invalidate(storageUsageFutureProvider);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBlock(
                          label: 'Connected Cloud',
                          value: '${accounts.length}',
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBlock(
                          label: 'Indexed Tracks',
                          value: '${tracks.length}',
                          color: cs.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  usageAsync.when(
                    data: (info) => _StorageBreakdownBar(info: info),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                    error: (_, __) => Text(
                      'Failed to compute disk storage statistics.',
                      style: TextStyle(color: cs.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 2. Download Policy & Quota Settings
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, color: cs.primary),
                        const SizedBox(width: 12),
                        Text(
                          'Download Policy & Quotas',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    secondary: Icon(
                      queueMgr.wifiOnly
                          ? Icons.wifi_rounded
                          : Icons.signal_cellular_alt_rounded,
                      color: cs.primary,
                    ),
                    title: const Text(
                      'Download on Wi-Fi Only',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Wait for Wi-Fi connection to download offline music',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: queueMgr.wifiOnly,
                    onChanged: (val) {
                      PixelHaptics.tick();
                      queueMgr.setWifiOnly(val);
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.storage_rounded, color: cs.tertiary),
                    title: const Text(
                      'Maximum Stream Cache',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Auto-purges oldest streamed audio. Offline downloads are never removed.',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: DropdownButton<int>(
                      value: queueMgr.maxCacheSizeMb,
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(16),
                      items: const [
                        DropdownMenuItem(value: 1024, child: Text('1 GB')),
                        DropdownMenuItem(value: 2048, child: Text('2 GB')),
                        DropdownMenuItem(value: 5120, child: Text('5 GB')),
                        DropdownMenuItem(value: 10240, child: Text('10 GB')),
                        DropdownMenuItem(value: 0, child: Text('Unlimited')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          PixelHaptics.tick();
                          queueMgr.setMaxCacheSizeMb(val, tracks);
                          ref.invalidate(storageUsageFutureProvider);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 3. Cache Maintenance
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cleaning_services_rounded, color: cs.tertiary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Cache Maintenance',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'FreeBeat caches audio byte-ranges locally to ensure instant, stutter-free playback. Clearing cache removes temporary files, picker buffers, and unpinned stream chunks without deleting your pinned offline songs.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      PixelHaptics.hifiConfirm();
                      final activeTrack = ref.read(playbackProvider).currentTrack;
                      final reclaimed = await cacheSvc.clearStreamCache(
                        tracks,
                        activeTrackId: activeTrack.id.isNotEmpty ? activeTrack.id : null,
                      );
                      await ref.read(tracksCatalogProvider.notifier).purgeDeletedLocalCachePaths();
                      ref.invalidate(storageUsageFutureProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Reclaimed ${StorageUsageInfo.formatBytes(reclaimed)} of cache. Pinned downloads preserved.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: Text(
                      usageAsync.valueOrNull != null
                          ? 'Clear Stream Cache (${usageAsync.valueOrNull!.streamCacheFormatted})'
                          : 'Clear Stream Cache',
                    ),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 4. Download Queue View
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.downloading_rounded, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Download Queue',
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (queueMgr.totalCount > 0)
                              Text(
                                '${queueMgr.completedCount} of ${queueMgr.totalCount} completed',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (queueMgr.totalCount > 0) ...[
                        IconButton(
                          icon: Icon(
                            queueMgr.isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            size: 20,
                          ),
                          tooltip: queueMgr.isPaused
                              ? 'Resume Queue'
                              : 'Pause Queue',
                          onPressed: () {
                            PixelHaptics.tick();
                            if (queueMgr.isPaused) {
                              queueMgr.resumeQueue();
                            } else {
                              queueMgr.pauseQueue();
                            }
                          },
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert_rounded, size: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onSelected: (val) {
                            PixelHaptics.tick();
                            if (val == 'cancel_all') {
                              queueMgr.cancelAll();
                            } else if (val == 'clear_completed') {
                              queueMgr.clearCompleted();
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'clear_completed',
                              child: Text('Clear completed'),
                            ),
                            const PopupMenuItem(
                              value: 'cancel_all',
                              child: Text('Cancel all downloads'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (queueMgr.queue.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 16,
                      ),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_done_rounded,
                            size: 36,
                            color: cs.primary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'All downloads up to date',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tracks pinned offline or playlists will appear here while syncing.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: queueMgr.queue.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final item = queueMgr.queue[idx];
                        return _DownloadQueueItemTile(
                          item: item,
                          onCancel: () => queueMgr.cancel(item.track.id),
                          onRetry: () => queueMgr.retry(item.track.id),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageBreakdownBar extends StatelessWidget {
  const _StorageBreakdownBar({required this.info});

  final StorageUsageInfo info;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = info.pinnedBytes +
        info.streamCacheBytes +
        info.transcodedBytes +
        info.freeDiskBytes;

    final pinnedFlex =
        ((info.pinnedBytes / (total == 0 ? 1 : total)) * 1000).toInt().clamp(info.pinnedBytes > 0 ? 5 : 0, 1000);
    final streamFlex =
        ((info.streamCacheBytes / (total == 0 ? 1 : total)) * 1000).toInt().clamp(info.streamCacheBytes > 0 ? 5 : 0, 1000);
    final transFlex =
        ((info.transcodedBytes / (total == 0 ? 1 : total)) * 1000).toInt().clamp(info.transcodedBytes > 0 ? 5 : 0, 1000);
    final freeFlex =
        (1000 - pinnedFlex - streamFlex - transFlex).clamp(10, 1000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'App Cache: ${info.totalFormatted}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            Text(
              'Free: ${info.freeFormatted}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                if (pinnedFlex > 0)
                  Expanded(
                    flex: pinnedFlex,
                    child: Container(color: cs.primary),
                  ),
                if (streamFlex > 0)
                  Expanded(
                    flex: streamFlex,
                    child: Container(color: cs.tertiary),
                  ),
                if (transFlex > 0)
                  Expanded(
                    flex: transFlex,
                    child: Container(color: cs.secondary),
                  ),
                Expanded(
                  flex: freeFlex,
                  child: Container(color: cs.surfaceContainerHighest),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _LegendItem(
              color: cs.primary,
              label: 'Pinned Offline',
              value: info.pinnedFormatted,
            ),
            _LegendItem(
              color: cs.tertiary,
              label: 'Stream Cache',
              value: info.streamCacheFormatted,
            ),
            _LegendItem(
              color: cs.secondary,
              label: 'Transcoded Audio',
              value: info.transcodedFormatted,
            ),
            _LegendItem(
              color: cs.outlineVariant,
              label: 'Free Device Space',
              value: info.freeFormatted,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DownloadQueueItemTile extends StatelessWidget {
  const _DownloadQueueItemTile({
    required this.item,
    required this.onCancel,
    required this.onRetry,
  });

  final DownloadQueueItem item;
  final VoidCallback onCancel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget statusTrailing;
    switch (item.status) {
      case DownloadStatus.downloading:
        statusTrailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                value: item.progress > 0.05 ? item.progress : null,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onCancel,
              tooltip: 'Cancel',
            ),
          ],
        );
        break;
      case DownloadStatus.completed:
        statusTrailing = Icon(
          Icons.check_circle_rounded,
          color: cs.primary,
          size: 20,
        );
        break;
      case DownloadStatus.failed:
        statusTrailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: cs.error, size: 20),
              onPressed: onRetry,
              tooltip: 'Retry',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onCancel,
              tooltip: 'Remove',
            ),
          ],
        );
        break;
      case DownloadStatus.paused:
        statusTrailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_outline_rounded,
                color: cs.onSurfaceVariant, size: 20),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: onCancel,
              tooltip: 'Remove',
            ),
          ],
        );
        break;
      case DownloadStatus.queued:
        statusTrailing = IconButton(
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: onCancel,
          tooltip: 'Remove',
        );
        break;
    }

    String statusLabel = '';
    switch (item.status) {
      case DownloadStatus.queued:
        statusLabel = 'Waiting in queue';
        break;
      case DownloadStatus.downloading:
        final pct = (item.progress * 100).toInt();
        statusLabel = 'Downloading $pct%...';
        break;
      case DownloadStatus.completed:
        statusLabel = 'Completed';
        break;
      case DownloadStatus.failed:
        statusLabel = item.errorMessage ?? 'Failed';
        break;
      case DownloadStatus.paused:
        statusLabel = 'Paused';
        break;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          item.status == DownloadStatus.completed
              ? Icons.download_done_rounded
              : Icons.music_note_rounded,
          color: item.status == DownloadStatus.completed
              ? cs.primary
              : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
      title: Text(
        item.track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: item.status == DownloadStatus.failed
                  ? cs.error
                  : item.status == DownloadStatus.completed
                      ? cs.primary
                      : cs.onSurfaceVariant,
            ),
          ),
          if (item.status == DownloadStatus.downloading && item.progress > 0) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: item.progress,
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
      trailing: statusTrailing,
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
