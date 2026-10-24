import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../core/storage/secure_credential_store.dart';
import '../../providers/implementations/network_and_saf_connectors.dart';

/// Rule A3: Authenticated Local Loopback Stream & Offline Cache Proxy (`127.0.0.1`).
/// Binds strictly to `InternetAddress.loopbackIPv4`, injects rolling cloud OAuth/SigV4/WebDAV
/// headers, handles HTTP `206 Partial Content` range requests for `<40ms` Hi-Fi seeking,
/// and adapts stream URLs to the user-configured [AudioQualityTier].
class CloudStreamProxy {
  CloudStreamProxy({
    required this.connectorRegistry,
    required this.credentialStore,
  });

  final CloudConnectorRegistry connectorRegistry;
  final SecureCredentialStore credentialStore;
  final http.Client _upstreamClient = http.Client();

  HttpServer? _server;
  int _port = 0;

  final Map<String, Track> _registeredTracks = {};
  final Map<String, CloudAccount> _registeredAccounts = {};
  AudioQualityTier _activeTier = AudioQualityTier.hifiLossless;

  int get port => _port;
  bool get isRunning => _server != null;

  void updateCatalog({
    required List<Track> tracks,
    required List<CloudAccount> accounts,
    required AudioQualityTier activeTier,
  }) {
    for (final t in tracks) {
      _registeredTracks[t.id] = t;
    }
    for (final a in accounts) {
      _registeredAccounts[a.id] = a;
    }
    _activeTier = activeTier;
  }

  void registerTrack(Track track, {CloudAccount? account}) {
    _registeredTracks[track.id] = track;
    if (account != null) {
      _registeredAccounts[account.id] = account;
    }
  }

  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(_handleRequest, onError: (_) {});
    } catch (_) {
      _port = 0;
    }
  }

  String _resolveTrackExtension(Track track) {
    final rawExt = p.extension(track.streamUrl).toLowerCase();
    if (rawExt.isNotEmpty && rawExt.startsWith('.')) return rawExt;
    final c = track.codec.toLowerCase();
    if (c == 'm4a' || c == 'aac' || c == 'alac') return '.m4a';
    if (c == 'wma' || c == 'asf') return '.wma';
    if (c == 'flac') return '.flac';
    if (c == 'wav') return '.wav';
    if (c == 'ogg') return '.ogg';
    if (c == 'opus') return '.opus';
    if (c == 'aiff' || c == 'aif') return '.aiff';
    if (c == 'ape') return '.ape';
    if (c == 'dsd' || c == 'dsf' || c == 'dff') return '.dsf';
    return '.mp3';
  }

  String _getMimeTypeForTrack(Track track) {
    final ext = _resolveTrackExtension(track);
    switch (ext) {
      case '.m4a':
      case '.mp4':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.wma':
      case '.asf':
        return 'audio/x-ms-wma';
      case '.flac':
        return 'audio/flac';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.ogg':
      case '.oga':
        return 'audio/ogg';
      case '.opus':
        return 'audio/opus';
      case '.aiff':
      case '.aif':
        return 'audio/x-aiff';
      case '.ape':
        return 'audio/x-ape';
      default:
        return 'audio/mpeg';
    }
  }

  /// Returns the loopback proxy URL for [track] at [tier], or direct URL if proxy isn't active.
  String buildPlaybackUrl(Track track, AudioQualityTier tier) {
    if (track.localCachePath != null &&
        track.localCachePath!.isNotEmpty &&
        (track.isPinnedOffline || File(track.localCachePath!).existsSync())) {
      return track.localCachePath!;
    }
    // If streamUrl is a local file on device storage or imported music, return direct path
    if (!track.streamUrl.startsWith('http://') &&
        !track.streamUrl.startsWith('https://')) {
      return track.streamUrl;
    }
    if (_port <= 0) return track.streamUrl;
    final ext = _resolveTrackExtension(track);
    return 'http://127.0.0.1:$_port/stream/${Uri.encodeComponent(track.id)}/stream$ext?tier=${tier.id}';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments.first != 'stream') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final trackId = Uri.decodeComponent(segments[1]);
      final track = _registeredTracks[trackId];
      if (track == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final account = _registeredAccounts[track.accountId] ??
          CloudAccount(
            id: track.accountId,
            providerType: track.providerType,
            displayName: track.providerType.displayName,
            endpointOrFolder: '/',
          );

      final secrets = await credentialStore.readSecrets(account.id);
      final connector = connectorRegistry.forType(track.providerType);

      // Parse incoming Range header from ExoPlayer (e.g. "bytes=65536-")
      int? startByte;
      int? endByte;
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        startByte = int.tryParse(parts.first);
        if (parts.length > 1 && parts[1].isNotEmpty) {
          endByte = int.tryParse(parts[1]);
        }
      }

      // If the track is cached or preloaded on disk, serve it directly with full byte-range support!
      final localFile = await _findPreloadedFile(track);
      if (localFile != null && localFile.existsSync()) {
        await _serveLocalFile(
          request,
          localFile,
          track,
          requestedStart: startByte,
          requestedEnd: endByte,
        );
        return;
      }

      final spec = await connector.resolveStream(
        track,
        account,
        secrets,
        targetQuality: _activeTier,
        startByte: startByte,
        endByte: endByte,
      );

      final upstreamReq = http.Request('GET', Uri.parse(spec.url));
      upstreamReq.headers.addAll(spec.headers);

      final upstreamResp = await _upstreamClient.send(upstreamReq);
      request.response.statusCode = upstreamResp.statusCode;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      String? upstreamContentType;
      upstreamResp.headers.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'content-length' || lower == 'content-range') {
          request.response.headers.set(key, value);
        } else if (lower == 'content-type') {
          upstreamContentType = value;
        }
      });

      // Ensure a valid, precise audio MIME type so ExoPlayer chooses the correct extractor
      final resolvedMime = (upstreamContentType != null &&
              upstreamContentType!.startsWith('audio/') &&
              !upstreamContentType!.contains('octet-stream'))
          ? upstreamContentType!
          : _getMimeTypeForTrack(track);
      request.response.headers.set(HttpHeaders.contentTypeHeader, resolvedMime);

      request.response.bufferOutput = false;
      await request.response.addStream(upstreamResp.stream);
      await request.response.close();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<File?> _findPreloadedFile(Track track) async {
    if (track.localCachePath != null && track.localCachePath!.isNotEmpty) {
      final f = File(track.localCachePath!);
      if (f.existsSync() && f.lengthSync() > 1024) return f;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(appDir.path, 'cached_music'));
      if (cacheDir.existsSync()) {
        final sanitizedId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        for (final entry in cacheDir.listSync()) {
          if (entry is File) {
            final base = p.basenameWithoutExtension(entry.path);
            if (base == sanitizedId && entry.lengthSync() > 1024) {
              return entry;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _serveLocalFile(
    HttpRequest request,
    File file,
    Track track, {
    int? requestedStart,
    int? requestedEnd,
  }) async {
    try {
      final fileLength = await file.length();
      int start = requestedStart ?? 0;
      int end = requestedEnd ?? (fileLength - 1);
      if (start >= fileLength) start = 0;
      if (end >= fileLength) end = fileLength - 1;

      final isPartial = (requestedStart != null || requestedEnd != null);
      request.response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (isPartial) {
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$fileLength');
        request.response.headers.set(HttpHeaders.contentLengthHeader, (end - start + 1).toString());
      } else {
        request.response.headers.set(HttpHeaders.contentLengthHeader, fileLength.toString());
      }
      request.response.headers.set(HttpHeaders.contentTypeHeader, _getMimeTypeForTrack(track));
      request.response.bufferOutput = false;

      await request.response.addStream(file.openRead(start, end + 1));
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _upstreamClient.close();
  }
}
