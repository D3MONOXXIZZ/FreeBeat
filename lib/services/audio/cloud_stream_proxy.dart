import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
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

  /// Returns the loopback proxy URL for [track] at [tier], or direct URL if proxy isn't active.
  String buildPlaybackUrl(Track track, AudioQualityTier tier) {
    if (track.isPinnedOffline &&
        track.localCachePath != null &&
        track.localCachePath!.isNotEmpty) {
      return track.localCachePath!;
    }
    if (_port <= 0) return track.streamUrl;
    return 'http://127.0.0.1:$_port/stream/${Uri.encodeComponent(track.id)}?tier=${tier.id}';
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

      upstreamResp.headers.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'content-type' ||
            lower == 'content-length' ||
            lower == 'content-range') {
          request.response.headers.set(key, value);
        }
      });

      await upstreamResp.stream.pipe(request.response);
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
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
