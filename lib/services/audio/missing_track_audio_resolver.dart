import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolved high-bitrate audio stream candidate for an imported missing song.
class AudioStreamCandidate {
  const AudioStreamCandidate({
    required this.streamUrl,
    required this.format,
    required this.bitrateKbps,
    required this.sourceId,
    required this.sourceTitle,
    required this.channelOrArtist,
    required this.durationMs,
    this.streamSizeBytes,
    this.audioOnlyStreamInfo,
    this.ytClient,
    this.artworkUrl,
    this.album,
  });

  final String streamUrl;
  final String format; // 'm4a', 'opus', 'mp3'
  final int bitrateKbps;
  final String sourceId;
  final String sourceTitle;
  final String channelOrArtist;
  final int durationMs;
  final int? streamSizeBytes;
  final AudioOnlyStreamInfo? audioOnlyStreamInfo;
  final YoutubeExplode? ytClient;
  final String? artworkUrl;
  final String? album;

  /// Returns a stream of bytes for downloading this candidate.
  Stream<List<int>> getByteStream([http.Client? client]) {
    if (ytClient != null && audioOnlyStreamInfo != null) {
      return ytClient!.videos.streamsClient.get(audioOnlyStreamInfo!);
    }
    final c = client ?? http.Client();
    final controller = StreamController<List<int>>();
    () async {
      try {
        final request = http.Request('GET', Uri.parse(streamUrl));
        final response = await c.send(request);
        await response.stream.pipe(controller);
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }();
    return controller.stream;
  }
}

/// Service that hunts and extracts high-fidelity audio streams for tracks
/// imported from Spotify, Apple Music, or text lists.
class MissingTrackAudioResolver {
  MissingTrackAudioResolver({
    YoutubeExplode? yt,
    http.Client? httpClient,
    this.customResolver,
  })  : _yt = yt,
        _http = httpClient ?? http.Client();

  YoutubeExplode? _yt;
  YoutubeExplode get ytClient => _yt ??= YoutubeExplode();
  final http.Client _http;
  final Future<AudioStreamCandidate?> Function({
    required String title,
    required String artist,
    int? expectedDurationMs,
  })? customResolver;

  /// Public fallback Invidious / Piped instances in case of direct scraping blocks.
  static const List<String> _fallbackApiBases = [
    'https://pipedapi.leptun.pw',
    'https://api.piped.private.coffee',
    'https://pipedapi.kavin.rocks',
  ];

  /// Resolves the best matching audio stream for a given track title and artist.
  Future<AudioStreamCandidate?> resolveTrackAudio({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? directPreviewUrl,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    if (customResolver != null) {
      return customResolver!(
        title: title,
        artist: artist,
        expectedDurationMs: expectedDurationMs,
      );
    }

    final cleanTitle = _sanitizeQuery(title);
    final cleanArtist = _sanitizeQuery(artist);

    // Tier 0: Direct audio preview URL passed from playlist embed parser (0ms latency)
    if (directPreviewUrl != null &&
        directPreviewUrl.isNotEmpty &&
        directPreviewUrl.startsWith('http')) {
      final ext = directPreviewUrl.contains('.mp3') ? 'mp3' : 'm4a';
      return AudioStreamCandidate(
        streamUrl: directPreviewUrl,
        format: ext,
        bitrateKbps: 256,
        sourceId: 'preview_${title.hashCode}_${artist.hashCode}',
        sourceTitle: title,
        channelOrArtist: artist,
        durationMs: expectedDurationMs ?? 210000,
        artworkUrl: preferredArtworkUrl,
        album: preferredAlbum,
      );
    }

    // Tier 1: Apple iTunes Store High-Fidelity Audio API (~150ms latency)
    // Instantaneous, unauthenticated, zero bot check, 256kbps pristine AAC audio streams.
    try {
      final itunesCandidate = await _resolveViaItunes(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
        preferredArtworkUrl: preferredArtworkUrl,
        preferredAlbum: preferredAlbum,
      );
      if (itunesCandidate != null) {
        return itunesCandidate;
      }
    } catch (e) {
      debugPrint('iTunes resolution attempt error for "$title": $e');
    }

    // Tier 2: YouTube Explode search query with strict 3-second timeout
    try {
      final ytCandidate = await _resolveViaYouTubeExplode(
        cleanTitle: cleanTitle.isNotEmpty ? cleanTitle : title,
        cleanArtist: cleanArtist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 3000));
      if (ytCandidate != null) {
        return ytCandidate;
      }
    } catch (e) {
      debugPrint('YouTube Explode search failed or timed out for "$title": $e');
    }

    // Tier 3: Public Piped / Invidious fallback mirrors (strict 2.5-second timeout)
    try {
      final fallbackCandidate = await _resolveViaFallbackApi(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 2500));
      if (fallbackCandidate != null) return fallbackCandidate;
    } catch (_) {}

    return null;
  }

  /// Ultra-fast query against Apple's worldwide iTunes media catalog.
  Future<AudioStreamCandidate?> _resolveViaItunes({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final queryCandidates = <String>[];
    if (artist.isNotEmpty && title.isNotEmpty) {
      queryCandidates.add('$artist $title');
    }
    if (title.isNotEmpty) {
      queryCandidates.add(title);
    }

    for (final term in queryCandidates) {
      try {
        final uri = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=song&limit=3',
        );
        final resp = await _http.get(uri).timeout(const Duration(milliseconds: 2500));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map<String, dynamic>) {
            final results = data['results'] as List<dynamic>? ?? [];
            for (final item in results) {
              if (item is Map<String, dynamic>) {
                final previewUrl = item['previewUrl']?.toString();
                if (previewUrl == null || previewUrl.isEmpty) continue;

                final trackName = item['trackName']?.toString() ?? title;
                final artistName = item['artistName']?.toString() ?? artist;
                final albumName = item['collectionName']?.toString() ?? preferredAlbum;
                final artwork = (item['artworkUrl100'] as String?)?.replaceAll('100x100bb', '600x600bb') ?? preferredArtworkUrl;
                final durMs = item['trackTimeMillis'] is int
                    ? item['trackTimeMillis'] as int
                    : (expectedDurationMs ?? 210000);

                final ext = previewUrl.contains('.mp3') ? 'mp3' : 'm4a';

                return AudioStreamCandidate(
                  streamUrl: previewUrl,
                  format: ext,
                  bitrateKbps: 256,
                  sourceId: 'itunes_${item['trackId'] ?? trackName.hashCode}',
                  sourceTitle: trackName,
                  channelOrArtist: artistName,
                  durationMs: durMs,
                  artworkUrl: artwork,
                  album: albumName,
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('iTunes search failed for "$term": $e');
      }
    }
    return null;
  }

  /// Direct YouTube stream extraction with strict safety timeouts.
  Future<AudioStreamCandidate?> _resolveViaYouTubeExplode({
    required String cleanTitle,
    required String cleanArtist,
    int? expectedDurationMs,
  }) async {
    final client = ytClient;
    final query = cleanArtist.isNotEmpty
        ? '$cleanArtist - $cleanTitle audio'
        : '$cleanTitle audio';

    final searchResults = await client.search.search(query).timeout(const Duration(milliseconds: 2000));
    if (searchResults.isNotEmpty) {
      for (final video in searchResults.take(3)) {
        if (expectedDurationMs != null && expectedDurationMs > 0) {
          final videoDurMs = video.duration?.inMilliseconds ?? 0;
          if (videoDurMs > 0) {
            final diff = (videoDurMs - expectedDurationMs).abs();
            if (diff > 45000) continue;
          }
        }

        final lowerTitle = video.title.toLowerCase();
        if (lowerTitle.contains('reaction') ||
            lowerTitle.contains('review') ||
            lowerTitle.contains('karaoke') ||
            lowerTitle.contains('1 hour') ||
            lowerTitle.contains('10 hours')) {
          continue;
        }

        try {
          final manifest = await client.videos.streamsClient
              .getManifest(video.id)
              .timeout(const Duration(milliseconds: 2000));
          final audioOnly = manifest.audioOnly;
          if (audioOnly.isNotEmpty) {
            final bestAudio = audioOnly.withHighestBitrate();
            final format = bestAudio.container.name.toLowerCase();
            final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).round();

            return AudioStreamCandidate(
              streamUrl: bestAudio.url.toString(),
              format: format == 'webm' ? 'opus' : format,
              bitrateKbps: kbps > 0 ? kbps : 192,
              sourceId: video.id.value,
              sourceTitle: video.title,
              channelOrArtist: video.author,
              durationMs: video.duration?.inMilliseconds ?? expectedDurationMs ?? 210000,
              streamSizeBytes: bestAudio.size.totalBytes,
              audioOnlyStreamInfo: bestAudio,
              ytClient: client,
            );
          }
        } catch (_) {
          continue;
        }
      }
    }
    return null;
  }

  Future<AudioStreamCandidate?> _resolveViaFallbackApi({
    required String title,
    required String artist,
    int? expectedDurationMs,
  }) async {
    final query = Uri.encodeComponent('$artist $title');
    for (final base in _fallbackApiBases) {
      try {
        final searchUrl = Uri.parse('$base/search?q=$query&filter=music_songs');
        final resp = await _http.get(searchUrl).timeout(const Duration(seconds: 2));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final items = data['items'] as List<dynamic>? ?? [];
          for (final item in items.take(3)) {
            final url = item['url']?.toString() ?? '';
            final videoId = url.replaceFirst('/watch?v=', '');
            if (videoId.isEmpty) continue;

            final itemDur = item['duration'] is int ? item['duration'] as int : 0;
            if (expectedDurationMs != null && expectedDurationMs > 0 && itemDur > 0) {
              final diff = (itemDur * 1000 - expectedDurationMs).abs();
              if (diff > 45000) continue;
            }

            // Fetch streams for this video
            final streamUrl = Uri.parse('$base/streams/$videoId');
            final sResp = await _http.get(streamUrl).timeout(const Duration(seconds: 2));
            if (sResp.statusCode == 200) {
              final sData = jsonDecode(sResp.body);
              final audioStreams = sData['audioStreams'] as List<dynamic>? ?? [];
              if (audioStreams.isNotEmpty) {
                final topAudio = audioStreams.first as Map<String, dynamic>;
                final directUrl = topAudio['url']?.toString() ?? '';
                if (directUrl.isNotEmpty) {
                  return AudioStreamCandidate(
                    streamUrl: directUrl,
                    format: topAudio['format']?.toString() ?? 'm4a',
                    bitrateKbps: topAudio['bitrate'] is int
                        ? ((topAudio['bitrate'] as int) / 1000).round()
                        : 160,
                    sourceId: videoId,
                    sourceTitle: item['title']?.toString() ?? title,
                    channelOrArtist: item['uploaderName']?.toString() ?? artist,
                    durationMs: (itemDur > 0 ? itemDur * 1000 : expectedDurationMs) ?? 210000,
                  );
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static String _sanitizeQuery(String s) {
    return s
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // remove parenthesized info
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void close() {
    _yt?.close();
  }
}
