import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../providers/implementations/network_and_saf_connectors.dart';
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Clouds & Hi-Fi Quality',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: cs.onSurface,
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
            FilledButton.icon(
              onPressed: () => _showAddCloudWizard(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Cloud'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 2. Connected Cloud Accounts List
        for (final acc in accounts) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: acc.providerType.accentColor.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      acc.providerType.accentColor.withValues(alpha: 0.2),
                  child: Icon(
                    acc.providerType.icon,
                    color: acc.providerType.accentColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acc.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${acc.providerType.displayName} • ${acc.endpointOrFolder}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Disconnect Cloud',
                  onPressed: () {
                    ref
                        .read(cloudAccountsProvider.notifier)
                        .removeAccount(acc.id);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

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

class _AddCloudWizardSheet extends ConsumerStatefulWidget {
  const _AddCloudWizardSheet();

  @override
  ConsumerState<_AddCloudWizardSheet> createState() =>
      _AddCloudWizardSheetState();
}

class _AddCloudWizardSheetState extends ConsumerState<_AddCloudWizardSheet> {
  CloudProviderType _selectedType = CloudProviderType.googleDrive;
  final _nameCtrl = TextEditingController(text: 'My Cloud Music');
  final _endpointCtrl =
      TextEditingController(text: 'https://cloud.example.com');
  final _userCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _userCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Connect Cloud or Media Server',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CloudProviderType.values
                  .where((t) => t != CloudProviderType.demoCloud)
                  .map((type) {
                final selected = _selectedType == type;
                return ChoiceChip(
                  avatar: Icon(type.icon, size: 16),
                  label: Text(type.displayName),
                  selected: selected,
                  onSelected: (_) {
                    PixelHaptics.tick();
                    setState(() {
                      _selectedType = type;
                      _nameCtrl.text = type.displayName;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text(
              _selectedType.subtitle,
              style: TextStyle(
                fontSize: 12.5,
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
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
                labelText: 'Server URL / Bucket / Cloud Folder Path',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                labelText: 'Username / Access Key ID / OAuth Client ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _secretCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password / OAuth Token / S3 Secret Key (Keystore)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_selectedType == CloudProviderType.androidSaf)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final account = CloudAccount(
                          id: 'saf_${DateTime.now().millisecondsSinceEpoch}',
                          providerType: CloudProviderType.androidSaf,
                          displayName: _nameCtrl.text.trim(),
                          endpointOrFolder: 'Android SAF Mount',
                        );
                        final saf = AndroidSafConnector();
                        final tracks = await saf.pickSafAudioFiles(account);
                        await ref
                            .read(cloudAccountsProvider.notifier)
                            .addAccount(account, {});
                        await ref
                            .read(tracksCatalogProvider.notifier)
                            .addIndexedTracks(tracks);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.folder_open_rounded),
                      label: const Text('Pick Phone Cloud Files'),
                    ),
                  ),
                if (_selectedType == CloudProviderType.androidSaf)
                  const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final account = CloudAccount(
                        id: 'acc_${DateTime.now().millisecondsSinceEpoch}',
                        providerType: _selectedType,
                        displayName: _nameCtrl.text.trim().isEmpty
                            ? _selectedType.displayName
                            : _nameCtrl.text.trim(),
                        endpointOrFolder: _endpointCtrl.text.trim(),
                        usernameOrEmail: _userCtrl.text.trim(),
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
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.cloud_done_rounded),
                    label: const Text('Mount Cloud Drive'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
