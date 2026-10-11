import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/models/track.dart';

/// Enriches missing high-resolution album art via iTunes Search API and
/// fetches millisecond-accurate time-synced `.lrc` lyrics via LRCLIB / cloud sidecars.
class ArtworkAndLyricsService {
  ArtworkAndLyricsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Parses standard LRC format `[mm:ss.xx] Lyric text` into sorted [LyricLine] objects.
  static List<LyricLine> parseLrcContent(String rawLrc) {
    final lines = <LyricLine>[];
    final regExp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)');

    for (final rawLine in const LineSplitter().convert(rawLrc)) {
      final match = regExp.firstMatch(rawLine.trim());
      if (match != null) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fracRaw = match.group(3) ?? '0';
        final millis = fracRaw.length == 2
            ? (int.tryParse(fracRaw) ?? 0) * 10
            : fracRaw.length == 1
                ? (int.tryParse(fracRaw) ?? 0) * 100
                : (int.tryParse(fracRaw) ?? 0);
        final text = (match.group(4) ?? '').trim();
        if (text.isNotEmpty) {
          lines.add(
            LyricLine(
              timestampMs: (minutes * 60 + seconds) * 1000 + millis,
              text: text,
            ),
          );
        }
      }
    }
    lines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return lines;
  }

  /// Queries LRCLIB (`https://lrclib.net/api/get`) for time-synced lyrics.
  Future<List<LyricLine>> fetchSyncedLyricsForTrack(Track track) async {
    if (track.syncedLyrics.isNotEmpty) return track.syncedLyrics;
    try {
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': track.title,
        'artist_name': track.artist,
        'album_name': track.album,
      });
      final resp =
          await _client.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final synced = data['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) {
          return parseLrcContent(synced);
        }
      }
    } catch (_) {}
    return track.syncedLyrics;
  }

  /// Resolves high-resolution 600x600 cover art URL via iTunes Search API fallback.
  Future<String?> lookupHighResArtwork({
    required String artist,
    required String title,
  }) async {
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': '$artist $title',
        'media': 'music',
        'entity': 'song',
        'limit': '1',
      });
      final resp =
          await _client.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        if (results.isNotEmpty) {
          final first = results.first as Map<String, dynamic>;
          final art100 = first['artworkUrl100'] as String?;
          if (art100 != null) {
            return art100.replaceAll('100x100bb', '600x600bb');
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
