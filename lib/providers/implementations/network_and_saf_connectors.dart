import 'package:file_picker/file_picker.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/metadata/range_tag_parser.dart';
import '../cloud_provider_connector.dart';
import 'media_server_connectors.dart';
import 'oauth_cloud_connectors.dart';
import 'open_protocol_connectors.dart';

/// 9. SFTP / SSH Home Lab & NAS Connector
class SftpNasConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.sftp;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    return account.endpointOrFolder.isNotEmpty &&
        account.usernameOrEmail.isNotEmpty;
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      [];

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// 10. SMB / LAN NAS Share Connector
class SmbNasConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.smb;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      account.endpointOrFolder.isNotEmpty;

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      [];

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// 11. Android Native Storage Access Framework (SAF) Connector
/// Allows mounting any cloud provider app installed on the Android phone
/// (Google Drive, OneDrive, Nextcloud, Proton Drive, MEGA, SD Card) via DocumentsContract.
class AndroidSafConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.androidSaf;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      true;

  /// Launches the native Android SAF multi-file audio picker to mount cloud/local tracks.
  Future<List<Track>> pickSafAudioFiles(CloudAccount account) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null) return [];
      final tracks = result.files.map((file) {
        final parsed = RangeTagParser.parseFromFilename(file.name);
        final effectiveUrl = (file.identifier != null && file.identifier!.startsWith('content://'))
            ? file.identifier!
            : (file.path ?? '');
        final isTrueLocal = file.path != null &&
            !file.path!.contains('/cache/file_picker/') &&
            !file.path!.contains('/cache/');

        return Track(
          id: 'saf_${file.name.hashCode.abs()}',
          accountId: account.id,
          providerType: type,
          remotePathOrId: effectiveUrl,
          title: parsed.title ?? file.name,
          artist: parsed.artist ?? 'Mounted Cloud Drive',
          album: parsed.album ?? account.displayName,
          durationMs: 210000,
          streamUrl: effectiveUrl,
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1411,
          sizeBytes: file.size,
          dominantColorValue: 0xFF1E293B,
          isPinnedOffline: isTrueLocal,
          localCachePath: isTrueLocal ? file.path : null,
        );
      }).where((t) => t.streamUrl.isNotEmpty).toList();

      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      return tracks;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      [];

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps: track.bitrateKbps,
      effectiveCodec: track.codec,
      isDirectLocalFile: true,
    );
  }
}

/// 12. Pixel Hi-Fi Demo Cloud Showcase Connector
class DemoCloudConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.demoCloud;

  static List<CloudAccount> defaultShowcaseAccounts() => const [];

  static List<Track> defaultShowcaseTracks() => const [];

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      true;

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      const [];



  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      headers: {
        if (startByte != null) 'Range': 'bytes=$startByte-${endByte ?? ''}',
      },
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// Central registry resolving any of the 12 [CloudProviderType] values to its connector.
class CloudConnectorRegistry {
  CloudConnectorRegistry() {
    _connectors = {
      CloudProviderType.googleDrive: GoogleDriveConnector(),
      CloudProviderType.oneDrive: OneDriveConnector(),
      CloudProviderType.dropbox: DropboxConnector(),
      CloudProviderType.box: BoxConnector(),
      CloudProviderType.jellyfin: JellyfinConnector(),
      CloudProviderType.subsonic: SubsonicConnector(),
      CloudProviderType.webdav: WebDavConnector(),
      CloudProviderType.s3: S3CompatibleConnector(),
      CloudProviderType.sftp: SftpNasConnector(),
      CloudProviderType.smb: SmbNasConnector(),
      CloudProviderType.androidSaf: AndroidSafConnector(),
      CloudProviderType.demoCloud: DemoCloudConnector(),
    };
  }

  late final Map<CloudProviderType, CloudProviderConnector> _connectors;

  CloudProviderConnector forType(CloudProviderType type) {
    return _connectors[type] ?? DemoCloudConnector();
  }
}
