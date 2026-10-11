import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/metadata/range_tag_parser.dart';
import '../cloud_provider_connector.dart';

/// Helper for 100% client-side OAuth2 PKCE (`com.freebeat.app://oauth2redirect`).
class OAuth2PkceHelper {
  static const String redirectUri = 'com.freebeat.app://oauth2redirect';

  static String generateCodeVerifier() {
    final rand = Random.secure();
    final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String generateCodeChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Uri buildAuthorizationUri({
    required CloudProviderType provider,
    required String clientId,
    required String codeChallenge,
  }) {
    switch (provider) {
      case CloudProviderType.googleDrive:
        return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'https://www.googleapis.com/auth/drive.readonly',
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          'access_type': 'offline',
        });
      case CloudProviderType.oneDrive:
        return Uri.https(
          'login.microsoftonline.com',
          '/common/oauth2/v2.0/authorize',
          {
            'client_id': clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': 'Files.Read offline_access User.Read',
            'code_challenge': codeChallenge,
            'code_challenge_method': 'S256',
          },
        );
      case CloudProviderType.dropbox:
        return Uri.https('www.dropbox.com', '/oauth2/authorize', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'token_access_type': 'offline',
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        });
      case CloudProviderType.box:
        return Uri.https('account.box.com', '/api/oauth2/authorize', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
        });
      default:
        return Uri.parse('https://google.com');
    }
  }
}

/// 1. Google Drive v3 Connector
class GoogleDriveConnector implements CloudProviderConnector {
  GoogleDriveConnector({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  CloudProviderType get type => CloudProviderType.googleDrive;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) return false;
    try {
      final resp = await _client.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/about?fields=user',
        ),
        headers: {'Authorization': 'Bearer $token'},
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
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) return [];
    try {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "mimeType contains 'audio/' and trashed = false",
        'fields': 'files(id,name,mimeType,size)',
        'pageSize': '250',
      });
      final resp = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as List<dynamic>? ?? [];
      return files.map((raw) {
        final f = raw as Map<String, dynamic>;
        final id = f['id'] as String;
        final name = f['name'] as String? ?? 'Drive Track.flac';
        final parsed = RangeTagParser.parseFromFilename(name);
        return Track(
          id: 'gdrive_$id',
          accountId: account.id,
          providerType: type,
          remotePathOrId: id,
          title: parsed.title ?? name,
          artist: parsed.artist ?? 'Google Drive Artist',
          album: parsed.album ?? account.displayName,
          durationMs: 215000,
          streamUrl:
              'https://www.googleapis.com/drive/v3/files/$id?alt=media',
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1411,
          sizeBytes: int.tryParse(f['size']?.toString() ?? '') ?? 32000000,
          dominantColorValue: type.accentColorValue,
        );
      }).toList();
    } catch (_) {
      return [];
    }
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
    final token = secrets['accessToken'] ?? '';
    final headers = <String, String>{
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (startByte != null)
        'Range': 'bytes=$startByte-${endByte ?? ''}',
    };
    return StreamRequestSpec(
      url: track.streamUrl,
      headers: headers,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// 2. Microsoft OneDrive (Graph API v1.0) Connector
class OneDriveConnector implements CloudProviderConnector {
  OneDriveConnector({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  CloudProviderType get type => CloudProviderType.oneDrive;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) return false;
    try {
      final resp = await _client.get(
        Uri.parse('https://graph.microsoft.com/v1.0/me/drive'),
        headers: {'Authorization': 'Bearer $token'},
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
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) return [];
    try {
      final resp = await _client.get(
        Uri.parse(
          "https://graph.microsoft.com/v1.0/me/drive/root/search(q='.flac')",
        ),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = data['value'] as List<dynamic>? ?? [];
      return items.map((raw) {
        final item = raw as Map<String, dynamic>;
        final id = item['id'] as String;
        final name = item['name'] as String? ?? 'OneDrive Audio.flac';
        final downloadUrl = item['@microsoft.graph.downloadUrl'] as String? ??
            'https://graph.microsoft.com/v1.0/me/drive/items/$id/content';
        final parsed = RangeTagParser.parseFromFilename(name);
        return Track(
          id: 'onedrive_$id',
          accountId: account.id,
          providerType: type,
          remotePathOrId: id,
          title: parsed.title ?? name,
          artist: parsed.artist ?? 'OneDrive Artist',
          album: parsed.album ?? account.displayName,
          durationMs: 210000,
          streamUrl: downloadUrl,
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1411,
          dominantColorValue: type.accentColorValue,
        );
      }).toList();
    } catch (_) {
      return [];
    }
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
    final token = secrets['accessToken'] ?? '';
    return StreamRequestSpec(
      url: track.streamUrl,
      headers: {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
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

/// 3. Dropbox API v2 Connector
class DropboxConnector implements CloudProviderConnector {
  DropboxConnector({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  @override
  CloudProviderType get type => CloudProviderType.dropbox;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final token = secrets['accessToken'] ?? '';
    return token.isNotEmpty;
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) return [];
    try {
      final resp = await _client.post(
        Uri.parse('https://api.dropboxapi.com/2/files/list_folder'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'path': account.endpointOrFolder == '/' ? '' : account.endpointOrFolder,
          'recursive': true,
        }),
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final entries = data['entries'] as List<dynamic>? ?? [];
      final tracks = <Track>[];
      for (final raw in entries) {
        final e = raw as Map<String, dynamic>;
        final name = e['name'] as String? ?? '';
        if (!RegExp(r'\.(flac|mp3|m4a|wav|ogg|opus)$', caseSensitive: false)
            .hasMatch(name)) {
          continue;
        }
        final pathLower = e['path_lower'] as String? ?? '/$name';
        final parsed = RangeTagParser.parseFromFilename(name);
        tracks.add(
          Track(
            id: 'dbx_${ e['id'] ?? pathLower }',
            accountId: account.id,
            providerType: type,
            remotePathOrId: pathLower,
            title: parsed.title ?? name,
            artist: parsed.artist ?? 'Dropbox Artist',
            album: parsed.album ?? account.displayName,
            durationMs: 225000,
            streamUrl: 'https://content.dropboxapi.com/2/files/download',
            codec: parsed.codec ?? 'FLAC',
            bitDepth: parsed.bitDepth ?? 24,
            sampleRateHz: parsed.sampleRateHz ?? 96000,
            bitrateKbps: parsed.bitrateKbps ?? 1411,
            dominantColorValue: type.accentColorValue,
          ),
        );
      }
      return tracks;
    } catch (_) {
      return [];
    }
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
    final token = secrets['accessToken'] ?? '';
    return StreamRequestSpec(
      url: track.streamUrl,
      headers: {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({'path': track.remotePathOrId}),
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

/// 4. Box Cloud API v2 Connector
class BoxConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.box;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    return (secrets['accessToken'] ?? '').isNotEmpty;
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
    final token = secrets['accessToken'] ?? '';
    return StreamRequestSpec(
      url: 'https://api.box.com/2.0/files/${track.remotePathOrId}/content',
      headers: {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
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
