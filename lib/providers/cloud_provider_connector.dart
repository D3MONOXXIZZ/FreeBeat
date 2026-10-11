import '../core/models/audio_quality_settings.dart';
import '../core/models/cloud_account.dart';
import '../core/models/track.dart';

/// Resolved stream specification returned by a CloudProviderConnector
/// so CloudStreamProxy (`127.0.0.1`) can fetch authenticated byte ranges.
class StreamRequestSpec {
  const StreamRequestSpec({
    required this.url,
    this.headers = const {},
    this.activeQualityTier = AudioQualityTier.hifiLossless,
    this.effectiveBitrateKbps = 1411,
    this.effectiveCodec = 'FLAC',
    this.isDirectLocalFile = false,
  });

  final String url;
  final Map<String, String> headers;
  final AudioQualityTier activeQualityTier;
  final int effectiveBitrateKbps;
  final String effectiveCodec;
  final bool isDirectLocalFile;
}

/// Abstract adapter implemented by all 12 cloud storage, media server,
/// open protocol, and local NAS/OS connectors.
abstract class CloudProviderConnector {
  CloudProviderType get type;

  /// Verifies credentials and endpoint reachability.
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  );

  /// Pass 1 bulk catalog scan returning playable tracks immediately.
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  );

  /// Resolves an authenticated stream URL and headers honoring the active
  /// user-configured [targetQuality] tier and optional HTTP byte range.
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  });
}
