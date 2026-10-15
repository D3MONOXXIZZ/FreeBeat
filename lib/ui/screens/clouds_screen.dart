import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../providers/implementations/oauth_cloud_connectors.dart';
import '../../services/discovery/local_media_server_discovery_service.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// Cloud Storage Hub, 12-Provider Add Cloud Wizard, Configurable Bitrate Tiers
/// (96 kbps -> 320 kbps -> 24-bit/192kHz Hi-Fi Lossless), and Universal Bluetooth Settings.
class CloudsScreen extends ConsumerWidget {
  const CloudsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final accounts = ref.watch(cloudAccountsProvider);
    final quality = ref.watch(audioQualityProvider);
    final qualityNotifier = ref.read(audioQualityProvider.notifier);
    final routeAsync = ref.watch(audioOutputRouteProvider);
    final route = routeAsync.valueOrNull ?? const AudioOutputRouteInfo();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
      physics: const BouncingScrollPhysics(),
      children: [
        // 1. Header & Add Cloud Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Clouds & Hi-Fi Quality',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    '100% Serverless • Android Keystore Encrypted',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
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

        // 2. Connected Cloud Accounts Grouped Card (Pixel Settings Style)
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
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    subtitle: Text(
                      '${accounts[i].providerType.displayName} • ${accounts[i].endpointOrFolder}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Disconnect Cloud',
                      onPressed: () {
                        ref
                            .read(cloudAccountsProvider.notifier)
                            .removeAccount(accounts[i].id);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 3. Configurable Audio Bitrate & Hi-Fi Lossless Tiers
        Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.high_quality_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Audio Bitrate & Hi-Fi Lossless Tiers',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _QualityDropdownTile(
                  title: 'Wi-Fi Streaming Quality',
                  subtitle: quality.wifiTier.subtitle,
                  value: quality.wifiTier,
                  onChanged: (tier) {
                    if (tier != null) qualityNotifier.setWifiTier(tier);
                  },
                ),
                const Divider(height: 20),
                _QualityDropdownTile(
                  title: 'Mobile Data Streaming Quality',
                  subtitle: quality.cellularTier.subtitle,
                  value: quality.cellularTier,
                  onChanged: (tier) {
                    if (tier != null) qualityNotifier.setCellularTier(tier);
                  },
                ),
                const Divider(height: 20),
                _QualityDropdownTile(
                  title: 'Offline Pinned Download Quality',
                  subtitle: quality.offlineDownloadTier.subtitle,
                  value: quality.offlineDownloadTier,
                  onChanged: (tier) {
                    if (tier != null) {
                      qualityNotifier.setOfflineDownloadTier(tier);
                    }
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '24-Bit / 192 kHz Hi-Res Direct Output',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Bypass standard resampling when streaming FLAC/ALAC/WAV',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: quality.enableHiResDirectOutput,
                  onChanged: qualityNotifier.toggleHiResDirectOutput,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 4. Universal Bluetooth Codec & Android OEM Compatibility Safeguards
        Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bluetooth_audio_rounded, color: cs.secondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bluetooth Codec & Device Compatibility',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Active Route: ${route.deviceName} (${route.bluetoothCodecName})',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Bluetooth Inter-Sample Peak Limiter (-0.5 dBFS)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Prevents resampling crackle on LDAC, aptX HD/Adaptive, AAC, SBC & LC3',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: quality.bluetoothIspProtection,
                  onChanged: qualityNotifier.toggleBluetoothIspProtection,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Disable DVC on Bluetooth Absolute Volume',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Prevents sudden AVRCP volume jumps on Samsung, Pixel & Xiaomi earbuds',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: quality.disableDvcOnBluetoothAbsoluteVolume,
                  onChanged: qualityNotifier.toggleDisableDvcOnBluetooth,
                ),
              ],
            ),
          ),
        ),
      ],
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

class _QualityDropdownTile extends StatelessWidget {
  const _QualityDropdownTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final AudioQualityTier value;
  final ValueChanged<AudioQualityTier?> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        DropdownButton<AudioQualityTier>(
          value: value,
          underline: const SizedBox.shrink(),
          items: AudioQualityTier.values.map((tier) {
            return DropdownMenuItem(
              value: tier,
              child: Text(
                tier.isLossless ? 'Hi-Fi Lossless' : '${tier.kbps} kbps',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

enum _AddCloudMode {
  oneTap('1-Tap Cloud', Icons.touch_app_rounded),
  wifiServers('Wi-Fi Servers', Icons.radar_rounded),
  installedApps('Installed Apps', Icons.apps_rounded),
  manual('Manual / S3', Icons.tune_rounded);

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
  _AddCloudMode _mode = _AddCloudMode.oneTap;

  // Google Sign-In state
  bool _isGoogleLoading = false;
  String? _googleNotice;

  // Wi-Fi Discovery state
  bool _isScanningWifi = false;
  List<DiscoveredMediaServer> _discoveredServers = [];

  // General connecting state
  bool _isConnecting = false;

  // Manual / Advanced setup controllers
  CloudProviderType _manualType = CloudProviderType.s3;
  final _nameCtrl = TextEditingController(text: 'My Cloud Vault');
  final _endpointCtrl =
      TextEditingController(text: 'https://s3.us-east-1.amazonaws.com');
  final _userCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _bucketCtrl = TextEditingController(text: 'lossless-music');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _userCtrl.dispose();
    _secretCtrl.dispose();
    _bucketCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1-Tap Google Drive Native Auth
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _googleNotice = null;
    });
    PixelHaptics.tick();

    try {
      final authService = ref.read(nativeCloudAuthServiceProvider);
      final result = await authService.signInWithGoogleDrive();

      if (!mounted) return;

      if (result.isSuccess && result.account != null) {
        final account = result.account!;
        final secrets = {'accessToken': result.accessToken ?? ''};
        await ref
            .read(cloudAccountsProvider.notifier)
            .addAccount(account, secrets);

        // Proactively scan Google Drive for audio files
        final connector = GoogleDriveConnector();
        final tracks = await connector.scanLibrary(account, secrets);
        if (tracks.isNotEmpty) {
          await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(tracks);
        }

        await PixelHaptics.hifiConfirm();
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Connected Google Drive for ${result.displayName ?? result.email}! '
                '(${tracks.isNotEmpty ? "${tracks.length} tracks indexed" : "Drive connected"})',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (result.isCancelled) {
        setState(() {
          _isGoogleLoading = false;
        });
      } else {
        setState(() {
          _isGoogleLoading = false;
          _googleNotice = result.errorMessage ??
              'Google Sign-In canceled or Play Services not configured on this device.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
          _googleNotice = e.toString();
        });
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1-Tap Mount via Android Storage Access Framework (SAF)
  // ───────────────────────────────────────────────────────────────────────────
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
      final tracks =
          await authService.pickFromInstalledCloudApp(account: account);

      if (tracks.isNotEmpty) {
        await ref.read(cloudAccountsProvider.notifier).addAccount(account, {});
        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(tracks);
        await PixelHaptics.hifiConfirm();

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Mounted ${tracks.length} audio tracks from $defaultName!',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        setState(() => _isConnecting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not mount files: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Wi-Fi Media Server Discovery
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _scanWifi() async {
    setState(() {
      _isScanningWifi = true;
    });
    PixelHaptics.tick();

    try {
      final discovery = ref.read(localMediaServerDiscoveryServiceProvider);
      final found = await discovery.discoverAll();
      if (mounted) {
        setState(() {
          _discoveredServers = found;
          _isScanningWifi = false;
        });
        PixelHaptics.tick(intensity: 0.8);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanningWifi = false;
        });
      }
    }
  }

  Future<void> _connectDiscoveredServer(DiscoveredMediaServer server) async {
    setState(() => _isConnecting = true);
    PixelHaptics.tick();

    try {
      final account = CloudAccount(
        id: '${server.type.id}_${DateTime.now().millisecondsSinceEpoch}',
        providerType: server.type,
        displayName: server.name,
        endpointOrFolder: server.url,
        lastSyncedAt: DateTime.now(),
      );

      await ref.read(cloudAccountsProvider.notifier).addAccount(account, {
        'apiKey': '',
        'accessToken': '',
      });

      // Scan default library for the server
      final registry = ref.read(connectorRegistryProvider);
      final connector = registry.forType(server.type);
      final tracks = await connector.scanLibrary(account, {});
      if (tracks.isNotEmpty) {
        await ref.read(tracksCatalogProvider.notifier).addIndexedTracks(tracks);
      }

      await PixelHaptics.hifiConfirm();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connected to ${server.name}! (${tracks.length} tracks indexed)',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Manual Account Mount
  // ───────────────────────────────────────────────────────────────────────────
  Future<void> _submitManual() async {
    setState(() => _isConnecting = true);
    PixelHaptics.tick();

    final account = CloudAccount(
      id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
      providerType: _manualType,
      displayName: _nameCtrl.text.trim().isEmpty
          ? _manualType.displayName
          : _nameCtrl.text.trim(),
      endpointOrFolder: _endpointCtrl.text.trim(),
      usernameOrEmail: _userCtrl.text.trim(),
      bucketOrShareName: _bucketCtrl.text.trim(),
      lastSyncedAt: DateTime.now(),
    );

    await ref.read(cloudAccountsProvider.notifier).addAccount(
      account,
      {
        'password': _secretCtrl.text.trim(),
        'accessToken': _secretCtrl.text.trim(),
        'apiKey': _secretCtrl.text.trim(),
        'accessKeyId': _userCtrl.text.trim(),
        'secretAccessKey': _secretCtrl.text.trim(),
      },
    );

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Cloud & Media Drive',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        '1-Tap Native Sign-In • Android App Mount • Auto-Discovery',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mode Selector Segmented Button
            SegmentedButton<_AddCloudMode>(
              segments: _AddCloudMode.values.map((mode) {
                return ButtonSegment<_AddCloudMode>(
                  value: mode,
                  icon: Icon(mode.icon, size: 16),
                  label: Text(
                    mode.label,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                );
              }).toList(),
              selected: {_mode},
              onSelectionChanged: (val) {
                PixelHaptics.tick();
                setState(() => _mode = val.first);
              },
            ),
            const SizedBox(height: 18),

            // Mode Body
            switch (_mode) {
              _AddCloudMode.oneTap => _buildOneTapCloudView(cs),
              _AddCloudMode.wifiServers => _buildWifiServersView(cs),
              _AddCloudMode.installedApps => _buildInstalledAppsView(cs),
              _AddCloudMode.manual => _buildManualSetupView(cs),
            },
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1-Tap Cloud View (Google Drive, OneDrive, Dropbox, Box)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildOneTapCloudView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Google Drive Hero Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF4285F4).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.add_to_drive_rounded,
                      color: Color(0xFF4285F4),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Google Drive',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4285F4).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Recommended',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF4285F4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Direct 1-tap sign in via your device Google Account',
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
              const SizedBox(height: 14),
              Text(
                'Seamlessly streams lossless FLAC, MP3, and WAV audio from your Google Drive without manual tokens or developer setup.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),

              // Sign in with Google Button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _isGoogleLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.account_circle_rounded, size: 20),
                  label: Text(
                    _isGoogleLoading
                        ? 'Connecting Google Account...'
                        : 'Continue with Google Account',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              if (_googleNotice != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: cs.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Google Sign-In Note',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cs.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _googleNotice!,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tip: You can also mount Google Drive directly via the Drive App button below with 0 configuration:',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Alternative: Mount via Google Drive App (Android SAF)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _mountViaSaf(
                    providerType: CloudProviderType.googleDrive,
                    defaultName: 'Google Drive App Mount',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.folder_shared_rounded, size: 18),
                  label: const Text(
                    'Mount via Google Drive App (Android SAF)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. Microsoft OneDrive Card
        _buildOAuthCard(
          cs: cs,
          type: CloudProviderType.oneDrive,
          accentColor: const Color(0xFF0078D4),
          title: 'Microsoft OneDrive',
          description:
              'Mount from the installed OneDrive app or sign in with your Microsoft 365 account.',
          primaryActionLabel: 'Mount via OneDrive App',
          onPrimaryAction: () => _mountViaSaf(
            providerType: CloudProviderType.oneDrive,
            defaultName: 'OneDrive App Mount',
          ),
          secondaryActionLabel: 'Sign in with Microsoft',
          onSecondaryAction: () async {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            await authService.launchOAuthAuthorization(
              provider: CloudProviderType.oneDrive,
              clientId: 'f9479b18-0524-460b-8d34-716b9b324d67',
            );
          },
        ),

        const SizedBox(height: 12),

        // 3. Dropbox & Box Cards
        _buildOAuthCard(
          cs: cs,
          type: CloudProviderType.dropbox,
          accentColor: const Color(0xFF0061FF),
          title: 'Dropbox',
          description:
              'Stream byte-range audio files directly from Dropbox cloud or installed app.',
          primaryActionLabel: 'Mount via Dropbox App',
          onPrimaryAction: () => _mountViaSaf(
            providerType: CloudProviderType.dropbox,
            defaultName: 'Dropbox App Mount',
          ),
          secondaryActionLabel: 'Sign in with Dropbox',
          onSecondaryAction: () async {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            await authService.launchOAuthAuthorization(
              provider: CloudProviderType.dropbox,
              clientId: 'dropbox_freebeat_client',
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
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accentColor.withValues(alpha: 0.15),
                child: Icon(type.icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onPrimaryAction,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    primaryActionLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onSecondaryAction,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    secondaryActionLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Wi-Fi Servers View (Jellyfin / Navidrome Auto-Discovery & Presets)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildWifiServersView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: cs.secondary.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.wifi_rounded, color: cs.secondary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto-Detect Local Media Servers',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Broadcasts UDP 7359 & scans home Wi-Fi for Jellyfin & Navidrome',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isScanningWifi ? null : _scanWifi,
                  icon: _isScanningWifi
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.radar_rounded, size: 18),
                  label: Text(
                    _isScanningWifi
                        ? 'Broadcasting & Scanning Wi-Fi...'
                        : 'Scan Wi-Fi for Media Servers',
                  ),
                ),
              ),
              if (_isScanningWifi) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Discovered Servers List
        if (_discoveredServers.isNotEmpty) ...[
          const Text(
            'Discovered on Local Network:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final server in _discoveredServers) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: server.type.accentColor.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        server.type.accentColor.withValues(alpha: 0.2),
                    child: Icon(
                      server.type.icon,
                      color: server.type.accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${server.url} • ${server.discoveredVia}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => _connectDiscoveredServer(server),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Connect'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
        ],

        // Quick Local Presets
        const Text(
          'Quick Host Presets:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.computer_rounded, size: 16),
              label: const Text('Host Jellyfin (10.0.2.2:8096)'),
              onPressed: () => _connectDiscoveredServer(
                const DiscoveredMediaServer(
                  id: 'preset_host_jf',
                  name: 'Host Jellyfin (10.0.2.2:8096)',
                  url: 'http://10.0.2.2:8096',
                  type: CloudProviderType.jellyfin,
                  discoveredVia: 'Host Preset',
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.surround_sound_rounded, size: 16),
              label: const Text('Host Navidrome (10.0.2.2:4533)'),
              onPressed: () => _connectDiscoveredServer(
                const DiscoveredMediaServer(
                  id: 'preset_host_navi',
                  name: 'Host Navidrome (10.0.2.2:4533)',
                  url: 'http://10.0.2.2:4533',
                  type: CloudProviderType.subsonic,
                  discoveredVia: 'Host Preset',
                ),
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.home_rounded, size: 16),
              label: const Text('Localhost (127.0.0.1:8096)'),
              onPressed: () => _connectDiscoveredServer(
                const DiscoveredMediaServer(
                  id: 'preset_local_jf',
                  name: 'Localhost Jellyfin (127.0.0.1:8096)',
                  url: 'http://127.0.0.1:8096',
                  type: CloudProviderType.jellyfin,
                  discoveredVia: 'Localhost Preset',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Installed Apps View (Universal SAF Mount)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildInstalledAppsView(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF3DDC84).withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3DDC84).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.phone_android_rounded,
                      color: Color(0xFF3DDC84),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mount Any Installed Cloud App',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Android Storage Access Framework (SAF)',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Connect directly to any cloud app installed on your phone without entering usernames or passwords. Tap below and choose your cloud provider from the Android file picker menu:',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),

              // Supported Cloud Apps Row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _appChip('Google Drive', Icons.add_to_drive_rounded, const Color(0xFF4285F4)),
                  _appChip('Microsoft OneDrive', Icons.cloud_queue_rounded, const Color(0xFF0078D4)),
                  _appChip('Dropbox', Icons.inventory_2_rounded, const Color(0xFF0061FF)),
                  _appChip('Nextcloud', Icons.language_rounded, const Color(0xFF0082C9)),
                  _appChip('MEGA', Icons.cloud_download_rounded, const Color(0xFFD9272E)),
                  _appChip('Proton Drive', Icons.shield_rounded, const Color(0xFF6D4AFF)),
                  _appChip('SD Card / Local Storage', Icons.sd_card_rounded, const Color(0xFF4CAF50)),
                ],
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  label: const Text(
                    'Pick Music from Installed Cloud App',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _appChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Manual Setup View (S3/R2, WebDAV, SFTP, SMB)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildManualSetupView(ColorScheme cs) {
    final manualTypes = [
      CloudProviderType.s3,
      CloudProviderType.webdav,
      CloudProviderType.sftp,
      CloudProviderType.smb,
      CloudProviderType.jellyfin,
      CloudProviderType.subsonic,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: manualTypes.map((type) {
            final selected = _manualType == type;
            return ChoiceChip(
              avatar: Icon(type.icon, size: 16),
              label: Text(type.displayName),
              selected: selected,
              onSelected: (_) {
                PixelHaptics.tick();
                setState(() {
                  _manualType = type;
                  _nameCtrl.text = type.displayName;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Account Display Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _endpointCtrl,
          decoration: const InputDecoration(
            labelText: 'Server URL / Endpoint / IP Address',
            border: OutlineInputBorder(),
          ),
        ),
        if (_manualType == CloudProviderType.s3) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _bucketCtrl,
            decoration: const InputDecoration(
              labelText: 'S3 / R2 Bucket Name',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _userCtrl,
          decoration: const InputDecoration(
            labelText: 'Username / Access Key ID',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _secretCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password / API Key / Secret Key (Keystore Encrypted)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isConnecting ? null : _submitManual,
            icon: const Icon(Icons.cloud_done_rounded),
            label: const Text('Mount Cloud Drive'),
          ),
        ),
      ],
    );
  }
}

