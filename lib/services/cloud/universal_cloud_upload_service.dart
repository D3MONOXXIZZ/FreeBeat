import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
// ignore: unused_import
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
  final Map<String, String> _folderIdCache = {};
  final Map<String, List<Map<String, dynamic>>> _folderFilesCache = {};
  final Map<String, Future<String>> _inFlightFolderCreation = {};

  static String _normalizeTrackString(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // remove parenthesized details
        .replaceAll(RegExp(r'[^\w\s]'), '') // remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Lists all audio files inside a Google Drive folder, cached per folderId.
  Future<List<Map<String, dynamic>>> _listDriveFolderFiles(
    String token,
    String folderId,
  ) async {
    final cacheKey = '$token:$folderId';
    if (_folderFilesCache.containsKey(cacheKey)) {
      return _folderFilesCache[cacheKey]!;
    }

    try {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': "'$folderId' in parents and trashed = false and mimeType != 'application/vnd.google-apps.folder'",
        'fields': 'files(id, name, size, mimeType)',
        'pageSize': '1000',
      });
      final resp = await _http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final files = (data['files'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        _folderFilesCache[cacheKey] = files;
        return files;
      }
    } catch (_) {}
    return [];
  }

  Map<String, dynamic>? _matchFileInList({
    required List<Map<String, dynamic>> files,
    String? expectedFilename,
    required String title,
    required String artist,
  }) {
    if (files.isEmpty) return null;

    final cleanTitle = _normalizeTrackString(title);
    final cleanArtist = _normalizeTrackString(artist);
    final primaryArtist = cleanArtist.split(RegExp(r'[,&;]')).first.trim();

    // 1. Exact filename match
    if (expectedFilename != null && expectedFilename.isNotEmpty) {
      final lowerExpected = expectedFilename.toLowerCase();
      for (final f in files) {
        final name = (f['name'] ?? '').toString().toLowerCase();
        if (name == lowerExpected) return f;
      }
    }

    // 2. Normalized filename match (artist + title)
    for (final f in files) {
      final name = _normalizeTrackString((f['name'] ?? '').toString());
      if (cleanArtist.isNotEmpty && cleanTitle.isNotEmpty) {
        if (name.contains(cleanTitle) && (name.contains(cleanArtist) || (primaryArtist.isNotEmpty && name.contains(primaryArtist)))) {
          return f;
        }
      }
    }

    // 3. Title match if candidate title is specific (> 3 chars)
    if (cleanTitle.length > 3) {
      for (final f in files) {
        final name = _normalizeTrackString((f['name'] ?? '').toString());
        if (name.contains(cleanTitle)) {
          // If artist is specified, ensure it doesn't contradict
          if (primaryArtist.isNotEmpty && name.contains(' - ')) {
            if (!name.contains(primaryArtist)) continue;
          }
          return f;
        }
      }
    }

    return null;
  }

  /// Checks if an audio file for a given track already exists in the destination cloud folder
  /// or local storage. Returns the existing [Track] if found, preventing redundant downloads
  /// and duplicate cloud uploads.
  Future<Track?> findExistingCloudTrack({
    required CloudAccount account,
    required Map<String, String> secrets,
    required String playlistName,
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final cleanPlaylist = _sanitizeFolder(playlistName);
    var token = secrets['accessToken'] ?? '';

    if (account.providerType == CloudProviderType.googleDrive) {
      if (token.isEmpty) return null;
      try {
        final folderId = await _getOrCreateGoogleDriveFolder(
          token: token,
          folderName: cleanPlaylist,
          parentFolderName: 'FreeBeat Music',
        );
        if (folderId.isEmpty) return null;

        final files = await _listDriveFolderFiles(token, folderId);
        final match = _matchFileInList(
          files: files,
          title: title,
          artist: artist,
        );
        if (match != null) {
          final fileId = match['id'] as String;
          final fileName = (match['name'] as String?) ?? '$artist - $title';
          final sizeBytes = int.tryParse(match['size']?.toString() ?? '') ?? 0;
          final ext = p.extension(fileName).replaceFirst('.', '').toLowerCase();

          final calculatedKbps = (sizeBytes > 0 && expectedDurationMs != null && expectedDurationMs > 0)
              ? ((sizeBytes * 8) / (expectedDurationMs / 1000) / 1000).round()
              : 320;
          final dynamicKbps = calculatedKbps.clamp(128, 320);
          return Track(
            id: 'gdrive_$fileId',
            accountId: account.id,
            providerType: CloudProviderType.googleDrive,
            remotePathOrId: fileId,
            title: title,
            artist: artist,
            album: preferredAlbum ?? playlistName,
            durationMs: expectedDurationMs ?? 210000,
            streamUrl: 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
            codec: ext.isNotEmpty ? ext.toUpperCase() : 'M4A',
            bitDepth: 16,
            sampleRateHz: 44100,
            bitrateKbps: dynamicKbps,
            sizeBytes: sizeBytes > 0 ? sizeBytes : 5000000,
            artworkUrl: preferredArtworkUrl,
            dominantColorValue: 0xFF1E293B,
            isPinnedOffline: false,
          );
        }
      } catch (_) {}
    } else if (account.providerType == CloudProviderType.androidSaf ||
        account.endpointOrFolder.contains('Android App Storage') ||
        account.endpointOrFolder.contains('Folder Import')) {
      // Local Storage Check
      try {
        final localMusicDir = await resolveMusicStorageDirectory(
          cleanPlaylist,
          customFolder: account.endpointOrFolder,
        );
        final cleanTitle = _normalizeTrackString(title);
        final cleanArtist = _normalizeTrackString(artist);
        final entities = localMusicDir.listSync();
        for (final entity in entities) {
          if (entity is File) {
            final fName = _normalizeTrackString(p.basename(entity.path));
            if (fName.contains(cleanTitle) && (cleanArtist.isEmpty || fName.contains(cleanArtist))) {
              final stat = entity.statSync();
              final ext = p.extension(entity.path).replaceFirst('.', '').toLowerCase();
              final calculatedKbps = (stat.size > 0 && expectedDurationMs != null && expectedDurationMs > 0)
                  ? ((stat.size * 8) / (expectedDurationMs / 1000) / 1000).round()
                  : 320;
              final dynamicKbps = calculatedKbps.clamp(128, 320);
              return Track(
                id: 'local_${stat.modified.millisecondsSinceEpoch}_${entity.path.hashCode.abs()}',
                accountId: account.id,
                providerType: CloudProviderType.androidSaf,
                remotePathOrId: entity.path,
                title: title,
                artist: artist,
                album: preferredAlbum ?? playlistName,
                durationMs: expectedDurationMs ?? 210000,
                streamUrl: entity.path,
                codec: ext.isNotEmpty ? ext.toUpperCase() : 'M4A',
                bitDepth: 16,
                sampleRateHz: 44100,
                bitrateKbps: dynamicKbps,
                sizeBytes: stat.size > 0 ? stat.size : 5000000,
                artworkUrl: preferredArtworkUrl,
                dominantColorValue: 0xFF1E293B,
                isPinnedOffline: false,
              );
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

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
    Future<String?> Function()? onTokenExpired,
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

    final isRemoteCloud = !isSafMount &&
        account.providerType != CloudProviderType.androidSaf &&
        account.providerType != CloudProviderType.demoCloud;

    if (isRemoteCloud) {
      if (!hasRemoteAuth && account.providerType == CloudProviderType.googleDrive && onTokenExpired != null) {
        final fresh = await onTokenExpired();
        if (fresh != null && fresh.isNotEmpty) {
          secrets['accessToken'] = fresh;
        }
      }

      switch (account.providerType) {
        case CloudProviderType.googleDrive:
          uploadedTrack = await _uploadToGoogleDrive(
            preparedAudio: preparedAudio,
            account: account,
            secrets: secrets,
            playlistName: cleanPlaylist,
            onProgress: onProgress,
            onTokenExpired: onTokenExpired,
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

      if (uploadedTrack != null) {
        await preparedAudio.purge();
        return uploadedTrack;
      }

      throw CloudUploadException(
        'Failed to upload to ${account.displayName}',
        provider: account.providerType,
      );
    }

    // High-Fidelity Local Storage Fallback:
    // Only used for explicit on-device storage accounts or SAF mounted app storage.
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
    Future<String?> Function()? onTokenExpired,
  }) async {
    var token = secrets['accessToken'] ?? '';
    if (token.isEmpty && onTokenExpired != null) {
      final fresh = await onTokenExpired();
      if (fresh != null && fresh.isNotEmpty) {
        token = fresh;
        secrets['accessToken'] = fresh;
      }
    }
    if (token.isEmpty) {
      throw CloudUploadException('Missing Google Drive access token', provider: account.providerType);
    }

    // 1. Resolve or create parent folder "FreeBeat Music/{playlistName}" with memory cache
    final parentFolderId = await _getOrCreateGoogleDriveFolder(
      token: token,
      folderName: playlistName,
      parentFolderName: 'FreeBeat Music',
    );

    // Deduplication check: verify if this track or file already exists in this Google Drive folder
    if (parentFolderId.isNotEmpty) {
      try {
        final existingFiles = await _listDriveFolderFiles(token, parentFolderId);
        final match = _matchFileInList(
          files: existingFiles,
          expectedFilename: preparedAudio.filename,
          title: preparedAudio.title,
          artist: preparedAudio.artist,
        );
        if (match != null) {
          final existingId = match['id'] as String;
          final existingSize = int.tryParse(match['size']?.toString() ?? '') ?? preparedAudio.sizeBytes;
          await preparedAudio.purge();
          onProgress?.call(1.0);
          return Track(
            id: 'gdrive_$existingId',
            accountId: account.id,
            providerType: CloudProviderType.googleDrive,
            remotePathOrId: existingId,
            title: preparedAudio.title,
            artist: preparedAudio.artist,
            album: preparedAudio.album,
            durationMs: preparedAudio.durationMs,
            streamUrl: 'https://www.googleapis.com/drive/v3/files/$existingId?alt=media',
            codec: preparedAudio.format.toUpperCase(),
            bitDepth: 16,
            sampleRateHz: 44100,
            bitrateKbps: preparedAudio.bitrateKbps,
            sizeBytes: existingSize,
            artworkUrl: preparedAudio.artworkUrl,
            dominantColorValue: preparedAudio.dominantColorValue,
            syncedLyrics: preparedAudio.syncedLyrics,
            isPinnedOffline: false,
          );
        }
      } catch (_) {}
    }

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
    ).timeout(const Duration(seconds: 40));

    if (resp.statusCode == 401 && onTokenExpired != null) {
      final freshToken = await onTokenExpired();
      if (freshToken != null && freshToken.isNotEmpty) {
        secrets['accessToken'] = freshToken;
        _folderIdCache.clear();
        return _uploadToGoogleDrive(
          preparedAudio: preparedAudio,
          account: account,
          secrets: secrets,
          playlistName: playlistName,
          onProgress: onProgress,
        );
      }
    }

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw CloudUploadException(
        'Google Drive upload failed: ${resp.body}',
        statusCode: resp.statusCode,
        provider: account.providerType,
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final fileId = (data['id'] as String?) ?? '${DateTime.now().millisecondsSinceEpoch}';

    // Update folder files cache so subsequent deduplication checks know this file exists
    if (parentFolderId.isNotEmpty) {
      final cacheKey = '$token:$parentFolderId';
      _folderFilesCache[cacheKey]?.add({
        'id': fileId,
        'name': preparedAudio.filename,
        'size': '${preparedAudio.sizeBytes}',
        'mimeType': mimeType,
      });
    }

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
      isPinnedOffline: false,
    );
  }

  Future<String> _getOrCreateGoogleDriveFolder({
    required String token,
    required String folderName,
    required String parentFolderName,
  }) async {
    final subCacheKey = '$token:$parentFolderName/$folderName';
    if (_folderIdCache.containsKey(subCacheKey)) {
      return _folderIdCache[subCacheKey]!;
    }

    // In-flight concurrency gate: if another worker is currently finding or creating
    // this folder, await that same in-flight future rather than creating duplicate folders!
    if (_inFlightFolderCreation.containsKey(subCacheKey)) {
      return await _inFlightFolderCreation[subCacheKey]!;
    }

    final future = _doGetOrCreateGoogleDriveFolder(
      token: token,
      folderName: folderName,
      parentFolderName: parentFolderName,
      subCacheKey: subCacheKey,
    );
    _inFlightFolderCreation[subCacheKey] = future;
    try {
      final res = await future;
      return res;
    } finally {
      _inFlightFolderCreation.remove(subCacheKey);
    }
  }

  Future<String> _doGetOrCreateGoogleDriveFolder({
    required String token,
    required String folderName,
    required String parentFolderName,
    required String subCacheKey,
  }) async {
    try {
      // 1. Find or create root container "FreeBeat Music"
      final rootCacheKey = '$token:$parentFolderName';
      String rootId = _folderIdCache[rootCacheKey] ?? '';
      if (rootId.isEmpty) {
        if (_inFlightFolderCreation.containsKey(rootCacheKey)) {
          rootId = await _inFlightFolderCreation[rootCacheKey]!;
        } else {
          final rootFuture = _findOrCreateDriveFolder(token, parentFolderName, null);
          _inFlightFolderCreation[rootCacheKey] = rootFuture;
          try {
            rootId = await rootFuture;
            if (rootId.isNotEmpty) {
              _folderIdCache[rootCacheKey] = rootId;
            }
          } finally {
            _inFlightFolderCreation.remove(rootCacheKey);
          }
        }
      }

      // 2. Find or create playlist subfolder under root container
      String subId = await _findDriveFolder(token, folderName, rootId.isNotEmpty ? rootId : null);
      if (subId.isEmpty) {
        subId = await _createDriveFolder(token, folderName, rootId.isNotEmpty ? rootId : null);
      }
      if (subId.isNotEmpty) {
        _folderIdCache[subCacheKey] = subId;
      }
      return subId;
    } catch (_) {
      return '';
    }
  }

  Future<String> _findOrCreateDriveFolder(String token, String name, String? parentId) async {
    var id = await _findDriveFolder(token, name, parentId);
    if (id.isEmpty) {
      id = await _createDriveFolder(token, name, parentId);
    }
    return id;
  }

  Future<String> _findDriveFolder(String token, String name, String? parentId) async {
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final safeName = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'q': "name = '$safeName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false$parentClause",
      'fields': 'files(id, name, createdTime)',
      'orderBy': 'createdTime asc',
    });
    final resp = await _http.get(uri, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final files = data['files'] as List<dynamic>? ?? [];
      if (files.isNotEmpty) {
        final primaryId = files.first['id'] as String;
        // If duplicate folders exist with this name, asynchronously consolidate files and trash duplicates!
        if (files.length > 1) {
          unawaited(_cleanupDuplicateDriveFolders(token, primaryId, files.sublist(1)));
        }
        return primaryId;
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
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 200 || resp.statusCode == 201) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['id'] as String;
    }
    return '';
  }

  /// Automatically consolidates files from duplicate folders into the primary folder
  /// and trashes the redundant empty folders so the user's Drive stays clean.
  Future<void> _cleanupDuplicateDriveFolders(
    String token,
    String primaryFolderId,
    List<dynamic> duplicateFolders,
  ) async {
    for (final dup in duplicateFolders) {
      if (dup is! Map) continue;
      final dupId = dup['id']?.toString() ?? '';
      if (dupId.isEmpty || dupId == primaryFolderId) continue;

      try {
        final files = await _listDriveFolderFiles(token, dupId);
        final primaryFiles = await _listDriveFolderFiles(token, primaryFolderId);

        for (final file in files) {
          final fileId = file['id'] as String?;
          final fileName = file['name'] as String?;
          if (fileId == null || fileId.isEmpty) continue;

          final alreadyInPrimary = primaryFiles.any((pf) => pf['name'] == fileName);
          if (alreadyInPrimary) {
            await _http.patch(
              Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'trashed': true}),
            );
          } else {
            await _http.patch(
              Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?addParents=$primaryFolderId&removeParents=$dupId'),
              headers: {'Authorization': 'Bearer $token'},
            );
            primaryFiles.add(file);
          }
        }

        // Trash the redundant duplicate folder
        await _http.patch(
          Uri.parse('https://www.googleapis.com/drive/v3/files/$dupId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'trashed': true}),
        );
      } catch (e) {
        debugPrint('Note: Cleanup of duplicate Drive folder $dupId caught: $e');
      }
    }
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
    ).timeout(const Duration(seconds: 40));

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
    ).timeout(const Duration(seconds: 40));

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
    ).timeout(const Duration(seconds: 40));

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
    ).timeout(const Duration(seconds: 40));

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

  /// Resolves the most accessible, user-visible public music directory
  /// for saving playlist tracks on the local device.
  ///
  /// Priority:
  /// 1. Custom folder path if configured and accessible.
  /// 2. Primary Public Android Music folder: `/storage/emulated/0/Music/<playlistName>/`
  /// 3. Public Android Download folder: `/storage/emulated/0/Download/FreeBeat Music/<playlistName>/`
  /// 4. App-specific External Storage Music directory:
  ///    `/storage/emulated/0/Android/data/com.freebeat.app/files/Music/<playlistName>/`
  /// 5. Application Documents Directory (Desktop, iOS, or sandboxed fallback).
  static Future<Directory> resolveMusicStorageDirectory(
    String playlistName, {
    String? customFolder,
  }) async {
    final clean = _sanitizeFolder(playlistName);

    // 1. Explicit valid custom folder
    if (customFolder != null &&
        customFolder.isNotEmpty &&
        customFolder != '/FreeBeat Music/' &&
        customFolder != 'Local Music Files') {
      try {
        final d = Directory(p.join(customFolder, clean));
        if (!await d.exists()) await d.create(recursive: true);
        final probe = File(p.join(d.path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
        await probe.writeAsString('ok');
        await probe.delete();
        return d;
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      // 2. Standard Public Music folder: /storage/emulated/0/Music/<playlistName>
      try {
        final d = Directory('/storage/emulated/0/Music/$clean');
        if (!await d.exists()) await d.create(recursive: true);
        final probe = File(p.join(d.path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
        await probe.writeAsString('ok');
        await probe.delete();
        return d;
      } catch (_) {}

      // 3. Public Download folder: /storage/emulated/0/Download/FreeBeat Music/<playlistName>
      try {
        final d = Directory('/storage/emulated/0/Download/FreeBeat Music/$clean');
        if (!await d.exists()) await d.create(recursive: true);
        final probe = File(p.join(d.path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
        await probe.writeAsString('ok');
        await probe.delete();
        return d;
      } catch (_) {}

      // 4. App-Specific External Storage Music directory
      // (always writable on Android 10-15+ without needing special permissions, accessible via USB)
      try {
        final extMusicDirs = await getExternalStorageDirectories(type: StorageDirectory.music);
        if (extMusicDirs != null && extMusicDirs.isNotEmpty) {
          final d = Directory(p.join(extMusicDirs.first.path, clean));
          if (!await d.exists()) await d.create(recursive: true);
          return d;
        }
      } catch (_) {}

      // 5. App-Specific External Storage Files root
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final d = Directory(p.join(extDir.path, 'Music', clean));
          if (!await d.exists()) await d.create(recursive: true);
          return d;
        }
      } catch (_) {}
    }

    // 6. Application Documents Directory (Desktop/iOS/sandbox fallback)
    final appDocDir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(appDocDir.path, 'FreeBeat Music', clean));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Returns the human-readable storage address where imported or downloaded
  /// songs are stored on device for a given playlist.
  static Future<String> getPublicMusicStorageAddress({String playlistName = 'YourPlaylist'}) async {
    final dir = await resolveMusicStorageDirectory(playlistName);
    return dir.path;
  }

  /// Public accessor for saving tracks directly to local on-device storage.
  Future<Track> uploadToLocalStorage({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) =>
      _uploadToLocalStorage(
        preparedAudio: preparedAudio,
        account: account,
        playlistName: playlistName,
        onProgress: onProgress,
      );

  Future<Track> _uploadToLocalStorage({
    required PreparedTrackAudio preparedAudio,
    required CloudAccount account,
    required String playlistName,
    void Function(double progress)? onProgress,
  }) async {
    final localMusicDir = await resolveMusicStorageDirectory(
      playlistName,
      customFolder: account.endpointOrFolder,
    );

    final destFile = File(p.join(localMusicDir.path, preparedAudio.filename));

    // Deduplication check: if destination file already exists and is non-empty valid audio, reuse it
    if (destFile.existsSync() && destFile.lengthSync() > 100000) {
      final existingSize = destFile.lengthSync();
      try {
        await preparedAudio.purge();
      } catch (_) {}
      onProgress?.call(1.0);
      return Track(
        id: 'local_${destFile.path.hashCode.abs()}',
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
        sizeBytes: existingSize,
        artworkUrl: preparedAudio.artworkUrl,
        dominantColorValue: preparedAudio.dominantColorValue,
        syncedLyrics: preparedAudio.syncedLyrics,
        isPinnedOffline: true,
      );
    }

    try {
      await preparedAudio.file.rename(destFile.path);
    } catch (_) {
      await preparedAudio.file.copy(destFile.path);
      await preparedAudio.purge();
    }

    onProgress?.call(1.0);

    return Track(
      id: 'local_${destFile.path.hashCode.abs()}',
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
      isPinnedOffline: false,
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
