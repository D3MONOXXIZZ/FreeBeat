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
          'scope':
              'https://www.googleapis.com/auth/drive.file https://www.googleapis.com/auth/drive.readonly email',
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
            'scope': 'Files.ReadWrite offline_access User.Read',
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

  static const Set<String> supportedAudioExtensions = {
    'mp3', 'flac', 'm4a', 'wav', 'ogg', 'opus', 'aac',
    'alac', 'aiff', 'aif', 'wma', 'asf', 'ape', 'dsd', 'dsf', 'dff', 'mka'
  };

  static const Set<String> blockedNonAudioExtensions = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf',
    'csv', 'json', 'xml', 'html', 'htm', 'zip', 'rar', 'tar', 'gz', '7z',
    'apk', 'exe', 'dmg', 'iso', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'svg',
    'bmp', 'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv'
  };

  /// Strictly determines if a file is audio and blocks PDFs, documents, images, and archives.
  static bool isAudioFile(String filename, String? mimeType) {
    final lowerName = filename.toLowerCase().trim();
    final dotIndex = lowerName.lastIndexOf('.');
    final ext = dotIndex != -1 ? lowerName.substring(dotIndex + 1) : '';

    if (blockedNonAudioExtensions.contains(ext)) {
      return false;
    }
    if (supportedAudioExtensions.contains(ext)) {
      return true;
    }
    if (mimeType != null && mimeType.startsWith('audio/')) {
      return true;
    }
    return false;
  }

  /// Lists Google Drive folders under root or an optional parent folder.
  Future<List<Map<String, String>>> listFolders(
    String token, {
    String? parentFolderId,
  }) async {
    if (token.isEmpty) return [];
    try {
      final parentClause = parentFolderId != null && parentFolderId.isNotEmpty
          ? "'$parentFolderId' in parents and "
          : '';
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "${parentClause}mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        'fields': 'files(id,name)',
        'pageSize': '100',
        'orderBy': 'name',
      });
      final resp = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as List<dynamic>? ?? [];
      return files
          .map((f) => {
                'id': (f['id'] as String?) ?? '',
                'name': (f['name'] as String?) ?? 'Folder',
              })
          .where((f) => f['id']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Finds or creates a Google Drive folder by name.
  Future<String> getOrCreateFolder(
    String token,
    String folderName, {
    String? parentFolderId,
  }) async {
    if (token.isEmpty) return '';
    try {
      final parentClause = parentFolderId != null && parentFolderId.isNotEmpty
          ? " and '$parentFolderId' in parents"
          : '';
      final searchUri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false$parentClause",
        'fields': 'files(id,name)',
      });
      final searchResp = await _client.get(
        searchUri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (searchResp.statusCode == 200) {
        final data = jsonDecode(searchResp.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>? ?? [];
        if (files.isNotEmpty) {
          return files.first['id'] as String;
        }
      }

      // Create folder if not found
      final createUri = Uri.parse('https://www.googleapis.com/drive/v3/files');
      final body = jsonEncode({
        'name': folderName,
        'mimeType': 'application/vnd.google-apps.folder',
        if (parentFolderId != null && parentFolderId.isNotEmpty)
          'parents': [parentFolderId],
      });
      final createResp = await _client.post(
        createUri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      if (createResp.statusCode == 200 || createResp.statusCode == 201) {
        final data = jsonDecode(createResp.body) as Map<String, dynamic>;
        return (data['id'] as String?) ?? '';
      }
    } catch (_) {}
    return '';
  }

  Future<List<Map<String, dynamic>>> _fetchFilesInParent(String token, String parentId) async {
    try {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'$parentId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false",
        'fields': 'files(id,name,mimeType,size)',
        'pageSize': '500',
      });
      final resp = await _client.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as List<dynamic>? ?? [];
      return files.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

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

    final folderId = secrets['folderId'] ?? '';
    final folderName = secrets['folderName'] ?? '';

    // If configured as Upload-Only, skip scanning entirely
    if (folderId == 'none' ||
        folderName == 'Uploads Only' ||
        account.endpointOrFolder.contains('Uploads Only')) {
      return [];
    }

    try {
      String targetFolderId = folderId;
      if (targetFolderId.isEmpty &&
          (account.endpointOrFolder.contains('FreeBeat Music') ||
           folderName.contains('FreeBeat Music'))) {
        targetFolderId = await getOrCreateFolder(token, 'FreeBeat Music');
      }

      final rawFiles = <Map<String, dynamic>>[];

      if (targetFolderId.isNotEmpty) {
        // Fetch files inside the designated folder
        final filesInRoot = await _fetchFilesInParent(token, targetFolderId);
        rawFiles.addAll(filesInRoot);

        // Fetch files inside child playlist folders within this designated folder
        final subfolders = await listFolders(token, parentFolderId: targetFolderId);
        for (final sub in subfolders) {
          final subId = sub['id'];
          if (subId != null && subId.isNotEmpty) {
            final filesInSub = await _fetchFilesInParent(token, subId);
            rawFiles.addAll(filesInSub);
          }
        }
      } else {
        // Fallback query for whole drive search: strictly audio files
        final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
          'q': "(mimeType contains 'audio/' or name contains '.mp3' or name contains '.flac') and trashed = false",
          'fields': 'files(id,name,mimeType,size)',
          'pageSize': '500',
        });
        final resp = await _client.get(
          uri,
          headers: {'Authorization': 'Bearer $token'},
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final files = data['files'] as List<dynamic>? ?? [];
          rawFiles.addAll(files.cast<Map<String, dynamic>>());
        }
      }

      // Filter: strictly reject PDFs, documents, images, and non-audio files
      final audioFiles = rawFiles.where((f) {
        final name = (f['name'] as String?) ?? '';
        final mime = f['mimeType'] as String?;
        return isAudioFile(name, mime);
      }).toList();

      return audioFiles.map((raw) {
        final f = raw;
        final id = f['id'] as String;
        final name = f['name'] as String? ?? 'Drive Track.flac';
        final parsed = RangeTagParser.parseFromFilename(name);
        final cleanTitle = parsed.title ?? name.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
        return Track(
          id: 'gdrive_$id',
          accountId: account.id,
          providerType: type,
          remotePathOrId: id,
          title: cleanTitle.isNotEmpty ? cleanTitle : name,
          artist: parsed.artist ?? (account.displayName.isNotEmpty ? account.displayName : 'Google Drive'),
          album: parsed.album ?? account.displayName,
          durationMs: 215000,
          streamUrl:
              'https://www.googleapis.com/drive/v3/files/$id?alt=media',
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1411,
          sizeBytes: int.tryParse(f['size']?.toString() ?? '') ?? 32000000,
          dominantColorValue: 0xFF1E293B,
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
          dominantColorValue: 0xFF1E293B,
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
        if (!RegExp(r'\.(flac|mp3|m4a|wav|ogg|opus|aac|alac|aiff|aif|wma|asf|ape|dsd|dsf|dff|mka)$', caseSensitive: false)
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
            dominantColorValue: 0xFF1E293B,
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
