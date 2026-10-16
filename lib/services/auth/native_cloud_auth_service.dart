import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../providers/implementations/oauth_cloud_connectors.dart';
import '../../services/metadata/range_tag_parser.dart';

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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null) return [];
      return result.files.where((f) => f.path != null).map((file) {
        final parsed = RangeTagParser.parseFromFilename(file.name);
        return Track(
          id: 'saf_${file.name.hashCode.abs()}_${DateTime.now().millisecondsSinceEpoch}',
          accountId: account.id,
          providerType: account.providerType,
          remotePathOrId: file.path!,
          title: parsed.title ?? file.name,
          artist: parsed.artist ?? account.displayName,
          album: parsed.album ?? account.displayName,
          durationMs: 210000,
          streamUrl: file.path!,
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1411,
          sizeBytes: file.size,
          dominantColorValue: account.providerType.accentColorValue,
          isPinnedOffline: true,
          localCachePath: file.path,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
