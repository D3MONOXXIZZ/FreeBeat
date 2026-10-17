import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/track.dart';
import 'artwork_extractor.dart';
import 'artwork_palette_extractor.dart';

/// Enriches missing high-resolution album art via embedded file tag extraction,
/// iTunes Search API fallback, and fetches millisecond-accurate time-synced `.lrc`
/// lyrics via LRCLIB / cloud sidecars.
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
      final cleanArtist = artist.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
      final cleanTitle = title.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
      final query = cleanArtist.isNotEmpty ? '$cleanArtist $cleanTitle' : cleanTitle;
      if (query.isEmpty) return null;

      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': query,
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

  /// Enriches [track] with high-res artwork from:
  /// 1. Embedded tags in local file (MP3 APIC or FLAC PICTURE)
  /// 2. iTunes Search API fallback, downloaded and cached locally
  /// Also extracts true artwork dominant and edge color palette.
  Future<Track> enrichTrackArtwork(Track track) async {
    // If artwork is already a valid existing file, sanitize palette if needed
    if (track.artworkUrl != null && track.artworkUrl!.isNotEmpty) {
      if (!track.artworkUrl!.startsWith('http://') &&
          !track.artworkUrl!.startsWith('https://')) {
        if (File(track.artworkUrl!).existsSync()) {
          // If legacy green or default seed, re-extract palette
          if (track.dominantColorValue == 0xFF3DDC84 ||
              track.dominantColorValue == 0xFF1DB954 ||
              track.dominantColorValue == 0xFF6750A4) {
            final palette =
                await ArtworkPaletteExtractor.extractPalette(track.artworkUrl);
            return track.copyWith(
                dominantColorValue: palette.dominantColor.toARGB32());
          }
          return track;
        }
      }
    }

    // 1. Try local embedded artwork extraction
    final potentialLocalPaths = [
      track.localCachePath,
      track.remotePathOrId,
      track.streamUrl,
    ];

    for (final path in potentialLocalPaths) {
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (file.existsSync()) {
          final extracted =
              await ArtworkExtractor.extractEmbeddedArtwork(file, track.id);
          if (extracted != null && File(extracted).existsSync()) {
            final palette =
                await ArtworkPaletteExtractor.extractPalette(extracted);
            return track.copyWith(
              artworkUrl: extracted,
              dominantColorValue: palette.dominantColor.toARGB32(),
            );
          }
        }
      }
    }

    // 2. Query iTunes Search API for 600x600 cover
    final netUrl = await lookupHighResArtwork(
      artist: track.artist,
      title: track.title,
    );

    if (netUrl != null && netUrl.isNotEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final artDir = Directory(p.join(appDir.path, 'album_art'));
        if (!artDir.existsSync()) {
          artDir.createSync(recursive: true);
        }
        final sanitizedId = track.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final targetFile = File(p.join(artDir.path, '$sanitizedId.jpg'));

        final imgResp = await _client.get(Uri.parse(netUrl)).timeout(const Duration(seconds: 6));
        if (imgResp.statusCode == 200 && imgResp.bodyBytes.length > 500) {
          await targetFile.writeAsBytes(imgResp.bodyBytes);
          final palette =
              await ArtworkPaletteExtractor.extractPalette(targetFile.path);
          return track.copyWith(
            artworkUrl: targetFile.path,
            dominantColorValue: palette.dominantColor.toARGB32(),
          );
        }
      } catch (_) {}
      final palette = await ArtworkPaletteExtractor.extractPalette(netUrl);
      return track.copyWith(
        artworkUrl: netUrl,
        dominantColorValue: palette.dominantColor.toARGB32(),
      );
    }

    return track;
  }
}
