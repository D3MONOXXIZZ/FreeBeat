import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/playlist/playlist_missing_tracks_sync_service.dart';
import '../../state/app_providers.dart';

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
    final authPrompt = syncState.pendingAuthPrompt;

    if (authPrompt != null) {
      return Padding(
        padding: margin,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: cs.error.withValues(alpha: 0.5),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 12,
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
                    backgroundColor: cs.error.withValues(alpha: 0.2),
                    child: Icon(Icons.cloud_off_rounded, size: 16, color: cs.error),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud Auth Error • ${authPrompt.account.displayName}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: cs.error,
                          ),
                        ),
                        Text(
                          'Session expired or not signed in. Download to local storage or sign in?',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    tooltip: 'Cancel Sync',
                    onPressed: () {
                      PixelHaptics.tick();
                      ref.read(playlistMissingTracksSyncProvider.notifier).cancelAuthPromptAndSync();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        PixelHaptics.tick();
                        ref.read(playlistMissingTracksSyncProvider.notifier).confirmAuthFallbackToLocalStorage();
                      },
                      icon: const Icon(Icons.phone_android_rounded, size: 15),
                      label: const Text('Save to Device', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _handleBannerSignIn(context, ref, authPrompt),
                      icon: Icon(authPrompt.account.providerType.icon, size: 15),
                      label: Text('Sign In', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

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
                  icon: const Icon(Icons.info_outline_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  tooltip: 'Storage Location',
                  onPressed: () {
                    PixelHaptics.tick();
                    _showStorageLocationDialog(context, syncState.activePlaylistTitle);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
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

  void _showStorageLocationDialog(BuildContext context, String? playlistTitle) {
    final title = (playlistTitle != null && playlistTitle.isNotEmpty)
        ? playlistTitle
        : 'FreeBeat Playlist';
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.folder_open_rounded, color: cs.primary),
            const SizedBox(width: 10),
            const Text(
              'Download Folder',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Imported and downloaded tracks are saved in your device\'s standard Music folder:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: SelectableText(
                '/storage/emulated/0/Music/$title/',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'How to find in File Manager:\nInternal Storage > Music > $title',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Fallback location:\n/storage/emulated/0/Android/data/com.freebeat.app/files/Music/$title/',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBannerSignIn(
    BuildContext context,
    WidgetRef ref,
    CloudAuthPromptRequest prompt,
  ) async {
    PixelHaptics.tick();
    if (prompt.account.providerType == CloudProviderType.googleDrive) {
      try {
        final authService = ref.read(nativeCloudAuthServiceProvider);
        final result = await authService.signInWithGoogleDrive();
        if (result.isSuccess && result.accessToken != null && result.accessToken!.isNotEmpty) {
          final credStore = ref.read(credentialStoreProvider);
          await credStore.saveSecrets(prompt.account.id, {'accessToken': result.accessToken!});
          ref.read(playlistMissingTracksSyncProvider.notifier).retryAuthWithFreshToken(result.accessToken!);
          await PixelHaptics.hifiConfirm();
          return;
        }
      } catch (e) {
        debugPrint('Google Drive sign-in error from banner: $e');
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sign-in cancelled or failed. You can tap "Save to Device" instead.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
