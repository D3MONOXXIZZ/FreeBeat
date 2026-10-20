import 'dart:async';
import 'dart:convert';
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

  /// Returns a stream of bytes for downloading this candidate.
  Stream<List<int>> getByteStream() {
    if (ytClient != null && audioOnlyStreamInfo != null) {
      return ytClient!.videos.streamsClient.get(audioOnlyStreamInfo!);
    }
    throw StateError('No active stream client available for candidate $sourceId');
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

  final YoutubeExplode? _yt;
  final http.Client _http;
  final Future<AudioStreamCandidate?> Function({
    required String title,
    required String artist,
    int? expectedDurationMs,
  })? customResolver;

  /// Public fallback Invidious / Piped instances in case of direct scraping blocks.
  static const List<String> _fallbackApiBases = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
  ];

  /// Resolves the best matching audio stream for a given track title and artist.
  Future<AudioStreamCandidate?> resolveTrackAudio({
    required String title,
    required String artist,
    int? expectedDurationMs,
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

    // 1. Primary: YouTube Explode search query (if yt client available or created)
    final ytClient = _yt;
    if (ytClient != null) {
      try {
        final query = cleanArtist.isNotEmpty
            ? '$cleanArtist - $cleanTitle audio'
            : '$cleanTitle audio';

        final searchResults = await ytClient.search.search(query);
        if (searchResults.isNotEmpty) {
          // Find best match matching duration if available
          for (final video in searchResults.take(6)) {
            if (expectedDurationMs != null && expectedDurationMs > 0) {
              final videoDurMs = video.duration?.inMilliseconds ?? 0;
              if (videoDurMs > 0) {
                final diff = (videoDurMs - expectedDurationMs).abs();
                if (diff > 35000) continue;
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
              final manifest = await ytClient.videos.streamsClient.getManifest(video.id);
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
                  ytClient: ytClient,
                );
              }
            } catch (_) {
              continue;
            }
          }
        }
      } catch (_) {}
    }

    // 2. Secondary: Public Piped / Invidious Fallback Search
    try {
      final fallbackCandidate = await _resolveViaFallbackApi(
        title: cleanTitle,
        artist: cleanArtist,
        expectedDurationMs: expectedDurationMs,
      );
      if (fallbackCandidate != null) return fallbackCandidate;
    } catch (_) {}

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
        final resp = await _http.get(searchUrl).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final items = data['items'] as List<dynamic>? ?? [];
          for (final item in items.take(4)) {
            final url = item['url']?.toString() ?? '';
            final videoId = url.replaceFirst('/watch?v=', '');
            if (videoId.isEmpty) continue;

            final itemDur = item['duration'] is int ? item['duration'] as int : 0;
            if (expectedDurationMs != null && expectedDurationMs > 0 && itemDur > 0) {
              final diff = (itemDur * 1000 - expectedDurationMs).abs();
              if (diff > 35000) continue;
            }

            // Fetch streams for this video
            final streamUrl = Uri.parse('$base/streams/$videoId');
            final sResp = await _http.get(streamUrl).timeout(const Duration(seconds: 4));
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
