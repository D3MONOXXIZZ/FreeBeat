import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/models/cloud_account.dart';

/// Represents a media server discovered on the local Wi-Fi or emulator host.
class DiscoveredMediaServer {
  const DiscoveredMediaServer({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    required this.discoveredVia,
  });

  final String id;
  final String name;
  final String url;
  final CloudProviderType type;
  final String discoveredVia;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredMediaServer &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;
}

/// Discovers local Jellyfin/Emby and Navidrome/Subsonic media servers on Wi-Fi/LAN
/// via UDP broadcast (port 7359) and fast endpoint probes.
class LocalMediaServerDiscoveryService {
  LocalMediaServerDiscoveryService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Discover all local servers using UDP broadcast and fast candidate probes.
  Future<List<DiscoveredMediaServer>> discoverAll({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final results = <DiscoveredMediaServer>{};

    // 1. Run UDP 7359 broadcast for Jellyfin/Emby
    final udpServers = await _discoverJellyfinUdp(timeout: timeout);
    results.addAll(udpServers);

    // 2. Fast candidate probes for emulator, localhost, and common LAN gateways
    final probeServers = await _probeCommonEndpoints();
    results.addAll(probeServers);

    return results.toList();
  }

  Future<List<DiscoveredMediaServer>> _discoverJellyfinUdp({
    required Duration timeout,
  }) async {
    final servers = <DiscoveredMediaServer>[];
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? sub;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final message = utf8.encode('who is JellyfinServer?');
      socket.send(message, InternetAddress('255.255.255.255'), 7359);

      final completer = Completer<void>();
      sub = socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            try {
              final raw = utf8.decode(datagram.data);
              final data = jsonDecode(raw) as Map<String, dynamic>;
              final address = data['Address']?.toString() ??
                  'http://${datagram.address.address}:8096';
              final name = data['Name']?.toString() ?? 'Jellyfin Media Server';
              final id = data['Id']?.toString() ?? address;
              servers.add(
                DiscoveredMediaServer(
                  id: id,
                  name: name,
                  url: address,
                  type: CloudProviderType.jellyfin,
                  discoveredVia: 'UDP 7359 Broadcast',
                ),
              );
            } catch (_) {}
          }
        }
      });

      await Future.any([
        Future.delayed(timeout),
        completer.future,
      ]);
    } catch (_) {
      // Ignore UDP socket errors in restricted sandbox or emulator environments
    } finally {
      await sub?.cancel();
      socket?.close();
    }

    return servers;
  }

  Future<List<DiscoveredMediaServer>> _probeCommonEndpoints() async {
    final candidates = <Map<String, dynamic>>[
      // Android Emulator Host loopbacks
      {
        'url': 'http://10.0.2.2:8096',
        'type': CloudProviderType.jellyfin,
        'name': 'Host Machine Jellyfin (Emulator)',
        'probePath': '/System/Info/Public',
      },
      {
        'url': 'http://10.0.2.2:4533',
        'type': CloudProviderType.subsonic,
        'name': 'Host Machine Navidrome (Emulator)',
        'probePath': '/rest/ping.view?v=1.16.1&c=FreeBeat&f=json',
      },
      // Localhost
      {
        'url': 'http://127.0.0.1:8096',
        'type': CloudProviderType.jellyfin,
        'name': 'Local Jellyfin Server',
        'probePath': '/System/Info/Public',
      },
      {
        'url': 'http://127.0.0.1:4533',
        'type': CloudProviderType.subsonic,
        'name': 'Local Navidrome Server',
        'probePath': '/rest/ping.view?v=1.16.1&c=FreeBeat&f=json',
      },
    ];

    final discovered = <DiscoveredMediaServer>[];

    await Future.wait(
      candidates.map((cand) async {
        final url = cand['url'] as String;
        final probePath = cand['probePath'] as String;
        final type = cand['type'] as CloudProviderType;
        final name = cand['name'] as String;

        try {
          final uri = Uri.parse('$url$probePath');
          final resp = await _client
              .get(uri)
              .timeout(const Duration(milliseconds: 700));
          if (resp.statusCode == 200) {
            String serverName = name;
            try {
              final json = jsonDecode(resp.body) as Map<String, dynamic>;
              if (json['ServerName'] != null) {
                serverName = json['ServerName'].toString();
              }
            } catch (_) {}

            discovered.add(
              DiscoveredMediaServer(
                id: 'probe_${url.hashCode.abs()}',
                name: serverName,
                url: url,
                type: type,
                discoveredVia: 'LAN Auto-Detect',
              ),
            );
          }
        } catch (_) {}
      }),
    );

    return discovered;
  }
}
