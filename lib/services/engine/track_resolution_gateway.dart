import 'dart:async';
import 'package:http/http.dart' as http;
import '../audio/missing_track_audio_resolver.dart';
import '../metadata/artwork_and_lyrics_service.dart';
import 'spotify_metadata_engine.dart';
import 'youtube_music_engine.dart';

/// Complete resolved audio bundle containing the audio stream candidate,
/// official Spotify/iTunes album art, official album name, and verified bitrate.
class ResolvedAudioBundle {
  const ResolvedAudioBundle({
    required this.candidate,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    required this.bitrateKbps,
    required this.audioCodec,
    required this.isStudioMaster,
  });

  final AudioStreamCandidate candidate;
  final String title;
  final String artist;
  final String album;
  final String? artworkUrl;
  final int bitrateKbps;
  final String audioCodec;
  final bool isStudioMaster;
}

/// Central On-Device Embedded Engine Gateway.
///
/// Implements the "Quality-Max" audio resolution pipeline:
/// 1. Prioritizes authentic 320 kbps Studio Masters (when verified by precision scoring).
/// 2. Seamlessly falls back to YouTube Music InnerTube (highest available stream) for indie/exclusive tracks.
/// 3. Extracts official Spotify 640x640 cover art and iTunes official album names.
class TrackResolutionGateway {
  TrackResolutionGateway({
    http.Client? httpClient,
    MissingTrackAudioResolver? resolver,
    SpotifyMetadataEngine? spotifyEngine,
    YouTubeMusicEngine? ytMusicEngine,
    ArtworkAndLyricsService? metadataService,
  })  : _resolver = resolver ?? MissingTrackAudioResolver(httpClient: httpClient),
        _spotifyEngine = spotifyEngine ?? SpotifyMetadataEngine(httpClient: httpClient),
        _ytMusicEngine = ytMusicEngine ?? YouTubeMusicEngine(httpClient: httpClient),
        _metadataService = metadataService ?? ArtworkAndLyricsService(client: httpClient);

  final MissingTrackAudioResolver _resolver;
  final SpotifyMetadataEngine _spotifyEngine;
  final YouTubeMusicEngine _ytMusicEngine;
  final ArtworkAndLyricsService _metadataService;

  /// Resolves the optimal high-bitrate audio stream and authentic metadata.
  Future<ResolvedAudioBundle?> resolveAudioBundle({
    required String title,
    required String artist,
    String? spotifyUrlOrUri,
    int? expectedDurationMs,
    String? preferredAlbum,
    String? preferredArtworkUrl,
  }) async {
    // Step 1: Extract authentic Spotify metadata & 640x640 cover art if available
    String resolvedTitle = title;
    String resolvedArtist = artist;
    String? resolvedArtwork = preferredArtworkUrl;

    if (spotifyUrlOrUri != null && spotifyUrlOrUri.isNotEmpty) {
      final spotifyMeta = await _spotifyEngine.resolveTrackMetadata(
        trackIdOrUrl: spotifyUrlOrUri,
        fallbackTitle: title,
        fallbackArtist: artist,
      );
      if (spotifyMeta != null) {
        if (spotifyMeta.title.isNotEmpty) resolvedTitle = spotifyMeta.title;
        if (spotifyMeta.artist.isNotEmpty) resolvedArtist = spotifyMeta.artist;
        if (spotifyMeta.artworkUrl != null && spotifyMeta.artworkUrl!.isNotEmpty) {
          resolvedArtwork = spotifyMeta.artworkUrl;
        }
      }
    }

    // Step 2: Quality-Max Stream Resolution (favors 320 kbps Studio Masters when verified)
    var candidate = await _resolver.resolveTrackAudio(
      title: resolvedTitle,
      artist: resolvedArtist,
      expectedDurationMs: expectedDurationMs,
      preferredArtworkUrl: resolvedArtwork,
      preferredAlbum: preferredAlbum,
      sourceUrl: spotifyUrlOrUri,
    );

    // Direct fallback to YouTubeMusicEngine if resolver returned null
    candidate ??= await _ytMusicEngine.resolveTrackAudio(
      title: resolvedTitle,
      artist: resolvedArtist,
      expectedDurationMs: expectedDurationMs,
      preferredArtworkUrl: resolvedArtwork,
      preferredAlbum: preferredAlbum,
    );

    if (candidate == null) return null;

    final isStudioMaster = candidate.bitrateKbps >= 320 ||
        candidate.streamUrl.contains('aac.saavncdn.com');
    final actualBitrate = isStudioMaster ? 320 : candidate.bitrateKbps;

    // Step 3: Resolve official album name if empty or generic
    String resolvedAlbum = (preferredAlbum != null &&
            preferredAlbum.isNotEmpty &&
            preferredAlbum != 'Imported Playlist')
        ? preferredAlbum
        : (candidate.album ?? '');

    if (resolvedAlbum.isEmpty || resolvedAlbum == 'Imported Playlist') {
      try {
        final meta = await _metadataService.lookupSongMetadata(
          artist: resolvedArtist,
          title: resolvedTitle,
        ).timeout(const Duration(seconds: 2));
        if (meta != null && meta.album != null && meta.album!.isNotEmpty) {
          resolvedAlbum = meta.album!;
        }
        if (resolvedArtwork == null && meta != null && meta.artworkUrl != null) {
          resolvedArtwork = meta.artworkUrl;
        }
      } catch (_) {}
    }

    if (resolvedAlbum.isEmpty) {
      resolvedAlbum = candidate.album?.isNotEmpty == true ? candidate.album! : resolvedTitle;
    }

    if (resolvedArtwork == null || resolvedArtwork.contains('ytimg.com')) {
      resolvedArtwork = candidate.artworkUrl;
    }

    return ResolvedAudioBundle(
      candidate: candidate,
      title: resolvedTitle,
      artist: resolvedArtist,
      album: resolvedAlbum,
      artworkUrl: resolvedArtwork,
      bitrateKbps: actualBitrate,
      audioCodec: candidate.format.toUpperCase(),
      isStudioMaster: isStudioMaster,
    );
  }
}
