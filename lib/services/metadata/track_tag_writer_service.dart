import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service that writes ID3 tags (Title, Artist, Album, Genre, Year) and embeds
/// front album cover artwork into local physical audio files (MP3, FLAC, M4A)
/// without re-encoding audio streams.
class TrackTagWriterService {
  const TrackTagWriterService();

  /// Updates metadata tags and optional embedded artwork for a local audio file.
  /// Returns `true` if the physical file was successfully updated, `false` otherwise.
  Future<bool> writeTagsToLocalFile({
    required String filePath,
    required String title,
    required String artist,
    required String album,
    String? genre,
    int? year,
    String? artworkPath,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return false;

      final ext = p.extension(filePath).toLowerCase();
      final tempDir = await getTemporaryDirectory();
      final tempOutputPath = p.join(
        tempDir.path,
        'tag_writer_${DateTime.now().millisecondsSinceEpoch}$ext',
      );

      final hasArtwork = artworkPath != null &&
          artworkPath.isNotEmpty &&
          File(artworkPath).existsSync();

      final args = <String>['-y', '-i', filePath];

      if (hasArtwork && (ext == '.mp3' || ext == '.m4a' || ext == '.flac')) {
        args.addAll(['-i', artworkPath]);
        args.addAll(['-map', '0:a', '-map', '1:0']);
        args.addAll(['-c', 'copy']);
        if (ext == '.mp3') {
          args.addAll(['-id3v2_version', '3']);
          args.addAll(['-metadata:s:v', 'title=Album cover']);
          args.addAll(['-metadata:s:v', 'comment=Cover (front)']);
        }
      } else {
        args.addAll(['-c', 'copy']);
        if (ext == '.mp3') {
          args.addAll(['-id3v2_version', '3']);
        }
      }

      args.addAll([
        '-metadata',
        'title=$title',
        '-metadata',
        'artist=$artist',
        '-metadata',
        'album=$album',
      ]);

      if (genre != null && genre.trim().isNotEmpty) {
        args.addAll(['-metadata', 'genre=${genre.trim()}']);
      }
      if (year != null && year > 0) {
        args.addAll(['-metadata', 'date=${year.toString()}']);
        args.addAll(['-metadata', 'year=${year.toString()}']);
      }

      args.add(tempOutputPath);

      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      final tempFile = File(tempOutputPath);

      if (ReturnCode.isSuccess(returnCode) &&
          tempFile.existsSync() &&
          tempFile.lengthSync() > 1000) {
        // Overwrite original file
        await tempFile.copy(filePath);
        try {
          await tempFile.delete();
        } catch (_) {}
        debugPrint('[TrackTagWriter] Successfully wrote tags to $filePath');
        return true;
      } else {
        try {
          if (tempFile.existsSync()) await tempFile.delete();
        } catch (_) {}
        debugPrint(
            '[TrackTagWriter] FFmpeg failed with return code $returnCode');
        return false;
      }
    } catch (e) {
      debugPrint('[TrackTagWriter] Could not write tags to file: $e');
      return false;
    }
  }
}
