import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../providers/implementations/oauth_cloud_connectors.dart';
import '../../services/discovery/local_media_server_discovery_service.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import 'settings/settings_screen.dart';

/// Clean, focused Cloud Storage Hub (Google Material 3 Expressive).
/// Dedicated solely to managing connected cloud drives, 1-tap cloud authorization,
/// installed cloud app launching/Play Store redirects, and local media servers.
class CloudsScreen extends ConsumerWidget {
  const CloudsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accounts = ref.watch(cloudAccountsProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
        physics: const BouncingScrollPhysics(),
      children: [
        // 1. Header with Title, Settings Icon & Add Cloud Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clouds & Hi-Fi Quality',
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '100% Serverless • Device Encrypted',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: () {
                PixelHaptics.tick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.settings_outlined, size: 20),
              tooltip: 'Settings',
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showAddCloudWizard(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Cloud'),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Connected Cloud Accounts Card
        if (accounts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_outlined,
                      size: 28,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No Cloud Accounts Connected',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap "Add Cloud" above to connect Google Drive, OneDrive, Dropbox, or a local server.',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: () => _showAddCloudWizard(context, ref),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Connect a Cloud Drive'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                children: [
                  for (int i = 0; i < accounts.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 68,
                        endIndent: 16,
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: accounts[i]
                            .providerType
                            .accentColor
                            .withValues(alpha: 0.16),
                        child: Icon(
                          accounts[i].providerType.icon,
                          color: accounts[i].providerType.accentColor,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        accounts[i].displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        accounts[i].endpointOrFolder,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: cs.error,
                        onPressed: () => _confirmRemoveAccount(
                          context,
                          ref,
                          accounts[i],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

        const SizedBox(height: 20),

        // 3. Fast Cloud App Launchers (Open installed app or Google Play Store)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.apps_rounded, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Installed Cloud Apps',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Opens the app or Google Play Store if not installed',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _AppLauncherRow(
                  name: 'Google Drive',
                  packageName: 'com.google.android.apps.docs',
                  icon: Icons.add_to_drive_rounded,
                  color: const Color(0xFF4285F4),
                ),
                const Divider(height: 14),
                _AppLauncherRow(
                  name: 'Microsoft OneDrive',
                  packageName: 'com.microsoft.skydrive',
                  icon: Icons.cloud_queue_rounded,
                  color: const Color(0xFF0078D4),
                ),
                const Divider(height: 14),
                _AppLauncherRow(
                  name: 'Dropbox',
                  packageName: 'com.dropbox.android',
                  icon: Icons.inventory_2_rounded,
                  color: const Color(0xFF0061FF),
                ),
                const Divider(height: 14),
                _AppLauncherRow(
                  name: 'Nextcloud',
                  packageName: 'com.nextcloud.client',
                  icon: Icons.language_rounded,
                  color: const Color(0xFF0082C9),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 4. Quick Device / SD Card Audio Import Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sd_card_rounded, color: cs.secondary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Device & SD Card Storage',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Import audio files downloaded on your phone',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => _pickLocalAudioFiles(context, ref),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Pick Music from Device Storage'),
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  }

  Future<void> _pickLocalAudioFiles(BuildContext context, WidgetRef ref) async {
    PixelHaptics.tick();
    final authService = ref.read(nativeCloudAuthServiceProvider);
    const safAccount = CloudAccount(
      id: 'local_storage',
      providerType: CloudProviderType.androidSaf,
      displayName: 'Device Storage',
      endpointOrFolder: 'Local Music Files',
    );
    final progressNotifier = ref.read(importProgressProvider.notifier);
    final tracks = await authService.pickFromInstalledCloudApp(
      account: safAccount,
      onFilesSelected: (filenames) {
        progressNotifier.startWithFiles(filenames);
      },
      onProgress: (current, total, track) {
        progressNotifier.update(
          current: current,
          total: total,
          name: track?.title ?? '',
          track: track,
        );
        if (track != null) {
          ref.read(tracksCatalogProvider.notifier).addIndexedTracks([track]);
        }
      },
    );
    progressNotifier.complete();
    if (tracks.isNotEmpty) {
      await ref.read(cloudAccountsProvider.notifier).addAccount(safAccount, {});
      await PixelHaptics.hifiConfirm();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Imported ${tracks.length} tracks from device storage!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _confirmRemoveAccount(
    BuildContext context,
    WidgetRef ref,
    CloudAccount account,
  ) {
    PixelHaptics.tick();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect ${account.displayName}?'),
        content: const Text(
          'This will remove the cloud account and its indexed tracks from your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () {
              ref.read(cloudAccountsProvider.notifier).removeAccount(account.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  void _showAddCloudWizard(BuildContext context, WidgetRef ref) {
    PixelHaptics.sheetExpand();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => const _AddCloudWizardSheet(),
    );
  }
}

class _AppLauncherRow extends ConsumerWidget {
  const _AppLauncherRow({
    required this.name,
    required this.packageName,
    required this.icon,
    required this.color,
  });

  final String name;
  final String packageName;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
        FilledButton.tonal(
          onPressed: () async {
            PixelHaptics.tick();
            final authService = ref.read(nativeCloudAuthServiceProvider);
            final opened = await authService.launchOrOpenPlayStore(
              packageName: packageName,
            );
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Opening Google Play Store for $name...'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: const StadiumBorder(),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Open / Install', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 14),
            ],
          ),
        ),
      ],
    );
  }
}

enum _AddCloudMode {
  oneTapCloud('1-Tap Cloud', Icons.touch_app_rounded),
  wifiServers('Wi-Fi Servers', Icons.wifi_find_rounded),
  installedApps('Installed Apps', Icons.apps_rounded),
  manual('Manual / S3', Icons.dns_rounded);

  const _AddCloudMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _AddCloudWizardSheet extends ConsumerStatefulWidget {
  const _AddCloudWizardSheet();

  @override
  ConsumerState<_AddCloudWizardSheet> createState() =>
      _AddCloudWizardSheetState();
}

class _AddCloudWizardSheetState extends ConsumerState<_AddCloudWizardSheet> {
  _AddCloudMode _mode = _AddCloudMode.oneTapCloud;
  bool _isGoogleLoading = false;
  bool _isConnecting = false;
  bool _isScanningWifi = false;

  final _manualServerUrlController = TextEditingController();
  final _manualUsernameController = TextEditingController();
  final _manualPasswordController = TextEditingController();
  final _manualBucketController = TextEditingController();

  CloudProviderType _selectedManualType = CloudProviderType.jellyfin;
  List<DiscoveredMediaServer> _discoveredWifiServers = [];

  @override
  void dispose() {
    _manualServerUrlController.dispose();
    _manualUsernameController.dispose();
    _manualPasswordController.dispose();
    _manualBucketController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    PixelHaptics.tick();

    final authService = ref.read(nativeCloudAuthServiceProvider);
    final result = await authService.signInWithGoogleDrive();

    setState(() => _isGoogleLoading = false);

    if (result.isSuccess && result.account != null) {
      final account = result.account!;
      final secrets = {'accessToken': result.accessToken ?? ''};
      await ref.read(cloudAccountsProvider.notifier).addAccount(account, secrets);

      // Automatically scan Google Drive for audio files if token is provided
      if (secrets['accessToken']!.isNotEmpty) {
        final connector = GoogleDriveConnector();
        final tracks = await connector.scanLibrary(account, secrets);
        if (tracks.isNotEmpty) {
          await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(tracks);
        }
      }

      await PixelHaptics.hifiConfirm();

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${result.displayName ?? result.email}!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (result.isDeveloperConfigError) {
      if (mounted) {
        _showGoogleDeveloperErrorDialog();
      }
    } else if (!result.isCancelled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Google Sign-In failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showGoogleDeveloperErrorDialog() {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.add_to_drive_rounded, color: Color(0xFF4285F4), size: 26),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Import from Google Drive',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Direct Google Play Services login requires SHA-1 registration in Google Cloud Console. You can immediately access your music using Android\'s built-in Google Drive document provider without any setup:',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _mountViaSaf(
                  providerType: CloudProviderType.googleDrive,
                  defaultName: 'Google Drive',
                );
              },
              icon: const Icon(Icons.audio_file_rounded, size: 20),
              label: const Text('Pick Audio Files from Google Drive', style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(ctx);
                _mountFolderViaSaf(
                  providerType: CloudProviderType.googleDrive,
                  defaultName: 'Google Drive Folder',
                );
              },
              icon: const Icon(Icons.folder_shared_rounded, size: 20),
              label: const Text('Import Music Folder from Drive / Device', style: TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () async {
                final authService = ref.read(nativeCloudAuthServiceProvider);
                final sha1 = await authService.getAppSha1Fingerprint();
                await Clipboard.setData(ClipboardData(
                  text: 'Package: com.freebeat.freebeat\nSHA-1: $sha1',
                ));
                PixelHaptics.tick();
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Copied Package & SHA-1 to clipboard: $sha1'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Copy SHA-1 & Package Name for Developer Console'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mountViaSaf({
    required CloudProviderType providerType,
    required String defaultName,
  }) async {
    setState(() => _isConnecting = true);
    PixelHaptics.tick();

    try {
      final account = CloudAccount(
        id: 'saf_${DateTime.now().millisecondsSinceEpoch}',
        providerType: providerType,
        displayName: defaultName,
        endpointOrFolder: 'Android App Storage (${providerType.displayName})',
        lastSyncedAt: DateTime.now(),
      );

      final authService = ref.read(nativeCloudAuthServiceProvider);
      final progressNotifier = ref.read(importProgressProvider.notifier);
      final tracks = await authService.pickFromInstalledCloudApp(
        account: account,
        onFilesSelected: (filenames) {
          progressNotifier.startWithFiles(filenames);
        },
        onProgress: (current, total, track) {
          progressNotifier.update(
            current: current,
            total: total,
            name: track?.title ?? '',
            track: track,
          );
          if (track != null) {
            ref.read(tracksCatalogProvider.notifier).addIndexedTracks([track]);
          }
        },
      );
      progressNotifier.complete();

      if (tracks.isNotEmpty) {
        await ref.read(cloudAccountsProvider.notifier).addAccount(account, {});
        await PixelHaptics.hifiConfirm();

        if (mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imported ${tracks.length} audio tracks from $defaultName!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) setState(() => _isConnecting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _mountFolderViaSaf({
    required CloudProviderType providerType,
    required String defaultName,
  }) async {
    setState(() => _isConnecting = true);
    PixelHaptics.tick();

    try {
      final account = CloudAccount(
        id: 'saf_folder_${DateTime.now().millisecondsSinceEpoch}',
        providerType: providerType,
        displayName: defaultName,
        endpointOrFolder: 'Folder Import (${providerType.displayName})',
        lastSyncedAt: DateTime.now(),
      );

      final authService = ref.read(nativeCloudAuthServiceProvider);
      final tracks = await authService.pickFolder(account: account);

      if (tracks.isNotEmpty) {
        await ref.read(cloudAccountsProvider.notifier).addAccount(account, {});
        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(tracks);
        await PixelHaptics.hifiConfirm();

        if (mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imported ${tracks.length} tracks from $defaultName!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) setState(() => _isConnecting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Folder import failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _scanWifi() async {
    setState(() => _isScanningWifi = true);
    PixelHaptics.tick();

    final discoveryService = ref.read(localMediaServerDiscoveryServiceProvider);
    final servers = await discoveryService.discoverAll(
      timeout: const Duration(seconds: 4),
    );

    setState(() {
      _discoveredWifiServers = servers;
      _isScanningWifi = false;
    });

    await PixelHaptics.hifiConfirm();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_rounded, color: cs.primary),
                const SizedBox(width: 10),
                const Text(
                  'Add Cloud & Media Drive',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Mode Selector
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_AddCloudMode>(
                segments: _AddCloudMode.values.map((mode) {
                  return ButtonSegment(
                    value: mode,
                    label: Text(mode.label),
                    icon: Icon(mode.icon, size: 16),
                  );
                }).toList(),
                selected: {_mode},
                onSelectionChanged: (newSelection) {
                  PixelHaptics.tick();
                  setState(() => _mode = newSelection.first);
                },
              ),
            ),
            const SizedBox(height: 16),

            // Mode Views
            switch (_mode) {
              _AddCloudMode.oneTapCloud => _buildOneTapCloudView(cs),
              _AddCloudMode.wifiServers => _buildWifiTab(cs),
              _AddCloudMode.installedApps => _buildInstalledAppsView(cs),
              _AddCloudMode.manual => _buildManualView(cs),
            },
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildOneTapCloudView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Google Drive Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF4285F4).withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.add_to_drive_rounded, color: Color(0xFF4285F4), size: 28),
                  SizedBox(width: 12),
                  Text('Google Drive', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Stream or import music directly from your Google Drive files or cloud folders.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _mountViaSaf(
                    providerType: CloudProviderType.googleDrive,
                    defaultName: 'Google Drive',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.audio_file_rounded, size: 20),
                  label: const Text('Pick Audio Files from Google Drive', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _mountFolderViaSaf(
                        providerType: CloudProviderType.googleDrive,
                        defaultName: 'Google Drive Folder',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.folder_shared_rounded, size: 16),
                      label: const Text('Import Folder', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      icon: _isGoogleLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_sync_rounded, size: 16),
                      label: const Text('Cloud Sign-In', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Microsoft OneDrive Card
        _buildOAuthCard(
          cs: cs,
          type: CloudProviderType.oneDrive,
          accentColor: const Color(0xFF0078D4),
          title: 'Microsoft OneDrive',
          description: 'Sign in with your Microsoft 365 account or open the OneDrive app.',
          primaryActionLabel: 'Sign in with Microsoft 365',
          onPrimaryAction: () async {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            await authService.launchOAuthAuthorization(
              provider: CloudProviderType.oneDrive,
              clientId: 'f9479b18-0524-460b-8d34-716b9b324d67',
            );
          },
          secondaryActionLabel: 'Open OneDrive App / Play Store',
          onSecondaryAction: () async {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            await authService.launchOrOpenPlayStore(
              packageName: 'com.microsoft.skydrive',
            );
          },
        ),

        const SizedBox(height: 12),

        // Dropbox Card
        _buildOAuthCard(
          cs: cs,
          type: CloudProviderType.dropbox,
          accentColor: const Color(0xFF0061FF),
          title: 'Dropbox',
          description: 'Stream audio files directly from Dropbox cloud or app.',
          primaryActionLabel: 'Sign in with Dropbox',
          onPrimaryAction: () async {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            await authService.launchOAuthAuthorization(
              provider: CloudProviderType.dropbox,
              clientId: 'dropbox_freebeat_client',
            );
          },
          secondaryActionLabel: 'Open Dropbox App / Play Store',
          onSecondaryAction: () async {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            await authService.launchOrOpenPlayStore(
              packageName: 'com.dropbox.android',
            );
          },
        ),
      ],
    );
  }

  Widget _buildOAuthCard({
    required ColorScheme cs,
    required CloudProviderType type,
    required Color accentColor,
    required String title,
    required String description,
    required String primaryActionLabel,
    required VoidCallback onPrimaryAction,
    required String secondaryActionLabel,
    required VoidCallback onSecondaryAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(type.icon, color: accentColor, size: 24),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(description, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onPrimaryAction,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(primaryActionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onSecondaryAction,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: const StadiumBorder(),
                ),
                child: Text(secondaryActionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWifiTab(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi_find_rounded, color: Color(0xFF00A4DC), size: 24),
                  SizedBox(width: 10),
                  Text('Auto-Detect Local Media Servers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Scans your local Wi-Fi network for Jellyfin, Emby, Subsonic, Navidrome, and Plex servers.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isScanningWifi ? null : _scanWifi,
                  icon: _isScanningWifi
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                      : const Icon(Icons.radar_rounded, size: 18),
                  label: Text(_isScanningWifi ? 'Broadcasting & Scanning Wi-Fi...' : 'Scan Wi-Fi for Media Servers'),
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                ),
              ),
            ],
          ),
        ),

        if (_discoveredWifiServers.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Discovered on your Wi-Fi:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final server in _discoveredWifiServers)
            Card(
              child: ListTile(
                leading: Icon(server.type.icon, color: server.type.accentColor),
                title: Text(server.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${server.url} • ${server.discoveredVia}'),
                trailing: FilledButton.tonal(
                  onPressed: () {
                    final acc = CloudAccount(
                      id: server.id,
                      providerType: server.type,
                      displayName: server.name,
                      endpointOrFolder: server.url,
                    );
                    ref.read(cloudAccountsProvider.notifier).addAccount(acc, {});
                    Navigator.of(context).pop();
                  },
                  child: const Text('Connect'),
                ),
              ),
            ),
        ],

        const SizedBox(height: 16),
        const Text('Quick Host Presets:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: const Text('Jellyfin (8096)'),
              onPressed: () {
                _manualServerUrlController.text = 'http://192.168.1.100:8096';
                setState(() => _mode = _AddCloudMode.manual);
              },
            ),
            ActionChip(
              label: const Text('Navidrome (4533)'),
              onPressed: () {
                _manualServerUrlController.text = 'http://192.168.1.100:4533';
                setState(() => _mode = _AddCloudMode.manual);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstalledAppsView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.phone_android_rounded, color: Color(0xFF3DDC84), size: 26),
                  SizedBox(width: 12),
                  Text('Mount Any Installed Cloud App', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Import audio files from Google Drive, OneDrive, Dropbox, or device storage via Android document picker.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isConnecting
                      ? null
                      : () => _mountViaSaf(
                            providerType: CloudProviderType.androidSaf,
                            defaultName: 'Mounted Cloud App',
                          ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.audio_file_rounded, size: 20),
                  label: const Text('Pick Music Files from Installed App', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isConnecting
                      ? null
                      : () => _mountFolderViaSaf(
                            providerType: CloudProviderType.androidSaf,
                            defaultName: 'Mounted Music Folder',
                          ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.folder_shared_rounded, size: 20),
                  label: const Text('Import Entire Folder', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildManualView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<CloudProviderType>(
          initialValue: _selectedManualType,
          decoration: InputDecoration(
            labelText: 'Server / Protocol Type',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          items: const [
            DropdownMenuItem(value: CloudProviderType.jellyfin, child: Text('Jellyfin / Emby Server')),
            DropdownMenuItem(value: CloudProviderType.subsonic, child: Text('Subsonic / Navidrome API')),
            DropdownMenuItem(value: CloudProviderType.webdav, child: Text('WebDAV (Nextcloud / ownCloud)')),
            DropdownMenuItem(value: CloudProviderType.s3, child: Text('S3 Object Storage (AWS / MinIO)')),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _selectedManualType = val);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualServerUrlController,
          decoration: InputDecoration(
            labelText: 'Server URL / Endpoint / IP Address',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualUsernameController,
          decoration: InputDecoration(
            labelText: 'Username / Access Key',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _manualPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password / API Key',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              final account = CloudAccount(
                id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
                providerType: _selectedManualType,
                displayName: '${_selectedManualType.displayName} Server',
                endpointOrFolder: _manualServerUrlController.text.trim(),
                usernameOrEmail: _manualUsernameController.text.trim(),
              );
              ref.read(cloudAccountsProvider.notifier).addAccount(account, {
                'password': _manualPasswordController.text,
              });
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Mount Cloud Drive', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}
