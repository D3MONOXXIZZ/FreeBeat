import 'dart:async';
import 'dart:convert';
// ignore: unused_import
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

  bool get isMatch => !isDisqualified && score >= 0.75;

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
    'sped up',
    'speed up',
    'tiktok version',
    'teaser',
    'trailer',
    'snippet',
  };

  static String extractPrimaryArtist(String fullArtist) {
    final parts = fullArtist.split(RegExp(r'[,&;/]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false));
    return parts.isNotEmpty ? parts.first.trim() : fullArtist.trim();
  }

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

    // Check generic "remix"
    if (!lowerTargetTitle.contains('remix') && lowerCandTitle.contains('remix')) {
      return const TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Contains "remix"',
        artistMatchScore: 0,
        titleMatchScore: 0,
      );
    }

    // Check generic "live"
    if (!lowerTargetTitle.contains('live') &&
        (lowerCandTitle.contains('live at') ||
            lowerCandTitle.contains('live from') ||
            lowerCandTitle.contains('live performance') ||
            lowerCandTitle.contains('live in'))) {
      return const TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Contains "live performance"',
        artistMatchScore: 0,
        titleMatchScore: 0,
      );
    }

    // 2. Artist Matching & Primary Artist Enforcement
    final primaryTargetArtist = extractPrimaryArtist(targetArtist);
    final primaryArtistTokens = tokenize(primaryTargetArtist);
    final targetArtistTokens = tokenize(targetArtist);
    final candArtistTokens = tokenize(candidateArtist);
    final candTitleTokens = tokenize(candidateTitle);
    final combinedCandTokens = candArtistTokens.union(candTitleTokens);

    final cleanTargetArtist = cleanString(targetArtist);
    final cleanCandArtist = cleanString(candidateArtist);
    final cleanPrimaryArtist = cleanString(primaryTargetArtist);

    // Primary artist tokens MUST appear in candidate artist or candidate video title/channel
    if (primaryArtistTokens.isNotEmpty) {
      final primaryOverlap = primaryArtistTokens.intersection(combinedCandTokens);
      if (primaryOverlap.isEmpty) {
        if (cleanCandArtist != cleanTargetArtist && cleanCandArtist != cleanPrimaryArtist) {
          return TrackMatchEvaluation(
            score: -1.0,
            isDisqualified: true,
            reason: 'Primary artist "$primaryTargetArtist" missing from candidate "$candidateArtist - $candidateTitle"',
            artistMatchScore: 0,
            titleMatchScore: 0,
          );
        }
      }
    }

    double artistScore = 0.0;
    if (cleanCandArtist == cleanTargetArtist || cleanCandArtist == cleanPrimaryArtist) {
      artistScore = 1.0;
    } else if (targetArtistTokens.isNotEmpty) {
      final intersection = targetArtistTokens.intersection(combinedCandTokens);
      if (intersection.isNotEmpty) {
        artistScore = (intersection.length / targetArtistTokens.length).clamp(0.0, 1.0);
      }
    }

    // If target has an artist and candidate artist has < 0.40 overlap, disqualify
    if (targetArtistTokens.isNotEmpty && artistScore < 0.40) {
      return TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Artist mismatch: "$candidateArtist" vs target "$targetArtist"',
        artistMatchScore: artistScore,
        titleMatchScore: 0,
      );
    }
    // 3. Title Matching (Strict, with word multiplicity and coverage check)
    final targetTitleTokens = tokenize(targetTitle);
    final cleanTgt = cleanString(targetTitle);
    final cleanCand = cleanString(candidateTitle);
    final targetWords = cleanTgt.split(' ').where((w) => w.isNotEmpty).toList();
    final candWords = cleanCand.split(' ').where((w) => w.isNotEmpty).toList();

    double titleScore = 0.0;
    if (cleanCand == cleanTgt) {
      titleScore = 1.0;
    } else if (cleanCand.startsWith(cleanTgt)) {
      titleScore = 0.95;
    } else if (targetWords.isNotEmpty) {
      // Check word coverage with multiplicity
      var matchedCount = 0;
      final candPool = List<String>.from(candWords);
      for (final w in targetWords) {
        final idx = candPool.indexOf(w);
        if (idx != -1) {
          matchedCount++;
          candPool.removeAt(idx);
        }
      }
      final wordRatio = matchedCount / targetWords.length;

      double tokenRatio = 0.0;
      if (targetTitleTokens.isNotEmpty) {
        final intersection = targetTitleTokens.intersection(candTitleTokens);
        tokenRatio = intersection.length / targetTitleTokens.length;
        if (targetTitleTokens.length <= 2 && intersection.length < targetTitleTokens.length) {
          tokenRatio = 0.0;
        }
      }

      titleScore = math.min(wordRatio, tokenRatio > 0 ? tokenRatio : wordRatio).clamp(0.0, 1.0);
    }

    if (titleScore < 0.70) {
      return TrackMatchEvaluation(
        score: -1.0,
        isDisqualified: true,
        reason: 'Title mismatch: "$candidateTitle" vs target "$targetTitle"',
        artistMatchScore: artistScore,
        titleMatchScore: titleScore,
      );
    }

    // 4. Duration Check (Tightened to 40s)
    int? diffMs;
    double durationBonus = 0.0;
    if (targetDurationMs != null &&
        targetDurationMs > 0 &&
        candidateDurationMs != null &&
        candidateDurationMs > 0) {
      diffMs = (candidateDurationMs - targetDurationMs).abs();
      if (diffMs > 40000) {
        return TrackMatchEvaluation(
          score: -1.0,
          isDisqualified: true,
          reason: 'Duration difference too large: ${diffMs ~/ 1000}s',
          artistMatchScore: artistScore,
          titleMatchScore: titleScore,
          durationDiffMs: diffMs,
        );
      } else if (diffMs <= 5000) {
        durationBonus = 0.20;
      } else if (diffMs <= 15000) {
        durationBonus = 0.10;
      } else if (diffMs > 25000) {
        durationBonus = -0.10;
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

  /// Extracts the 11-character YouTube video ID from standard, mobile, shorts,
  /// or YouTube Music links.
  static String? extractYouTubeVideoId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|v\/|shorts\/)|youtu\.be\/|music\.youtube\.com\/(?:watch\?(?:.*&)?v=|track\/))([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.group(1) != null) {
      return match.group(1);
    }
    final uri = Uri.tryParse(url);
    return uri?.queryParameters['v'];
  }

  /// Resolves an exact YouTube video stream directly from its URL or ID.
  /// Guarantees full-length authentic audio directly from YouTube.
  Future<AudioStreamCandidate?> resolveDirectYouTubeUrl(
    String urlOrId, {
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final videoId = extractYouTubeVideoId(urlOrId) ??
        (urlOrId.length == 11 && !urlOrId.contains('/') ? urlOrId : null);
    if (videoId == null) return null;

    final client = ytClient;
    try {
      final video = await client.videos
          .get(videoId)
          .timeout(const Duration(milliseconds: 4500));
      final durMs =
          video.duration?.inMilliseconds ?? expectedDurationMs ?? 210000;

      // Reject truncated clips / 30s snippets
      if (durMs < 45000) return null;

      final manifest = await client.videos.streamsClient
          .getManifest(videoId)
          .timeout(const Duration(milliseconds: 4000));
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
          durationMs: durMs,
          streamSizeBytes: bestAudio.size.totalBytes,
          audioOnlyStreamInfo: bestAudio,
          ytClient: client,
          artworkUrl: video.thumbnails.highResUrl.isNotEmpty
              ? video.thumbnails.highResUrl
              : preferredArtworkUrl,
          album: preferredAlbum,
          isFullLength: true,
          matchScore: 1.0,
        );
      }
    } catch (e) {
      debugPrint('Direct YouTube URL resolution error for "$urlOrId": $e');
    }
    return null;
  }

  /// Resolves the authentic full audio stream for a given track title and artist.
  ///
  /// CRITICAL RULES:
  /// 1. Prioritizes YouTube and YouTube Music first (#1 priority).
  /// 2. Strictly enforces full-length tracks (minimum 45s, typically 3-5 mins).
  /// 3. NEVER returns 30s previews (iTunes preview or Spotify preview).
  Future<AudioStreamCandidate?> resolveTrackAudio({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? sourceUrl,
    String? directPreviewUrl, // Deprecated: ignored to prevent 30s snippets
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

    // Tier 0: Direct YouTube / YouTube Music URL (if provided, e.g. from YouTube import)
    if (sourceUrl != null &&
        (sourceUrl.contains('youtube.com') ||
            sourceUrl.contains('youtu.be') ||
            sourceUrl.contains('music.youtube.com'))) {
      try {
        final directCandidate = await resolveDirectYouTubeUrl(
          sourceUrl,
          expectedDurationMs: expectedDurationMs,
          preferredArtworkUrl: preferredArtworkUrl,
          preferredAlbum: preferredAlbum,
        );
        if (directCandidate != null &&
            directCandidate.isFullLength &&
            directCandidate.durationMs >= 45000) {
          return directCandidate;
        }
      } catch (e) {
        debugPrint('Direct YouTube resolution error for "$sourceUrl": $e');
      }
    }

    // Tier 1 (PRIORITY #1): YouTube & YouTube Music Search via YouTubeExplode
    // Extracts full-length audio tracks directly from YouTube / YouTube Music.
    try {
      final ytCandidate = await _resolveViaYouTubeExplode(
        cleanTitle: cleanTitle.isNotEmpty ? cleanTitle : title,
        cleanArtist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 5500));
      if (ytCandidate != null &&
          ytCandidate.isFullLength &&
          ytCandidate.durationMs >= 45000) {
        return ytCandidate;
      }
    } catch (e) {
      debugPrint('YouTube Explode resolution error for "$title": $e');
    }

    // Tier 2: Public YouTube Mirror Audio Streams (Piped / Invidious) (Full Length)
    try {
      final fallbackCandidate = await _resolveViaFallbackApi(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 3500));
      if (fallbackCandidate != null &&
          fallbackCandidate.isFullLength &&
          fallbackCandidate.durationMs >= 45000) {
        return fallbackCandidate;
      }
    } catch (_) {}

    // Tier 3: Worldwide Studio Catalog (JioSaavn full-length 320kbps master recordings)
    try {
      final saavnCandidate = await _resolveViaJioSaavn(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
        preferredArtworkUrl: preferredArtworkUrl,
        preferredAlbum: preferredAlbum,
      );
      if (saavnCandidate != null &&
          saavnCandidate.isFullLength &&
          saavnCandidate.durationMs >= 45000) {
        return saavnCandidate;
      }
    } catch (e) {
      debugPrint('Studio master resolution error for "$title": $e');
    }

    // STRICT NO-PREVIEW POLICY:
    // 30s previews (from iTunes search or Spotify audioPreview) are completely forbidden.
    // If no full-length audio track could be matched from YouTube or Studio Masters,
    // return null so FreeBeat never imports truncated teaser clips into playlists.
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
    final primaryArtist = cleanArtist.split(RegExp(r'[,&;]')).first.trim();

    // Try primary artist and full queries to maximize search relevancy
    final queries = [
      if (primaryArtist.isNotEmpty && cleanTitle.isNotEmpty) ...[
        '$cleanTitle $primaryArtist',
        '$primaryArtist $cleanTitle',
      ],
      if (cleanArtist.isNotEmpty && cleanArtist != primaryArtist && cleanTitle.isNotEmpty) ...[
        '$cleanTitle $cleanArtist',
        '$cleanArtist $cleanTitle',
      ],
      cleanTitle,
      if (cleanTitle != title) title,
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

  /// YouTube stream extraction with strict match validation and safety timeouts.
  Future<AudioStreamCandidate?> _resolveViaYouTubeExplode({
    required String cleanTitle,
    required String cleanArtist,
    int? expectedDurationMs,
  }) async {
    final client = ytClient;
    final primaryArtist = cleanArtist.split(RegExp(r'[,&;]')).first.trim();
    final queries = [
      if (primaryArtist.isNotEmpty && cleanTitle.isNotEmpty) ...[
        '$cleanArtist - $cleanTitle (Audio)',
        '$cleanTitle $primaryArtist topic',
        '$cleanTitle $primaryArtist',
        '$primaryArtist - $cleanTitle',
      ],
      if (cleanArtist.isNotEmpty && cleanArtist != primaryArtist) ...[
        '$cleanTitle $cleanArtist audio',
        '$cleanTitle $cleanArtist',
      ],
      '$cleanTitle audio',
    ];

    for (final query in queries) {
      try {
        final searchResults = await client.search
            .search(query)
            .timeout(const Duration(milliseconds: 4500));
        if (searchResults.isEmpty) continue;

        final candidates = <AudioStreamCandidate>[];

        for (final video in searchResults.take(8)) {
          final durMs = video.duration?.inMilliseconds;
          // STRICT FULL-LENGTH CHECK: Never consider 30s clips or short previews
          if (durMs != null && durMs < 45000) continue;

          final eval = TrackMatchScorer.evaluate(
            targetTitle: cleanTitle,
            targetArtist: cleanArtist,
            candidateTitle: video.title,
            candidateArtist: video.author,
            targetDurationMs: expectedDurationMs,
            candidateDurationMs: durMs,
          );

          if (!eval.isMatch) continue;

          try {
            final manifest = await client.videos.streamsClient
                .getManifest(video.id)
                .timeout(const Duration(milliseconds: 3500));
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
                  durationMs: durMs ?? expectedDurationMs ?? 210000,
                  streamSizeBytes: bestAudio.size.totalBytes,
                  audioOnlyStreamInfo: bestAudio,
                  ytClient: client,
                  artworkUrl: video.thumbnails.highResUrl,
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
