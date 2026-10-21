import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dart_des/dart_des.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolved audio stream candidate for an imported missing song.
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
    this.matchScore = 1.0,
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
  final double matchScore;

  /// Returns a stream of bytes for downloading this candidate.
  Stream<List<int>> getByteStream([http.Client? client]) {
    if (ytClient != null && audioOnlyStreamInfo != null) {
      try {
        return ytClient!.videos.streamsClient.get(audioOnlyStreamInfo!);
      } catch (_) {
        // Fall back to direct HTTP stream with headers below
      }
    }
    final c = client ?? http.Client();
    final controller = StreamController<List<int>>();
    () async {
      try {
        final request = http.Request('GET', Uri.parse(streamUrl));
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
        request.headers['Accept'] = '*/*';
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

/// Evaluation result from comparing a search candidate against target track metadata.
class TrackMatchEvaluation {
  const TrackMatchEvaluation({
    required this.score,
    required this.isDisqualified,
    required this.reason,
    required this.artistMatchScore,
    required this.titleMatchScore,
    this.durationDiffMs,
  });

  final double score;
  final bool isDisqualified;
  final String reason;
  final double artistMatchScore;
  final double titleMatchScore;
  final int? durationDiffMs;

  bool get isMatch => !isDisqualified && score >= 0.65;

  @override
  String toString() =>
      'TrackMatchEvaluation(score: ${score.toStringAsFixed(2)}, isMatch: $isMatch, reason: $reason)';
}

/// Precision scoring engine that rigorously evaluates candidate songs to eliminate
/// covers, karaoke, lullabies, soundalikes, tributes, and wrong artists.
class TrackMatchScorer {
  static const Set<String> negativeKeywords = {
    'karaoke',
    'instrumental',
    'backing track',
    'minus one',
    'play along',
    'sing along',
    'sing-along',
    'tribute',
    'originally performed by',
    'originally by',
    'in the style of',
    'as made famous by',
    'soundalike',
    'sound-alike',
    'lullaby',
    'baby sleep',
    'twinkle twinkle',
    'guitar lesson',
    'tutorial',
    'how to play',
    'synthesia',
    'piano cover',
    'acoustic cover',
    'drum cover',
    'violin cover',
    'orchestra cover',
    'reaction',
    'review',
    'parody',
    'bass boosted',
    'slowed + reverb',
    'slowed and reverb',
    'nightcore',
    '8d audio',
    '10 hours',
    '1 hour',
  };

  static String cleanString(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Set<String> tokenize(String s) {
    const stopWords = {
      'the',
      'a',
      'an',
      'and',
      'feat',
      'ft',
      'with',
      'by',
      'of',
      'in',
      'on',
      'to'
    };
    return cleanString(s)
        .split(' ')
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && !stopWords.contains(w) && w.length > 1)
        .toSet();
  }

  static TrackMatchEvaluation evaluate({
    required String targetTitle,
    required String targetArtist,
    required String candidateTitle,
    required String candidateArtist,
    int? targetDurationMs,
    int? candidateDurationMs,
  }) {
    final lowerTargetTitle = targetTitle.toLowerCase();
    final lowerTargetArtist = targetArtist.toLowerCase();
    final lowerCandTitle = candidateTitle.toLowerCase();
    final lowerCandArtist = candidateArtist.toLowerCase();

    // 1. Check Negative Keywords (unless requested in target title or artist)
    for (final kw in negativeKeywords) {
      if (!lowerTargetTitle.contains(kw) && !lowerTargetArtist.contains(kw)) {
        if (lowerCandTitle.contains(kw) || lowerCandArtist.contains(kw)) {
          return TrackMatchEvaluation(
            score: -1.0,
            isDisqualified: true,
            reason: 'Contains negative keyword: "$kw"',
            artistMatchScore: 0,
            titleMatchScore: 0,
          );
        }
      }
    }

    // Check generic "cover"
    if (!lowerTargetTitle.contains('cover') &&
        (lowerCandTitle.contains(' cover') ||
            lowerCandTitle.endsWith('cover') ||
            lowerCandArtist.contains('cover band'))) {
      return const TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Contains "cover"',
        artistMatchScore: 0,
        titleMatchScore: 0,
      );
    }

    // 2. Artist Matching
    final targetArtistTokens = tokenize(targetArtist);
    final candArtistTokens = tokenize(candidateArtist);

    double artistScore = 0.0;
    if (lowerCandArtist.contains(lowerTargetArtist) ||
        lowerTargetArtist.contains(lowerCandArtist)) {
      artistScore = 1.0;
    } else if (targetArtistTokens.isNotEmpty) {
      final intersection = targetArtistTokens.intersection(candArtistTokens);
      if (intersection.isNotEmpty) {
        final ratio = intersection.length /
            math.min(targetArtistTokens.length, candArtistTokens.length);
        artistScore = ratio.clamp(0.0, 1.0);
      }
    }

    // If target has an artist and candidate artist has 0 or negligible overlap, disqualify
    if (targetArtistTokens.isNotEmpty && artistScore < 0.3) {
      return TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Artist mismatch: "$candidateArtist" vs target "$targetArtist"',
        artistMatchScore: artistScore,
        titleMatchScore: 0,
      );
    }

    // 3. Title Matching
    final targetTitleTokens = tokenize(targetTitle);
    final candTitleTokens = tokenize(candidateTitle);

    double titleScore = 0.0;
    final cleanTgt = cleanString(targetTitle);
    final cleanCand = cleanString(candidateTitle);

    if (cleanCand == cleanTgt || cleanCand.startsWith(cleanTgt)) {
      titleScore = 1.0;
    } else if (targetTitleTokens.isNotEmpty) {
      final intersection = targetTitleTokens.intersection(candTitleTokens);
      titleScore = (intersection.length / targetTitleTokens.length).clamp(0.0, 1.0);
    }

    if (titleScore < 0.5) {
      return TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Title mismatch: "$candidateTitle" vs target "$targetTitle"',
        artistMatchScore: artistScore,
        titleMatchScore: titleScore,
      );
    }

    // 4. Duration Check
    int? diffMs;
    double durationBonus = 0.0;
    if (targetDurationMs != null &&
        targetDurationMs > 0 &&
        candidateDurationMs != null &&
        candidateDurationMs > 0) {
      diffMs = (candidateDurationMs - targetDurationMs).abs();
      if (diffMs > 65000) {
        // Disqualify if duration differs by more than 65 seconds
        return TrackMatchEvaluation(
          score: -1.0,
          isDisqualified: true,
          reason: 'Duration difference too large: ${diffMs ~/ 1000}s',
          artistMatchScore: artistScore,
          titleMatchScore: titleScore,
          durationDiffMs: diffMs,
        );
      } else if (diffMs <= 6000) {
        durationBonus = 0.25;
      } else if (diffMs <= 15000) {
        durationBonus = 0.15;
      } else if (diffMs <= 30000) {
        durationBonus = 0.05;
      }
    }

    // 5. Total Score calculation
    double totalScore = (artistScore * 0.45) + (titleScore * 0.45) + durationBonus;

    // Bonus for official / original
    if (lowerCandTitle.contains('official') ||
        lowerCandArtist.contains('vevo') ||
        lowerCandArtist.contains('topic')) {
      totalScore += 0.05;
    }

    return TrackMatchEvaluation(
      score: totalScore,
      isDisqualified: false,
      reason: 'OK',
      artistMatchScore: artistScore,
      titleMatchScore: titleScore,
      durationDiffMs: diffMs,
    );
  }
}

/// Service that hunts and extracts high-fidelity full audio streams for tracks
/// imported from Spotify, Apple Music, or text lists with precision scoring.
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
    'https://api.piped.private.coffee',
    'https://pipedapi.ducks.party',
    'https://pipedapi.leptun.pw',
    'https://pipedapi.kavin.rocks',
  ];

  /// Resolves the authentic full audio stream for a given track title and artist.
  /// Prioritizes complete studio recordings by the original artist over covers or short previews.
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

    // Tier 1: High-Speed Studio Master Engine (Full 320kbps MP4/AAC Stream)
    // Evaluates results with TrackMatchScorer to guarantee authentic recording by original artist.
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
      debugPrint('Studio master resolution error for "$title": $e');
    }

    // Tier 2: Public Piped / Invidious Mirror Audio Streams (Full Length)
    try {
      final fallbackCandidate = await _resolveViaFallbackApi(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 3500));
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
      ).timeout(const Duration(milliseconds: 4500));
      if (ytCandidate != null && ytCandidate.durationMs >= 60000) {
        return ytCandidate;
      }
    } catch (e) {
      debugPrint('YouTube Explode resolution error for "$title": $e');
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

  /// Queries worldwide studio catalog for authentic full-length 320kbps master recordings.
  Future<AudioStreamCandidate?> _resolveViaJioSaavn({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final cleanTitle = _sanitizeQuery(title);
    final cleanArtist = _sanitizeQuery(artist);

    // Try both query orders to handle search engine token prioritization
    final queries = [
      if (cleanArtist.isNotEmpty && cleanTitle.isNotEmpty) ...[
        '$cleanArtist $cleanTitle',
        '$cleanTitle $cleanArtist',
      ] else
        cleanTitle,
      if (cleanTitle != title) cleanTitle,
    ];

    final candidates = <AudioStreamCandidate>[];
    final seenIds = <String>{};

    for (final q in queries) {
      try {
        final uri = Uri.parse(
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&cc=in&p=1&n=10&q=${Uri.encodeComponent(q)}',
        );
        final resp = await _http.get(uri).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final results = data['results'] as List<dynamic>? ?? [];
          for (final item in results) {
            if (item is! Map<String, dynamic>) continue;
            final itemId = item['id']?.toString() ?? '';
            if (itemId.isNotEmpty && seenIds.contains(itemId)) continue;
            if (itemId.isNotEmpty) seenIds.add(itemId);

            final encUrl = item['encrypted_media_url']?.toString() ?? '';
            if (encUrl.isEmpty) continue;

            final itemDur = int.tryParse(item['duration']?.toString() ?? '0') ?? 0;
            if (itemDur < 45) continue;

            final songName =
                item['song']?.toString() ?? item['title']?.toString() ?? title;
            final primaryArtists =
                item['primary_artists']?.toString() ?? item['singers']?.toString() ?? artist;

            // Evaluate candidate against target track using the precision scoring engine
            final eval = TrackMatchScorer.evaluate(
              targetTitle: title,
              targetArtist: artist,
              candidateTitle: songName,
              candidateArtist: primaryArtists,
              targetDurationMs: expectedDurationMs,
              candidateDurationMs: itemDur * 1000,
            );

            if (!eval.isMatch) continue;

            final decryptedUrl = _decryptSaavnUrl(encUrl);
            if (decryptedUrl == null || decryptedUrl.isEmpty) continue;

            // Upgrade stream to 320kbps high-quality studio stream
            final stream320 = decryptedUrl.replaceAll('_96.mp4', '_320.mp4');
            final albumName = item['album']?.toString() ?? preferredAlbum;
            final rawImage = item['image']?.toString();
            final artwork = (rawImage != null && rawImage.isNotEmpty)
                ? rawImage.replaceAll('150x150', '500x500')
                : preferredArtworkUrl;

            candidates.add(
              AudioStreamCandidate(
                streamUrl: stream320,
                format: 'm4a',
                bitrateKbps: 320,
                sourceId: 'saavn_${itemId.isNotEmpty ? itemId : songName.hashCode}',
                sourceTitle: songName,
                channelOrArtist: primaryArtists,
                durationMs: itemDur * 1000,
                artworkUrl: artwork,
                album: albumName,
                isFullLength: true,
                matchScore: eval.score,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('JioSaavn search failed for "$q": $e');
      }

      // If we already found high-confidence authentic matches (score >= 1.0), pick the best
      if (candidates.any((c) => c.matchScore >= 1.0)) {
        break;
      }
    }

    if (candidates.isNotEmpty) {
      // Pick highest scoring authentic recording
      candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
      return candidates.first;
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

  /// Query against Apple's worldwide iTunes media catalog.
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
      queryCandidates.add('$title $artist');
    }
    if (title.isNotEmpty) {
      queryCandidates.add(title);
    }

    for (final term in queryCandidates) {
      try {
        final uri = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(term)}&entity=song&limit=5',
        );
        final resp = await _http.get(uri).timeout(const Duration(milliseconds: 2500));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          if (data is Map<String, dynamic>) {
            final results = data['results'] as List<dynamic>? ?? [];
            final candidates = <AudioStreamCandidate>[];

            for (final item in results) {
              if (item is Map<String, dynamic>) {
                final previewUrl = item['previewUrl']?.toString();
                if (previewUrl == null || previewUrl.isEmpty) continue;

                final trackName = item['trackName']?.toString() ?? title;
                final artistName = item['artistName']?.toString() ?? artist;
                final durMs = item['trackTimeMillis'] is int
                    ? item['trackTimeMillis'] as int
                    : (expectedDurationMs ?? 210000);

                final eval = TrackMatchScorer.evaluate(
                  targetTitle: title,
                  targetArtist: artist,
                  candidateTitle: trackName,
                  candidateArtist: artistName,
                  targetDurationMs: expectedDurationMs,
                  candidateDurationMs: durMs,
                );

                if (!eval.isMatch) continue;

                final albumName = item['collectionName']?.toString() ?? preferredAlbum;
                final artwork = (item['artworkUrl100'] as String?)
                        ?.replaceAll('100x100bb', '600x600bb') ??
                    preferredArtworkUrl;
                final ext = previewUrl.contains('.mp3') ? 'mp3' : 'm4a';

                candidates.add(
                  AudioStreamCandidate(
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
                    matchScore: eval.score,
                  ),
                );
              }
            }

            if (candidates.isNotEmpty) {
              candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
              return candidates.first;
            }
          }
        }
      } catch (e) {
        debugPrint('iTunes search failed for "$term": $e');
      }
    }
    return null;
  }

  /// YouTube stream extraction with strict match validation and safety timeouts.
  Future<AudioStreamCandidate?> _resolveViaYouTubeExplode({
    required String cleanTitle,
    required String cleanArtist,
    int? expectedDurationMs,
  }) async {
    final client = ytClient;
    final queries = [
      if (cleanArtist.isNotEmpty) '$cleanArtist - $cleanTitle',
      '$cleanTitle $cleanArtist audio',
    ];

    for (final query in queries) {
      try {
        final searchResults =
            await client.search.search(query).timeout(const Duration(milliseconds: 3500));
        if (searchResults.isEmpty) continue;

        final candidates = <AudioStreamCandidate>[];

        for (final video in searchResults.take(6)) {
          final eval = TrackMatchScorer.evaluate(
            targetTitle: cleanTitle,
            targetArtist: cleanArtist,
            candidateTitle: video.title,
            candidateArtist: video.author,
            targetDurationMs: expectedDurationMs,
            candidateDurationMs: video.duration?.inMilliseconds,
          );

          if (!eval.isMatch) continue;

          try {
            final manifest = await client.videos.streamsClient
                .getManifest(video.id)
                .timeout(const Duration(milliseconds: 3000));
            final audioOnly = manifest.audioOnly;
            if (audioOnly.isNotEmpty) {
              final bestAudio = audioOnly.withHighestBitrate();
              final format = bestAudio.container.name.toLowerCase();
              final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).round();

              candidates.add(
                AudioStreamCandidate(
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
                  matchScore: eval.score,
                ),
              );
            }
          } catch (_) {
            continue;
          }
        }

        if (candidates.isNotEmpty) {
          candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
          return candidates.first;
        }
      } catch (_) {}
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
          final candidates = <AudioStreamCandidate>[];

          for (final item in items.take(5)) {
            final url = item['url']?.toString() ?? '';
            final videoId = url.replaceFirst('/watch?v=', '');
            if (videoId.isEmpty) continue;

            final candTitle = item['title']?.toString() ?? title;
            final candUploader = item['uploaderName']?.toString() ?? artist;
            final itemDur = item['duration'] is int ? item['duration'] as int : 0;

            final eval = TrackMatchScorer.evaluate(
              targetTitle: title,
              targetArtist: artist,
              candidateTitle: candTitle,
              candidateArtist: candUploader,
              targetDurationMs: expectedDurationMs,
              candidateDurationMs: itemDur > 0 ? itemDur * 1000 : null,
            );

            if (!eval.isMatch) continue;

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
                  candidates.add(
                    AudioStreamCandidate(
                      streamUrl: directUrl,
                      format: topAudio['format']?.toString() ?? 'm4a',
                      bitrateKbps: topAudio['bitrate'] is int
                          ? ((topAudio['bitrate'] as int) / 1000).round()
                          : 160,
                      sourceId: videoId,
                      sourceTitle: candTitle,
                      channelOrArtist: candUploader,
                      durationMs:
                          (itemDur > 0 ? itemDur * 1000 : expectedDurationMs) ?? 210000,
                      isFullLength: true,
                      matchScore: eval.score,
                    ),
                  );
                }
              }
            }
          }

          if (candidates.isNotEmpty) {
            candidates.sort((a, b) => b.matchScore.compareTo(a.matchScore));
            return candidates.first;
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
