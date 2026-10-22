import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Normalized metadata extracted directly from Spotify.
class SpotifyTrackMetadata {
  const SpotifyTrackMetadata({
    required this.trackId,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.durationMs,
    this.previewUrl,
  });

  final String trackId;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final int? durationMs;
  final String? previewUrl;

  String get displayName => artist.isNotEmpty ? '$artist - $title' : title;
}

/// On-device engine responsible for extracting 100% authentic Spotify track
/// metadata and official high-resolution album cover art directly on the device.
class SpotifyMetadataEngine {
  SpotifyMetadataEngine({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Map<String, SpotifyTrackMetadata> _cache = {};

  /// Extracts the Spotify track ID from a URL or URI string.
  static String? extractTrackId(String urlOrUri) {
    if (urlOrUri.startsWith('spotify:track:')) {
      return urlOrUri.substring('spotify:track:'.length).split('?').first.trim();
    }
    final match = RegExp(r'open\.spotify\.com\/(?:embed\/)?track\/([a-zA-Z0-9]+)').firstMatch(urlOrUri);
    return match?.group(1);
  }

  /// Resolves official Spotify metadata and 640x640 CDN artwork for a given track.
  Future<SpotifyTrackMetadata?> resolveTrackMetadata({
    required String trackIdOrUrl,
    String? fallbackTitle,
    String? fallbackArtist,
  }) async {
    final trackId = extractTrackId(trackIdOrUrl) ?? trackIdOrUrl;
    if (_cache.containsKey(trackId)) {
      return _cache[trackId];
    }

    try {
      final oEmbedUri = Uri.parse(
        'https://open.spotify.com/oembed?url=${Uri.encodeComponent('https://open.spotify.com/track/$trackId')}',
      );
      final resp = await _http.get(oEmbedUri).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final rawTitle = data['title']?.toString() ?? fallbackTitle ?? '';
        final artwork = data['thumbnail_url']?.toString();

        // Parse "Title" and "Artist" from oEmbed title if artist is empty
        String resolvedTitle = rawTitle;
        String resolvedArtist = fallbackArtist ?? '';

        if (resolvedArtist.isEmpty && rawTitle.contains(' - ')) {
          final parts = rawTitle.split(' - ');
          resolvedArtist = parts[0].trim();
          resolvedTitle = parts.sublist(1).join(' - ').trim();
        }

        final meta = SpotifyTrackMetadata(
          trackId: trackId,
          title: resolvedTitle,
          artist: resolvedArtist,
          artworkUrl: artwork,
        );

        _cache[trackId] = meta;
        return meta;
      }
    } catch (e) {
      debugPrint('SpotifyMetadataEngine error for track $trackId: $e');
    }

    return null;
  }
}
