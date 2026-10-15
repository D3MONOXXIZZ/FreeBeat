import 'package:file_picker/file_picker.dart';
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
  NativeCloudAuthService({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: <String>[
                'email',
                'https://www.googleapis.com/auth/drive.readonly',
              ],
            );

  final GoogleSignIn _googleSignIn;

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
      return NativeGoogleAuthResult(
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Sign out from Google Drive
  Future<void> signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  GoogleSignInAccount? get currentGoogleUser => _googleSignIn.currentUser;

  /// 1-Tap OAuth Browser Redirect for Microsoft OneDrive, Dropbox, or Box.
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
