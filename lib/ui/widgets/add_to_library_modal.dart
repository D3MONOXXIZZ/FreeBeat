import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../screens/playlist_details_screen.dart';
import 'playlist_import_modal.dart';

/// Opens the unified Material You "Add to Library" modal sheet.
Future<void> showAddToLibraryModal(BuildContext context, WidgetRef ref) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddToLibrarySheet(parentRef: ref),
  );
}

class _AddToLibrarySheet extends ConsumerWidget {
  const _AddToLibrarySheet({required this.parentRef});

  final WidgetRef parentRef;

  Future<void> _pickCloudFolder(BuildContext context, WidgetRef ref) async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    final accounts = ref.read(cloudAccountsProvider);
    final safAccount = accounts.firstWhere(
      (a) => a.providerType == CloudProviderType.androidSaf,
      orElse: () => const CloudAccount(
        id: 'cloud_folder_saf',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Cloud & Storage Folders',
        endpointOrFolder: 'Cloud Music Folder',
      ),
    );
    final progressNotifier = ref.read(importProgressProvider.notifier);
    final picked = await authService.pickFolder(
      account: safAccount,
      batchSize: 10,
      onBatchStarted: (batchFilenames, batchStartIndex, totalFiles) {
        progressNotifier.startBatch(
          batchFilenames: batchFilenames,
          batchStartIndex: batchStartIndex,
          totalFiles: totalFiles,
        );
      },
      onProgress: (current, total, track) {
        progressNotifier.update(
          current: current,
          total: total,
          name: track?.title ?? '',
          track: track,
        );
      },
      onBatchCompleted: (batchTracks) async {
        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(batchTracks);
      },
    );
    if (picked.isNotEmpty) {
      await PixelHaptics.hifiConfirm();
      progressNotifier.complete();
      ref.read(tracksCatalogProvider.notifier).enrichLibraryArtwork(picked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${picked.length} tracks from folder into Library'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      }
    } else {
      progressNotifier.clearPending();
    }
  }

  Future<void> _pickLocalFiles(BuildContext context, WidgetRef ref) async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    final accounts = ref.read(cloudAccountsProvider);
    final safAccount = accounts.firstWhere(
      (a) => a.providerType == CloudProviderType.androidSaf,
      orElse: () => const CloudAccount(
        id: 'local_storage_saf',
        providerType: CloudProviderType.androidSaf,
        displayName: 'Local Storage',
        endpointOrFolder: 'Local Music Files',
      ),
    );
    final progressNotifier = ref.read(importProgressProvider.notifier);
    final picked = await authService.pickFromInstalledCloudApp(
      account: safAccount,
      batchSize: 10,
      onBatchStarted: (batchFilenames, batchStartIndex, totalFiles) {
        progressNotifier.startBatch(
          batchFilenames: batchFilenames,
          batchStartIndex: batchStartIndex,
          totalFiles: totalFiles,
        );
      },
      onProgress: (current, total, track) {
        progressNotifier.update(
          current: current,
          total: total,
          name: track?.title ?? '',
          track: track,
        );
      },
      onBatchCompleted: (batchTracks) async {
        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(batchTracks);
      },
    );
    if (picked.isNotEmpty) {
      await PixelHaptics.hifiConfirm();
      progressNotifier.complete();
      ref.read(tracksCatalogProvider.notifier).enrichLibraryArtwork(picked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${picked.length} tracks into Library'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      }
    } else {
      progressNotifier.clearPending();
    }
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    PixelHaptics.tick();
    final titleController = TextEditingController();
    final descController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: const Text(
            'New Playlist',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Playlist Name',
                  hintText: 'e.g. Late Night Drives, Chill Lofi',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showPlaylistImportModal(context);
                },
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Or import from Spotify, Apple, or YouTube'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isNotEmpty) {
                  Navigator.of(ctx).pop();
                  final playlist = await ref
                      .read(playlistsProvider.notifier)
                      .createPlaylist(
                        title,
                        description: descController.text.trim(),
                      );
                  await PixelHaptics.hifiConfirm();
                  if (context.mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaylistDetailsScreen(playlist: playlist),
                      ),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveRef = parentRef;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.add_to_photos_rounded,
                  color: cs.onPrimaryContainer,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Add to Library',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Import music from links, cloud folders, or files',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Option 1: Import from Link (Tracks, Albums, Playlists)
          _buildOptionTile(
            context: context,
            icon: Icons.link_rounded,
            iconBgColor: cs.primaryContainer,
            iconColor: cs.onPrimaryContainer,
            title: 'Import from Link',
            subtitle:
                'Import individual tracks, full albums, or playlists from Spotify, Apple Music, or YouTube',
            badgeText: 'Spotify / Apple / YT',
            badgeColor: cs.primary,
            onTap: () {
              Navigator.pop(context);
              showPlaylistImportModal(context);
            },
          ),
          const SizedBox(height: 10),

          // Option 2: Import Folder from Cloud / Storage
          _buildOptionTile(
            context: context,
            icon: Icons.cloud_sync_rounded,
            iconBgColor: cs.secondaryContainer,
            iconColor: cs.onSecondaryContainer,
            title: 'Import Folder from Cloud',
            subtitle:
                'Scan an entire audio folder from Google Drive, OneDrive, Dropbox, or SD Card',
            badgeText: 'Cloud Folder',
            badgeColor: cs.secondary,
            onTap: () {
              Navigator.pop(context);
              _pickCloudFolder(context, effectiveRef);
            },
          ),
          const SizedBox(height: 10),

          // Option 3: Pick Audio Files
          _buildOptionTile(
            context: context,
            icon: Icons.audio_file_rounded,
            iconBgColor: cs.tertiaryContainer,
            iconColor: cs.onTertiaryContainer,
            title: 'Pick Audio Files',
            subtitle:
                'Select individual audio files (.mp3, .flac, .m4a, .wav, .opus) from device or cloud',
            onTap: () {
              Navigator.pop(context);
              _pickLocalFiles(context, effectiveRef);
            },
          ),
          const SizedBox(height: 10),

          // Option 4: New Playlist
          _buildOptionTile(
            context: context,
            icon: Icons.playlist_add_rounded,
            iconBgColor: cs.surfaceContainerHighest,
            iconColor: cs.onSurface,
            title: 'New Playlist',
            subtitle: 'Create an empty custom playlist',
            onTap: () {
              Navigator.pop(context);
              _showCreatePlaylistDialog(context, effectiveRef);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required BuildContext context,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          PixelHaptics.tick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (badgeText != null && badgeColor != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: badgeColor.withValues(alpha: 0.35),
                                width: 0.7,
                              ),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
