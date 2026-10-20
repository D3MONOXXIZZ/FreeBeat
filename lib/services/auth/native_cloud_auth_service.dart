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
                'https://www.googleapis.com/auth/drive.file',
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

  /// Opens the native Android Storage Access Framework directory picker
  /// (ACTION_OPEN_DOCUMENT_TREE), returning the tree URI and folder display name.
  Future<({String uri, String name})?> pickDirectoryNative() async {
    try {
      final res = await _channel.invokeMethod<dynamic>('pickDirectory');
      if (res != null && res is Map && res['uri'] != null) {
        return (
          uri: res['uri'] as String,
          name: res['name'] as String? ?? 'Music Folder',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Opens the native Android Storage Access Framework multi-file audio picker
  /// (ACTION_OPEN_DOCUMENT), returning selected audio content:// URIs, display names,
  /// and file sizes without copying any bytes to local cache.
  Future<List<({String uri, String name, int size})>?> pickAudioFilesNative() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('pickAudioFiles');
      if (res != null) {
        final list = <({String uri, String name, int size})>[];
        for (final item in res) {
          if (item is Map) {
            final uri = item['uri'] as String?;
            if (uri != null && uri.isNotEmpty) {
              list.add((
                uri: uri,
                name: item['name'] as String? ?? 'Audio Track',
                size: (item['size'] as num?)?.toInt() ?? 0,
              ));
            }
          }
        }
        return list;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Queries the total size in bytes of Android's app cache directory.
  Future<int> getNativeAppCacheSize() async {
    try {
      final size = await _channel.invokeMethod<int>('getAppCacheSize');
      return size ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Reclaims disk space by clearing Android's internal and external app cache directories.
  Future<int> clearNativeAppCache() async {
    try {
      final reclaimed = await _channel.invokeMethod<int>('clearAppCache');
      return reclaimed ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Reads initial header bytes (up to 128 KB) from a content:// URI.
  Future<Uint8List?> readContentUriHeaderBytes(String uri, {int maxBytes = 131072}) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'readContentUriHeaderBytes',
        {'uri': uri, 'maxBytes': maxBytes},
      );
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Extracts native audio metadata and embedded picture bytes using Android's MediaMetadataRetriever.
  Future<Map<String, dynamic>?> extractAudioMetadataNative(String uriOrPath) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'extractAudioMetadata',
        {'uri': uriOrPath, 'path': uriOrPath},
      );
      return res;
    } catch (_) {
      return null;
    }
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
      List<SelectedFileEntry> allFiles = [];

      // 1. High-Performance Zero-Copy Android SAF Picker (copies 0 MB to cache)
      if (Platform.isAndroid) {
        final nativeFiles = await pickAudioFilesNative();
        if (nativeFiles != null) {
          if (nativeFiles.isEmpty) {
            // User cancelled picker
            return [];
          }
          allFiles = nativeFiles.map((f) => SelectedFileEntry(
            name: f.name,
            path: null,
            identifier: f.uri,
            size: f.size,
          )).toList();
        }
      }

      // 2. Fallback to FilePicker if not on Android or native picker returned null
      if (allFiles.isEmpty) {
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

        allFiles = result.files.map((f) => SelectedFileEntry(
          name: f.name,
          path: f.path,
          identifier: f.identifier,
          size: f.size,
        )).toList();
      }

      final imported = await _processBatchAudioFiles(
        allFiles: allFiles,
        account: account,
        onFilesSelected: onFilesSelected,
        onProgress: onProgress,
        onBatchStarted: onBatchStarted,
        onBatchCompleted: onBatchCompleted,
        batchSize: batchSize,
      );

      // Immediately purge temporary picker cache copies
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      return imported;
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
      String? targetDirUriOrPath;

      // 1. On Android, prioritize the native SAF tree directory picker
      // (ACTION_OPEN_DOCUMENT_TREE) so Google Drive, cloud providers, and SD cards
      // provide their true tree URI without returning "/" or failing scoped storage.
      if (Platform.isAndroid) {
        final nativePicked = await pickDirectoryNative();
        if (nativePicked != null && nativePicked.uri.isNotEmpty) {
          targetDirUriOrPath = nativePicked.uri;
        } else if (nativePicked == null) {
          // User intentionally cancelled the system picker
          return [];
        }
      }

      // 2. Fallback to FilePicker if not on Android or native picker wasn't used
      if (targetDirUriOrPath == null) {
        final dirPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Select ${account.displayName} Music Folder',
        );
        if (dirPath == null || dirPath.trim().isEmpty) return [];
        final trimmed = dirPath.trim();
        // Guard against selecting device root, which would query all files
        if (trimmed == '/' ||
            trimmed == '/storage' ||
            trimmed == '/storage/emulated' ||
            trimmed == '/storage/emulated/0') {
          return [];
        }
        targetDirUriOrPath = trimmed;
      }

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
      final nativeFiles = await scanDirectoryNative(targetDirUriOrPath);
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
            scannedTitle: m['title'] as String?,
            scannedArtist: m['artist'] as String?,
            scannedAlbum: m['album'] as String?,
            scannedDurationMs: (m['durationMs'] as num?)?.toInt(),
            scannedAlbumArtUri: m['albumArtUri'] as String?,
          ));
        }
      }

      // 2. If native scan returned empty and local directory exists, scan dart:io Directory
      if (allFiles.isEmpty && !targetDirUriOrPath.startsWith('content://')) {
        try {
          final dir = Directory(targetDirUriOrPath);
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

            // 1. Try native MediaMetadataRetriever (API 10+ handles both SAF content:// URIs and local files directly)
            Map<String, dynamic>? nativeMeta;
            if (Platform.isAndroid) {
              nativeMeta = await extractAudioMetadataNative(effectiveStreamUrl);
            }

            String? rawTitle = file.scannedTitle ?? nativeMeta?['title'] as String?;
            String? rawArtist = file.scannedArtist ?? nativeMeta?['artist'] as String?;
            String? rawAlbum = file.scannedAlbum ?? nativeMeta?['album'] as String?;
            int? nativeDurationMs = file.scannedDurationMs ?? (nativeMeta?['durationMs'] as num?)?.toInt();
            int? nativeBitrateKbps = (nativeMeta?['bitrateKbps'] as num?)?.toInt();
            Uint8List? nativePicBytes = nativeMeta?['pictureBytes'] as Uint8List?;

            // 2. Fall back to RangeTagParser if native tag extraction didn't yield both artist and title
            ParsedAudioMetadata? parsed;
            if (rawArtist == null || rawArtist.isEmpty || rawTitle == null || rawTitle.isEmpty) {
              if (localTagFile != null) {
                parsed = await RangeTagParser.parseLocalFile(localTagFile);
              } else if (effectiveStreamUrl.startsWith('content://')) {
                final headerBytes = await readContentUriHeaderBytes(effectiveStreamUrl);
                if (headerBytes != null && headerBytes.isNotEmpty) {
                  parsed = RangeTagParser.parseHeaderBytes(
                    headerBytes,
                    fallbackFilename: name,
                  );
                } else {
                  parsed = RangeTagParser.parseFromFilename(name);
                }
              } else {
                parsed = RangeTagParser.parseFromFilename(name);
              }
            }

            final cleanTitle = (rawTitle != null && rawTitle.isNotEmpty)
                ? rawTitle
                : ((parsed?.title != null && parsed!.title!.isNotEmpty)
                    ? parsed.title!
                    : name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), ''));

            bool isInvalidArtist(String? s) {
              if (s == null) return true;
              final lower = s.trim().toLowerCase();
              return lower.isEmpty ||
                  lower == 'cloud artist' ||
                  lower == 'unknown artist' ||
                  lower == 'unknown' ||
                  lower == 'various artists' ||
                  lower.contains('cloud') ||
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

            String? artist = rawArtist ?? parsed?.artist;
            String? album = rawAlbum ?? parsed?.album;

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
                : 'Unknown Artist';

            final effectiveAlbum = (!isInvalidArtist(album) &&
                    album != 'Cloud Library')
                ? album!
                : (name.contains('-') ? 'Single' : 'Library');

            final trackId =
                'cloud_${name.hashCode.abs()}_${DateTime.now().microsecondsSinceEpoch}_$fileIndex';

            // High-Performance Embedded Artwork Extraction:
            String? embeddedArt;
            if (nativePicBytes != null && nativePicBytes.isNotEmpty) {
              embeddedArt = await ArtworkExtractor.saveArtworkBytes(
                nativePicBytes,
                trackId,
              );
            } else if (file.scannedAlbumArtUri != null) {
              embeddedArt = file.scannedAlbumArtUri;
            } else if (parsed?.embeddedArtworkBytes != null && parsed!.embeddedArtworkBytes!.isNotEmpty) {
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

            final finalDurationMs = (nativeDurationMs != null && nativeDurationMs > 0)
                ? nativeDurationMs
                : (parsed?.durationMs ?? 210000);
            final finalBitrate = (nativeBitrateKbps != null && nativeBitrateKbps > 0)
                ? nativeBitrateKbps
                : (parsed?.bitrateKbps ?? 320);

            // Fast fallback dominant color (0xFF1E293B) during import.
            // Avoids blocking CPU on heavy color-quantization across 50+ files during active import.
            final dominantColor = 0xFF1E293B;

            final isTrueLocalFile = localTagFile != null &&
                !localTagFile.path.contains('/cache/file_picker/') &&
                !localTagFile.path.contains('/cache/') &&
                !localTagFile.path.contains('\\cache\\') &&
                !localTagFile.path.contains('/tmp/');

            final newTrack = Track(
              id: trackId,
              accountId: account.id,
              providerType: account.providerType,
              remotePathOrId: effectiveStreamUrl,
              title: cleanTitle.isNotEmpty ? cleanTitle : 'Unknown Track',
              artist: effectiveArtist,
              album: effectiveAlbum,
              durationMs: finalDurationMs,
              streamUrl: effectiveStreamUrl,
              artworkUrl: embeddedArt,
              codec: parsed?.codec ??
                  (ext.isNotEmpty
                      ? ext.replaceAll('.', '').toUpperCase()
                      : 'FLAC'),
              bitDepth: parsed?.bitDepth ?? 24,
              sampleRateHz: parsed?.sampleRateHz ?? 96000,
              bitrateKbps: finalBitrate,
              sizeBytes: file.size > 0 ? file.size : 25000000,
              dominantColorValue: dominantColor,
              isPinnedOffline: isTrueLocalFile,
              localCachePath: isTrueLocalFile ? localTagFile.path : null,
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
    this.scannedTitle,
    this.scannedArtist,
    this.scannedAlbum,
    this.scannedDurationMs,
    this.scannedAlbumArtUri,
  });

  final String name;
  final String? path;
  final String? identifier;
  final int size;
  final String? scannedTitle;
  final String? scannedArtist;
  final String? scannedAlbum;
  final int? scannedDurationMs;
  final String? scannedAlbumArtUri;
}
