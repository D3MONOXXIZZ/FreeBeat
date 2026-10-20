import 'dart:async';
import 'dart:convert';
import 'package:dart_des/dart_des.dart';
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
    this.isFullLength = true,
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
  final bool isFullLength;

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

/// Service that hunts and extracts high-fidelity full audio streams for tracks
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

  /// Resolves the best matching full audio stream for a given track title and artist.
  /// Prioritizes complete studio recordings (3-5 minutes) over short promotional previews.
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

    // Tier 1: High-Speed Studio Engine (Full 320kbps / 160kbps MP4/AAC Stream)
    // Delivers complete 3-5 minute high-bitrate studio audio directly via global CDN.
    try {
      final saavnCandidate = await _resolveViaJioSaavn(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
        preferredArtworkUrl: preferredArtworkUrl,
        preferredAlbum: preferredAlbum,
      );
      if (saavnCandidate != null && saavnCandidate.durationMs >= 45000) {
        return saavnCandidate;
      }
    } catch (e) {
      debugPrint('Studio full-song resolution error for "$title": $e');
    }

    // Tier 2: Public Piped / Invidious Mirror Audio Streams (Full Length)
    try {
      final fallbackCandidate = await _resolveViaFallbackApi(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 2500));
      if (fallbackCandidate != null && fallbackCandidate.durationMs >= 60000) {
        return fallbackCandidate;
      }
    } catch (_) {}

    // Tier 3: Direct YouTube Explode Search & Audio Manifest (Full Length)
    try {
      final ytCandidate = await _resolveViaYouTubeExplode(
        cleanTitle: cleanTitle.isNotEmpty ? cleanTitle : title,
        cleanArtist: cleanArtist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 3000));
      if (ytCandidate != null && ytCandidate.durationMs >= 60000) {
        return ytCandidate;
      }
    } catch (e) {
      debugPrint('YouTube Explode search failed or timed out for "$title": $e');
    }

    // Tier 4 (Fallback Only): Apple iTunes Store API
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
      debugPrint('iTunes resolution error for "$title": $e');
    }

    // Tier 5 (Emergency Fallback Only): Direct preview URL if provided
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
        isFullLength: false,
      );
    }

    return null;
  }

  /// Queries worldwide studio catalog for full-length 320kbps/160kbps master recordings.
  Future<AudioStreamCandidate?> _resolveViaJioSaavn({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final cleanTitle = _sanitizeQuery(title);
    final cleanArtist = _sanitizeQuery(artist);

    final queries = [
      if (cleanArtist.isNotEmpty && cleanTitle.isNotEmpty)
        '$cleanArtist $cleanTitle'
      else
        cleanTitle,
      cleanTitle,
    ];

    for (final q in queries) {
      try {
        final uri = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&p=1&n=5&q=${Uri.encodeComponent(q)}',
        );
        final resp = await _http.get(uri).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final results = data['results'] as List<dynamic>? ?? [];
          for (final item in results) {
            if (item is! Map<String, dynamic>) continue;
            final encUrl = item['encrypted_media_url']?.toString() ?? '';
            if (encUrl.isEmpty) continue;

            final itemDur = int.tryParse(item['duration']?.toString() ?? '0') ?? 0;
            // Guarantee full song (at least 45 seconds)
            if (itemDur < 45) continue;

            // Check duration difference if expected duration was specified
            if (expectedDurationMs != null && expectedDurationMs > 0) {
              final diff = (itemDur * 1000 - expectedDurationMs).abs();
              if (diff > 55000) continue;
            }

            final decryptedUrl = _decryptSaavnUrl(encUrl);
            if (decryptedUrl == null || decryptedUrl.isEmpty) continue;

            // Upgrade stream to 320kbps high-quality studio stream
            final stream320 = decryptedUrl.replaceAll('_96.mp4', '_320.mp4');

            final songName = item['song']?.toString() ?? item['title']?.toString() ?? title;
            final primaryArtists = item['primary_artists']?.toString() ?? artist;
            final albumName = item['album']?.toString() ?? preferredAlbum;
            final rawImage = item['image']?.toString();
            final artwork = (rawImage != null && rawImage.isNotEmpty)
                ? rawImage.replaceAll('150x150', '500x500')
                : preferredArtworkUrl;

            return AudioStreamCandidate(
              streamUrl: stream320,
              format: 'm4a',
              bitrateKbps: 320,
              sourceId: 'saavn_${item['id'] ?? songName.hashCode}',
              sourceTitle: songName,
              channelOrArtist: primaryArtists,
              durationMs: itemDur * 1000,
              artworkUrl: artwork,
              album: albumName,
              isFullLength: true,
            );
          }
        }
      } catch (e) {
        debugPrint('JioSaavn search failed for "$q": $e');
      }
    }
    return null;
  }

  /// Decrypts DES-ECB encrypted media stream URLs using JioSaavn's public key.
  static String? _decryptSaavnUrl(String encUrl) {
    try {
      final key = utf8.encode('38346591');
      final des = DES(key: key, mode: DESMode.ECB, paddingType: DESPaddingType.PKCS5);
      final encBytes = base64Decode(encUrl);
      final decryptedBytes = des.decrypt(encBytes);
      return utf8.decode(decryptedBytes);
    } catch (_) {
      return null;
    }
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
                  isFullLength: false,
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
              isFullLength: true,
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
                    isFullLength: true,
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
