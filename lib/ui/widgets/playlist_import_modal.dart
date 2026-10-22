import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/playlist.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../services/playlist/playlist_import_service.dart';
import '../../services/playlist/playlist_missing_tracks_sync_service.dart';
import '../../state/app_providers.dart';
import '../screens/playlist_details_screen.dart';
import 'material_you_album_cover.dart';
import 'platform_app_icons.dart';

/// Opens the Material 3 Expressive Playlist Importer modal.
Future<void> showPlaylistImportModal(BuildContext context, {Playlist? targetPlaylist}) {
  PixelHaptics.sheetExpand();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PlaylistImportSheet(targetPlaylist: targetPlaylist),
  );
}

enum _CloudAuthChoice {
  signIn,
  deviceStorage,
  cancel,
}

class _PlaylistImportSheet extends ConsumerStatefulWidget {
  const _PlaylistImportSheet({this.targetPlaylist});
  final Playlist? targetPlaylist;

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
  String? _detectedSourceUrl;

  bool _syncMissingTracks = true;
  String? _selectedAccountId;
  bool _isConnectingGoogle = false;
  Set<String> _authenticatedAccountIds = {};

  static const CloudAccount _defaultLocalStorageAccount = CloudAccount(
    id: 'device_storage_import',
    providerType: CloudProviderType.androidSaf,
    displayName: 'Device Storage (FreeBeat Music)',
    endpointOrFolder: '/FreeBeat Music/',
    usernameOrEmail: 'Local Storage',
  );

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.targetPlaylist?.title ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAuthenticatedAccounts();
    });
  }

  Future<void> _refreshAuthenticatedAccounts() async {
    final accounts = ref.read(cloudAccountsProvider);
    final credStore = ref.read(credentialStoreProvider);
    final authed = <String>{};
    for (final acc in accounts) {
      if (acc.providerType == CloudProviderType.androidSaf) {
        authed.add(acc.id);
      } else {
        final s = await credStore.readSecrets(acc.id);
        if ((s['accessToken'] ?? '').isNotEmpty ||
            (s['password'] ?? '').isNotEmpty ||
            (s['accessKeyId'] ?? '').isNotEmpty) {
          authed.add(acc.id);
        }
      }
    }
    if (mounted) {
      setState(() {
        _authenticatedAccountIds = authed;
        if (_selectedAccountId == null ||
            (_selectedAccountId != 'device_storage' && !_authenticatedAccountIds.contains(_selectedAccountId))) {
          _selectedAccountId = _authenticatedAccountIds.isNotEmpty ? _authenticatedAccountIds.first : 'device_storage';
        }
      });
    }
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
      final authService = ref.read(nativeCloudAuthServiceProvider);
      final result = await authService.signInWithGoogleDrive();
      if (result.isSuccess && result.account != null) {
        final account = result.account!;
        final secrets = {'accessToken': result.accessToken ?? ''};
        await ref.read(cloudAccountsProvider.notifier).addAccount(account, secrets);
        if (mounted) {
          setState(() {
            _selectedAccountId = account.id;
            _authenticatedAccountIds.add(account.id);
          });
        }
        await PixelHaptics.hifiConfirm();
      } else if (!result.isCancelled) {
        if (mounted) {
          await _showGoogleDriveAlternativeDialog(
            error: result.errorMessage ?? 'Google Play Services requires app registration (Code 10).',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to connect Google Drive: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isConnectingGoogle = false);
      }
    }
  }

  Future<void> _showGoogleDriveAlternativeDialog({required String error}) async {
    final cs = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: CircleAvatar(
          radius: 24,
          backgroundColor: cs.errorContainer,
          child: Icon(Icons.cloud_off_rounded, color: cs.error, size: 28),
        ),
        title: const Text(
          'Google Drive Sign-In Error',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Google Play Services native sign-in is unavailable on this device:\n$error\n\n'
              'Because FreeBeat is installed directly as an APK outside Google Play, Google requires SHA-1 registration in Google Cloud Console for 1-tap sign-in.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: Colors.green),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Recommended: Use Device Storage to import tracks directly into your Music folder (/storage/emulated/0/Music/<PlaylistName>/).',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                setState(() => _selectedAccountId = 'device_storage');
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Switched to Device Storage (Music folder). Ready to import!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.phone_android_rounded, size: 16),
            label: const Text('Use Device Storage'),
          ),
        ],
      ),
    );
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
        _detectedSourceUrl = trimmed;
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

      if (res.totalParsed == 0) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'No tracks could be found in this playlist. Please check that the playlist link is public.';
        });
        return;
      }

      setState(() {
        _result = res;
        _titleController.text = widget.targetPlaylist?.title ?? res.title;
        _isLoading = false;
      });
      await PixelHaptics.hifiConfirm();

      if (directSave) {
        if (res.matchedCount == 0) {
          setState(() {
            _errorMessage =
                'No matching tracks found in library. Tap "Get Missing Tracks" to download them to cloud!';
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

    Playlist target;
    if (widget.targetPlaylist != null) {
      target = widget.targetPlaylist!;
      if (_detectedSourceUrl != null && target.syncSourceUrl == null) {
        await ref
            .read(playlistsProvider.notifier)
            .updatePlaylistSyncSource(target.id, _detectedSourceUrl);
      }
      // Append matched tracks to existing playlist
      if (_result!.matchedTracks.isNotEmpty) {
        await ref.read(playlistsProvider.notifier).addTracksToPlaylist(
          target.id,
          _result!.matchedTracks.map((t) => t.id).toList(),
        );
      }
    } else {
      final title = _titleController.text.trim().isEmpty
          ? _result!.title
          : _titleController.text.trim();

      final playlistCover = _result!.artworkUrl ??
          _result!.missingTracks
              .firstWhere(
                (m) => m.preferredArtworkUrl != null && m.preferredArtworkUrl!.isNotEmpty,
                orElse: () => const MissingTrackItem(title: '', artist: ''),
              )
              .preferredArtworkUrl ??
          (_result!.matchedTracks.isNotEmpty ? _result!.matchedTracks.first.artworkUrl : null);

      target = await ref.read(playlistsProvider.notifier).createPlaylist(
            title,
            description: _result!.description,
            initialTrackIds: _result!.matchedTracks.map((t) => t.id).toList(),
            syncSourceUrl: _detectedSourceUrl,
            lastSyncedAt: _detectedSourceUrl != null ? DateTime.now() : null,
            customArtworkUrl: playlistCover,
          );
    }

    final missing = _result!.missingTracks;

    if (syncMissing && missing.isNotEmpty) {
      final accounts = ref.read(cloudAccountsProvider);
      final remoteAccounts = accounts
          .where((a) =>
              a.providerType != CloudProviderType.androidSaf &&
              a.providerType != CloudProviderType.demoCloud)
          .toList();

      CloudAccount targetAccount;
      if (_selectedAccountId == 'device_storage') {
        targetAccount = _defaultLocalStorageAccount;
      } else if (_selectedAccountId != null) {
        targetAccount = accounts.firstWhere(
          (a) => a.id == _selectedAccountId,
          orElse: () => _defaultLocalStorageAccount,
        );
      } else {
        // Autodetect: use authenticated remote cloud account if credentials exist,
        // otherwise default to device local music storage.
        final credStore = ref.read(credentialStoreProvider);
        CloudAccount? authedAccount;
        for (final ra in remoteAccounts) {
          final s = await credStore.readSecrets(ra.id);
          if ((s['accessToken'] ?? '').isNotEmpty ||
              (s['password'] ?? '').isNotEmpty ||
              (s['accessKeyId'] ?? '').isNotEmpty) {
            authedAccount = ra;
            break;
          }
        }
        targetAccount = authedAccount ??
            (remoteAccounts.isNotEmpty ? remoteAccounts.first : _defaultLocalStorageAccount);
      }

      bool fallbackApproved = false;
      final isRemote = targetAccount.providerType != CloudProviderType.androidSaf &&
          targetAccount.providerType != CloudProviderType.demoCloud;

      if (isRemote) {
        final credStore = ref.read(credentialStoreProvider);
        var secrets = await credStore.readSecrets(targetAccount.id);
        var token = secrets['accessToken'] ?? '';

        if (token.isEmpty && targetAccount.providerType == CloudProviderType.googleDrive) {
          try {
            final authService = ref.read(nativeCloudAuthServiceProvider);
            final fresh = await authService.getFreshGoogleAccessToken();
            if (fresh != null && fresh.isNotEmpty) {
              token = fresh;
              secrets = {'accessToken': fresh};
              await credStore.saveSecrets(targetAccount.id, secrets);
            }
          } catch (_) {}
        }

        final hasCredentials = token.isNotEmpty ||
            (secrets['password'] ?? '').isNotEmpty ||
            (secrets['accessKeyId'] ?? '').isNotEmpty;

        if (!hasCredentials) {
          // PROMPT THE USER BEFORE DOWNLOADING TO LOCAL STORAGE!
          if (!mounted) return;
          final choice = await _showCloudAuthRequiredDialog(context, targetAccount);
          if (choice == _CloudAuthChoice.cancel || choice == null) {
            return;
          } else if (choice == _CloudAuthChoice.signIn) {
            await _connectGoogleDrive();
            if (_selectedAccountId == 'device_storage') {
              targetAccount = _defaultLocalStorageAccount;
              fallbackApproved = true;
            } else {
              final updatedSecrets = await credStore.readSecrets(targetAccount.id);
              if ((updatedSecrets['accessToken'] ?? '').isEmpty) {
                if (!mounted) return;
                final switchChoice = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    title: const Text('Google Sign-In Unsuccessful', style: TextStyle(fontWeight: FontWeight.w800)),
                    content: const Text(
                      'Google Drive could not be authenticated on this device.\n\n'
                      'Would you like to save these tracks to your device\'s Music folder instead (/storage/emulated/0/Music/<PlaylistName>/)?'
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.phone_android_rounded, size: 16),
                        label: const Text('Save to Device Storage'),
                      ),
                    ],
                  ),
                );
                if (switchChoice == true) {
                  if (mounted) setState(() => _selectedAccountId = 'device_storage');
                  targetAccount = _defaultLocalStorageAccount;
                  fallbackApproved = true;
                } else {
                  return;
                }
              }
            }
          } else if (choice == _CloudAuthChoice.deviceStorage) {
            targetAccount = _defaultLocalStorageAccount;
            fallbackApproved = true;
          }
        }
      }

      unawaited(
        ref.read(playlistMissingTracksSyncProvider.notifier).startSync(
              missingTracks: missing,
              playlistId: target.id,
              playlistTitle: target.title,
              account: targetAccount,
              fallbackToLocalStorageApproved: fallbackApproved,
            ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
      final title = target.title;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.targetPlaylist != null
                ? (syncMissing && missing.isNotEmpty
                    ? 'Syncing ${missing.length} missing songs into "$title" to cloud...'
                    : 'Added ${_result!.matchedCount} songs to "$title"')
                : (syncMissing && missing.isNotEmpty
                    ? 'Created "$title" • Downloading & syncing ${missing.length} missing songs in parallel...'
                    : 'Created playlist "$title" with ${_result!.matchedCount} tracks!'),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );

      // Only push new screen if this was creating a brand new playlist
      if (widget.targetPlaylist == null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlaylistDetailsScreen(playlist: target),
          ),
        );
      }
    }
  }

  Future<_CloudAuthChoice?> _showCloudAuthRequiredDialog(
    BuildContext context,
    CloudAccount account, {
    String? reason,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<_CloudAuthChoice>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        icon: CircleAvatar(
          radius: 24,
          backgroundColor: cs.errorContainer,
          child: Icon(Icons.cloud_off_rounded, color: cs.error, size: 28),
        ),
        title: const Text(
          'Cloud Authentication Required',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reason ??
                  'FreeBeat cannot upload to ${account.displayName} because you are not currently signed in or your session has expired.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Would you like to sign in to ${account.displayName}, or download tracks to your device\'s Music folder?',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () {
              PixelHaptics.tick();
              Navigator.of(ctx).pop(_CloudAuthChoice.cancel);
            },
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () {
              PixelHaptics.tick();
              Navigator.of(ctx).pop(_CloudAuthChoice.signIn);
            },
            icon: Icon(account.providerType.icon, size: 16),
            label: Text('Sign In to ${account.displayName}'),
          ),
          FilledButton.icon(
            onPressed: () {
              PixelHaptics.tick();
              Navigator.of(ctx).pop(_CloudAuthChoice.deviceStorage);
            },
            icon: const Icon(Icons.phone_android_rounded, size: 16),
            label: const Text('Save to Device Storage'),
          ),
        ],
      ),
    );
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
                      widget.targetPlaylist != null ? 'Import Songs into Playlist' : 'Import Playlist',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      widget.targetPlaylist != null
                          ? 'Adding songs to "${widget.targetPlaylist!.title}"'
                          : 'Tracks, albums, or playlists from Spotify, Apple Music, YouTube',
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
            // Platform Badges
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const _PlatformPill(
                    label: 'Spotify',
                    color: Color(0xFF1DB954),
                    icon: SpotifyAppIcon(size: 16),
                  ),
                  const SizedBox(width: 6),
                  const _PlatformPill(
                    label: 'Apple Music',
                    color: Color(0xFFFC3C44),
                    icon: AppleMusicAppIcon(size: 16),
                  ),
                  const SizedBox(width: 6),
                  const _PlatformPill(
                    label: 'YouTube & Music',
                    color: Color(0xFFFF0000),
                    icon: YouTubeAppIcon(size: 16),
                  ),
                  const SizedBox(width: 6),
                  _PlatformPill(
                    label: '.M3U8 / Text',
                    color: cs.primary,
                    icon: Icon(Icons.queue_music_rounded, size: 14, color: cs.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Input Mode: Paste link or text
            TextField(
              controller: _inputController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'Paste a Spotify, Apple Music, or YouTube link (individual track, full album, or playlist), or enter tracks:\nArtist - Song Title\nSong Title, Artist\n#EXTM3U ...',
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
                    label: const Text('Pick .M3U File'),
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
                    label: Text(widget.targetPlaylist != null ? 'Add Matched' : 'Save Playlist'),
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
                    label: Text(widget.targetPlaylist != null ? 'Sync & Add Missing' : 'Get Missing Tracks'),
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
            if (widget.targetPlaylist != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(Icons.playlist_play_rounded, size: 22, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Adding to Playlist',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            widget.targetPlaylist!.title,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
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
                      _result!.totalParsed == 1
                          ? (_result!.matchedCount > 0
                              ? 'Track is already in your library'
                              : 'Ready to import and download track to your library')
                          : '${_result!.matchedCount} of ${_result!.totalParsed} tracks matched (${_result!.matchPercentage.toStringAsFixed(0)}%) in your library',
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
                                  : (_authenticatedAccountIds.isNotEmpty
                                      ? _authenticatedAccountIds.first
                                      : 'device_storage'),
                              items: [
                                for (final acc in accounts)
                                  DropdownMenuItem(
                                    value: acc.id,
                                    child: Row(
                                      children: [
                                        Icon(
                                          acc.providerType.icon,
                                          size: 18,
                                          color: _authenticatedAccountIds.contains(acc.id)
                                              ? acc.providerType.accentColor
                                              : cs.outline,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _authenticatedAccountIds.contains(acc.id)
                                                ? '${acc.displayName} (${acc.providerType.displayName})'
                                                : '${acc.displayName} (Sign-In Required)',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: _authenticatedAccountIds.contains(acc.id)
                                                  ? null
                                                  : cs.onSurfaceVariant.withValues(alpha: 0.6),
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
                                      Icon(Icons.folder_special_rounded,
                                          size: 18, color: Colors.teal),
                                      SizedBox(width: 8),
                                      Text(
                                        'Device Storage (Music Folder)',
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
                        if (accounts.every((a) =>
                            a.providerType == CloudProviderType.androidSaf ||
                            a.providerType == CloudProviderType.demoCloud)) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.cloud_outlined, size: 14, color: cs.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Tip: Connect Google Drive to save to cloud & stream on demand.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _isConnectingGoogle ? null : _connectGoogleDrive,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                child: _isConnectingGoogle
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Connect', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ],
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
                        widget.targetPlaylist != null
                            ? 'Add Matched (${_result!.matchedCount})'
                            : 'Save Playlist (${_result!.matchedCount})',
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
                          ? (widget.targetPlaylist != null
                              ? 'Sync Missing & Add (${_result!.totalParsed})'
                              : (_result!.totalParsed == 1
                                  ? 'Import Track to Library'
                                  : 'Get Missing Tracks (${_result!.totalParsed})'))
                          : (widget.targetPlaylist != null
                              ? 'Add to Playlist (${_result!.matchedCount})'
                              : (_result!.totalParsed == 1
                                  ? 'Save Track to Library'
                                  : 'Save Playlist (${_result!.matchedCount})')),
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

class _PlatformPill extends StatelessWidget {
  const _PlatformPill({
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            icon!,
            const SizedBox(width: 5),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
