import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../core/models/track.dart';
import '../metadata/artist_helper.dart';
import 'playlist_missing_tracks_sync_service.dart';

/// Result of an imported playlist analysis.
class PlaylistImportResult {
  PlaylistImportResult({
    required this.title,
    this.description = '',
    required this.matchedTracks,
    required this.unmatchedTrackNames,
    List<MissingTrackItem>? missingTracks,
    required this.totalParsed,
    this.sourceType = 'text',
    this.artworkUrl,
  }) : missingTracks = missingTracks ??
            unmatchedTrackNames.map(MissingTrackItem.fromString).toList();

  final String title;
  final String description;
  final List<Track> matchedTracks;
  final List<String> unmatchedTrackNames;
  final List<MissingTrackItem> missingTracks;
  final int totalParsed;
  final String sourceType; // 'spotify', 'apple', 'youtube', 'm3u', 'text', 'csv'
  final String? artworkUrl;

  int get matchedCount => matchedTracks.length;
  int get unmatchedCount => unmatchedTrackNames.length;
  double get matchPercentage =>
      totalParsed > 0 ? (matchedCount / totalParsed) * 100 : 0.0;
}

/// Service that parses Spotify links, Apple Music links, YouTube playlists,
/// CSV/text track lists, and M3U/M3U8 files, matching entries against the user's library.
class PlaylistImportService {
  const PlaylistImportService({http.Client? httpClient}) : _client = httpClient;

  final http.Client? _client;
  http.Client get _http => _client ?? http.Client();

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // remove parenthesized details
        .replaceAll(RegExp(r'[^\w\s]'), '') // remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _canonicalTitle(String s) {
    var clean = s
        .toLowerCase()
        .replaceAll(RegExp(r'[\(\[\{].*?[\)\]\}]'), '') // remove parenthesized details
        .replaceAll(RegExp(r'\s+[-–—:]\s+.*$'), '') // remove trailing " - Single", " - Studio Version", etc.
        .replaceAll(RegExp(r'[^\w\s]'), '') // remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const fluffWords = [
      'studio version',
      'single version',
      'album version',
      'radio edit',
      'original mix',
      'remastered',
      'remaster',
      'official audio',
      'official video',
      'lyric video',
    ];
    for (final fw in fluffWords) {
      if (clean.endsWith(fw)) {
        clean = clean.substring(0, clean.length - fw.length).trim();
      }
    }
    return clean;
  }

  /// Finds the best matching track in the user's library using strict title & artist confidence scoring.
  ///
  /// Prevents false substring collisions (e.g. searching for "Love lost" must NOT falsely match
  /// a completely different song named "Lost").
  static Track? findBestMatch(
    String queryTitle,
    String queryArtist,
    List<Track> libraryTracks,
  ) {
    final cleanQTitle = _normalize(queryTitle);
    final canonQTitle = _canonicalTitle(queryTitle);
    final cleanQArtist = _normalize(queryArtist);
    if (cleanQTitle.isEmpty) return null;

    final qArtists = ArtistHelper.extractArtists(queryArtist, queryTitle)
        .map((a) => _normalize(a))
        .where((a) => a.isNotEmpty)
        .toSet();

    Track? bestCandidate;
    double bestScore = 0.0;

    for (final t in libraryTracks) {
      final tTitle = _normalize(t.title);
      final canonTTitle = _canonicalTitle(t.title);
      final tArtist = _normalize(t.artist);

      // --- 1. TITLE MATCH EVALUATION ---
      double titleScore = 0.0;
      if (tTitle == cleanQTitle) {
        // Exact normalized title match: e.g. "love lost" == "love lost"
        titleScore = 1.0;
      } else if (canonTTitle.isNotEmpty && canonTTitle == canonQTitle) {
        // Canonical title match: e.g. "Faasle - Studio Version" vs "Faasle"
        titleScore = 0.92;
      } else {
        // Distinct titles must NEVER match through substring containment!
        // E.g. "Love lost" must NEVER match "Lost".
        continue;
      }

      // --- 2. ARTIST MATCH EVALUATION ---
      double artistScore = 0.0;

      if (cleanQArtist.isEmpty) {
        // Query did not provide an artist (title-only lookup)
        artistScore = 0.65;
      } else if (tArtist == cleanQArtist) {
        // Exact normalized artist match
        artistScore = 1.0;
      } else {
        final tArtists = ArtistHelper.extractArtists(t.artist, t.title)
            .map((a) => _normalize(a))
            .where((a) => a.isNotEmpty)
            .toSet();

        final overlap = qArtists.intersection(tArtists);
        if (overlap.isNotEmpty) {
          // Participating collaborator overlap: e.g. "Umair, Talha Anjum" and "Talha Anjum"
          artistScore = (overlap.length / qArtists.length).clamp(0.55, 0.95);
          if (qArtists.isNotEmpty &&
              tArtists.isNotEmpty &&
              qArtists.first == tArtists.first) {
            artistScore = math.max(artistScore, 0.88);
          }
        } else if (tArtist.isNotEmpty &&
            (tArtist.contains(cleanQArtist) ||
                cleanQArtist.contains(tArtist))) {
          artistScore = 0.72;
        } else {
          // Both query and candidate have artists, but they have ZERO correlation!
          // E.g. Query artist is "Adele", candidate artist is "Lionel Richie".
          // Disqualify this candidate completely.
          continue;
        }
      }

      // Total composite score (weighted towards exact title & artist match)
      final compositeScore = (titleScore * 0.60) + (artistScore * 0.40);

      // Require high confidence (minimum 0.75) to accept as a library match
      if (compositeScore >= 0.75 && compositeScore > bestScore) {
        bestScore = compositeScore;
        bestCandidate = t;
        if (bestScore >= 0.99) break;
      }
    }

    return bestCandidate;
  }

  /// Parses M3U or M3U8 string content and matches against library tracks.
  PlaylistImportResult parseM3u(String m3uContent, List<Track> libraryTracks) {
    final lines = const LineSplitter().convert(m3uContent);
    String title = 'Imported M3U Playlist';
    final List<_RawTrackEntry> entries = [];

    String? pendingTitle;
    String? pendingArtist;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('#PLAYLIST:')) {
        title = trimmed.substring('#PLAYLIST:'.length).trim();
      } else if (trimmed.startsWith('#EXTINF:')) {
        // e.g. #EXTINF:244,Artist Name - Song Title
        final commaIdx = trimmed.indexOf(',');
        if (commaIdx != -1) {
          final info = trimmed.substring(commaIdx + 1).trim();
          final parts = info.split(' - ');
          if (parts.length >= 2) {
            pendingArtist = parts[0].trim();
            pendingTitle = parts.sublist(1).join(' - ').trim();
          } else {
            pendingTitle = info;
            pendingArtist = '';
          }
        }
      } else if (!trimmed.startsWith('#')) {
        // File path or stream URL
        if (pendingTitle != null) {
          entries.add(_RawTrackEntry(
            title: pendingTitle,
            artist: pendingArtist ?? '',
            urlOrPath: trimmed,
          ));
          pendingTitle = null;
          pendingArtist = null;
        } else {
          // Extract filename from path/url
          final uri = Uri.tryParse(trimmed);
          final seg = uri != null && uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : trimmed.split(RegExp(r'[\\/]')).last;
          final dot = seg.lastIndexOf('.');
          final baseName = dot != -1 ? seg.substring(0, dot) : seg;
          final parts = baseName.split(' - ');
          if (parts.length >= 2) {
            entries.add(_RawTrackEntry(
              artist: parts[0].trim(),
              title: parts.sublist(1).join(' - ').trim(),
              urlOrPath: trimmed,
            ));
          } else {
            entries.add(_RawTrackEntry(
              artist: '',
              title: baseName,
              urlOrPath: trimmed,
            ));
          }
        }
      }
    }

    return _matchEntries(
      entries: entries,
      title: title,
      description: 'Imported from .m3u8 playlist file',
      libraryTracks: libraryTracks,
      sourceType: 'm3u',
    );
  }

  /// Parses plain text, CSV, or line-by-line track listings.
  PlaylistImportResult parseTextOrCsv(
    String rawText,
    List<Track> libraryTracks, {
    String? defaultTitle,
  }) {
    final lines = const LineSplitter().convert(rawText);
    final List<_RawTrackEntry> entries = [];
    String playlistTitle = defaultTitle ?? 'Imported Tracklist';

    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final lower = trimmed.toLowerCase();
      // Check for custom playlist name header: Playlist: My Mix or #PLAYLIST:
      if (lower.startsWith('playlist:') ||
          lower.startsWith('title:') ||
          lower.startsWith('#playlist:')) {
        final colonIdx = trimmed.indexOf(':');
        if (colonIdx != -1) {
          playlistTitle = trimmed.substring(colonIdx + 1).trim();
          continue;
        }
      }

      // Ignore common CSV headers
      if (lower.startsWith('title,') ||
          lower.startsWith('track,') ||
          lower.startsWith('artist,') ||
          lower.startsWith('track name,')) {
        continue;
      }

      // 1. Check for CSV format: title, artist OR artist, title
      if (trimmed.contains(',')) {
        final cols = trimmed.split(',').map((c) => c.trim().replaceAll('"', '')).toList();
        if (cols.length >= 2) {
          entries.add(_RawTrackEntry(
            artist: cols[0],
            title: cols[1],
          ));
          continue;
        }
      }

      // 2. Check for "Artist - Title" or "Title - Artist"
      if (trimmed.contains(' - ')) {
        final parts = trimmed.split(' - ');
        entries.add(_RawTrackEntry(
          artist: parts[0].trim(),
          title: parts.sublist(1).join(' - ').trim(),
        ));
        continue;
      }

      // 3. Fallback: Entire line as Title
      entries.add(_RawTrackEntry(
        artist: '',
        title: trimmed,
      ));
    }

    return _matchEntries(
      entries: entries,
      title: playlistTitle,
      description: 'Imported from text tracklist',
      libraryTracks: libraryTracks,
      sourceType: 'text',
    );
  }

  /// Fetches and parses a public Spotify, Apple Music, or YouTube playlist URL.
  Future<PlaylistImportResult> importFromUrl(
    String url,
    List<Track> libraryTracks,
  ) async {
    final cleanUrl = url.trim();
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https') && !cleanUrl.startsWith('spotify:'))) {
      throw const FormatException('Invalid URL. Please enter a valid playlist link.');
    }

    final isSpotify = cleanUrl.startsWith('spotify:') ||
        (uri.host.contains('spotify.com') || uri.host.contains('spotify.link'));
    final isApple = uri.host.contains('apple.com');
    final isYoutube = uri.host.contains('youtube.com') || uri.host.contains('youtu.be');

    if (!isSpotify && !isApple && !isYoutube) {
      throw const FormatException(
          'Unsupported URL. Spotify, Apple Music, and YouTube / YouTube Music links are supported.');
    }

    if (isSpotify) {
      return _importSpotify(cleanUrl, uri, libraryTracks);
    } else if (isApple) {
      return _importAppleMusic(cleanUrl, uri, libraryTracks);
    } else {
      return _importYouTube(cleanUrl, uri, libraryTracks);
    }
  }

  Future<PlaylistImportResult> _importSpotify(
    String cleanUrl,
    Uri uri,
    List<Track> libraryTracks,
  ) async {
    // 1. Resolve redirect if it is spotify.link
    String resolvedUrl = cleanUrl;
    if (cleanUrl.contains('spotify.link')) {
      try {
        final req = http.Request('GET', Uri.parse(cleanUrl))..followRedirects = false;
        final res = await _http.send(req);
        final loc = res.headers['location'];
        if (loc != null && loc.isNotEmpty) {
          resolvedUrl = loc;
        }
      } catch (_) {}
    }

    // 2. Extract entity type and ID
    final idMatch = RegExp(
      r'(?:spotify:|(?:https?:\/\/)?open\.spotify\.com\/(?:embed\/)?)(playlist|album|track)[\/:]([a-zA-Z0-9]+)',
      caseSensitive: false,
    ).firstMatch(resolvedUrl);

    String entityType = 'playlist';
    String entityId = '';
    if (idMatch != null) {
      entityType = idMatch.group(1)!.toLowerCase();
      entityId = idMatch.group(2)!;
    } else {
      final segs = Uri.tryParse(resolvedUrl)?.pathSegments ?? [];
      if (segs.length >= 2) {
        entityType = segs[segs.length - 2];
        entityId = segs.last;
      }
    }

    String title = 'Spotify Playlist';
    String description = 'Imported from Spotify';
    String? playlistArtworkUrl;
    final List<_RawTrackEntry> entries = [];

    // 3. Query Spotify oEmbed for exact clean playlist title & cover art
    if (entityId.isNotEmpty) {
      try {
        final oembedUri = Uri.parse(
          'https://open.spotify.com/oembed?url=https://open.spotify.com/$entityType/$entityId',
        );
        final oembedRes = await _http.get(oembedUri).timeout(const Duration(seconds: 5));
        if (oembedRes.statusCode == 200) {
          final oembedJson = jsonDecode(oembedRes.body) as Map<String, dynamic>;
          if (oembedJson['title'] != null && oembedJson['title'].toString().isNotEmpty) {
            title = _unescapeHtml(oembedJson['title'].toString());
          }
          if (oembedJson['thumbnail_url'] != null) {
            playlistArtworkUrl = oembedJson['thumbnail_url']?.toString();
          }
        }
      } catch (_) {}
    }

    // 4. Fetch Spotify Embed Page (Contains __NEXT_DATA__ SSR track list)
    if (entityId.isNotEmpty) {
      try {
        final cacheBuster =
            'utm_source=generator&t=${DateTime.now().millisecondsSinceEpoch}&_cb=${DateTime.now().microsecondsSinceEpoch}';
        final embedUrl =
            'https://open.spotify.com/embed/$entityType/$entityId?$cacheBuster';
        final response = await _http.get(
          Uri.parse(embedUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
        ).timeout(const Duration(seconds: 12));

        if (response.statusCode == 200) {
          final html = response.body;

          // Parse __NEXT_DATA__
          final nextDataMatch = RegExp(
            r'<script\s+id=["' "'" r']__NEXT_DATA__["' "'" r']\s+type=["' "'" r']application/json["' "'" r']>(.*?)</script>',
            dotAll: true,
            caseSensitive: false,
          ).firstMatch(html);

          if (nextDataMatch != null && nextDataMatch.group(1) != null) {
            try {
              final json = jsonDecode(nextDataMatch.group(1)!) as Map<String, dynamic>;
              final entity = json['props']?['pageProps']?['state']?['data']?['entity'];
              if (entity is Map<String, dynamic>) {
                if (entity['images'] is List && (entity['images'] as List).isNotEmpty) {
                  playlistArtworkUrl ??= entity['images'][0]['url']?.toString();
                }
                if (entity['coverArt'] is Map && entity['coverArt']['sources'] is List && (entity['coverArt']['sources'] as List).isNotEmpty) {
                  playlistArtworkUrl ??= entity['coverArt']['sources'][0]['url']?.toString();
                }
                final rawName = entity['name']?.toString();
                if (rawName != null &&
                    rawName.isNotEmpty &&
                    rawName != 'Spotify – Web Player' &&
                    rawName != 'Spotify - Web Player') {
                  title = _unescapeHtml(rawName);
                }
                final rawDesc = entity['subtitle']?.toString() ?? entity['description']?.toString();
                if (rawDesc != null && rawDesc.isNotEmpty) {
                  description = _unescapeHtml(rawDesc);
                }

                final trackList = entity['trackList'];
                if (trackList is List) {
                  for (final item in trackList) {
                    if (item is Map) {
                      final tName = item['title']?.toString() ?? '';
                      final tArtist = (item['subtitle']?.toString() ?? '')
                          .replaceAll('\u00A0', ' ')
                          .replaceAll('\u202F', ' ')
                          .trim();
                      final tDur = (item['duration'] as num?)?.toInt();
                      final uriStr = item['uri']?.toString() ?? '';
                      String? trackWebUrl;
                      if (uriStr.startsWith('spotify:track:')) {
                        final trackId = uriStr.split(':').last;
                        trackWebUrl = 'https://open.spotify.com/track/$trackId';
                      }

                      String? previewUrl;
                      if (item['audioPreview'] is Map && item['audioPreview']['url'] != null) {
                        previewUrl = item['audioPreview']['url']?.toString();
                      } else if (item['previewUrl'] != null) {
                        previewUrl = item['previewUrl']?.toString();
                      } else if (item['preview_url'] != null) {
                        previewUrl = item['preview_url']?.toString();
                      }

                      String? artwork;
                      if (item['images'] is List && (item['images'] as List).isNotEmpty) {
                        artwork = item['images'][0]['url']?.toString();
                      } else if (item['album'] is Map && item['album']['images'] is List && (item['album']['images'] as List).isNotEmpty) {
                        artwork = item['album']['images'][0]['url']?.toString();
                      } else if (item['coverArt'] is Map && item['coverArt']['sources'] is List && (item['coverArt']['sources'] as List).isNotEmpty) {
                        artwork = item['coverArt']['sources'][0]['url']?.toString();
                      }

                      String? albumName;
                      if (item['album'] is Map && item['album']['name'] != null) {
                        albumName = item['album']['name']?.toString();
                      } else if (item['albumName'] != null) {
                        albumName = item['albumName']?.toString();
                      }

                      if (tName.isNotEmpty) {
                        entries.add(_RawTrackEntry(
                          title: _unescapeHtml(tName),
                          artist: _unescapeHtml(tArtist),
                          durationMs: tDur,
                          previewAudioUrl: previewUrl,
                          artworkUrl: artwork,
                          album: albumName != null ? _unescapeHtml(albumName) : null,
                          urlOrPath: trackWebUrl,
                        ));
                      }
                    }
                  }
                }

                // For playlists, query Spotify Pathfinder GraphQL with pagination
                // to fetch ALL tracks (bypassing the embed SSR 100-track truncation).
                if (entityType == 'playlist') {
                  String? accessToken;
                  final session = json['props']?['pageProps']?['state']?['settings']?['session'];
                  if (session is Map && session['accessToken'] != null) {
                    accessToken = session['accessToken']?.toString();
                  }
                  if (accessToken == null || accessToken.isEmpty) {
                    final tokenMatch = RegExp(r'"accessToken":"([^"]+)"').firstMatch(html);
                    if (tokenMatch != null) {
                      accessToken = tokenMatch.group(1);
                    }
                  }

                  if (accessToken != null && accessToken.isNotEmpty) {
                    final fullTracks = await _fetchSpotifyPathfinderTracks(entityId, accessToken);
                    if (fullTracks.isNotEmpty) {
                      entries.clear();
                      entries.addAll(fullTracks);
                    }
                  }
                }

                // Single Track Page support: if entity represents an individual track
                if (entries.isEmpty && (entityType == 'track' || entity['type'] == 'track')) {
                  final tName = entity['name']?.toString() ?? entity['title']?.toString() ?? '';
                  String tArtist = '';
                  if (entity['artists'] is List && (entity['artists'] as List).isNotEmpty) {
                    tArtist = (entity['artists'] as List)
                        .map((a) => a is Map ? a['name']?.toString() : a.toString())
                        .where((s) => s != null && s.isNotEmpty)
                        .join(', ');
                  } else if (entity['subtitle'] != null) {
                    tArtist = entity['subtitle'].toString();
                  }

                  final tDur = (entity['duration'] as num?)?.toInt() ??
                      (entity['duration_ms'] as num?)?.toInt();

                  String? artwork;
                  if (entity['visualIdentity'] is Map &&
                      entity['visualIdentity']['image'] is List) {
                    final imgs = entity['visualIdentity']['image'] as List;
                    if (imgs.isNotEmpty) {
                      final sorted = List<dynamic>.from(imgs)..sort((a, b) {
                        final ha = (a is Map ? (a['maxHeight'] as num?)?.toInt() : 0) ?? 0;
                        final hb = (b is Map ? (b['maxHeight'] as num?)?.toInt() : 0) ?? 0;
                        return hb.compareTo(ha);
                      });
                      artwork = sorted.first['url']?.toString();
                    }
                  }
                  if (artwork == null && entity['images'] is List && (entity['images'] as List).isNotEmpty) {
                    artwork = entity['images'][0]['url']?.toString();
                  } else if (artwork == null &&
                      entity['album'] is Map &&
                      entity['album']['images'] is List &&
                      (entity['album']['images'] as List).isNotEmpty) {
                    artwork = entity['album']['images'][0]['url']?.toString();
                  } else if (artwork == null &&
                      entity['coverArt'] is Map &&
                      entity['coverArt']['sources'] is List &&
                      (entity['coverArt']['sources'] as List).isNotEmpty) {
                    artwork = entity['coverArt']['sources'][0]['url']?.toString();
                  }
                  artwork ??= playlistArtworkUrl;

                  String? previewUrl;
                  if (entity['audioPreview'] is Map && entity['audioPreview']['url'] != null) {
                    previewUrl = entity['audioPreview']['url']?.toString();
                  } else if (entity['previewUrl'] != null) {
                    previewUrl = entity['previewUrl']?.toString();
                  }

                  String? albumName;
                  if (entity['album'] is Map && entity['album']['name'] != null) {
                    albumName = entity['album']['name']?.toString();
                  } else if (entity['albumName'] != null) {
                    albumName = entity['albumName']?.toString();
                  }

                  if (tName.isNotEmpty) {
                    entries.add(_RawTrackEntry(
                      title: _unescapeHtml(tName),
                      artist: _unescapeHtml(tArtist),
                      durationMs: tDur,
                      previewAudioUrl: previewUrl,
                      artworkUrl: artwork,
                      album: albumName != null ? _unescapeHtml(albumName) : null,
                      urlOrPath: resolvedUrl,
                    ));
                    title = _unescapeHtml(tName);
                    description = tArtist.isNotEmpty
                        ? 'Track by $tArtist'
                        : 'Imported from Spotify';
                    playlistArtworkUrl ??= artwork;
                  }
                }
              }
            } catch (_) {}
          }

          // Fallback: If __NEXT_DATA__ was not found, check HTML regex
          if (entries.isEmpty) {
            final trackMatches = RegExp(
              r'"title":"([^"]+)","subtitle":"([^"]+)"',
            ).allMatches(html);
            for (final m in trackMatches) {
              final tName = _unescapeHtml(m.group(1) ?? '').trim();
              final tArtist = _unescapeHtml(m.group(2) ?? '')
                  .replaceAll('\u00A0', ' ')
                  .replaceAll('\u202F', ' ')
                  .trim();
              if (tName.isNotEmpty && !entries.any((e) => e.title == tName && e.artist == tArtist)) {
                entries.add(_RawTrackEntry(title: tName, artist: tArtist));
              }
            }
          }
        }
      } catch (_) {}
    }

    // Fallback: If still empty, try fetching main URL directly (for mock client test compatibility)
    if (entries.isEmpty) {
      try {
        final mainRes = await _http.get(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
            'Pragma': 'no-cache',
          },
        ).timeout(const Duration(seconds: 8));
        if (mainRes.statusCode == 200) {
          final res = _parseSpotifyHtml(mainRes.body, uri, libraryTracks);
          if (res.totalParsed > 0) return res;
        }
      } catch (_) {}
    }

    return _matchEntries(
      entries: entries,
      title: title,
      description: description,
      libraryTracks: libraryTracks,
      sourceType: 'spotify',
      artworkUrl: playlistArtworkUrl,
    );
  }

  /// Fetches complete tracks for a Spotify playlist using Spotify's internal Pathfinder
  /// GraphQL API with pagination, ensuring playlists beyond 100 tracks (e.g. 121+ tracks)
  /// are imported completely and losslessly.
  Future<List<_RawTrackEntry>> _fetchSpotifyPathfinderTracks(
    String playlistId,
    String accessToken,
  ) async {
    final List<_RawTrackEntry> result = [];
    int offset = 0;
    const int limit = 100;
    int totalCount = 100;

    try {
      while (offset < totalCount && offset < 10000) {
        final pathfinderUrl = Uri.parse(
          'https://api-partner.spotify.com/pathfinder/v1/query',
        ).replace(
          queryParameters: {
            'operationName': 'fetchPlaylist',
            'variables': jsonEncode({
              'uri': 'spotify:playlist:$playlistId',
              'offset': offset,
              'limit': limit,
            }),
            'extensions': jsonEncode({
              'persistedQuery': {
                'version': 1,
                'sha256Hash':
                    '91d4c2bc3e0cd1bc672281c4f1f59f43ff55ba726ca04a45810d99bd091f3f0e',
              }
            }),
          },
        );

        final res = await _http.get(
          pathfinderUrl,
          headers: {
            'Authorization': 'Bearer $accessToken',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) {
          break;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final content = data['data']?['playlistV2']?['content'];
        if (content == null) break;

        final reportedTotal = content['totalCount'] as int?;
        if (reportedTotal != null) {
          totalCount = reportedTotal;
        }

        final items = content['items'] as List?;
        if (items == null || items.isEmpty) break;

        for (final item in items) {
          final itemData = item['itemV2']?['data'];
          if (itemData is Map) {
            final tName = itemData['name']?.toString() ?? '';
            final artistList = itemData['artists']?['items'] as List?;
            final tArtist = artistList
                    ?.map((a) => a['profile']?['name']?.toString())
                    .where((n) => n != null && n.isNotEmpty)
                    .join(', ') ??
                '';
            final durMs = (itemData['trackDuration']?['totalMilliseconds']
                    as num?)
                ?.toInt();
            final uriStr = itemData['uri']?.toString() ?? '';
            String? trackWebUrl;
            if (uriStr.startsWith('spotify:track:')) {
              final trackId = uriStr.split(':').last;
              trackWebUrl = 'https://open.spotify.com/track/$trackId';
            }

            final albumName =
                itemData['albumOfTrack']?['name']?.toString();
            final coverSources =
                itemData['albumOfTrack']?['coverArt']?['sources'] as List?;
            String? artwork;
            if (coverSources != null && coverSources.isNotEmpty) {
              final sorted = List<dynamic>.from(coverSources)
                ..sort((a, b) {
                  final ha = (a is Map
                          ? (a['height'] as num?)?.toInt()
                          : 0) ??
                      0;
                  final hb = (b is Map
                          ? (b['height'] as num?)?.toInt()
                          : 0) ??
                      0;
                  return hb.compareTo(ha);
                });
              artwork = sorted.first['url']?.toString();
            }

            if (tName.isNotEmpty) {
              result.add(
                _RawTrackEntry(
                  title: _unescapeHtml(tName),
                  artist: _unescapeHtml(tArtist),
                  durationMs: durMs,
                  artworkUrl: artwork,
                  album: albumName != null ? _unescapeHtml(albumName) : null,
                  urlOrPath: trackWebUrl,
                ),
              );
            }
          }
        }

        offset += limit;
      }
    } catch (e) {
      debugPrint('Spotify Pathfinder pagination note: $e');
    }

    return result;
  }

  Future<PlaylistImportResult> _importAppleMusic(
    String cleanUrl,
    Uri uri,
    List<Track> libraryTracks,
  ) async {
    String title = 'Apple Music Playlist';
    String description = 'Imported from Apple Music';
    String? playlistArtworkUrl;
    final List<_RawTrackEntry> entries = [];

    // 1. Query Apple Music oEmbed for exact clean playlist title & cover art
    try {
      final oembedUri = Uri.parse(
        'https://music.apple.com/api/oembed?url=${Uri.encodeComponent(cleanUrl)}&t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final oembedRes = await _http.get(
        oembedUri,
        headers: {
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 5));
      if (oembedRes.statusCode == 200) {
        final oembedJson = jsonDecode(oembedRes.body) as Map<String, dynamic>;
        if (oembedJson['title'] != null && oembedJson['title'].toString().isNotEmpty) {
          title = _unescapeHtml(oembedJson['title'].toString());
        }
        if (oembedJson['thumbnail_url'] != null) {
          playlistArtworkUrl = oembedJson['thumbnail_url']?.toString();
        }
      }
    } catch (_) {}

    // 2. Fetch Apple Music Page
    try {
      final response = await _http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Cache-Control': 'no-cache, no-store, must-revalidate, max-age=0',
          'Pragma': 'no-cache',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final html = response.body;

        // Check for JSON-LD scripts
        final jsonLdMatches = RegExp(
          r'<script[^>]*application/ld\+json[^>]*>(.*?)</script>',
          dotAll: true,
          caseSensitive: false,
        ).allMatches(html);

        for (final match in jsonLdMatches) {
          final jsonStr = match.group(1);
          if (jsonStr == null) continue;
          try {
            final decoded = jsonDecode(jsonStr);
            if (decoded is Map<String, dynamic>) {
              if (decoded['name'] != null && (title == 'Apple Music Playlist' || title.isEmpty)) {
                title = _unescapeHtml(decoded['name'].toString());
              }
              if (decoded['description'] != null) {
                description = _unescapeHtml(decoded['description'].toString());
              }
              final trackList = decoded['track'] ?? decoded['tracks'];
              if (trackList is List) {
                for (final t in trackList) {
                  if (t is Map) {
                    final tName = t['name']?.toString() ?? '';
                    String tArtist = '';
                    final byArtist = t['byArtist'];
                    if (byArtist is List && byArtist.isNotEmpty) {
                      tArtist = byArtist.first['name']?.toString() ?? '';
                    } else if (byArtist is Map) {
                      tArtist = byArtist['name']?.toString() ?? '';
                    } else if (t['author'] is Map) {
                      tArtist = t['author']['name']?.toString() ?? '';
                    }

                    int? durMs;
                    if (t['duration'] != null) {
                      durMs = _parseIsoDuration(t['duration'].toString());
                    }

                    String? previewUrl;
                    if (t['audio'] is Map && t['audio']['url'] != null) {
                      previewUrl = t['audio']['url']?.toString();
                    } else if (t['audio'] is String) {
                      previewUrl = t['audio']?.toString();
                    }

                    String? artwork;
                    if (t['image'] is String) {
                      artwork = t['image']?.toString();
                    } else if (t['image'] is Map && t['image']['url'] != null) {
                      artwork = t['image']['url']?.toString();
                    }

                    if (tName.isNotEmpty) {
                      entries.add(_RawTrackEntry(
                        title: _unescapeHtml(tName),
                        artist: _unescapeHtml(tArtist),
                        durationMs: durMs,
                        previewAudioUrl: previewUrl,
                        artworkUrl: artwork,
                        urlOrPath: t['url']?.toString(),
                      ));
                    }
                  }
                }
              }

              // Single Song support on Apple Music
              if (entries.isEmpty) {
                final type = decoded['@type']?.toString();
                if (type == 'MusicRecording' || (trackList == null && decoded['name'] != null)) {
                  final tName = decoded['name']?.toString() ?? '';
                  String tArtist = '';
                  final byArtist = decoded['byArtist'];
                  if (byArtist is List && byArtist.isNotEmpty) {
                    tArtist = byArtist.first['name']?.toString() ?? '';
                  } else if (byArtist is Map) {
                    tArtist = byArtist['name']?.toString() ?? '';
                  } else if (decoded['author'] is Map) {
                    tArtist = decoded['author']['name']?.toString() ?? '';
                  }

                  int? durMs;
                  if (decoded['duration'] != null) {
                    durMs = _parseIsoDuration(decoded['duration'].toString());
                  }

                  String? artwork;
                  if (decoded['image'] is String) {
                    artwork = decoded['image']?.toString();
                  } else if (decoded['image'] is Map && decoded['image']['url'] != null) {
                    artwork = decoded['image']['url']?.toString();
                  }

                  if (tName.isNotEmpty) {
                    entries.add(_RawTrackEntry(
                      title: _unescapeHtml(tName),
                      artist: _unescapeHtml(tArtist),
                      durationMs: durMs,
                      artworkUrl: artwork,
                      urlOrPath: cleanUrl,
                    ));
                    title = _unescapeHtml(tName);
                    description = tArtist.isNotEmpty
                        ? 'Song by $tArtist'
                        : 'Imported from Apple Music';
                    playlistArtworkUrl ??= artwork;
                  }
                }
              }
            }
          } catch (_) {}
        }

      // If user shared an individual track link with ?i=<songId>, isolate that track
      final songIdParam = uri.queryParameters['i'];
      if (songIdParam != null && songIdParam.isNotEmpty && entries.length > 1) {
        final target = entries.firstWhere(
          (e) => e.urlOrPath != null && e.urlOrPath!.contains('i=$songIdParam'),
          orElse: () => entries.first,
        );
        entries
          ..clear()
          ..add(target);
        title = target.title;
        description = target.artist.isNotEmpty ? 'Song by ${target.artist}' : 'Imported from Apple Music';
      }

        // Clean up title
        title = title
            .replaceAll('\u200E', '') // remove left-to-right mark
            .replaceAll(' - Playlist - Apple Music', '')
            .replaceAll(' on Apple Music', '')
            .trim();
      }
    } catch (_) {}

    // Fallback: If empty, try legacy HTML parser
    if (entries.isEmpty) {
      try {
        final fallbackRes = await _http.get(uri).timeout(const Duration(seconds: 8));
        if (fallbackRes.statusCode == 200) {
          final res = _parseAppleMusicHtml(fallbackRes.body, uri, libraryTracks);
          if (res.totalParsed > 0) return res;
        }
      } catch (_) {}
    }

    return _matchEntries(
      entries: entries,
      title: title,
      description: description,
      libraryTracks: libraryTracks,
      sourceType: 'apple',
      artworkUrl: playlistArtworkUrl,
    );
  }

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

  /// Extracts the playlist ID (e.g. PL..., RD..., etc.) from a YouTube or YouTube Music link.
  static String? extractYouTubePlaylistId(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final list = uri.queryParameters['list'];
      if (list != null && list.isNotEmpty) {
        return list;
      }
    }
    final regExp = RegExp(r'[?&]list=([a-zA-Z0-9_-]+)', caseSensitive: false);
    return regExp.firstMatch(url)?.group(1);
  }

  /// Cleans YouTube video titles and channel authors into neat music title and artist pairs.
  ///
  /// Strips fluff like "(Official Music Video)", "[4K Remaster]", "(Audio)",
  /// decomposes "Artist - Title" strings, and removes "- Topic" or "VEVO" channel artifacts.
  static ({String title, String artist}) _cleanYouTubeTrackInfo(
    String rawTitle,
    String rawAuthor,
  ) {
    // 1. Clean author / channel name
    var author = rawAuthor.trim();
    if (author.endsWith(' - Topic')) {
      author = author.substring(0, author.length - ' - Topic'.length).trim();
    }
    if (author.toLowerCase().endsWith('vevo')) {
      author = author.substring(0, author.length - 4).trim();
    }

    // 2. Strip standard video fluff brackets / parentheses
    final fluffRegex = RegExp(
      r'[\(\[\{]\s*(?:official\s+)?(?:music\s+)?(?:video|audio|lyric|lyrics|visualizer|hd|4k|remaster(?:ed)?|explicit|clean|live|studio|clip|performance).*?[\)\]\}]',
      caseSensitive: false,
    );
    var cleanedTitle = rawTitle.replaceAll(fluffRegex, '').trim();

    // Strip generic trailing quality/media tags
    cleanedTitle = cleanedTitle
        .replaceAll(
          RegExp(
            r'[\(\[]\s*(?:4k|hd|hq|audio|video|remastered)\s*[\)\]]',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    // 3. Check for "Artist - Title" separator
    final separatorRegex = RegExp(r'\s+[-–—:]\s+');
    final match = separatorRegex.firstMatch(cleanedTitle);

    if (match != null) {
      final part1 = cleanedTitle.substring(0, match.start).trim();
      final part2 = cleanedTitle.substring(match.end).trim();

      if (part1.isNotEmpty && part2.isNotEmpty) {
        final unquotedTitle =
            part2.replaceAll(RegExp(r'^["' "'" r']|["' "'" r']$'), '').trim();
        return (title: unquotedTitle, artist: part1);
      }
    }

    // If no hyphen separator, use cleanedTitle and author
    return (
      title: cleanedTitle.isNotEmpty ? cleanedTitle : rawTitle,
      artist: author,
    );
  }

  Future<PlaylistImportResult> _importSingleYouTubeVideo(
    String videoId,
    List<Track> libraryTracks,
  ) async {
    String rawTitle = '';
    String rawAuthor = '';
    int? durationMs;
    String? artworkUrl;

    // 1. Try YoutubeExplode
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(videoId);
      rawTitle = video.title;
      rawAuthor = video.author;
      durationMs = video.duration?.inMilliseconds;
      artworkUrl = video.thumbnails.highResUrl;
    } catch (e) {
      debugPrint('YoutubeExplode video fetch note ($e), trying oEmbed...');
    } finally {
      yt.close();
    }

    // 2. Fallback to YouTube oEmbed API if YoutubeExplode was unavailable
    if (rawTitle.isEmpty) {
      try {
        final oembedUri = Uri.parse(
          'https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json',
        );
        final res =
            await _http.get(oembedUri).timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          if (json['title'] != null) {
            rawTitle = json['title'].toString();
          }
          if (json['author_name'] != null) {
            rawAuthor = json['author_name'].toString();
          }
          if (json['thumbnail_url'] != null) {
            artworkUrl = json['thumbnail_url'].toString();
          }
        }
      } catch (e) {
        debugPrint('YouTube oEmbed fallback note: $e');
      }
    }

    // 3. Fallback to InnerTube Android client player API (never blocked by web PO-tokens)
    if (rawTitle.isEmpty) {
      try {
        final innerTubeRes = await _http.post(
          Uri.parse('https://music.youtube.com/youtubei/v1/player'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'com.google.android.youtube/19.09.37 (Linux; U; Android 14; en_US)',
          },
          body: jsonEncode({
            'videoId': videoId,
            'context': {
              'client': {
                'clientName': 'ANDROID',
                'clientVersion': '19.09.37',
                'androidSdkVersion': 34,
                'hl': 'en',
                'gl': 'US',
              }
            }
          }),
        ).timeout(const Duration(seconds: 6));
        if (innerTubeRes.statusCode == 200) {
          final data = jsonDecode(innerTubeRes.body) as Map<String, dynamic>;
          final vd = data['videoDetails'] as Map<String, dynamic>?;
          if (vd != null) {
            rawTitle = vd['title']?.toString() ?? '';
            rawAuthor = vd['author']?.toString() ?? '';
            final lengthSec = int.tryParse(vd['lengthSeconds']?.toString() ?? '');
            if (lengthSec != null) durationMs = lengthSec * 1000;
            final thumbs = vd['thumbnail']?['thumbnails'] as List?;
            if (thumbs != null && thumbs.isNotEmpty) {
              artworkUrl = thumbs.last['url']?.toString();
            }
          }
        }
      } catch (e) {
        debugPrint('YouTube InnerTube fallback note: $e');
      }
    }

    if (rawTitle.isEmpty) {
      throw const FormatException(
        'Could not load YouTube track. Please ensure the link is public and valid.',
      );
    }

    final cleaned = _cleanYouTubeTrackInfo(rawTitle, rawAuthor);
    final entries = [
      _RawTrackEntry(
        title: cleaned.title,
        artist: cleaned.artist,
        durationMs: durationMs,
        artworkUrl: artworkUrl,
        urlOrPath: 'https://www.youtube.com/watch?v=$videoId',
      ),
    ];

    return _matchEntries(
      entries: entries,
      title: cleaned.title,
      description: cleaned.artist.isNotEmpty
          ? 'YouTube track by ${cleaned.artist}'
          : 'Imported YouTube track',
      libraryTracks: libraryTracks,
      sourceType: 'youtube',
    );
  }

  Future<PlaylistImportResult> _importYouTube(
    String cleanUrl,
    Uri uri,
    List<Track> libraryTracks,
  ) async {
    final listId = extractYouTubePlaylistId(cleanUrl);
    final videoId = extractYouTubeVideoId(cleanUrl);

    if (listId == null && videoId == null) {
      throw const FormatException(
        'Could not find YouTube playlist or track ID in link.',
      );
    }

    // 1. If it is a dynamic YouTube Music radio/mix (RD... or UL...) or single track link,
    // import the song directly.
    if (videoId != null &&
        (listId == null || listId.startsWith('RD') || listId.startsWith('UL'))) {
      return _importSingleYouTubeVideo(videoId, libraryTracks);
    }

    // 2. If a playlist ID is present, fetch the full playlist.
    if (listId != null) {
      String title = 'YouTube Playlist';
      String description = 'Imported from YouTube';
      String? playlistArtworkUrl;
      final List<_RawTrackEntry> entries = [];

      final yt = YoutubeExplode();
      try {
        final playlist = await yt.playlists.get(listId);
        title = playlist.title;
        description = playlist.description;
        playlistArtworkUrl = playlist.thumbnails.highResUrl;

        await for (final video in yt.playlists.getVideos(listId).take(5000)) {
          final cleaned = _cleanYouTubeTrackInfo(video.title, video.author);
          entries.add(_RawTrackEntry(
            title: cleaned.title,
            artist: cleaned.artist,
            durationMs: video.duration?.inMilliseconds,
            artworkUrl: video.thumbnails.highResUrl,
            urlOrPath: 'https://www.youtube.com/watch?v=${video.id.value}',
          ));
        }
      } catch (e) {
        debugPrint('YouTube playlist import note: $e');
        // If playlist enumeration failed (e.g. unlisted/private or special mix)
        // but a videoId was provided, fall back to importing the single video!
        if (videoId != null) {
          return _importSingleYouTubeVideo(videoId, libraryTracks);
        }
        rethrow;
      } finally {
        yt.close();
      }

      if (entries.isEmpty && videoId != null) {
        return _importSingleYouTubeVideo(videoId, libraryTracks);
      }

      return _matchEntries(
        entries: entries,
        title: title,
        description: description,
        libraryTracks: libraryTracks,
        sourceType: 'youtube',
        artworkUrl: playlistArtworkUrl,
      );
    }

    // 3. Otherwise import single video.
    return _importSingleYouTubeVideo(videoId!, libraryTracks);
  }

  static int? _parseIsoDuration(String? iso) {
    if (iso == null || !iso.startsWith('PT')) return null;
    final match = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?').firstMatch(iso);
    if (match == null) return null;
    final h = int.tryParse(match.group(1) ?? '0') ?? 0;
    final m = int.tryParse(match.group(2) ?? '0') ?? 0;
    final s = int.tryParse(match.group(3) ?? '0') ?? 0;
    return (h * 3600 + m * 60 + s) * 1000;
  }

  PlaylistImportResult _parseSpotifyHtml(
    String html,
    Uri uri,
    List<Track> libraryTracks,
  ) {
    // 1. Extract title from OpenGraph or Title tag
    String title = 'Spotify Playlist';
    final ogTitleMatch = RegExp(r'<meta\s+property=["' "'" r']og:title["' "'" r']\s+content=["' "'" r'](.*?)["' "'" r']', caseSensitive: false).firstMatch(html);
    if (ogTitleMatch != null && ogTitleMatch.group(1) != null) {
      title = _unescapeHtml(ogTitleMatch.group(1)!);
    } else {
      final titleTag = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(html);
      if (titleTag != null && titleTag.group(1) != null) {
        title = _unescapeHtml(titleTag.group(1)!).replaceAll(' | Spotify', '').trim();
      }
    }

    // 2. Extract description
    String description = '';
    final ogDescMatch = RegExp(r'<meta\s+property=["' "'" r']og:description["' "'" r']\s+content=["' "'" r'](.*?)["' "'" r']', caseSensitive: false).firstMatch(html);
    if (ogDescMatch != null && ogDescMatch.group(1) != null) {
      description = _unescapeHtml(ogDescMatch.group(1)!);
    }

    final List<_RawTrackEntry> entries = [];

    // 3. Try parsing schema.org JSON-LD
    final jsonLdMatches = RegExp(r'<script\s+type=["' "'" r']application/ld\+json["' "'" r']>(.*?)</script>', dotAll: true, caseSensitive: false).allMatches(html);
    for (final match in jsonLdMatches) {
      final jsonStr = match.group(1);
      if (jsonStr == null) continue;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          if (decoded['name'] != null && title == 'Spotify Playlist') {
            title = decoded['name'].toString();
          }
          final trackList = decoded['track'] ?? decoded['tracks'];
          if (trackList is List) {
            for (final t in trackList) {
              if (t is Map) {
                final trackName = t['name']?.toString() ?? '';
                String artistName = '';
                final byArtist = t['byArtist'];
                if (byArtist is List && byArtist.isNotEmpty) {
                  artistName = byArtist.first['name']?.toString() ?? '';
                } else if (byArtist is Map) {
                  artistName = byArtist['name']?.toString() ?? '';
                }
                if (trackName.isNotEmpty) {
                  entries.add(_RawTrackEntry(title: trackName, artist: artistName));
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 4. Fallback: Parse Spotify metadata music:song links or track names
    if (entries.isEmpty) {
      final trackMatches = RegExp(r'data-testid=["' "'" r']tracklist-row["' "'" r'].*?<div dir=["' "'" r']auto["' "'" r']>(.*?)</div>', dotAll: true).allMatches(html);
      for (final m in trackMatches) {
        final name = _unescapeHtml(m.group(1) ?? '').replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (name.isNotEmpty) {
          entries.add(_RawTrackEntry(title: name, artist: ''));
        }
      }
    }

    return _matchEntries(
      entries: entries,
      title: title,
      description: description.isNotEmpty ? description : 'Imported from Spotify',
      libraryTracks: libraryTracks,
      sourceType: 'spotify',
    );
  }

  PlaylistImportResult _parseAppleMusicHtml(
    String html,
    Uri uri,
    List<Track> libraryTracks,
  ) {
    String title = 'Apple Music Playlist';
    final ogTitleMatch = RegExp(r'<meta\s+property=["' "'" r']og:title["' "'" r']\s+content=["' "'" r'](.*?)["' "'" r']', caseSensitive: false).firstMatch(html);
    if (ogTitleMatch != null && ogTitleMatch.group(1) != null) {
      title = _unescapeHtml(ogTitleMatch.group(1)!).replaceAll(' on Apple Music', '').trim();
    }

    String description = '';
    final ogDescMatch = RegExp(r'<meta\s+property=["' "'" r']og:description["' "'" r']\s+content=["' "'" r'](.*?)["' "'" r']', caseSensitive: false).firstMatch(html);
    if (ogDescMatch != null && ogDescMatch.group(1) != null) {
      description = _unescapeHtml(ogDescMatch.group(1)!);
    }

    final List<_RawTrackEntry> entries = [];

    // Parse JSON-LD or meta tags
    final jsonLdMatches = RegExp(r'<script\s+type=["' "'" r']application/ld\+json["' "'" r']>(.*?)</script>', dotAll: true, caseSensitive: false).allMatches(html);
    for (final match in jsonLdMatches) {
      final jsonStr = match.group(1);
      if (jsonStr == null) continue;
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          final trackList = decoded['track'] ?? decoded['tracks'];
          if (trackList is List) {
            for (final t in trackList) {
              if (t is Map) {
                final trackName = t['name']?.toString() ?? '';
                String artistName = '';
                final byArtist = t['byArtist'];
                if (byArtist is List && byArtist.isNotEmpty) {
                  artistName = byArtist.first['name']?.toString() ?? '';
                } else if (byArtist is Map) {
                  artistName = byArtist['name']?.toString() ?? '';
                }
                if (trackName.isNotEmpty) {
                  entries.add(_RawTrackEntry(title: trackName, artist: artistName));
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    return _matchEntries(
      entries: entries,
      title: title,
      description: description.isNotEmpty ? description : 'Imported from Apple Music',
      libraryTracks: libraryTracks,
      sourceType: 'apple',
    );
  }

  PlaylistImportResult _matchEntries({
    required List<_RawTrackEntry> entries,
    required String title,
    required String description,
    required List<Track> libraryTracks,
    required String sourceType,
    String? artworkUrl,
  }) {
    final List<Track> matched = [];
    final List<String> unmatched = [];
    final List<MissingTrackItem> missingTrackItems = [];
    final Set<String> matchedIds = {};

    final effectiveArtwork = artworkUrl ??
        entries
            .firstWhere(
              (e) => e.artworkUrl != null && e.artworkUrl!.isNotEmpty,
              orElse: () => const _RawTrackEntry(title: '', artist: ''),
            )
            .artworkUrl;

    for (final entry in entries) {
      Track? best;

      // First check path/url if present
      if (entry.urlOrPath != null && entry.urlOrPath!.isNotEmpty) {
        for (final t in libraryTracks) {
          if (t.streamUrl == entry.urlOrPath ||
              t.remotePathOrId == entry.urlOrPath ||
              t.streamUrl.endsWith(entry.urlOrPath!)) {
            best = t;
            break;
          }
        }
      }

      // Otherwise match by title + artist
      best ??= findBestMatch(entry.title, entry.artist, libraryTracks);

      if (best != null) {
        if (!matchedIds.contains(best.id)) {
          matched.add(best);
          matchedIds.add(best.id);
        }
      } else {
        final display = entry.artist.isNotEmpty
            ? '${entry.artist} - ${entry.title}'
            : entry.title;
        if (!unmatched.contains(display)) {
          unmatched.add(display);
          missingTrackItems.add(
            MissingTrackItem(
              title: entry.title,
              artist: entry.artist,
              expectedDurationMs: entry.durationMs,
              preferredArtworkUrl: entry.artworkUrl,
              previewAudioUrl: entry.previewAudioUrl,
              album: entry.album,
              sourceUrl: entry.urlOrPath,
            ),
          );
        }
      }
    }

    return PlaylistImportResult(
      title: title,
      description: description,
      matchedTracks: matched,
      unmatchedTrackNames: unmatched,
      missingTracks: missingTrackItems,
      totalParsed: entries.length,
      sourceType: sourceType,
      artworkUrl: effectiveArtwork,
    );
  }

  static String _unescapeHtml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}

class _RawTrackEntry {
  const _RawTrackEntry({
    required this.title,
    required this.artist,
    this.urlOrPath,
    this.durationMs,
    this.previewAudioUrl,
    this.artworkUrl,
    this.album,
  });

  final String title;
  final String artist;
  final String? urlOrPath;
  final int? durationMs;
  final String? previewAudioUrl;
  final String? artworkUrl;
  final String? album;
}

class HttpException implements Exception {
  final String message;
  const HttpException(this.message);
  @override
  String toString() => message;
}
