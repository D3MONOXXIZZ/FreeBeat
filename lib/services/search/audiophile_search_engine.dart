import '../../core/models/playlist.dart';
import '../../core/models/track.dart';
import '../metadata/artist_helper.dart';

enum SearchFilterType {
  all('All'),
  hiRes('Hi-Res 24-Bit'),
  offline('Offline'),
  flac('FLAC'),
  wma('WMA'),
  m4a('M4A / AAC'),
  wav('WAV'),
  mp3('MP3'),
  artists('Artists'),
  albums('Albums'),
  playlists('Playlists');

  const SearchFilterType(this.label);
  final String label;
}

class SearchResultGroup {
  const SearchResultGroup({
    this.topMatch,
    this.tracks = const [],
    this.artists = const [],
    this.albums = const {},
    this.playlists = const [],
  });

  final Track? topMatch;
  final List<Track> tracks;
  final List<String> artists;
  final Map<String, List<Track>> albums;
  final List<Playlist> playlists;

  int get totalCount =>
      tracks.length +
      artists.length +
      albums.keys.length +
      playlists.length;

  bool get isEmpty => totalCount == 0;
  bool get isNotEmpty => !isEmpty;
}

/// Unified Audiophile Fuzzy Search Engine.
/// Searches across all connected clouds and local storage with deep format,
/// codec, and Hi-Fi bit-depth filtering.
class AudiophileSearchEngine {
  static SearchResultGroup search({
    required String query,
    required List<Track> allTracks,
    required List<Playlist> allPlaylists,
    SearchFilterType filter = SearchFilterType.all,
  }) {
    final cleanQuery = query.trim().toLowerCase();

    // 1. If query is empty and filter is 'all', return empty group (showing history/discover)
    if (cleanQuery.isEmpty && filter == SearchFilterType.all) {
      return const SearchResultGroup();
    }

    // 2. Filter tracks by query and active audiophile filter
    final matchedTracks = <Track>[];
    for (final track in allTracks) {
      if (!_passesFilter(track, filter)) continue;

      if (cleanQuery.isEmpty) {
        matchedTracks.add(track);
        continue;
      }

      final titleMatch = track.title.toLowerCase().contains(cleanQuery);
      final artistMatch = track.artist.toLowerCase().contains(cleanQuery) ||
          ArtistHelper.trackBelongsToArtist(track, cleanQuery);
      final albumMatch = track.album.toLowerCase().contains(cleanQuery);
      final codecMatch = track.codec.toLowerCase().contains(cleanQuery) ||
          track.streamUrl.toLowerCase().contains(cleanQuery);
      final hiFiMatch = cleanQuery.contains('hires') || cleanQuery.contains('hi-res')
          ? track.isHiRes
          : false;

      if (titleMatch || artistMatch || albumMatch || codecMatch || hiFiMatch) {
        matchedTracks.add(track);
      }
    }

    // 3. Extract matching artists (unified individual profiles)
    final matchedArtists = <String>{};
    if (filter == SearchFilterType.all || filter == SearchFilterType.artists) {
      for (final track in allTracks) {
        final artists = ArtistHelper.extractArtists(track.artist, track.title);
        for (final a in artists) {
          if (cleanQuery.isEmpty && filter == SearchFilterType.artists) {
            matchedArtists.add(a);
          } else if (cleanQuery.isNotEmpty && a.toLowerCase().contains(cleanQuery)) {
            matchedArtists.add(a);
          }
        }
      }
    }

    // 4. Extract matching albums
    final matchedAlbums = <String, List<Track>>{};
    if (filter == SearchFilterType.all || filter == SearchFilterType.albums) {
      for (final track in allTracks) {
        if (track.album.isEmpty || track.album == 'Unknown Album') continue;
        final passes = _passesFilter(track, filter);
        if (!passes) continue;

        if (cleanQuery.isEmpty && filter == SearchFilterType.albums) {
          matchedAlbums.putIfAbsent(track.album, () => []).add(track);
        } else if (cleanQuery.isNotEmpty && track.album.toLowerCase().contains(cleanQuery)) {
          matchedAlbums.putIfAbsent(track.album, () => []).add(track);
        }
      }
    }

    // 5. Extract matching playlists
    final matchedPlaylists = <Playlist>[];
    if (filter == SearchFilterType.all || filter == SearchFilterType.playlists) {
      for (final pl in allPlaylists) {
        if (cleanQuery.isEmpty && filter == SearchFilterType.playlists) {
          matchedPlaylists.add(pl);
        } else if (cleanQuery.isNotEmpty && pl.title.toLowerCase().contains(cleanQuery)) {
          matchedPlaylists.add(pl);
        }
      }
    }

    // 6. Identify Top Match
    Track? topMatch;
    if (matchedTracks.isNotEmpty && cleanQuery.isNotEmpty) {
      // Prioritize exact title match or startsWith
      final exactTitle = matchedTracks.where(
        (t) => t.title.toLowerCase() == cleanQuery,
      );
      if (exactTitle.isNotEmpty) {
        topMatch = exactTitle.first;
      } else {
        final startsWithTitle = matchedTracks.where(
          (t) => t.title.toLowerCase().startsWith(cleanQuery),
        );
        if (startsWithTitle.isNotEmpty) {
          topMatch = startsWithTitle.first;
        } else {
          topMatch = matchedTracks.first;
        }
      }
    }

    // Filter category overrides
    List<Track> finalTracks = matchedTracks;
    List<String> finalArtists = matchedArtists.toList()..sort();
    Map<String, List<Track>> finalAlbums = matchedAlbums;
    List<Playlist> finalPlaylists = matchedPlaylists;

    if (filter == SearchFilterType.artists) {
      finalTracks = [];
      finalAlbums = {};
      finalPlaylists = [];
    } else if (filter == SearchFilterType.albums) {
      finalTracks = [];
      finalArtists = [];
      finalPlaylists = [];
    } else if (filter == SearchFilterType.playlists) {
      finalTracks = [];
      finalArtists = [];
      finalAlbums = {};
    }

    return SearchResultGroup(
      topMatch: filter == SearchFilterType.all ? topMatch : null,
      tracks: finalTracks,
      artists: finalArtists,
      albums: finalAlbums,
      playlists: finalPlaylists,
    );
  }

  static bool _passesFilter(Track track, SearchFilterType filter) {
    switch (filter) {
      case SearchFilterType.all:
      case SearchFilterType.artists:
      case SearchFilterType.albums:
      case SearchFilterType.playlists:
        return true;
      case SearchFilterType.hiRes:
        return track.isHiRes;
      case SearchFilterType.offline:
        return track.isPinnedOffline;
      case SearchFilterType.flac:
        return track.codec.toLowerCase() == 'flac' ||
            track.streamUrl.toLowerCase().contains('.flac');
      case SearchFilterType.wma:
        return track.codec.toLowerCase() == 'wma' ||
            track.streamUrl.toLowerCase().contains('.wma');
      case SearchFilterType.m4a:
        return track.codec.toLowerCase() == 'm4a' ||
            track.codec.toLowerCase() == 'aac' ||
            track.streamUrl.toLowerCase().contains('.m4a') ||
            track.streamUrl.toLowerCase().contains('.aac');
      case SearchFilterType.wav:
        return track.codec.toLowerCase() == 'wav' ||
            track.streamUrl.toLowerCase().contains('.wav');
      case SearchFilterType.mp3:
        return track.codec.toLowerCase() == 'mp3' ||
            track.streamUrl.toLowerCase().contains('.mp3');
    }
  }
}
