import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
    'dsd',
    'dff',
    'wma',
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

  /// Universal 1-Tap Mount for Any Installed Cloud App on Android (Google Drive,
  /// Microsoft OneDrive, Dropbox, Nextcloud, Mega, Proton Drive, Box, SD Card).
  /// Launches Android's DocumentsProvider where installed cloud sync apps are natively integrated.
  Future<List<Track>> pickFromInstalledCloudApp({
    required CloudAccount account,
  }) async {
    try {
      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: supportedAudioExtensions,
          allowMultiple: true,
          withData: false,
          withReadStream: true,
        );
      } catch (_) {
        // Fallback to FileType.any if custom throws on OEM Android picker
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: true,
          withData: false,
          withReadStream: true,
        );
      }

      if (result == null || result.files.isEmpty) return [];

      Directory? appMusicDir;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        appMusicDir = Directory(p.join(appDir.path, 'imported_music'));
        if (!appMusicDir.existsSync()) {
          appMusicDir.createSync(recursive: true);
        }
      } catch (_) {}

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
        '.wma',
        '.dsd',
        '.dff',
      };

      int fileIndex = 0;
      for (final file in result.files) {
        fileIndex++;
        try {
          final name = file.name;
          final ext = p.extension(name).toLowerCase();
          if (ext.isNotEmpty && !supportedAudioExts.contains(ext)) continue;

          String finalPath = file.path ?? '';

          // If file.path is null or in a temporary cache, persist it to app documents
          if (appMusicDir != null) {
            try {
              final destFile = File(p.join(appMusicDir.path, name));
              if (file.path != null && File(file.path!).existsSync()) {
                if (!destFile.existsSync() || destFile.lengthSync() == 0) {
                  await File(file.path!).copy(destFile.path);
                }
                finalPath = destFile.existsSync() ? destFile.path : file.path!;
              } else if (file.readStream != null) {
                final sink = destFile.openWrite();
                await sink.addStream(file.readStream!);
                await sink.close();
                finalPath = destFile.existsSync() ? destFile.path : (file.path ?? '');
              } else if (file.bytes != null && file.bytes!.isNotEmpty) {
                await destFile.writeAsBytes(file.bytes!);
                finalPath = destFile.path;
              } else if (file.identifier != null && file.identifier!.isNotEmpty) {
                finalPath = file.identifier!;
              }
            } catch (_) {
              finalPath = file.path ?? file.identifier ?? '';
            }
          }

          if (finalPath.isEmpty) {
            finalPath = file.path ?? file.identifier ?? '';
          }
          if (finalPath.isEmpty) continue;

          final parsed = RangeTagParser.parseFromFilename(name);
          final cleanTitle = parsed.title ??
              name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
          final providerLabel = account.displayName.isNotEmpty
              ? account.displayName
              : account.providerType.displayName;
          final trackId =
              'drive_${name.hashCode.abs()}_${DateTime.now().microsecondsSinceEpoch}_$fileIndex';

          String? embeddedArt;
          if (File(finalPath).existsSync()) {
            embeddedArt = await ArtworkExtractor.extractEmbeddedArtwork(
              File(finalPath),
              trackId,
            );
          }

          tracks.add(
            Track(
              id: trackId,
              accountId: account.id,
              providerType: account.providerType,
              remotePathOrId: finalPath,
              title: cleanTitle.isNotEmpty ? cleanTitle : 'Unknown Track',
              artist: parsed.artist ?? providerLabel,
              album: parsed.album ?? providerLabel,
              durationMs: 210000,
              streamUrl: finalPath,
              artworkUrl: embeddedArt,
              codec: parsed.codec ??
                  (ext.isNotEmpty
                      ? ext.replaceAll('.', '').toUpperCase()
                      : 'FLAC'),
              bitDepth: parsed.bitDepth ?? 24,
              sampleRateHz: parsed.sampleRateHz ?? 96000,
              bitrateKbps: parsed.bitrateKbps ?? 1411,
              sizeBytes: file.size > 0 ? file.size : 25000000,
              dominantColorValue: account.providerType.accentColorValue,
              isPinnedOffline: true,
              localCachePath: finalPath,
            ),
          );
        } catch (_) {
          // If one file fails in batch, continue importing remaining files
          continue;
        }
      }

      return tracks;
    } catch (_) {
      return [];
    }
  }

  /// 1-Tap Folder Import: Scans an entire music directory (e.g. from Google Drive or device)
  Future<List<Track>> pickFolder({
    required CloudAccount account,
  }) async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select ${account.displayName} Music Folder',
      );
      if (dirPath == null || dirPath.isEmpty) return [];

      final dir = Directory(dirPath);
      if (!dir.existsSync()) return [];

      final supportedExts = {
        '.mp3',
        '.flac',
        '.m4a',
        '.wav',
        '.aac',
        '.ogg',
        '.opus',
        '.alac',
        '.aiff',
        '.wma',
        '.dsd',
        '.dff',
      };

      final entities = dir.listSync(recursive: true, followLinks: false);
      final audioFiles = entities.whereType<File>().where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return supportedExts.contains(ext);
      }).toList();

      if (audioFiles.isEmpty) return [];

      final providerLabel = account.displayName.isNotEmpty
          ? account.displayName
          : account.providerType.displayName;

      final tracks = <Track>[];
      int folderFileIndex = 0;
      for (final file in audioFiles) {
        folderFileIndex++;
        try {
          final name = p.basename(file.path);
          final ext = p.extension(name).toLowerCase();
          final parsed = RangeTagParser.parseFromFilename(name);
          final cleanTitle = parsed.title ??
              name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
          final parentFolder = p.basename(p.dirname(file.path));
          final trackId =
              'folder_${file.path.hashCode.abs()}_${DateTime.now().microsecondsSinceEpoch}_$folderFileIndex';

          String? embeddedArt;
          if (file.existsSync()) {
            embeddedArt =
                await ArtworkExtractor.extractEmbeddedArtwork(file, trackId);
          }

          tracks.add(
            Track(
              id: trackId,
              accountId: account.id,
              providerType: account.providerType,
              remotePathOrId: file.path,
              title: cleanTitle.isNotEmpty ? cleanTitle : 'Unknown Track',
              artist: parsed.artist ?? providerLabel,
              album: parsed.album ??
                  (parentFolder.isNotEmpty ? parentFolder : providerLabel),
              durationMs: 210000,
              streamUrl: file.path,
              artworkUrl: embeddedArt,
              codec: parsed.codec ??
                  (ext.isNotEmpty
                      ? ext.replaceAll('.', '').toUpperCase()
                      : 'FLAC'),
              bitDepth: parsed.bitDepth ?? 24,
              sampleRateHz: parsed.sampleRateHz ?? 96000,
              bitrateKbps: parsed.bitrateKbps ?? 1411,
              sizeBytes: file.existsSync() ? file.lengthSync() : 25000000,
              dominantColorValue: account.providerType.accentColorValue,
              isPinnedOffline: true,
              localCachePath: file.path,
            ),
          );
        } catch (_) {
          continue;
        }
      }
      return tracks;
    } catch (_) {
      return [];
    }
  }
}
