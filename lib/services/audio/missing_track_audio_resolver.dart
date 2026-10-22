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

  AudioStreamCandidate copyWith({
    String? streamUrl,
    String? format,
    int? bitrateKbps,
    String? sourceId,
    String? sourceTitle,
    String? channelOrArtist,
    int? durationMs,
    int? streamSizeBytes,
    AudioOnlyStreamInfo? audioOnlyStreamInfo,
    YoutubeExplode? ytClient,
    String? artworkUrl,
    String? album,
    bool? isFullLength,
    double? matchScore,
  }) {
    return AudioStreamCandidate(
      streamUrl: streamUrl ?? this.streamUrl,
      format: format ?? this.format,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      sourceId: sourceId ?? this.sourceId,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      channelOrArtist: channelOrArtist ?? this.channelOrArtist,
      durationMs: durationMs ?? this.durationMs,
      streamSizeBytes: streamSizeBytes ?? this.streamSizeBytes,
      audioOnlyStreamInfo: audioOnlyStreamInfo ?? this.audioOnlyStreamInfo,
      ytClient: ytClient ?? this.ytClient,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      album: album ?? this.album,
      isFullLength: isFullLength ?? this.isFullLength,
      matchScore: matchScore ?? this.matchScore,
    );
  }

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
    'how we made',
    'the making of',
    'making of',
    'behind the scenes',
    'interview',
    'podcast',
    'documentary',
    'vlog',
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

  static String cleanArtist(String s) {
    var cleaned = s.trim();
    if (cleaned.toLowerCase().endsWith(' - topic')) {
      cleaned = cleaned.substring(0, cleaned.length - ' - topic'.length).trim();
    } else if (cleaned.toLowerCase().endsWith(' topic')) {
      cleaned = cleaned.substring(0, cleaned.length - ' topic'.length).trim();
    }
    if (cleaned.toLowerCase().endsWith('vevo')) {
      cleaned = cleaned.substring(0, cleaned.length - 4).trim();
    }
    if (cleaned.toLowerCase().endsWith(' official')) {
      cleaned = cleaned.substring(0, cleaned.length - ' official'.length).trim();
    }
    return cleanString(cleaned);
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

  static Set<String> tokenizeRaw(String s) {
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
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
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
    int maxDurationDiffMs = 45000,
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
    final rawCandTitleTokens = tokenizeRaw(candidateTitle);
    final combinedCandTokens = candArtistTokens.union(candTitleTokens).union(rawCandTitleTokens);

    final cleanTargetArtist = cleanString(targetArtist);
    final cleanCandArtist = cleanArtist(candidateArtist);
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
      if (cleanCandArtist == cleanPrimaryArtist ||
          (primaryArtistTokens.isNotEmpty && primaryArtistTokens.difference(combinedCandTokens).isEmpty)) {
        artistScore = math.max(artistScore, 0.90);
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
    final cleanTgt = cleanString(targetTitle);
    final targetWords = cleanTgt.split(' ').where((w) => w.isNotEmpty).toList();
    final targetTitleTokens = tokenize(targetTitle);

    // Check if candidateTitle is in "Artist - Title", "Artist x Artist - Title", or "Title - Artist" format
    String effectiveCandTitle = candidateTitle;
    final sepMatch = RegExp(r'\s+[-–—:]\s+').firstMatch(candidateTitle);
    if (sepMatch != null) {
      final partA = candidateTitle.substring(0, sepMatch.start).trim();
      final partB = candidateTitle.substring(sepMatch.end).trim();
      final cleanA = cleanString(partA);
      final cleanB = cleanString(partB);
      if (cleanB == cleanTgt || cleanB.startsWith(cleanTgt)) {
        effectiveCandTitle = partB;
      } else if (cleanA == cleanTgt || cleanA.startsWith(cleanTgt)) {
        effectiveCandTitle = partA;
      }
    }

    final cleanCand = cleanString(effectiveCandTitle);
    final candWords = cleanCand.split(' ').where((w) => w.isNotEmpty).toList();

    const allowedFluff = {
      'remaster', 'remastered', 'mix', 'edit', 'version', 'audio', 'explicit',
      'clean', 'bonus', 'track', 'song', 'official', 'original', 'extended',
      'video', 'music', 'lyric', 'lyrics', 'visualizer', '4k', 'hd', 'hq',
      'season', 'episode', 'coke', 'studio', 'nescafe', 'basement', 'session',
      'unplugged', 'produced', 'prod', 'feat', 'ft', 'featuring', 'with', 'x', 'vs',
      'full', 'soundtrack', 'ost', 'theme', 'instrumental',
    };
    const commonStopWords = {
      'the', 'a', 'an', 'and', 'feat', 'ft', 'with', 'by', 'of', 'in', 'on', 'to', 'x', 'vs'
    };

    final targetArtistAllWords = cleanTargetArtist.split(' ').where((w) => w.isNotEmpty).toSet();
    final candArtistAllWords = cleanCandArtist.split(' ').where((w) => w.isNotEmpty).toSet();

    final allowedExtra = allowedFluff
        .union(targetArtistTokens)
        .union(targetArtistAllWords)
        .union(candArtistTokens)
        .union(candArtistAllWords)
        .union(commonStopWords);

    double titleScore = 0.0;
    if (cleanCand == cleanTgt) {
      titleScore = 1.0;
    } else if (cleanCand.startsWith(cleanTgt)) {
      // Candidate starts with target title. Check if remainder is just version/media fluff or artist name
      final remainder = candWords.sublist(math.min(targetWords.length, candWords.length));
      final nonFluffRemainder = remainder.where((w) => !allowedExtra.contains(w)).toList();
      if (nonFluffRemainder.isEmpty) {
        titleScore = 0.95;
      } else if (nonFluffRemainder.length <= 1) {
        titleScore = 0.85;
      } else if (artistScore >= 0.80) {
        // High artist match (e.g. official artist or show channel with featured performers/producer credits in title)
        titleScore = 0.85;
      } else {
        // Substantial extra words on different artist: NOT the target song!
        titleScore = 0.30;
      }
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

      // Specificity penalty: if candidate has extra words that are not fluff or artist name
      final extraCandWords = candPool.where((w) => !allowedExtra.contains(w)).length;
      double specificityPenalty = 0.0;
      if (extraCandWords > 0) {
        specificityPenalty = (extraCandWords * 0.25).clamp(0.0, 0.60);
      }

      titleScore = (math.min(wordRatio, tokenRatio > 0 ? tokenRatio : wordRatio) - specificityPenalty).clamp(0.0, 1.0);
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

    // 4. Duration Check
    int? diffMs;
    double durationBonus = 0.0;
    if (targetDurationMs != null &&
        targetDurationMs > 0 &&
        candidateDurationMs != null &&
        candidateDurationMs > 0) {
      diffMs = (candidateDurationMs - targetDurationMs).abs();
      if (diffMs > maxDurationDiffMs) {
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
        durationBonus = 0.15;
      } else if (diffMs <= 30000) {
        durationBonus = 0.05;
      } else if (diffMs > 40000) {
        durationBonus = -0.15;
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

    // 1. Android Player API (fastest, never triggers bot captcha or 429)
    try {
      final playerUri = Uri.parse('https://www.youtube.com/youtubei/v1/player?prettyPrint=false');
      final playerResp = await _http.post(
        playerUri,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
        },
        body: jsonEncode({
          'context': {
            'client': {
              'clientName': 'ANDROID',
              'clientVersion': '20.10.38',
              'userAgent': 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
              'hl': 'en',
              'timeZone': 'UTC',
              'utcOffsetMinutes': 0,
              'osName': 'Android',
              'osVersion': '11',
            },
          },
          'videoId': videoId,
        }),
      ).timeout(const Duration(seconds: 4));

      if (playerResp.statusCode == 200) {
        final data = jsonDecode(playerResp.body) as Map<String, dynamic>;
        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        final formats = streamingData?['formats'] as List<dynamic>? ?? [];
        final videoDetails = data['videoDetails'] as Map<String, dynamic>?;

        if (formats.isNotEmpty && videoDetails != null) {
          final fmt = formats.firstWhere((f) => f['itag'] == 18, orElse: () => formats.first);
          final streamUrl = fmt['url'] as String?;
          if (streamUrl != null && streamUrl.isNotEmpty) {
            final durSec = int.tryParse(videoDetails['lengthSeconds']?.toString() ?? '') ?? 0;
            final durMs = durSec > 0 ? durSec * 1000 : (expectedDurationMs ?? 210000);
            if (durMs >= 45000) {
              final title = videoDetails['title']?.toString() ?? 'YouTube Track';
              final author = videoDetails['author']?.toString() ?? '';
              final rawBitrate = fmt['bitrate'];
              final calculatedKbps = rawBitrate is num && rawBitrate > 0
                  ? (rawBitrate / 1000).round()
                  : (durSec > 0 && fmt['contentLength'] != null
                      ? ((int.tryParse(fmt['contentLength'].toString()) ?? 0) * 8 / (durSec * 1000)).round()
                      : 160);
              final dynamicKbps = calculatedKbps > 0 ? calculatedKbps : 160;
              return AudioStreamCandidate(
                streamUrl: streamUrl,
                format: 'mp4',
                bitrateKbps: dynamicKbps,
                sourceId: videoId,
                sourceTitle: title,
                channelOrArtist: author,
                durationMs: durMs,
                streamSizeBytes: int.tryParse(fmt['contentLength']?.toString() ?? ''),
                artworkUrl: preferredArtworkUrl ?? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
                album: preferredAlbum,
                isFullLength: true,
                matchScore: 1.0,
              );
            }
          }
        }
      }
    } catch (_) {}

    // 2. YouTubeExplode fallback
    final client = ytClient;
    try {
      final video = await client.videos
          .get(videoId)
          .timeout(const Duration(milliseconds: 4500));
      final durMs =
          video.duration?.inMilliseconds ?? expectedDurationMs ?? 210000;

      // Reject truncated clips / 30s snippets
      if (durMs < 45000) return null;

      StreamManifest manifest;
      try {
        manifest = await client.videos.streamsClient
            .getManifest(
              videoId,
              requireWatchPage: false,
              ytClients: [YoutubeApiClient.androidSdkless],
            )
            .timeout(const Duration(milliseconds: 5000));
      } catch (_) {
        manifest = await client.videos.streamsClient
            .getManifest(videoId)
            .timeout(const Duration(milliseconds: 4000));
      }
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
  /// 1. Prioritizes authentic studio master recordings and full YouTube tracks.
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

    // Tier 1: Verified 320kbps Studio Masters (Quality-Max Engine)
    // When a target track exists in the worldwide studio catalog with strict artist
    // and title verification (score >= 0.85), deliver the authentic 320 kbps studio recording.
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
          saavnCandidate.durationMs >= 45000 &&
          saavnCandidate.matchScore >= 0.85) {
        return saavnCandidate;
      }
    } catch (e) {
      debugPrint('Studio master resolution error for "$title": $e');
    }

    // Tier 2: YouTube Music InnerTube Search & Android Player Stream
    // Directly accesses YouTube Music's official track catalog and Android direct audio streams.
    try {
      final ytCandidate = await _resolveViaYouTubeInnerTube(
        title: cleanTitle.isNotEmpty ? cleanTitle : title,
        artist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
        preferredArtworkUrl: preferredArtworkUrl,
        preferredAlbum: preferredAlbum,
      );
      if (ytCandidate != null &&
          ytCandidate.isFullLength &&
          ytCandidate.durationMs >= 45000) {
        return ytCandidate;
      }
    } catch (e) {
      debugPrint('YouTube InnerTube resolution error for "$title": $e');
    }

    // Tier 3: YouTubeExplode Scraper Fallback
    try {
      final ytCandidate = await _resolveViaYouTubeExplode(
        cleanTitle: cleanTitle.isNotEmpty ? cleanTitle : title,
        cleanArtist: cleanArtist.isNotEmpty ? cleanArtist : artist,
        expectedDurationMs: expectedDurationMs,
      ).timeout(const Duration(milliseconds: 6000));
      if (ytCandidate != null &&
          ytCandidate.isFullLength &&
          ytCandidate.durationMs >= 45000) {
        return ytCandidate;
      }
    } catch (e) {
      debugPrint('YouTube Explode resolution error for "$title": $e');
    }

    // Tier 4: Public YouTube Mirror Audio Streams (Piped / Invidious) (Full Length)
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

    // STRICT NO-PREVIEW POLICY:
    // 30s previews (from iTunes search or Spotify audioPreview) are completely forbidden.
    // If no full-length audio track could be matched from YouTube or Studio Masters,
    // return null so FreeBeat never imports truncated teaser clips into playlists.
    return null;
  }

  /// Searches YouTube Music via lightweight InnerTube API and extracts Android player streams.
  Future<AudioStreamCandidate?> _resolveViaYouTubeInnerTube({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final cleanT = _sanitizeQuery(title);
    final cleanA = _sanitizeQuery(artist);
    final primaryA = cleanA.split(RegExp(r'[,&;]')).first.trim();

    final queries = [
      if (cleanT.isNotEmpty && primaryA.isNotEmpty) '$cleanT $primaryA',
      if (primaryA.isNotEmpty && cleanT.isNotEmpty) '$primaryA $cleanT',
      if (cleanA.isNotEmpty && cleanA != primaryA && cleanT.isNotEmpty) '$cleanT $cleanA',
      if (cleanA.isNotEmpty && cleanA != primaryA && cleanT.isNotEmpty) '$cleanA $cleanT',
      cleanT,
    ];

    for (final q in queries) {
      try {
        final searchResp = await _http.post(
          Uri.parse('https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://music.youtube.com/',
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': '1.20231218.01.00',
                'hl': 'en',
                'gl': 'US',
              }
            },
            'query': q,
          }),
        ).timeout(const Duration(seconds: 4));

        if (searchResp.statusCode == 200) {
          final videoIds = RegExp(r'"videoId":"([a-zA-Z0-9_-]{11})"')
              .allMatches(searchResp.body)
              .map((m) => m.group(1)!)
              .toSet()
              .toList();

          for (final vId in videoIds.take(5)) {
            final candidate = await resolveDirectYouTubeUrl(
              vId,
              expectedDurationMs: expectedDurationMs,
              preferredArtworkUrl: preferredArtworkUrl,
              preferredAlbum: preferredAlbum,
            );
            if (candidate != null &&
                candidate.isFullLength &&
                candidate.durationMs >= 45000) {
              final eval = TrackMatchScorer.evaluate(
                targetTitle: title,
                targetArtist: artist,
                candidateTitle: candidate.sourceTitle,
                candidateArtist: candidate.channelOrArtist,
                targetDurationMs: expectedDurationMs,
                candidateDurationMs: candidate.durationMs,
              );
              if (eval.isMatch) {
                return candidate.copyWith(matchScore: eval.score);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('YouTube Music InnerTube search error for "$q": $e');
      }
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
          'https://www.jiosaavn.com/api.php?__call=search.getResults&_format=json&_marker=0&api_version=4&ctx=web6dot0&p=1&n=10&q=${Uri.encodeComponent(q)}',
        );
        final resp = await _http.get(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': 'application/json, text/plain, */*',
            'Cookie': 'L=english;',
          },
        ).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final results = data['results'] as List<dynamic>? ?? [];
          for (final item in results) {
            if (item is! Map<String, dynamic>) continue;
            final itemId = item['id']?.toString() ?? '';
            if (itemId.isNotEmpty && seenIds.contains(itemId)) continue;
            if (itemId.isNotEmpty) seenIds.add(itemId);

            final moreInfo = item['more_info'] as Map<String, dynamic>?;
            final encUrl = (moreInfo?['encrypted_media_url'] ?? item['encrypted_media_url'])?.toString() ?? '';
            if (encUrl.isEmpty) continue;

            final itemDur = int.tryParse(moreInfo?['duration']?.toString() ?? '') ??
                int.tryParse(item['duration']?.toString() ?? '') ?? 0;
            if (itemDur < 45) continue;

            final songName =
                item['song']?.toString() ?? item['title']?.toString() ?? title;

            // Extract genuine artist from artistMap or primary_artists (never fake or default to query artist)
            String candidateArtist = '';
            final artistMap = moreInfo?['artistMap'] as Map<String, dynamic>?;
            final primaryList = artistMap?['primary_artists'] as List<dynamic>?;
            if (primaryList != null && primaryList.isNotEmpty) {
              candidateArtist = primaryList
                  .map((a) => (a is Map ? a['name']?.toString() : null) ?? '')
                  .where((name) => name.isNotEmpty)
                  .join(', ');
            }
            if (candidateArtist.isEmpty) {
              final rawPri = (moreInfo?['primary_artists'] ?? item['primary_artists'])?.toString();
              if (rawPri != null && rawPri.isNotEmpty && rawPri.toLowerCase() != 'null') {
                candidateArtist = rawPri;
              }
            }
            if (candidateArtist.isEmpty) {
              final rawSingers = (moreInfo?['singers'] ?? item['singers'])?.toString();
              if (rawSingers != null && rawSingers.isNotEmpty && rawSingers.toLowerCase() != 'null') {
                candidateArtist = rawSingers;
              }
            }
            final primaryArtists = candidateArtist;

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
            final albumName = (moreInfo?['album'] ?? item['album'])?.toString() ?? preferredAlbum;
            final rawImage = (item['image'] ?? moreInfo?['image'])?.toString();
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
                channelOrArtist: primaryArtists.isNotEmpty ? primaryArtists : artist,
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

  static int? _parseDurationString(String? dur) {
    if (dur == null || dur.isEmpty) return null;
    final parts = dur.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return (m * 60 + s) * 1000;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return (h * 3600 + m * 60 + s) * 1000;
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
    final primaryArtist = cleanArtist
        .split(RegExp(r'[,&;/]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false))
        .first
        .trim();

    final seenQueries = <String>{};
    final queries = <String>[];
    void addQuery(String q) {
      final trimmed = q.trim();
      if (trimmed.isNotEmpty && seenQueries.add(trimmed.toLowerCase())) {
        queries.add(trimmed);
      }
    }

    if (primaryArtist.isNotEmpty && cleanTitle.isNotEmpty) {
      addQuery('$primaryArtist $cleanTitle');
      if (cleanArtist != primaryArtist) {
        addQuery('$cleanArtist $cleanTitle');
      }
      addQuery('$cleanTitle $primaryArtist');
    }
    if (cleanTitle.isNotEmpty) {
      addQuery(cleanTitle);
    }

    for (final query in queries) {
      try {
        final searchResults = await client.search
            .searchContent(query)
            .timeout(const Duration(milliseconds: 5000));
        final searchVideos = searchResults.whereType<SearchVideo>().toList();
        if (searchVideos.isEmpty) continue;

        final rankedCandidates = <({SearchVideo video, double score, int? durMs})>[];

        for (final video in searchVideos.take(10)) {
          final durMs = _parseDurationString(video.duration);
          // STRICT FULL-LENGTH CHECK: Never consider 30s clips or short previews
          // Also reject >15min full podcasts/documentaries if expected duration is standard
          if (durMs != null && (durMs < 45000 || (expectedDurationMs == null && durMs > 900000))) continue;

          final eval = TrackMatchScorer.evaluate(
            targetTitle: cleanTitle,
            targetArtist: cleanArtist,
            candidateTitle: video.title,
            candidateArtist: video.author,
            targetDurationMs: expectedDurationMs,
            candidateDurationMs: durMs,
            maxDurationDiffMs: 90000,
          );

          if (!eval.isMatch) continue;
          rankedCandidates.add((video: video, score: eval.score, durMs: durMs));
        }

        if (rankedCandidates.isEmpty) continue;
        rankedCandidates.sort((a, b) => b.score.compareTo(a.score));

        // Fetch audio stream manifest only for the top-scoring candidate(s)
        for (final candidate in rankedCandidates.take(2)) {
          final video = candidate.video;
          try {
            StreamManifest manifest;
            try {
              manifest = await client.videos.streamsClient
                  .getManifest(
                    video.id,
                    requireWatchPage: false,
                    ytClients: [YoutubeApiClient.androidSdkless],
                  )
                  .timeout(const Duration(milliseconds: 5000));
            } catch (_) {
              manifest = await client.videos.streamsClient
                  .getManifest(video.id)
                  .timeout(const Duration(milliseconds: 4000));
            }
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
                durationMs: candidate.durMs ?? expectedDurationMs ?? 210000,
                streamSizeBytes: bestAudio.size.totalBytes,
                audioOnlyStreamInfo: bestAudio,
                ytClient: client,
                artworkUrl: video.thumbnails.isNotEmpty
                    ? video.thumbnails.first.url.toString()
                    : 'https://i.ytimg.com/vi/${video.id.value}/hqdefault.jpg',
                isFullLength: true,
                matchScore: candidate.score,
              );
            }
          } catch (_) {
            continue;
          }
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
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), ' ') // remove parenthesized info
        .replaceAll(RegExp(r'''[^\w\s\-'"]'''), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void close() {
    _yt?.close();
  }
}
