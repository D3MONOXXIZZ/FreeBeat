import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/track.dart';
import 'artwork_extractor.dart';
import 'artwork_palette_extractor.dart';

/// Represents a lyric candidate returned by LRCLIB online search.
class OnlineLyricResult {
  const OnlineLyricResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    this.syncedLyrics,
    this.plainLyrics,
  });

  final int id;
  final String trackName;
  final String artistName;
  final String albumName;
  final int durationSeconds;
  final String? syncedLyrics;
  final String? plainLyrics;

  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  List<LyricLine> get parsedSyncedLyrics =>
      hasSyncedLyrics ? ArtworkAndLyricsService.parseLrcContent(syncedLyrics!) : const [];
}

/// Represents an album cover candidate returned by online search.
class OnlineArtworkResult {
  const OnlineArtworkResult({
    required this.artworkUrl,
    required this.title,
    required this.artist,
    required this.album,
  });

  final String artworkUrl;
  final String title;
  final String artist;
  final String album;
}

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

  /// Searches LRCLIB (`https://lrclib.net/api/search`) for lyrics matching [query].
  Future<List<OnlineLyricResult>> searchOnlineLyrics({
    required String query,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {
        'q': cleanQuery,
      });
      final resp =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List<dynamic>? ?? [];
        return list.map((item) {
          final m = item as Map<String, dynamic>;
          return OnlineLyricResult(
            id: m['id'] as int? ?? 0,
            trackName: m['trackName'] as String? ?? 'Unknown Track',
            artistName: m['artistName'] as String? ?? 'Unknown Artist',
            albumName: m['albumName'] as String? ?? '',
            durationSeconds: (m['duration'] as num?)?.round() ?? 0,
            syncedLyrics: m['syncedLyrics'] as String?,
            plainLyrics: m['plainLyrics'] as String?,
          );
        }).toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Searches iTunes API for multiple high-res album artworks matching [query].
  Future<List<OnlineArtworkResult>> searchOnlineArtwork({
    required String query,
    int limit = 20,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];
    try {
      final uri = Uri.https('itunes.apple.com', '/search', {
        'term': cleanQuery,
        'media': 'music',
        'entity': 'song',
        'limit': limit.toString(),
      });
      final resp =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final results = data['results'] as List<dynamic>? ?? [];
        final out = <OnlineArtworkResult>[];
        final seen = <String>{};
        for (final item in results) {
          final m = item as Map<String, dynamic>;
          final art100 = m['artworkUrl100'] as String?;
          if (art100 != null && art100.isNotEmpty) {
            final highRes = art100.replaceAll('100x100bb', '1400x1400bb');
            if (seen.add(highRes)) {
              out.add(
                OnlineArtworkResult(
                  artworkUrl: highRes,
                  title: m['trackName'] as String? ?? '',
                  artist: m['artistName'] as String? ?? '',
                  album: m['collectionName'] as String? ?? '',
                ),
              );
            }
          }
        }
        return out;
      }
    } catch (_) {}
    return const [];
  }

  /// Downloads a remote artwork URL and caches it permanently in the app's album_art folder.
  Future<String?> downloadAndCacheArtwork(String remoteUrl, String trackId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final artDir = Directory(p.join(appDir.path, 'album_art'));
      if (!artDir.existsSync()) {
        artDir.createSync(recursive: true);
      }
      final sanitizedId = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File(
          p.join(artDir.path, '${sanitizedId}_${DateTime.now().millisecondsSinceEpoch}.jpg'));

      final resp = await _client
          .get(Uri.parse(remoteUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
        await targetFile.writeAsBytes(resp.bodyBytes);
        return targetFile.path;
      }
    } catch (_) {}
    return remoteUrl;
  }

  /// Copies a user-picked local image file into the app's persistent album_art folder.
  Future<String?> copyLocalImageToAppStorage(
      String sourcePath, String trackId) async {
    try {
      final source = File(sourcePath);
      if (!source.existsSync()) return null;
      final appDir = await getApplicationDocumentsDirectory();
      final artDir = Directory(p.join(appDir.path, 'album_art'));
      if (!artDir.existsSync()) {
        artDir.createSync(recursive: true);
      }
      final ext =
          p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
      final sanitizedId = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File(
          p.join(artDir.path, '${sanitizedId}_${DateTime.now().millisecondsSinceEpoch}$ext'));
      await source.copy(targetFile.path);
      return targetFile.path;
    } catch (_) {}
    return sourcePath;
  }

  /// Returns true if the artist string is missing, generic, or an Android/cloud package/URI string.
  static bool isInvalidOrGenericArtist(String? artist) {
    if (artist == null) return true;
    final trimmed = artist.trim();
    if (trimmed.isEmpty) return true;
    final lower = trimmed.toLowerCase();
    return lower == 'cloud artist' ||
        lower == 'unknown artist' ||
        lower == 'unknown' ||
        lower == 'various artists' ||
        lower.contains('cloud') ||
        lower.startsWith('com.') ||
        lower.startsWith('org.') ||
        lower.startsWith('net.') ||
        lower.startsWith('content:') ||
        lower.contains('.storage') ||
        lower.contains('android') ||
        lower.contains('documents') ||
        lower.contains('providers') ||
        lower.contains('/') ||
        lower.contains(':') ||
        lower.contains('local_storage');
  }

  /// Searches iTunes for song metadata (real artist, album, high-res artwork).
  Future<({String? artworkUrl, String? artist, String? album})?> lookupSongMetadata({
    required String artist,
    required String title,
  }) async {
    try {
      final isGeneric = isInvalidOrGenericArtist(artist);
      final cleanArtist = isGeneric
          ? ''
          : artist.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();

      // Clean the title: remove file extension if present
      final cleanTitle = title
          .replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '')
          .trim();

      // Guard: If artist is unknown and title is generic/numeric (e.g. "01", "track 1", "audio"),
      // do not search iTunes, as it will return a random popular song matching that number/word.
      final isGenericTitle = RegExp(r'^(\d+|track\s*\d+|audio\s*\d+|recording\s*\d*)$', caseSensitive: false).hasMatch(cleanTitle);
      if (cleanArtist.isEmpty && (cleanTitle.length < 4 || isGenericTitle)) {
        return null;
      }

      // Candidate search queries:
      // 1. With artist if valid + full title
      // 2. Full title alone (e.g. "Needed You (StayLoose Remix)")
      // 3. Title stripped of parentheses (e.g. "Needed You")
      final candidates = <String>[];
      if (cleanArtist.isNotEmpty) {
        candidates.add('$cleanArtist $cleanTitle');
      }
      candidates.add(cleanTitle);
      final strippedTitle = cleanTitle
          .replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]\s*'), '')
          .trim();
      if (strippedTitle.isNotEmpty && strippedTitle != cleanTitle) {
        if (cleanArtist.isNotEmpty) {
          candidates.add('$cleanArtist $strippedTitle');
        }
        candidates.add(strippedTitle);
      }

      for (final query in candidates) {
        if (query.trim().isEmpty) continue;
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
            final itunesArtist = first['artistName'] as String?;
            final itunesAlbum = first['collectionName'] as String?;
            final art600 = art100?.replaceAll('100x100bb', '600x600bb');
            return (
              artworkUrl: art600,
              artist: itunesArtist,
              album: itunesAlbum,
            );
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Resolves high-resolution 600x600 cover art URL via iTunes Search API fallback.
  Future<String?> lookupHighResArtwork({
    required String artist,
    required String title,
  }) async {
    final meta = await lookupSongMetadata(artist: artist, title: title);
    return meta?.artworkUrl;
  }

  /// Enriches [track] with high-res artwork from:
  /// 1. Embedded tags in local file (MP3 APIC or FLAC PICTURE)
  /// 2. iTunes Search API fallback, downloaded and cached locally
  /// Also extracts true artwork dominant and edge color palette,
  /// and heals generic artist/album names (e.g. "Cloud Artist").
  Future<Track> enrichTrackArtwork(Track track) async {
    Track currentTrack = track;

    // 0. If artist or album is generic or invalid, query iTunes for real metadata
    final isGeneric = isInvalidOrGenericArtist(currentTrack.artist) ||
        currentTrack.album == 'Cloud Library' ||
        currentTrack.album.isEmpty ||
        isInvalidOrGenericArtist(currentTrack.album);

    String? itunesArtUrl;
    if (isGeneric ||
        currentTrack.artworkUrl == null ||
        currentTrack.artworkUrl!.isEmpty) {
      final meta = await lookupSongMetadata(
        artist: currentTrack.artist,
        title: currentTrack.title,
      );
      if (meta != null) {
        currentTrack = currentTrack.copyWith(
          artist: (meta.artist != null && meta.artist!.isNotEmpty)
              ? meta.artist
              : (isInvalidOrGenericArtist(currentTrack.artist)
                  ? 'Unknown Artist'
                  : currentTrack.artist),
          album: (meta.album != null && meta.album!.isNotEmpty)
              ? meta.album
              : currentTrack.album,
        );
        itunesArtUrl = meta.artworkUrl;
      } else if (isInvalidOrGenericArtist(currentTrack.artist)) {
        currentTrack = currentTrack.copyWith(artist: 'Unknown Artist');
      }
    }

    // 1. If artwork is already a valid existing file, sanitize palette if needed
    if (currentTrack.artworkUrl != null && currentTrack.artworkUrl!.isNotEmpty) {
      if (!currentTrack.artworkUrl!.startsWith('http://') &&
          !currentTrack.artworkUrl!.startsWith('https://')) {
        if (File(currentTrack.artworkUrl!).existsSync()) {
          // If legacy green or default seed, re-extract palette
          if (currentTrack.dominantColorValue == 0xFF3DDC84 ||
              currentTrack.dominantColorValue == 0xFF1DB954 ||
              currentTrack.dominantColorValue == 0xFF6750A4) {
            final palette =
                await ArtworkPaletteExtractor.extractPalette(currentTrack.artworkUrl);
            return currentTrack.copyWith(
                dominantColorValue: palette.dominantColor.toARGB32());
          }
          return currentTrack;
        }
      }
    }

    // 2. Try local embedded artwork extraction
    final potentialLocalPaths = [
      currentTrack.localCachePath,
      currentTrack.remotePathOrId,
      currentTrack.streamUrl,
    ];

    for (final path in potentialLocalPaths) {
      if (path != null && path.isNotEmpty) {
        if (path.startsWith('content://')) {
          try {
            const channel = MethodChannel('com.freebeat.native_bridge');
            final meta = await channel.invokeMapMethod<String, dynamic>(
              'extractAudioMetadata',
              {'uri': path, 'path': path},
            );
            final picBytes = meta?['pictureBytes'] as Uint8List?;
            if (picBytes != null && picBytes.isNotEmpty) {
              final saved = await ArtworkExtractor.saveArtworkBytes(
                picBytes,
                currentTrack.id,
              );
              if (saved != null && File(saved).existsSync()) {
                final palette = await ArtworkPaletteExtractor.extractPalette(saved);
                return currentTrack.copyWith(
                  artworkUrl: saved,
                  dominantColorValue: palette.dominantColor.toARGB32(),
                );
              }
            }
          } catch (_) {}
        } else {
          final file = File(path);
          if (file.existsSync()) {
            final extracted =
                await ArtworkExtractor.extractEmbeddedArtwork(file, currentTrack.id);
            if (extracted != null && File(extracted).existsSync()) {
              final palette =
                  await ArtworkPaletteExtractor.extractPalette(extracted);
              return currentTrack.copyWith(
                artworkUrl: extracted,
                dominantColorValue: palette.dominantColor.toARGB32(),
              );
            }
          }
        }
      }
    }

    // 3. Fallback to iTunes Search API for 600x600 cover
    final netUrl = itunesArtUrl ??
        await lookupHighResArtwork(
          artist: currentTrack.artist,
          title: currentTrack.title,
        );

    if (netUrl != null && netUrl.isNotEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final artDir = Directory(p.join(appDir.path, 'album_art'));
        if (!artDir.existsSync()) {
          artDir.createSync(recursive: true);
        }
        final sanitizedId =
            currentTrack.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final targetFile = File(p.join(artDir.path, '$sanitizedId.jpg'));

        final imgResp = await _client
            .get(Uri.parse(netUrl))
            .timeout(const Duration(seconds: 6));
        if (imgResp.statusCode == 200 && imgResp.bodyBytes.length > 500) {
          await targetFile.writeAsBytes(imgResp.bodyBytes);
          final palette =
              await ArtworkPaletteExtractor.extractPalette(targetFile.path);
          return currentTrack.copyWith(
            artworkUrl: targetFile.path,
            dominantColorValue: palette.dominantColor.toARGB32(),
          );
        }
      } catch (_) {}
      final palette = await ArtworkPaletteExtractor.extractPalette(netUrl);
      return currentTrack.copyWith(
        artworkUrl: netUrl,
        dominantColorValue: palette.dominantColor.toARGB32(),
      );
    }

    return currentTrack;
  }
}
