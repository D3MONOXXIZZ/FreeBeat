import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../cloud_provider_connector.dart';

/// 5. Jellyfin / Emby Media Server Connector
/// Supports both Bit-Perfect Hi-Fi Lossless Direct Play (`static=true`)
/// and dynamic server-side bitrate transcoding (`maxStreamingBitrate`).
class JellyfinConnector implements CloudProviderConnector {
  JellyfinConnector({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  CloudProviderType get type => CloudProviderType.jellyfin;

  String _cleanBaseUrl(String raw) =>
      raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final baseUrl = _cleanBaseUrl(account.endpointOrFolder);
    final apiKey = secrets['apiKey'] ?? secrets['accessToken'] ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) return false;
    try {
      final resp = await _client.get(
        Uri.parse('$baseUrl/System/Info'),
        headers: {'X-Emby-Token': apiKey},
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final baseUrl = _cleanBaseUrl(account.endpointOrFolder);
    final apiKey = secrets['apiKey'] ?? secrets['accessToken'] ?? '';
    if (baseUrl.isEmpty || apiKey.isEmpty) return [];
    try {
      final uri = Uri.parse(
        '$baseUrl/Items?IncludeItemTypes=Audio&Recursive=true&Fields=MediaSources,RunTimeTicks&Limit=300',
      );
      final resp = await _client.get(uri, headers: {'X-Emby-Token': apiKey});
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = data['Items'] as List<dynamic>? ?? [];
      return items.map((raw) {
        final item = raw as Map<String, dynamic>;
        final id = item['Id'] as String;
        final ticks = item['RunTimeTicks'] as int? ?? 2000000000;
        final artists = (item['Artists'] as List<dynamic>? ?? []);
        final container =
            (item['Container'] as String? ?? 'FLAC').toUpperCase();
        return Track(
          id: 'jellyfin_$id',
          accountId: account.id,
          providerType: type,
          remotePathOrId: id,
          title: item['Name'] as String? ?? 'Jellyfin Track',
          artist: artists.isNotEmpty
              ? artists.first.toString()
              : 'Jellyfin Artist',
          album: item['Album'] as String? ?? 'Jellyfin Library',
          durationMs: (ticks / 10000).round(),
          streamUrl: '$baseUrl/Audio/$id/universal',
          artworkUrl: '$baseUrl/Items/$id/Images/Primary?maxHeight=600',
          codec: container,
          bitDepth: container == 'FLAC' ? 24 : 16,
          sampleRateHz: container == 'FLAC' ? 96000 : 48000,
          bitrateKbps: container == 'FLAC' ? 1850 : 320,
          dominantColorValue: 0xFF1E293B,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Builds the exact Jellyfin streaming URL honoring [targetQuality] (Hi-Fi Lossless vs Bitrate Cap).
  static String buildStreamingUrl({
    required String baseUrl,
    required String itemId,
    required String apiKey,
    required AudioQualityTier targetQuality,
  }) {
    final clean =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    if (targetQuality.isLossless) {
      return '$clean/Audio/$itemId/stream?static=true&api_key=$apiKey';
    }
    final maxBitrateBps = targetQuality.kbps * 1000;
    final codec = targetQuality.codec.toLowerCase();
    return '$clean/Audio/$itemId/universal?UserId=freebeat&DeviceId=pixel&MaxStreamingBitrate=$maxBitrateBps&AudioCodec=$codec&Container=$codec&api_key=$apiKey';
  }

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    final apiKey = secrets['apiKey'] ?? secrets['accessToken'] ?? '';
    final url = buildStreamingUrl(
      baseUrl: account.endpointOrFolder,
      itemId: track.remotePathOrId,
      apiKey: apiKey,
      targetQuality: targetQuality,
    );
    return StreamRequestSpec(
      url: url,
      headers: {
        if (apiKey.isNotEmpty) 'X-Emby-Token': apiKey,
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

/// 6. Subsonic / Navidrome / OpenSubsonic Connector
/// Uses salted MD5 token authentication (`t = md5(password + salt)`).
class SubsonicConnector implements CloudProviderConnector {
  SubsonicConnector({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  CloudProviderType get type => CloudProviderType.subsonic;

  /// Generates salted MD5 authentication query parameters per Subsonic API 1.16.1 spec.
  static Map<String, String> buildAuthParams({
    required String username,
    required String password,
    String? fixedSalt,
  }) {
    final salt = fixedSalt ??
        List.generate(8, (_) => Random.secure().nextInt(36).toRadixString(36))
            .join();
    final token = md5.convert(utf8.encode('$password$salt')).toString();
    return {
      'u': username,
      't': token,
      's': salt,
      'v': '1.16.1',
      'c': 'FreeBeatPixel',
      'f': 'json',
    };
  }

  /// Builds the Subsonic `/rest/stream` URL honoring [targetQuality].
  static Uri buildStreamUri({
    required String baseServerUrl,
    required String songId,
    required String username,
    required String password,
    required AudioQualityTier targetQuality,
    String? fixedSalt,
  }) {
    final auth = buildAuthParams(
      username: username,
      password: password,
      fixedSalt: fixedSalt,
    );
    final baseUri = Uri.parse(baseServerUrl);
    final query = <String, String>{
      ...auth,
      'id': songId,
      if (targetQuality.isLossless) ...{
        'maxBitRate': '0',
        'format': 'raw',
      } else ...{
        'maxBitRate': '${targetQuality.kbps}',
        'format': targetQuality.codec.toLowerCase(),
      },
    };
    return baseUri.replace(
      path: '${baseUri.path.replaceAll(RegExp(r'/$'), '')}/rest/stream',
      queryParameters: query,
    );
  }

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final password = secrets['password'] ?? '';
    if (account.endpointOrFolder.isEmpty || password.isEmpty) return false;
    try {
      final auth = buildAuthParams(
        username: account.usernameOrEmail,
        password: password,
      );
      final base = Uri.parse(account.endpointOrFolder);
      final pingUri = base.replace(
        path: '${base.path.replaceAll(RegExp(r'/$'), '')}/rest/ping',
        queryParameters: auth,
      );
      final resp = await _client.get(pingUri);
      return resp.statusCode == 200 && resp.body.contains('"status":"ok"');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    return [];
  }

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    final uri = buildStreamUri(
      baseServerUrl: account.endpointOrFolder,
      songId: track.remotePathOrId,
      username: account.usernameOrEmail,
      password: secrets['password'] ?? '',
      targetQuality: targetQuality,
    );
    return StreamRequestSpec(
      url: uri.toString(),
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
