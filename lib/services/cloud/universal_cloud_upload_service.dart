import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../audio/track_audio_tagger_service.dart';

/// Exception thrown when a cloud upload fails.
class CloudUploadException implements Exception {
  CloudUploadException(this.message, {this.statusCode, this.provider});
  final String message;
  final int? statusCode;
  final CloudProviderType? provider;

  @override
  String toString() =>
      'CloudUploadException(${provider?.displayName ?? "Cloud"}): $message ${statusCode != null ? "(HTTP $statusCode)" : ""}';
}

/// Universal multi-cloud uploader that coordinates uploads to any cloud provider
/// configured in FreeBeat (Google Drive, OneDrive, Dropbox, WebDAV, S3, Box, or Local Storage).
class UniversalCloudUploadService {
  UniversalCloudUploadService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Uploads a prepared scratch audio file to the target cloud account inside
  /// `FreeBeat Music/{playlistName}/` and returns a fully initialized [Track] model.
  /// Automatically purges scratch audio files after remote cloud upload to prevent
  /// local device storage accumulation.
  Future<Track> uploadPreparedTrack({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final cleanPlaylist = _sanitizeFolder(playlistName);
    Track? uploadedTrack;

    final token = secrets['accessToken'] ?? '';
    final isSafMount = account.endpointOrFolder.contains('Android App Storage') ||
        account.endpointOrFolder.contains('Folder Import');
    final hasRemoteAuth = !isSafMount &&
        (token.isNotEmpty ||
            (secrets['accessKeyId'] ?? '').isNotEmpty ||
            (secrets['password'] ?? '').isNotEmpty ||
            (secrets['username'] ?? '').isNotEmpty ||
            (account.providerType == CloudProviderType.webdav &&
                account.usernameOrEmail.isNotEmpty));

    final isRemoteCloud = account.providerType != CloudProviderType.androidSaf &&
        account.providerType != CloudProviderType.demoCloud;

    if (isRemoteCloud && hasRemoteAuth) {
      try {
        switch (account.providerType) {
          case CloudProviderType.googleDrive:
            uploadedTrack = await _uploadToGoogleDrive(
              preparedAudio: preparedAudio,
              account: account,
              secrets: secrets,
              playlistName: cleanPlaylist,
              onProgress: onProgress,
            );
            break;

          case CloudProviderType.oneDrive:
            uploadedTrack = await _uploadToOneDrive(
              preparedAudio: preparedAudio,
              account: account,
              secrets: secrets,
              playlistName: cleanPlaylist,
              onProgress: onProgress,
            );
            break;

          case CloudProviderType.dropbox:
            uploadedTrack = await _uploadToDropbox(
              preparedAudio: preparedAudio,
              account: account,
              secrets: secrets,
              playlistName: cleanPlaylist,
              onProgress: onProgress,
            );
            break;

          case CloudProviderType.box:
            uploadedTrack = await _uploadToBox(
              preparedAudio: preparedAudio,
              account: account,
              secrets: secrets,
              playlistName: cleanPlaylist,
              onProgress: onProgress,
            );
            break;

          case CloudProviderType.webdav:
            uploadedTrack = await _uploadToWebDav(
              preparedAudio: preparedAudio,
              account: account,
              secrets: secrets,
              playlistName: cleanPlaylist,
              onProgress: onProgress,
            );
            break;

          case CloudProviderType.s3:
            uploadedTrack = await _uploadToS3(
              preparedAudio: preparedAudio,
              account: account,
              secrets: secrets,
              playlistName: cleanPlaylist,
              onProgress: onProgress,
            );
            break;

          default:
            break;
        }
      } catch (e) {
        // If remote cloud upload encounters an error (token expired, permission denied, or offline),
        // we log the error and gracefully fall back to local device storage below.
        debugPrint(
            'Remote cloud upload to ${account.displayName} failed ($e). Gracefully falling back to on-device storage.');
      }
    }

    // If remote upload succeeded, purge local scratch audio file and return
    if (uploadedTrack != null) {
      await preparedAudio.purge();
      return uploadedTrack;
    }

    // High-Fidelity Local Storage Fallback:
    // If the account has no valid OAuth token (e.g. SAF mounted drive), or if remote upload
    // failed/timed out, save the downloaded song safely on-device so it is NEVER lost
    // and ALWAYS reaches the user's playlist!
    return _uploadToLocalStorage(
      preparedAudio: preparedAudio,
      account: account,
      playlistName: cleanPlaylist,
      onProgress: onProgress,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. Google Drive Multipart Upload (REST v3)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToGoogleDrive({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) {
      throw CloudUploadException('Missing Google Drive access token', provider: account.providerType);
    }

    // 1. Resolve or create parent folder "FreeBeat Music/{playlistName}"
    final parentFolderId = await _getOrCreateGoogleDriveFolder(
      token: token,
      folderName: playlistName,
      parentFolderName: 'FreeBeat Music',
    );

    // 2. Upload via multipart/related
    final boundary = 'FreeBeatBoundary_${DateTime.now().millisecondsSinceEpoch}';
    final metadataPart = jsonEncode({
      'name': preparedAudio.filename,
      if (parentFolderId.isNotEmpty) 'parents': [parentFolderId],
    });

    final fileBytes = await preparedAudio.file.readAsBytes();
    final mimeType = _getMimeType(preparedAudio.format);

    final bodyBytes = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadataPart\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Type: $mimeType\r\n\r\n'),
      ...fileBytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];

    final uri = Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size');
    final resp = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/related; boundary=$boundary',
        'Content-Length': '${bodyBytes.length}',
      },
      body: bodyBytes,
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw CloudUploadException(
        'Google Drive upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final fileId = (data['id'] as String?) ?? '${DateTime.now().millisecondsSinceEpoch}';

    return Track(
      id: 'gdrive_$fileId',
      accountId: account.id,
      providerType: CloudProviderType.googleDrive,
      remotePathOrId: fileId,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
    );
  }

  Future<String> _getOrCreateGoogleDriveFolder({
    required String token,
    required String folderName,
    required String parentFolderName,
  }) async {
    try {
      // Find or create root container "FreeBeat Music"
      String rootId = await _findDriveFolder(token, parentFolderName, null);
      if (rootId.isEmpty) {
        rootId = await _createDriveFolder(token, parentFolderName, null);
      }

      // Find or create playlist subfolder under root container
      String subId = await _findDriveFolder(token, folderName, rootId);
      if (subId.isEmpty) {
        subId = await _createDriveFolder(token, folderName, rootId);
      }
      return subId;
    } catch (_) {
      return '';
    }
  }

  Future<String> _findDriveFolder(String token, String name, String? parentId) async {
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': "name = '$name' and mimeType = 'application/vnd.google-apps.folder' and trashed = false$parentClause",
      'fields': 'files(id, name)',
    });
    final resp = await _http.get(uri, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as List<dynamic>? ?? [];
      if (files.isNotEmpty) {
        return files.first['id'] as String;
      }
    }
    return '';
  }

  Future<String> _createDriveFolder(String token, String name, String? parentId) async {
    final uri = Uri.parse('https://www.googleapis.com/drive/v3/files');
    final resp = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'mimeType': 'application/vnd.google-apps.folder',
        if (parentId != null) 'parents': [parentId],
      }),
    );
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['id'] as String;
    }
    return '';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. Microsoft OneDrive (Graph v1.0 /content)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToOneDrive({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) {
      throw CloudUploadException('Missing OneDrive access token', provider: account.providerType);
    }

    final encodedPlaylist = Uri.encodeComponent(playlistName);
    final encodedFilename = Uri.encodeComponent(preparedAudio.filename);
    final uri = Uri.parse('https://graph.microsoft.com/v1.0/me/drive/root:/FreeBeat%20Music/$encodedPlaylist/$encodedFilename:/content');

    final fileBytes = await preparedAudio.file.readAsBytes();
    final resp = await _http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': _getMimeType(preparedAudio.format),
      },
      body: fileBytes,
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw CloudUploadException(
        'OneDrive upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = data['id'] as String;
    final downloadUrl = data['@microsoft.graph.downloadUrl'] as String? ??
        'https://graph.microsoft.com/v1.0/me/drive/items/$id/content';

    return Track(
      id: 'onedrive_$id',
      accountId: account.id,
      providerType: CloudProviderType.oneDrive,
      remotePathOrId: id,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: downloadUrl,
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 3. Dropbox API v2 (/files/upload)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToDropbox({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) {
      throw CloudUploadException('Missing Dropbox access token', provider: account.providerType);
    }

    final targetPath = '/FreeBeat Music/$playlistName/${preparedAudio.filename}';
    final uri = Uri.parse('https://content.dropboxapi.com/2/files/upload');

    final fileBytes = await preparedAudio.file.readAsBytes();
    final resp = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Dropbox-API-Arg': jsonEncode({
          'path': targetPath,
          'mode': 'add',
          'autorename': true,
          'mute': false,
          'strict_conflict': false,
        }),
        'Content-Type': 'application/octet-stream',
      },
      body: fileBytes,
    );

    if (resp.statusCode != 200) {
      throw CloudUploadException(
        'Dropbox upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = data['id'] as String? ?? targetPath;
    final pathLower = data['path_lower'] as String? ?? targetPath.toLowerCase();

    return Track(
      id: 'dbx_${id.hashCode.abs()}',
      accountId: account.id,
      providerType: CloudProviderType.dropbox,
      remotePathOrId: pathLower,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: 'https://content.dropboxapi.com/2/files/download',
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 4. Box Cloud API v2 (upload.box.com/api/2.0/files/content)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToBox({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final token = secrets['accessToken'] ?? '';
    if (token.isEmpty) {
      throw CloudUploadException('Missing Box access token', provider: account.providerType);
    }

    final uri = Uri.parse('https://upload.box.com/api/2.0/files/content');
    final boundary = 'BoxBoundary_${DateTime.now().millisecondsSinceEpoch}';

    final attributes = jsonEncode({
      'name': preparedAudio.filename,
      'parent': {'id': '0'},
    });

    final fileBytes = await preparedAudio.file.readAsBytes();
    final bodyBytes = <int>[
      ...utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="attributes"\r\n\r\n$attributes\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="${preparedAudio.filename}"\r\nContent-Type: ${_getMimeType(preparedAudio.format)}\r\n\r\n'),
      ...fileBytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];

    final resp = await _http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'multipart/form-data; boundary=$boundary',
      },
      body: bodyBytes,
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw CloudUploadException(
        'Box upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final entries = data['entries'] as List<dynamic>? ?? [];
    final id = entries.isNotEmpty ? (entries.first['id'] as String) : '${DateTime.now().millisecondsSinceEpoch}';

    return Track(
      id: 'box_$id',
      accountId: account.id,
      providerType: CloudProviderType.box,
      remotePathOrId: id,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: 'https://api.box.com/2.0/files/$id/content',
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 5. WebDAV / Nextcloud (MKCOL & PUT)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToWebDav({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final password = secrets['password'] ?? '';
    final authHeader = 'Basic ${base64Encode(utf8.encode("${account.usernameOrEmail}:$password"))}';
    final baseUri = account.endpointOrFolder.endsWith('/')
        ? account.endpointOrFolder.substring(0, account.endpointOrFolder.length - 1)
        : account.endpointOrFolder;

    // Create folders if they don't exist
    try {
      final req1 = http.Request('MKCOL', Uri.parse('$baseUri/FreeBeat%20Music'));
      req1.headers['Authorization'] = authHeader;
      await _http.send(req1);

      final req2 = http.Request('MKCOL', Uri.parse('$baseUri/FreeBeat%20Music/${Uri.encodeComponent(playlistName)}'));
      req2.headers['Authorization'] = authHeader;
      await _http.send(req2);
    } catch (_) {}

    final targetUrl = '$baseUri/FreeBeat%20Music/${Uri.encodeComponent(playlistName)}/${Uri.encodeComponent(preparedAudio.filename)}';
    final fileBytes = await preparedAudio.file.readAsBytes();

    final resp = await _http.put(
      Uri.parse(targetUrl),
      headers: {
        'Authorization': authHeader,
        'Content-Type': _getMimeType(preparedAudio.format),
      },
      body: fileBytes,
    );

    if (resp.statusCode != 200 && resp.statusCode != 201 && resp.statusCode != 204) {
      throw CloudUploadException(
        'WebDAV upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final remotePath = '/FreeBeat Music/$playlistName/${preparedAudio.filename}';
    return Track(
      id: 'webdav_${remotePath.hashCode.abs()}',
      accountId: account.id,
      providerType: CloudProviderType.webdav,
      remotePathOrId: remotePath,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: targetUrl,
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 6. S3 / Cloudflare R2 / MinIO (AWS SigV4 Presigned PUT)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToS3({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final accessKey = secrets['accessKeyId'] ?? '';
    final secretKey = secrets['secretAccessKey'] ?? '';
    final bucket = account.bucketOrShareName.isNotEmpty ? account.bucketOrShareName : 'music';
    final objectKey = 'FreeBeat Music/$playlistName/${preparedAudio.filename}';

    final presignedPutUrl = _generatePresignedPutUrl(
      endpointHost: account.endpointOrFolder,
      bucket: bucket,
      objectKey: objectKey,
      accessKeyId: accessKey,
      secretAccessKey: secretKey,
      region: account.region,
    );

    final fileBytes = await preparedAudio.file.readAsBytes();
    final resp = await _http.put(
      Uri.parse(presignedPutUrl),
      headers: {
        'Content-Type': _getMimeType(preparedAudio.format),
      },
      body: fileBytes,
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw CloudUploadException(
        'S3 upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final cleanHost = account.endpointOrFolder
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '');
    final streamUrl = 'https://$cleanHost/$bucket/$objectKey';

    return Track(
      id: 's3_${objectKey.hashCode.abs()}',
      accountId: account.id,
      providerType: CloudProviderType.s3,
      remotePathOrId: objectKey,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: streamUrl,
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
    );
  }

  static String _generatePresignedPutUrl({
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
    final cleanKey = objectKey.startsWith('/') ? objectKey.substring(1) : objectKey;
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
        .map((k) => '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(queryParams[k]!)}')
        .join('&');

    final canonicalRequest = [
      'PUT',
      canonicalUri,
      canonicalQueryString,
      'host:$cleanHost\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final canonicalRequestHash = sha256.convert(utf8.encode(canonicalRequest)).toString();

    final stringToSign = [
      'AWS4-HMAC-SHA256',
      amzDate,
      credentialScope,
      canonicalRequestHash,
    ].join('\n');

    List<int> hmacSha256(List<int> key, String data) => Hmac(sha256, key).convert(utf8.encode(data)).bytes;

    final kDate = hmacSha256(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = hmacSha256(kDate, region);
    final kService = hmacSha256(kRegion, 's3');
    final kSigning = hmacSha256(kService, 'aws4_request');
    final signature = Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();

    return 'https://$cleanHost$canonicalUri?$canonicalQueryString&X-Amz-Signature=$signature';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 7. On-Device Local Storage (Fallback)
  // ───────────────────────────────────────────────────────────────────────────

  Future<Track> _uploadToLocalStorage({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final localMusicDir = Directory(p.join(appDocDir.path, 'imported_music', playlistName));
    if (!await localMusicDir.exists()) {
      await localMusicDir.create(recursive: true);
    }

    final destFile = File(p.join(localMusicDir.path, preparedAudio.filename));
    await preparedAudio.file.copy(destFile.path);
    await preparedAudio.purge();

    onProgress?.call(1.0);

    return Track(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}_${preparedAudio.filename.hashCode.abs()}',
      accountId: account.id,
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: destFile.path,
      title: preparedAudio.title,
      artist: preparedAudio.artist,
      album: preparedAudio.album,
      durationMs: preparedAudio.durationMs,
      streamUrl: destFile.path,
      codec: preparedAudio.format.toUpperCase(),
      bitDepth: 16,
      sampleRateHz: 44100,
      bitrateKbps: preparedAudio.bitrateKbps,
      sizeBytes: preparedAudio.sizeBytes,
      artworkUrl: preparedAudio.artworkUrl,
      dominantColorValue: preparedAudio.dominantColorValue,
      syncedLyrics: preparedAudio.syncedLyrics,
      isPinnedOffline: true,
      localCachePath: destFile.path,
    );
  }

  static String _getMimeType(String format) {
    switch (format.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'opus':
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
      case 'aac':
      default:
        return 'audio/mp4';
    }
  }

  static String _sanitizeFolder(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
