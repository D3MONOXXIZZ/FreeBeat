import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/models/track.dart';

/// Universal Audio Transcoder Service using native FFmpeg (via ffmpeg_kit)
/// with fallback to Android MediaCodec hardware transcoding.
///
/// Converts WMA, ASF, and any unsupported audio containers into standard
/// 16-bit PCM WAV files stored in a persistent local cache for zero-latency,
/// bit-perfect playback through just_audio and the Smart EQ DSP engine.
class UniversalAudioTranscoderService {
  static const MethodChannel _channel = MethodChannel('com.freebeat.freebeat/dsp');

  /// Detects whether an audio file or track requires decoding to PCM WAV before playback.
  static bool requiresTranscoding(Track track, [String? effectivePath]) {
    final codec = track.codec.toLowerCase().trim();
    if (codec == 'wma' || codec == 'asf') return true;

    final candidates = [
      effectivePath,
      track.streamUrl,
      track.localCachePath,
      track.title,
      track.id,
    ];

    for (final c in candidates) {
      if (c != null && c.isNotEmpty) {
        final l = c.toLowerCase();
        if (l.contains('.wma') || l.contains('.asf')) return true;
      }
    }
    return false;
  }

  /// Copies an Android content:// URI to a local temporary file for safe FFmpeg decoding.
  Future<String?> _copyContentUriToLocal(String contentUri, String trackId) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final inDir = Directory(p.join(tempDir.path, 'transcode_in'));
      if (!inDir.existsSync()) inDir.createSync(recursive: true);

      final safeName = 'saf_in_${trackId.hashCode.toRadixString(16)}.wma';
      final targetFile = File(p.join(inDir.path, safeName));

      if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
        return targetFile.path;
      }

      final success = await _channel.invokeMethod<bool>('copyContentUriToFile', {
        'uri': contentUri,
        'destPath': targetFile.path,
      });

      if (success == true && targetFile.existsSync() && targetFile.lengthSync() > 0) {
        return targetFile.path;
      }
    } catch (e) {
      debugPrint('[Transcoder] copyContentUriToFile failed: $e');
    }
    return null;
  }

  /// Transcodes an input audio track (WMA, ASF, etc.) to 16-bit PCM WAV.
  /// Returns the absolute path of the playable WAV file, or null on failure.
  Future<String?> transcodeToWav({
    required Track track,
    required String sourcePath,
  }) async {
    if (sourcePath.isEmpty) return null;

    try {
      final tempDir = await getTemporaryDirectory();
      final transcodeDir = Directory(p.join(tempDir.path, 'transcoded_audio'));
      if (!transcodeDir.existsSync()) {
        transcodeDir.createSync(recursive: true);
      }

      final safeKey = 'wma_${track.id.hashCode.toRadixString(16)}_${sourcePath.hashCode.toRadixString(16)}';
      final outputWav = File(p.join(transcodeDir.path, '$safeKey.wav'));

      // If already transcoded in cache, return immediately
      if (outputWav.existsSync() && outputWav.lengthSync() > 1024) {
        debugPrint('[Transcoder] Cache hit: ${outputWav.path} (${outputWav.lengthSync()} bytes)');
        return outputWav.path;
      }

      String effectiveInput = sourcePath;

      // Handle Android content:// URIs
      if (sourcePath.startsWith('content://')) {
        final localCopy = await _copyContentUriToLocal(sourcePath, track.id);
        if (localCopy != null && localCopy.isNotEmpty) {
          effectiveInput = localCopy;
        } else {
          try {
            final safParam = await FFmpegKitConfig.getSafParameterForRead(sourcePath);
            if (safParam != null && safParam.isNotEmpty) {
              effectiveInput = safParam;
            }
          } catch (_) {}
        }
      }

      final tempWavPath = '${outputWav.path}.tmp.wav';
      final tempWavFile = File(tempWavPath);
      if (tempWavFile.existsSync()) {
        try {
          tempWavFile.deleteSync();
        } catch (_) {}
      }

      debugPrint('[Transcoder] Starting FFmpeg decode: $effectiveInput -> $tempWavPath');
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        effectiveInput,
        '-vn',
        '-c:a',
        'pcm_s16le',
        tempWavPath,
      ]);

      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) && tempWavFile.existsSync() && tempWavFile.lengthSync() > 44) {
        tempWavFile.renameSync(outputWav.path);
        debugPrint('[Transcoder] FFmpeg transcode SUCCESS: ${outputWav.path} (${outputWav.lengthSync()} bytes)');
        return outputWav.path;
      } else {
        final logs = await session.getAllLogsAsString();
        debugPrint('[Transcoder] FFmpeg session failed with code $returnCode: $logs');
      }

      // Hardware fallback via Android MediaCodec MethodChannel
      debugPrint('[Transcoder] Trying native MediaCodec hardware fallback for $sourcePath');
      final nativeRes = await _channel.invokeMethod<String>('transcodeAudioIfNeeded', {
        'path': effectiveInput,
      });
      if (nativeRes != null && nativeRes.isNotEmpty && nativeRes.endsWith('.wav') && File(nativeRes).existsSync()) {
        debugPrint('[Transcoder] Native MediaCodec transcode SUCCESS: $nativeRes');
        return nativeRes;
      }
    } catch (e, st) {
      debugPrint('[Transcoder] Error during audio transcode for "${track.title}": $e\n$st');
    }
    return null;
  }
}
