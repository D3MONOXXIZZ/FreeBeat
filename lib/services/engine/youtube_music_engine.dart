import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../audio/missing_track_audio_resolver.dart';

/// On-device engine responsible for querying YouTube Music InnerTube endpoints
/// directly from the user's phone, extracting high-speed audio streams with zero
/// datacenter IP blocking.
class YouTubeMusicEngine {
  YouTubeMusicEngine({
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Resolves the authentic audio stream for a given track from YouTube Music.
  Future<AudioStreamCandidate?> resolveTrackAudio({
    required String title,
    required String artist,
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
    final cleanT = _sanitize(title);
    final cleanA = _sanitize(artist);
    final primaryA = cleanA.split(RegExp(r'[,&;]')).first.trim();

    final queries = [
      if (cleanT.isNotEmpty && primaryA.isNotEmpty) '$cleanT $primaryA',
      if (primaryA.isNotEmpty && cleanT.isNotEmpty) '$primaryA $cleanT',
      if (cleanA.isNotEmpty && cleanA != primaryA && cleanT.isNotEmpty) '$cleanT $cleanA',
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
            final candidate = await resolveVideoId(
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
        debugPrint('YouTubeMusicEngine search error for "$q": $e');
      }
    }

    return null;
  }

  /// Resolves direct audio stream for a given YouTube video ID using the Android player endpoint.
  Future<AudioStreamCandidate?> resolveVideoId(
    String videoId, {
    int? expectedDurationMs,
    String? preferredArtworkUrl,
    String? preferredAlbum,
  }) async {
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
          // Select itag 18 (AAC/MP4 audio) to bypass the 800KB PO token cutoff
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
    } catch (e) {
      debugPrint('YouTubeMusicEngine error resolving video $videoId: $e');
    }

    return null;
  }

  static String _sanitize(String s) {
    return s
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
