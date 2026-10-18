import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../providers/implementations/oauth_cloud_connectors.dart';
import '../../services/metadata/range_tag_parser.dart';
import '../metadata/artwork_extractor.dart';

/// Result object for Native Google Sign-In operations.
class NativeGoogleAuthResult {
  const NativeGoogleAuthResult({
    required this.isSuccess,
    this.isCancelled = false,
    this.isDeveloperConfigError = false,
    this.email,
    this.displayName,
    this.photoUrl,
    this.accessToken,
    this.idToken,
    this.errorMessage,
    this.account,
  });

  final bool isSuccess;
  final bool isCancelled;
  final bool isDeveloperConfigError;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final String? accessToken;
  final String? idToken;
  final String? errorMessage;
  final CloudAccount? account;
}

/// Native cloud authentication service providing 1-tap Google Sign-In,
/// 1-tap Android Storage Access Framework (SAF) integration for installed cloud apps,
/// and OAuth2 PKCE deep-link launch for Microsoft, Dropbox, and Box.
class NativeCloudAuthService {
  NativeCloudAuthService({
    GoogleSignIn? googleSignIn,
    MethodChannel channel = const MethodChannel('com.freebeat.app/dsp'),
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: <String>[
                'email',
                'https://www.googleapis.com/auth/drive.readonly',
              ],
            ),
        _channel = channel;

  final GoogleSignIn _googleSignIn;
  final MethodChannel _channel;

  /// High-fidelity and standard audio extensions recognized across Android DocumentsProvider and Google Drive.
  static const List<String> supportedAudioExtensions = [
    'mp3',
    'flac',
    'm4a',
    'wav',
    'aac',
    'ogg',
    'opus',
    'alac',
    'aiff',
    'aif',
    'wma',
    'asf',
    'ape',
    'dsd',
    'dsf',
    'dff',
    'mka',
  ];

  /// 1-Tap Google Drive Native Sign-In using the Android Google Account chooser modal.
  /// On devices with Google Play Services / Google accounts, this displays the native bottom sheet
  /// allowing users to tap their account with zero password or token entry.
  Future<NativeGoogleAuthResult> signInWithGoogleDrive() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return const NativeGoogleAuthResult(
          isSuccess: false,
          isCancelled: true,
        );
      }

      final auth = await account.authentication;
      final token = auth.accessToken ?? '';

      final cloudAccount = CloudAccount(
        id: 'gdrive_${account.id}',
        providerType: CloudProviderType.googleDrive,
        displayName: account.displayName != null && account.displayName!.isNotEmpty
            ? '${account.displayName} (Drive)'
            : 'Google Drive (${account.email})',
        endpointOrFolder: 'Google Drive • ${account.email}',
        usernameOrEmail: account.email,
        lastSyncedAt: DateTime.now(),
      );

      return NativeGoogleAuthResult(
        isSuccess: true,
        email: account.email,
        displayName: account.displayName,
        photoUrl: account.photoUrl,
        accessToken: token,
        idToken: auth.idToken,
        account: cloudAccount,
      );
    } catch (e) {
      final errStr = e.toString();
      final isCode10 = errStr.contains('10') ||
          errStr.contains('sign_in_failed') ||
          errStr.contains('DEVELOPER_ERROR') ||
          errStr.contains('25:10:');
      return NativeGoogleAuthResult(
        isSuccess: false,
        isDeveloperConfigError: isCode10,
        errorMessage: isCode10
            ? 'Google Play Services requires app registration (Code 10: Missing SHA-1 in Google Cloud Console).'
            : e.toString(),
      );
    }
  }

  /// Creates and connects a Google Drive CloudAccount directly.
  NativeGoogleAuthResult createGoogleDriveAccount({
    required String email,
    String? displayName,
    String? accessToken,
  }) {
    final cleanEmail = email.trim();
    final cleanName = displayName?.trim();
    final safeId = 'gdrive_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    final cloudAccount = CloudAccount(
      id: safeId,
      providerType: CloudProviderType.googleDrive,
      displayName: cleanName != null && cleanName.isNotEmpty
          ? '$cleanName (Drive)'
          : 'Google Drive ($cleanEmail)',
      endpointOrFolder: 'Google Drive • $cleanEmail',
      usernameOrEmail: cleanEmail,
      isConnected: true,
      lastSyncedAt: DateTime.now(),
    );

    return NativeGoogleAuthResult(
      isSuccess: true,
      email: cleanEmail,
      displayName: cleanName,
      accessToken: accessToken,
      account: cloudAccount,
    );
  }

  /// Proactively requests a silent token refresh for Google Drive via Google Play Services.
  Future<String?> getFreshGoogleAccessToken() async {
    try {
      var account = _googleSignIn.currentUser;
      account ??= await _googleSignIn.signInSilently();
      if (account != null) {
        final auth = await account.authentication;
        return auth.accessToken;
      }
    } catch (e) {
      debugPrint('Silent Google sign-in failed: $e');
    }
    return null;
  }

  /// Checks if an app is installed on the Android device.
  Future<bool> isAppInstalled(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAppInstalled',
        {'packageName': packageName},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launches an installed app directly. Returns false if not installed.
  Future<bool> launchApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'launchApp',
        {'packageName': packageName},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the installed app, or if not installed, opens the Google Play Store page directly.
  Future<bool> launchOrOpenPlayStore({
    required String packageName,
  }) async {
    final launched = await launchApp(packageName);
    if (launched) return true;

    // Not installed: redirect directly to Play Store
    final marketUri = Uri.parse('market://details?id=$packageName');
    final webPlayStoreUri =
        Uri.parse('https://play.google.com/store/apps/details?id=$packageName');

    try {
      if (await canLaunchUrl(marketUri)) {
        return await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      } else {
        return await launchUrl(webPlayStoreUri,
            mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      return await launchUrl(webPlayStoreUri,
          mode: LaunchMode.externalApplication);
    }
  }

  /// Retrieves the app's SHA-1 certificate fingerprint from the device package manager.
  Future<String> getAppSha1Fingerprint() async {
    try {
      final sha1 = await _channel.invokeMethod<String>('getAppSha1Fingerprint');
      return sha1 ?? 'UNAVAILABLE';
    } catch (_) {
      return 'UNAVAILABLE';
    }
  }

  /// Sign out from Google Drive
  Future<void> signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  GoogleSignInAccount? get currentGoogleUser => _googleSignIn.currentUser;

  /// 1-Tap OAuth Browser Redirect for Google Drive, Microsoft OneDrive, Dropbox, or Box.
  Future<bool> launchOAuthAuthorization({
    required CloudProviderType provider,
    required String clientId,
  }) async {
    final verifier = OAuth2PkceHelper.generateCodeVerifier();
    final challenge = OAuth2PkceHelper.generateCodeChallenge(verifier);
    final uri = OAuth2PkceHelper.buildAuthorizationUri(
      provider: provider,
      clientId: clientId,
      codeChallenge: challenge,
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static const MethodChannel _dspChannel = MethodChannel('com.freebeat.app/dsp');

  /// Persists Android SAF content:// read permission across app closures and system reboots.
  Future<bool> takePersistableUriPermission(String contentUri) async {
    try {
      final res = await _dspChannel.invokeMethod<bool>(
        'takePersistableUriPermission',
        {'uri': contentUri},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Scans directory tree natively using Android SAF / DocumentsContract or MediaStore.
  Future<List<Map<String, dynamic>>> scanDirectoryNative(String uriOrPath) async {
    try {
      final res = await _channel.invokeListMethod<dynamic>(
        'scanDirectory',
        {'uri': uriOrPath, 'path': uriOrPath},
      );
      if (res != null) {
        return res.map((m) => Map<String, dynamic>.from(m as Map)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Universal 1-Tap Mount for Any Installed Cloud App on Android (Google Drive,
  /// Microsoft OneDrive, Dropbox, Nextcloud, Mega, Proton Drive, Box, SD Card).
  /// Launches Android's DocumentsProvider where installed cloud sync apps are natively integrated.
  Future<List<Track>> pickFromInstalledCloudApp({
    required CloudAccount account,
    void Function(List<String> filenames)? onFilesSelected,
    void Function(int current, int total, Track? track)? onProgress,
    void Function(List<String> batchFilenames, int batchStartIndex, int totalFiles)? onBatchStarted,
    Future<void> Function(List<Track> batchTracks)? onBatchCompleted,
    int batchSize = 10,
  }) async {
    try {
      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: supportedAudioExtensions,
          allowMultiple: true,
          withData: false,
          withReadStream: false,
        );
      } catch (_) {
        // Fallback to FileType.any if custom throws on OEM Android picker
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: true,
          withData: false,
          withReadStream: false,
        );
      }

      if (result == null || result.files.isEmpty) return [];

      final allFiles = result.files.map((f) => SelectedFileEntry(
        name: f.name,
        path: f.path,
        identifier: f.identifier,
        size: f.size,
      )).toList();

      return await _processBatchAudioFiles(
        allFiles: allFiles,
        account: account,
        onFilesSelected: onFilesSelected,
        onProgress: onProgress,
        onBatchStarted: onBatchStarted,
        onBatchCompleted: onBatchCompleted,
        batchSize: batchSize,
      );
    } catch (_) {
      return [];
    }
  }

  /// 1-Tap Folder Import: Scans an entire music directory (e.g. from Google Drive or device)
  Future<List<Track>> pickFolder({
    required CloudAccount account,
    void Function(List<String> filenames)? onFilesSelected,
    void Function(int current, int total, Track? track)? onProgress,
    void Function(List<String> batchFilenames, int batchStartIndex, int totalFiles)? onBatchStarted,
    Future<void> Function(List<Track> batchTracks)? onBatchCompleted,
    int batchSize = 10,
  }) async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select ${account.displayName} Music Folder',
      );
      if (dirPath == null || dirPath.isEmpty) return [];

      final supportedAudioExts = {
        '.mp3',
        '.flac',
        '.m4a',
        '.wav',
        '.aac',
        '.ogg',
        '.opus',
        '.alac',
        '.aiff',
        '.aif',
        '.wma',
        '.asf',
        '.ape',
        '.dsd',
        '.dsf',
        '.dff',
        '.mka',
      };

      final allFiles = <SelectedFileEntry>[];

      // 1. Try native Directory scan (handles Android SAF tree URIs and Scoped Storage MediaStore)
      final nativeFiles = await scanDirectoryNative(dirPath);
      if (nativeFiles.isNotEmpty) {
        for (final m in nativeFiles) {
          final uri = m['uri'] as String?;
          final path = m['path'] as String?;
          final name = m['name'] as String? ?? 'Audio Track';
          final size = (m['size'] as num?)?.toInt() ?? 0;
          allFiles.add(SelectedFileEntry(
            name: name,
            path: path,
            identifier: uri,
            size: size,
          ));
        }
      }

      // 2. If native scan returned empty and local directory exists, scan dart:io Directory
      if (allFiles.isEmpty) {
        try {
          final dir = Directory(dirPath);
          if (dir.existsSync()) {
            final entities = dir.listSync(recursive: true, followLinks: false);
            for (final entity in entities) {
              if (entity is File) {
                final ext = p.extension(entity.path).toLowerCase();
                if (supportedAudioExts.contains(ext)) {
                  allFiles.add(SelectedFileEntry(
                    name: p.basename(entity.path),
                    path: entity.path,
                    identifier: null,
                    size: entity.existsSync() ? entity.lengthSync() : 0,
                  ));
                }
              }
            }
          }
        } catch (_) {}
      }

      if (allFiles.isEmpty) return [];

      return await _processBatchAudioFiles(
        allFiles: allFiles,
        account: account,
        onFilesSelected: onFilesSelected,
        onProgress: onProgress,
        onBatchStarted: onBatchStarted,
        onBatchCompleted: onBatchCompleted,
        batchSize: batchSize,
      );
    } catch (_) {
      return [];
    }
  }

  /// High-Performance Parallel Batch Audio Processing Engine:
  /// Concurrently parses batches of audio files without blocking the UI isolate.
  Future<List<Track>> _processBatchAudioFiles({
    required List<SelectedFileEntry> allFiles,
    required CloudAccount account,
    void Function(List<String> filenames)? onFilesSelected,
    void Function(int current, int total, Track? track)? onProgress,
    void Function(List<String> batchFilenames, int batchStartIndex, int totalFiles)? onBatchStarted,
    Future<void> Function(List<Track> batchTracks)? onBatchCompleted,
    int batchSize = 10,
  }) async {
    final totalFiles = allFiles.length;
    final filenames = allFiles.map((f) => f.name).toList();
    onFilesSelected?.call(filenames);

    final tracks = <Track>[];
    final supportedAudioExts = {
      '.mp3',
      '.flac',
      '.m4a',
      '.wav',
      '.aac',
      '.ogg',
      '.opus',
      '.alac',
      '.aiff',
      '.aif',
      '.wma',
      '.asf',
      '.ape',
      '.dsd',
      '.dsf',
      '.dff',
      '.mka',
    };

    onProgress?.call(0, totalFiles, null);

    // Process in smooth, parallel batches of 10 tracks
    for (int batchStart = 0; batchStart < totalFiles; batchStart += batchSize) {
      final batchEnd = math.min(batchStart + batchSize, totalFiles);
      final batchFiles = allFiles.sublist(batchStart, batchEnd);
      final batchFilenames = batchFiles.map((f) => f.name).toList();

      onBatchStarted?.call(batchFilenames, batchStart, totalFiles);

      // Concurrently parse all tracks in the batch
      final batchTracks = await Future.wait(
        batchFiles.asMap().entries.map((entry) async {
          final i = entry.key;
          final file = entry.value;
          final fileIndex = batchStart + i + 1;

          try {
            final name = file.name;
            final ext = p.extension(name).toLowerCase();
            if (ext.isNotEmpty && !supportedAudioExts.contains(ext)) {
              onProgress?.call(fileIndex, totalFiles, null);
              return null;
            }

            // Direct Cloud Streaming: Persist SAF URI permission so closing the app never revokes access
            String effectiveStreamUrl = '';
            if (file.identifier != null && file.identifier!.startsWith('content://')) {
              await takePersistableUriPermission(file.identifier!);
              effectiveStreamUrl = file.identifier!;
            } else if (file.path != null && !file.path!.contains('/cache/file_picker/')) {
              effectiveStreamUrl = file.path!;
            } else if (file.identifier != null && file.identifier!.isNotEmpty) {
              effectiveStreamUrl = file.identifier!;
            } else {
              effectiveStreamUrl = file.path ?? '';
            }

            if (effectiveStreamUrl.isEmpty) {
              onProgress?.call(fileIndex, totalFiles, null);
              return null;
            }

            File? localTagFile;
            if (file.path != null && File(file.path!).existsSync()) {
              localTagFile = File(file.path!);
            } else if (File(effectiveStreamUrl).existsSync()) {
              localTagFile = File(effectiveStreamUrl);
            }

            ParsedAudioMetadata parsed;
            if (localTagFile != null) {
              parsed = await RangeTagParser.parseLocalFile(localTagFile);
            } else {
              parsed = RangeTagParser.parseFromFilename(name);
            }

            final cleanTitle = (parsed.title != null && parsed.title!.isNotEmpty)
                ? parsed.title!
                : name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

            bool isInvalidArtist(String? s) {
              if (s == null) return true;
              final lower = s.trim().toLowerCase();
              return lower.isEmpty ||
                  lower == 'cloud artist' ||
                  lower == 'unknown artist' ||
                  lower == 'unknown' ||
                  lower.startsWith('com.') ||
                  lower.startsWith('org.') ||
                  lower.startsWith('net.') ||
                  lower.startsWith('content:') ||
                  lower.contains('.storage') ||
                  lower.contains('android') ||
                  lower.contains('documents') ||
                  lower.contains('providers') ||
                  lower.contains('/') ||
                  lower.contains(':') ||
                  lower.contains('local_storage');
            }

            String? artist = parsed.artist;
            String? album = parsed.album;

            if (isInvalidArtist(artist)) {
              final fnParsed = RangeTagParser.parseFromFilename(name);
              if (!isInvalidArtist(fnParsed.artist)) {
                artist = fnParsed.artist;
              }
            }

            if (isInvalidArtist(artist)) {
              final parentDir = p.dirname(effectiveStreamUrl);
              final parentName = p.basename(parentDir);
              final grandParentName = p.basename(p.dirname(parentDir));
              if (!isInvalidArtist(parentName) &&
                  parentName != '.' &&
                  parentName != 'Music' &&
                  parentName != 'Download') {
                if (!isInvalidArtist(grandParentName) &&
                    grandParentName != '.' &&
                    grandParentName != 'Music' &&
                    grandParentName != 'Download') {
                  artist = grandParentName;
                  if (!isInvalidArtist(parentName)) album ??= parentName;
                } else {
                  artist = parentName;
                }
              }
            }

            final effectiveArtist = (!isInvalidArtist(artist))
                ? artist!
                : (account.displayName.isNotEmpty ? account.displayName : 'Unknown Artist');

            final effectiveAlbum = (!isInvalidArtist(album) &&
                    album != 'Cloud Library')
                ? album!
                : (account.displayName.isNotEmpty ? account.displayName : 'Local Library');

            final trackId =
                'cloud_${name.hashCode.abs()}_${DateTime.now().microsecondsSinceEpoch}_$fileIndex';

            // High-Performance Embedded Artwork Extraction:
            // If RangeTagParser already read the embedded artwork bytes into memory, save directly to disk
            String? embeddedArt;
            if (parsed.embeddedArtworkBytes != null && parsed.embeddedArtworkBytes!.isNotEmpty) {
              embeddedArt = await ArtworkExtractor.saveArtworkBytes(
                parsed.embeddedArtworkBytes!,
                trackId,
              );
            } else if (localTagFile != null) {
              embeddedArt = await ArtworkExtractor.extractEmbeddedArtwork(
                localTagFile,
                trackId,
              );
            }

            // Fast fallback dominant color (0xFF1E293B) during import.
            // Avoids blocking CPU on heavy color-quantization across 50+ files during active import.
            final dominantColor = 0xFF1E293B;

            final newTrack = Track(
              id: trackId,
              accountId: account.id,
              providerType: account.providerType,
              remotePathOrId: effectiveStreamUrl,
              title: cleanTitle.isNotEmpty ? cleanTitle : 'Unknown Track',
              artist: effectiveArtist,
              album: effectiveAlbum,
              durationMs: parsed.durationMs ?? 210000,
              streamUrl: effectiveStreamUrl,
              artworkUrl: embeddedArt,
              codec: parsed.codec ??
                  (ext.isNotEmpty
                      ? ext.replaceAll('.', '').toUpperCase()
                      : 'FLAC'),
              bitDepth: parsed.bitDepth ?? 24,
              sampleRateHz: parsed.sampleRateHz ?? 96000,
              bitrateKbps: parsed.bitrateKbps ?? 1411,
              sizeBytes: file.size > 0 ? file.size : 25000000,
              dominantColorValue: dominantColor,
              isPinnedOffline: localTagFile != null,
              localCachePath: localTagFile?.path,
            );

            onProgress?.call(fileIndex, totalFiles, newTrack);
            return newTrack;
          } catch (_) {
            onProgress?.call(fileIndex, totalFiles, null);
            return null;
          }
        }),
      );

      final currentBatchTracks = batchTracks.whereType<Track>().toList();
      tracks.addAll(currentBatchTracks);

      if (currentBatchTracks.isNotEmpty && onBatchCompleted != null) {
        await onBatchCompleted(currentBatchTracks);
      }
    }

    return tracks;
  }
}

/// Generic file descriptor for both picked files and directory-scanned entries.
class SelectedFileEntry {
  const SelectedFileEntry({
    required this.name,
    this.path,
    this.identifier,
    this.size = 0,
  });

  final String name;
  final String? path;
  final String? identifier;
  final int size;
}
