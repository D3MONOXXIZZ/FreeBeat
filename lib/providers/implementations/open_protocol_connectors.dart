import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/metadata/range_tag_parser.dart';
import '../cloud_provider_connector.dart';

/// 7. WebDAV / Nextcloud / ownCloud / Synology Connector
class WebDavConnector implements CloudProviderConnector {
  WebDavConnector({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  CloudProviderType get type => CloudProviderType.webdav;

  String _basicAuthHeader(String user, String pass) {
    final token = base64Encode(utf8.encode('$user:$pass'));
    return 'Basic $token';
  }

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final pass = secrets['password'] ?? '';
    if (account.endpointOrFolder.isEmpty) return false;
    try {
      final req = http.Request('PROPFIND', Uri.parse(account.endpointOrFolder));
      req.headers['Depth'] = '0';
      req.headers['Authorization'] =
          _basicAuthHeader(account.usernameOrEmail, pass);
      final streamed = await _client.send(req);
      return streamed.statusCode == 207 || streamed.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Parses WebDAV `207 Multi-Status` XML response into playable [Track] items.
  static List<Track> parsePropfindXml({
    required String xmlBody,
    required CloudAccount account,
  }) {
    final doc = XmlDocument.parse(xmlBody);
    final tracks = <Track>[];
    final responses = doc.findAllElements('response', namespace: '*');

    for (final resp in responses) {
      final hrefElem = resp.findElements('href', namespace: '*').firstOrNull;
      if (hrefElem == null) continue;
      final href = Uri.decodeFull(hrefElem.innerText.trim());
      if (!RegExp(r'\.(flac|mp3|m4a|wav|ogg|opus|aac|alac|aiff|aif|wma|asf|ape|dsd|dsf|dff|mka)$', caseSensitive: false)
          .hasMatch(href)) {
        continue;
      }
      final filename = href.split('/').where((s) => s.isNotEmpty).last;
      final parsed = RangeTagParser.parseFromFilename(filename);
      final baseUri = Uri.parse(account.endpointOrFolder);
      final fullUrl = href.startsWith('http')
          ? href
          : '${baseUri.scheme}://${baseUri.authority}$href';

      tracks.add(
        Track(
          id: 'webdav_${href.hashCode.abs()}',
          accountId: account.id,
          providerType: CloudProviderType.webdav,
          remotePathOrId: href,
          title: parsed.title ?? filename,
          artist: parsed.artist ??
              (account.displayName.isNotEmpty
                  ? account.displayName
                  : 'Unknown Artist'),
          album: parsed.album ?? account.displayName,
          durationMs: 230000,
          streamUrl: fullUrl,
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1650,
          dominantColorValue: 0xFF1E293B,
        ),
      );
    }
    return tracks;
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final pass = secrets['password'] ?? '';
    try {
      final req = http.Request('PROPFIND', Uri.parse(account.endpointOrFolder));
      req.headers['Depth'] = '1';
      req.headers['Authorization'] =
          _basicAuthHeader(account.usernameOrEmail, pass);
      final streamed = await _client.send(req);
      if (streamed.statusCode == 207 || streamed.statusCode == 200) {
        final body = await streamed.stream.bytesToString();
        return parsePropfindXml(xmlBody: body, account: account);
      }
    } catch (_) {}
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
    final pass = secrets['password'] ?? '';
    return StreamRequestSpec(
      url: track.streamUrl,
      headers: {
        'Authorization': _basicAuthHeader(account.usernameOrEmail, pass),
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

/// 8. S3-Compatible Storage Connector (AWS S3, Cloudflare R2, Backblaze B2, MinIO)
/// Implements pure-Dart AWS Signature Version 4 (HMAC-SHA256) presigned URLs.
class S3CompatibleConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.s3;

  static List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }

  /// Generates an AWS Signature Version 4 Presigned GET URL for zero-latency
  /// byte-range streaming from S3, Cloudflare R2, Backblaze B2, or MinIO.
  static String generatePresignedGetUrl({
    required String endpointHost,
    required String bucket,
    required String objectKey,
    required String accessKeyId,
    required String secretAccessKey,
    String region = 'auto',
    DateTime? nowUtc,
    int expiresSeconds = 3600,
  }) {
    final timestamp = (nowUtc ?? DateTime.now().toUtc());
    final dateStamp =
        '${timestamp.year.toString().padLeft(4, '0')}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}';
    final amzDate =
        '${dateStamp}T${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}Z';

    final cleanHost = endpointHost
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '');
    final cleanKey =
        objectKey.startsWith('/') ? objectKey.substring(1) : objectKey;
    final canonicalUri = '/$bucket/$cleanKey';
    final credentialScope = '$dateStamp/$region/s3/aws4_request';

    final queryParams = <String, String>{
      'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
      'X-Amz-Credential': '$accessKeyId/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '$expiresSeconds',
      'X-Amz-SignedHeaders': 'host',
    };

    final sortedKeys = queryParams.keys.toList()..sort();
    final canonicalQueryString = sortedKeys
        .map(
          (k) =>
              '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(queryParams[k]!)}',
        )
        .join('&');

    final canonicalRequest = [
      'GET',
      canonicalUri,
      canonicalQueryString,
      'host:$cleanHost\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final canonicalRequestHash =
        sha256.convert(utf8.encode(canonicalRequest)).toString();

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      canonicalRequestHash,
    ].join('\n');

    final kDate = _hmacSha256(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, 's3');
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signature = Hmac(sha256, kSigning)
        .convert(utf8.encode(stringToSign))
        .toString();

    return 'https://$cleanHost$canonicalUri?$canonicalQueryString&X-Amz-Signature=$signature';
  }

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    return (secrets['accessKeyId'] ?? '').isNotEmpty &&
        (secrets['secretAccessKey'] ?? '').isNotEmpty;
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
    final signedUrl = generatePresignedGetUrl(
      endpointHost: account.endpointOrFolder,
      bucket: account.bucketOrShareName.isEmpty
          ? 'music'
          : account.bucketOrShareName,
      objectKey: track.remotePathOrId,
      accessKeyId: secrets['accessKeyId'] ?? 'demo',
      secretAccessKey: secrets['secretAccessKey'] ?? 'demo',
      region: account.region,
    );
    return StreamRequestSpec(
      url: signedUrl,
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
