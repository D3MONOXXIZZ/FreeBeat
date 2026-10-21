import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../metadata/artwork_and_lyrics_service.dart';
import '../metadata/artwork_palette_extractor.dart';
import 'missing_track_audio_resolver.dart';

/// Encapsulates a downloaded and tagged scratch audio file ready for cloud upload.
class PreparedTrackAudio {
  const PreparedTrackAudio({
    required this.file,
    required this.filename,
    required this.title,
    required this.artist,
    required this.album,
    required this.format,
    required this.durationMs,
    required this.sizeBytes,
    required this.bitrateKbps,
    this.artworkUrl,
    this.dominantColorValue = 0xFF1E293B,
    this.syncedLyrics = const [],
  });

  final File file;
  final String filename;
  final String title;
  final String artist;
  final String album;
  final String format; // e.g. 'm4a', 'opus', 'mp3'
  final int durationMs;
  final int sizeBytes;
  final int bitrateKbps;
  final String? artworkUrl;
  final int dominantColorValue;
  final List<LyricLine> syncedLyrics;

  /// Deletes the local scratch audio file immediately after cloud upload
  /// ensuring 0 local storage cache bloat.
  Future<void> purge() async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to purge scratch file ${file.path}: $e');
    }
  }
}

/// Service that downloads candidate audio streams into temporary scratch files,
/// fetches high-resolution cover art and synced lyrics, and prepares them for
/// cloud upload.
class TrackAudioTaggerService {
  TrackAudioTaggerService({
    http.Client? httpClient,
    ArtworkAndLyricsService? metadataService,
  })  : _http = httpClient ?? http.Client(),
        _metadataService = metadataService ?? ArtworkAndLyricsService(client: httpClient);

  final http.Client _http;
  final ArtworkAndLyricsService _metadataService;

  /// Downloads candidate audio stream into a temporary scratch file and tags it.
  Future<PreparedTrackAudio> downloadAndPrepareAudio({
    required AudioStreamCandidate candidate,
    required String targetTitle,
    required String targetArtist,
    String? targetAlbum,
    String? preferredArtworkUrl,
    void Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final scratchDir = Directory(p.join(tempDir.path, 'freebeat_scratch_audio'));
    if (!await scratchDir.exists()) {
      await scratchDir.create(recursive: true);
    }

    final ext = candidate.format.toLowerCase() == 'opus'
        ? 'opus'
        : (candidate.format.toLowerCase() == 'mp3' ? 'mp3' : 'm4a');
    final safeBaseName = _sanitizeFilename('$targetArtist - $targetTitle');
    final filename = '$safeBaseName.$ext';
    final scratchFile = File(p.join(scratchDir.path, '${DateTime.now().millisecondsSinceEpoch}_$filename'));

    final sink = scratchFile.openWrite();
    int receivedBytes = 0;
    final totalExpectedBytes = candidate.streamSizeBytes ?? (candidate.bitrateKbps * 125 * (candidate.durationMs ~/ 1000));

    try {
      Stream<List<int>> byteStream;
      if (candidate.ytClient != null && candidate.audioOnlyStreamInfo != null) {
        byteStream = candidate.getByteStream();
      } else {
        final request = http.Request('GET', Uri.parse(candidate.streamUrl));
        final response = await _http.send(request).timeout(const Duration(seconds: 15));
        byteStream = response.stream;
      }

      await for (final chunk in byteStream.timeout(const Duration(seconds: 15))) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (onProgress != null && totalExpectedBytes > 0) {
          final progress = (receivedBytes / totalExpectedBytes).clamp(0.0, 1.0);
          onProgress(progress);
        }
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      if (await scratchFile.exists()) {
        await scratchFile.delete().catchError((_) => scratchFile);
      }
      rethrow;
    }

    final actualSizeBytes = await scratchFile.length();

    // 2. Resolve High-Res Artwork & Official Album Name via iTunes metadata if needed
    String resolvedArtworkUrl = preferredArtworkUrl ?? candidate.artworkUrl ?? '';
    String resolvedAlbum = (targetAlbum != null && targetAlbum != 'Imported Playlist')
        ? targetAlbum
        : (candidate.album ?? 'Imported Playlist');
    String resolvedArtist = targetArtist.isNotEmpty ? targetArtist : candidate.channelOrArtist;

    if (resolvedArtworkUrl.isEmpty || resolvedAlbum == 'Imported Playlist') {
      try {
        final meta = await _metadataService.lookupSongMetadata(
          artist: resolvedArtist,
          title: targetTitle,
        ).timeout(const Duration(seconds: 2));
        if (meta != null) {
          if (meta.artworkUrl != null && meta.artworkUrl!.isNotEmpty && resolvedArtworkUrl.isEmpty) {
            resolvedArtworkUrl = meta.artworkUrl!;
          }
          if (meta.album != null && meta.album!.isNotEmpty && resolvedAlbum == 'Imported Playlist') {
            resolvedAlbum = meta.album!;
          }
          if (meta.artist != null && meta.artist!.isNotEmpty && ArtworkAndLyricsService.isInvalidOrGenericArtist(resolvedArtist)) {
            resolvedArtist = meta.artist!;
          }
        }
      } catch (_) {}
    }

    // 3. Extract Dominant Color for Material You Theme
    int dominantColor = 0xFF1E293B;
    if (resolvedArtworkUrl.isNotEmpty) {
      try {
        final palette = await ArtworkPaletteExtractor.extractPalette(resolvedArtworkUrl);
        dominantColor = palette.dominantColor.toARGB32();
      } catch (_) {}
    }

    // 4. Fetch Synced Lyrics (with strict 2.5s safety timeout)
    List<LyricLine> lyrics = const [];
    try {
      final dummyTrack = Track(
        id: 'scratch_${DateTime.now().millisecondsSinceEpoch}',
        accountId: '',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '',
        title: targetTitle,
        artist: resolvedArtist,
        album: resolvedAlbum,
        durationMs: candidate.durationMs,
        streamUrl: '',
      );
      lyrics = await _metadataService.fetchSyncedLyricsForTrack(dummyTrack)
          .timeout(const Duration(milliseconds: 600));
    } catch (_) {}

    return PreparedTrackAudio(
      file: scratchFile,
      filename: filename,
      title: targetTitle,
      artist: resolvedArtist,
      album: resolvedAlbum,
      format: ext,
      durationMs: candidate.durationMs,
      sizeBytes: actualSizeBytes,
      bitrateKbps: candidate.bitrateKbps,
      artworkUrl: resolvedArtworkUrl.isNotEmpty ? resolvedArtworkUrl : null,
      dominantColorValue: dominantColor,
      syncedLyrics: lyrics,
    );
  }

  static String _sanitizeFilename(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
