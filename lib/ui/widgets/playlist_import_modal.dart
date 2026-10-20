import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../services/auth/native_cloud_auth_service.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/playlist/playlist_import_service.dart';
import '../../services/playlist/playlist_missing_tracks_sync_service.dart';
import '../../state/app_providers.dart';
import '../screens/playlist_details_screen.dart';
import 'material_you_album_cover.dart';

/// Opens the Material 3 Expressive Playlist Importer modal.
Future<void> showPlaylistImportModal(BuildContext context) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => const _PlaylistImportSheet(),
  );
}

class _PlaylistImportSheet extends ConsumerStatefulWidget {
  const _PlaylistImportSheet();

  @override
  ConsumerState<_PlaylistImportSheet> createState() =>
      _PlaylistImportSheetState();
}

class _PlaylistImportSheetState extends ConsumerState<_PlaylistImportSheet> {
  final TextEditingController _inputController = TextEditingController();
  final PlaylistImportService _importService = const PlaylistImportService();

  bool _isLoading = false;
  String? _errorMessage;
  PlaylistImportResult? _result;
  late TextEditingController _titleController;

  bool _syncMissingTracks = true;
  String? _selectedAccountId;
  bool _isConnectingGoogle = false;

  static const CloudAccount _defaultLocalStorageAccount = CloudAccount(
    id: 'device_storage_import',
    providerType: CloudProviderType.androidSaf,
    displayName: 'Device Storage (Offline)',
    endpointOrFolder: '/imported_music/',
    usernameOrEmail: 'Local Storage',
  );

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _connectGoogleDrive() async {
    PixelHaptics.tick();
    setState(() => _isConnectingGoogle = true);
    try {
      final authService = NativeCloudAuthService();
      final result = await authService.signInWithGoogleDrive();
      if (result.isSuccess && result.account != null) {
        final account = result.account!;
        final secrets = {'accessToken': result.accessToken ?? ''};
        await ref.read(cloudAccountsProvider.notifier).addAccount(account, secrets);
        setState(() {
          _selectedAccountId = account.id;
        });
        await PixelHaptics.hifiConfirm();
      }
    } catch (e) {
      setState(() => _errorMessage = 'Failed to connect Google Drive: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnectingGoogle = false);
      }
    }
  }

  Future<void> _pickM3uFile() async {
    PixelHaptics.tick();
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u8', 'm3u', 'txt', 'csv'],
      );
      if (res != null && res.files.single.path != null) {
        final file = File(res.files.single.path!);
        final content = await file.readAsString();
        _analyzeContent(content, fileName: res.files.single.name);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to read file: $e';
      });
    }
  }

  Future<void> _analyzeInput() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please paste a link, tracklist, or QR share payload.');
      return;
    }
    await _analyzeContent(text);
  }

  Future<void> _directImport({required bool syncMissing}) async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Please paste a link or tracklist first.');
      return;
    }
    await _analyzeContent(
      text,
      autoSync: syncMissing,
      directSave: !syncMissing,
    );
  }

  Future<void> _analyzeContent(
    String content, {
    String? fileName,
    bool autoSync = false,
    bool directSave = false,
  }) async {
    PixelHaptics.tick();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final allTracks = ref.read(tracksCatalogProvider);

    try {
      PlaylistImportResult res;
      final trimmed = content.trim();

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        // Spotify or Apple Music URL
        res = await _importService.importFromUrl(trimmed, allTracks);
      } else if (trimmed.startsWith('{') && trimmed.contains('"tracks"')) {
        // FreeBeat QR Code JSON share payload
        try {
          final decoded = jsonDecode(trimmed) as Map<String, dynamic>;
          final title = decoded['title']?.toString() ?? 'Shared Playlist';
          final desc = decoded['desc']?.toString() ?? 'Imported via QR share';
          final tracksList = decoded['tracks'] as List? ?? [];
          final rawText = tracksList.map((t) {
            if (t is Map) {
              return '${t['a'] ?? ''} - ${t['t'] ?? ''}';
            }
            return t.toString();
          }).join('\n');
          res = _importService.parseTextOrCsv(rawText, allTracks, defaultTitle: title);
          if (desc.isNotEmpty) {
            res = PlaylistImportResult(
              title: res.title,
              description: desc,
              matchedTracks: res.matchedTracks,
              unmatchedTrackNames: res.unmatchedTrackNames,
              totalParsed: res.totalParsed,
              sourceType: 'qr',
            );
          }
        } catch (_) {
          res = _importService.parseTextOrCsv(trimmed, allTracks);
        }
      } else if (trimmed.contains('#EXTM3U') || (fileName != null && fileName.endsWith('.m3u8'))) {
        // M3U / M3U8 content
        res = _importService.parseM3u(trimmed, allTracks);
      } else {
        // Plain text or CSV tracklist
        final defaultTitle = fileName != null
            ? fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '')
            : 'Imported Playlist';
        res = _importService.parseTextOrCsv(trimmed, allTracks, defaultTitle: defaultTitle);
      }

      setState(() {
        _result = res;
        _titleController.text = res.title;
        _isLoading = false;
      });
      await PixelHaptics.hifiConfirm();

      if (directSave) {
        if (res.matchedCount == 0) {
          setState(() {
            _errorMessage = 'No matching tracks found in library. Tap "Get Missing Tracks" to download them to cloud!';
          });
        } else {
          await _createAndSyncPlaylist(syncMissing: false);
        }
      } else if (autoSync) {
        await _createAndSyncPlaylist(syncMissing: res.missingTracks.isNotEmpty);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _createAndSyncPlaylist({required bool syncMissing}) async {
    if (_result == null) return;
    PixelHaptics.hifiConfirm();

    final title = _titleController.text.trim().isEmpty
        ? _result!.title
        : _titleController.text.trim();

    final playlist = await ref.read(playlistsProvider.notifier).createPlaylist(
          title,
          description: _result!.description,
          initialTrackIds: _result!.matchedTracks.map((t) => t.id).toList(),
        );

    final missing = _result!.missingTracks;

    if (syncMissing && missing.isNotEmpty) {
      final accounts = ref.read(cloudAccountsProvider);
      CloudAccount targetAccount;
      if (_selectedAccountId != null && _selectedAccountId != 'device_storage') {
        targetAccount = accounts.firstWhere(
          (a) => a.id == _selectedAccountId,
          orElse: () => _defaultLocalStorageAccount,
        );
      } else if (accounts.isNotEmpty && _selectedAccountId != 'device_storage') {
        targetAccount = accounts.first;
      } else {
        targetAccount = _defaultLocalStorageAccount;
      }

      unawaited(
        ref.read(playlistMissingTracksSyncProvider.notifier).startSync(
              missingTracks: missing,
              playlistId: playlist.id,
              playlistTitle: title,
              account: targetAccount,
            ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncMissing && missing.isNotEmpty
                ? 'Created "$title" • Syncing ${missing.length} missing songs in background...'
                : 'Created playlist "$title" with ${_result!.matchedCount} tracks!',
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

      // Navigate to the newly created playlist
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlaylistDetailsScreen(playlist: playlist),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final accounts = ref.watch(cloudAccountsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).padding.bottom + bottomInset + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.playlist_add_check_circle_rounded,
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
                      'Import Playlist',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Spotify, Apple Music, .M3U8, or CSV tracklists',
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
          const SizedBox(height: 18),

          if (_result == null) ...[
            // Input Mode: Paste link or text
            TextField(
              controller: _inputController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'Paste a public Spotify or Apple Music link, or enter a list of songs:\nArtist - Song Title\nSong Title, Artist\n#EXTM3U ...',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: cs.error,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _pickM3uFile,
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Pick File'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isLoading ? null : _analyzeInput,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.manage_search_rounded, size: 18),
                    label: Text(_isLoading ? 'Matching...' : 'Match Tracks'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : () => _directImport(syncMissing: false),
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Save Playlist'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : () => _directImport(syncMissing: true),
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: const Text('Get Missing Tracks'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Result View
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Playlist Title',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            // Match stat chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _result!.matchedCount > 0
                    ? cs.primaryContainer.withValues(alpha: 0.6)
                    : cs.errorContainer.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    _result!.matchedCount > 0
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 18,
                    color: _result!.matchedCount > 0
                        ? cs.primary
                        : cs.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_result!.matchedCount} of ${_result!.totalParsed} tracks matched (${_result!.matchPercentage.toStringAsFixed(0)}%) in your library',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _result!.matchedCount > 0
                            ? cs.onPrimaryContainer
                            : cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // List of matched tracks
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _result!.matchedTracks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final track = _result!.matchedTracks[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: MaterialYouAlbumCover(
                      track: track,
                      size: 40,
                      borderRadius: 10,
                      showQualityBadge: false,
                      showSourceBadge: false,
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(
                      Icons.check_rounded,
                      color: Colors.green,
                      size: 20,
                    ),
                  );
                },
              ),
            ),

            if (_result!.missingTracks.isNotEmpty) ...[
              const SizedBox(height: 10),
              // Cloud Sync Missing Songs Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.28),
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.cloud_sync_rounded,
                              size: 19, color: cs.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sync Missing Songs to Cloud',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${_result!.missingTracks.length} tracks will be downloaded & saved',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _syncMissingTracks,
                          onChanged: (val) {
                            PixelHaptics.tick();
                            setState(() => _syncMissingTracks = val);
                          },
                        ),
                      ],
                    ),
                    if (_syncMissingTracks) ...[
                      const SizedBox(height: 10),
                      Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 10),
                      Text(
                        'Cloud Destination',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (accounts.isEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _isConnectingGoogle ? null : _connectGoogleDrive,
                                icon: _isConnectingGoogle
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.add_to_drive_rounded, size: 16),
                                label: const Text('Connect Google Drive',
                                    style: TextStyle(fontSize: 11.5)),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () {
                                PixelHaptics.tick();
                                setState(() => _selectedAccountId = 'device_storage');
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              child: const Text('Device Storage',
                                  style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: (_selectedAccountId != null &&
                                      (accounts.any((a) => a.id == _selectedAccountId) ||
                                          _selectedAccountId == 'device_storage'))
                                  ? _selectedAccountId
                                  : accounts.first.id,
                              items: [
                                for (final acc in accounts)
                                  DropdownMenuItem(
                                    value: acc.id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          acc.providerType.icon,
                                          size: 18,
                                          color: acc.providerType.accentColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${acc.displayName} (${acc.providerType.displayName})',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const DropdownMenuItem(
                                  value: 'device_storage',
                                  child: Row(
                                    children: [
                                      Icon(Icons.phone_android_rounded,
                                          size: 18, color: Colors.teal),
                                      SizedBox(width: 8),
                                      Text(
                                        'Device Storage (No Cloud / Offline)',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  PixelHaptics.tick();
                                  setState(() => _selectedAccountId = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  dense: true,
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${_result!.missingTracks.length} tracks missing from library',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  children: [
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _result!.missingTracks.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '• ${_result!.missingTracks[i].displayName}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _result = null;
                      _errorMessage = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Back'),
                ),
                const SizedBox(width: 8),
                if (_result!.matchedCount > 0) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _createAndSyncPlaylist(syncMissing: false),
                      icon: const Icon(Icons.playlist_add_rounded, size: 16),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      label: Text(
                        'Save Playlist (${_result!.matchedCount})',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 1,
                  child: FilledButton.icon(
                    onPressed: (_result!.matchedCount > 0 || _result!.missingTracks.isNotEmpty)
                        ? () => _createAndSyncPlaylist(
                            syncMissing: _syncMissingTracks && _result!.missingTracks.isNotEmpty)
                        : null,
                    icon: Icon(
                      _syncMissingTracks && _result!.missingTracks.isNotEmpty
                          ? Icons.cloud_download_rounded
                          : Icons.playlist_add_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _syncMissingTracks && _result!.missingTracks.isNotEmpty
                          ? 'Get Missing Tracks (${_result!.totalParsed})'
                          : 'Save Playlist (${_result!.matchedCount})',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
