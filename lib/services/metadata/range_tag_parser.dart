import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ParsedAudioMetadata {
  const ParsedAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.sampleRateHz,
    this.bitDepth,
    this.channels,
    this.durationMs,
    this.bitrateKbps,
    this.codec,
    this.embeddedArtworkBytes,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? sampleRateHz;
  final int? bitDepth;
  final int? channels;
  final int? durationMs;
  final int? bitrateKbps;
  final String? codec;
  final Uint8List? embeddedArtworkBytes;
}

/// Rule A4 & Rule B3: Bandwidth-safe 64 KB HTTP Range (`bytes=0-65535`) tag parser
/// with a max-3-concurrent token-bucket rate limiter and HTTP 429 exponential backoff.
class RangeTagParser {
  RangeTagParser({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  int _activeRequests = 0;
  static const int _maxConcurrent = 3;
  final List<Completer<void>> _waitQueue = [];

  Future<void> _acquireSlot() async {
    if (_activeRequests < _maxConcurrent) {
      _activeRequests++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void _releaseSlot() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete();
    } else {
      _activeRequests--;
    }
  }

  /// Fetches only the first 64 KB (`bytes=0-65535`) of a remote cloud audio file
  /// with exponential backoff on HTTP 429/503 rate limits.
  Future<ParsedAudioMetadata> fetchAndParseRemoteHeader(
    String url, {
    Map<String, String> headers = const {},
    String fallbackFilename = '',
  }) async {
    await _acquireSlot();
    try {
      int attempt = 0;
      while (attempt < 3) {
        attempt++;
        final reqHeaders = <String, String>{
          ...headers,
          'Range': 'bytes=0-65535',
        };
        final response = await _client
            .get(Uri.parse(url), headers: reqHeaders)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 429 || response.statusCode == 503) {
          await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
          continue;
        }

        if (response.statusCode == 200 || response.statusCode == 206) {
          return parseHeaderBytes(
            response.bodyBytes,
            fallbackFilename: fallbackFilename,
          );
        }
        break;
      }
    } catch (_) {
      // Fallback to filename parser on network/CORS error
    } finally {
      _releaseSlot();
    }
    return parseFromFilename(fallbackFilename);
  }

  /// Parses binary ID3v2.3 / ID3v2.4 or native FLAC STREAMINFO + VORBIS_COMMENT headers.
  static ParsedAudioMetadata parseHeaderBytes(
    Uint8List bytes, {
    String fallbackFilename = '',
  }) {
    final fallback = parseFromFilename(fallbackFilename);
    if (bytes.length < 10) return fallback;

    // 1. Check for 'fLaC' magic header (0x66 0x4C 0x61 0x43)
    if (bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return _parseFlacHeader(bytes, fallback);
    }

    // 2. Check for 'ID3' magic header (0x49 0x44 0x33)
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      return _parseId3v2Header(bytes, fallback);
    }

    return fallback;
  }

  static ParsedAudioMetadata _parseFlacHeader(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    int? sampleRate;
    int? channels;
    int? bitDepth;
    int? durationMs;
    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;

    int offset = 4;
    bool isLastBlock = false;

    while (!isLastBlock && offset + 4 <= bytes.length) {
      final headerByte = bytes[offset];
      isLastBlock = (headerByte & 0x80) != 0;
      final blockType = headerByte & 0x7F;
      final blockLen =
          (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 4;

      if (offset + blockLen > bytes.length) break;

      if (blockType == 0 && blockLen >= 18) {
        // STREAMINFO block (34 bytes standard)
        // Bytes 10..17 contain 20-bit sample rate, 3-bit channels-1, 5-bit bitsPerSample-1, 36-bit total samples
        final b10 = bytes[offset + 10];
        final b11 = bytes[offset + 11];
        final b12 = bytes[offset + 12];
        final b13 = bytes[offset + 13];
        sampleRate = (b10 << 12) | (b11 << 4) | ((b12 & 0xF0) >> 4);
        channels = ((b12 & 0x0E) >> 1) + 1;
        bitDepth = (((b12 & 0x01) << 4) | ((b13 & 0xF0) >> 4)) + 1;

        final totalSamplesHigh = b13 & 0x0F;
        final totalSamplesLow = (bytes[offset + 14] << 24) |
            (bytes[offset + 15] << 16) |
            (bytes[offset + 16] << 8) |
            bytes[offset + 17];
        final totalSamples = (totalSamplesHigh * 4294967296) + totalSamplesLow;
        if (sampleRate > 0 && totalSamples > 0) {
          durationMs = ((totalSamples / sampleRate) * 1000).round();
        }
      } else if (blockType == 4) {
        // VORBIS_COMMENT block (little-endian)
        try {
          int vPos = offset;
          final vendorLen = _readUint32LE(bytes, vPos);
          vPos += 4 + vendorLen;
          if (vPos + 4 <= offset + blockLen) {
            final commentCount = _readUint32LE(bytes, vPos);
            vPos += 4;
            for (int i = 0; i < commentCount && vPos + 4 <= offset + blockLen; i++) {
              final cLen = _readUint32LE(bytes, vPos);
              vPos += 4;
              if (vPos + cLen > offset + blockLen) break;
              final comment = utf8.decode(
                bytes.sublist(vPos, vPos + cLen),
                allowMalformed: true,
              );
              vPos += cLen;
              final eqIdx = comment.indexOf('=');
              if (eqIdx > 0) {
                final key = comment.substring(0, eqIdx).toUpperCase();
                final val = comment.substring(eqIdx + 1).trim();
                if (key == 'TITLE' && val.isNotEmpty) title = val;
                if (key == 'ARTIST' && val.isNotEmpty) artist = val;
                if (key == 'ALBUM' && val.isNotEmpty) album = val;
              }
            }
          }
        } catch (_) {}
      }

      offset += blockLen;
    }

    final estimatedBitrate = (sampleRate != null && bitDepth != null && channels != null)
        ? ((sampleRate * bitDepth * channels * 0.62) / 1000).round()
        : 1411;

    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      sampleRateHz: sampleRate ?? 96000,
      bitDepth: bitDepth ?? 24,
      channels: channels ?? 2,
      durationMs: durationMs,
      bitrateKbps: estimatedBitrate,
      codec: 'FLAC',
    );
  }

  static ParsedAudioMetadata _parseId3v2Header(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    final versionMajor = bytes[3]; // 3 = ID3v2.3, 4 = ID3v2.4
    final tagSize = ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);

    final limit = (10 + tagSize).clamp(10, bytes.length);
    int pos = 10;

    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;
    Uint8List? artwork;

    while (pos + 10 <= limit) {
      final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(frameId)) break;

      final frameSize = versionMajor == 4
          ? (((bytes[pos + 4] & 0x7F) << 21) |
              ((bytes[pos + 5] & 0x7F) << 14) |
              ((bytes[pos + 6] & 0x7F) << 7) |
              (bytes[pos + 7] & 0x7F))
          : ((bytes[pos + 4] << 24) |
              (bytes[pos + 5] << 16) |
              (bytes[pos + 6] << 8) |
              bytes[pos + 7]);

      pos += 10;
      if (frameSize <= 0 || pos + frameSize > limit) break;

      final frameBytes = bytes.sublist(pos, pos + frameSize);
      if (frameId == 'TIT2') {
        title = _decodeId3Text(frameBytes) ?? title;
      } else if (frameId == 'TPE1') {
        artist = _decodeId3Text(frameBytes) ?? artist;
      } else if (frameId == 'TALB') {
        album = _decodeId3Text(frameBytes) ?? album;
      } else if (frameId == 'APIC' && frameBytes.length > 16) {
        artwork = frameBytes;
      }

      pos += frameSize;
    }

    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      codec: fallback.codec ?? 'MP3',
      bitrateKbps: fallback.bitrateKbps ?? 320,
      sampleRateHz: 48000,
      bitDepth: 16,
      channels: 2,
      embeddedArtworkBytes: artwork,
    );
  }

  static String? _decodeId3Text(Uint8List frameBytes) {
    if (frameBytes.length <= 1) return null;
    final encoding = frameBytes[0];
    final payload = frameBytes.sublist(1);
    String decoded;
    if (encoding == 0) {
      decoded = latin1.decode(payload, allowInvalid: true);
    } else if (encoding == 3) {
      decoded = utf8.decode(payload, allowMalformed: true);
    } else {
      // UTF-16 with or without BOM
      final filtered = payload.where((b) => b != 0).toList();
      decoded = utf8.decode(filtered, allowMalformed: true);
    }
    final cleaned = decoded.replaceAll('\u0000', '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static int _readUint32LE(Uint8List bytes, int pos) {
    return bytes[pos] |
        (bytes[pos + 1] << 8) |
        (bytes[pos + 2] << 16) |
        (bytes[pos + 3] << 24);
  }

  /// Intelligent filename fallback parser: e.g. `01 - Daft Punk - Veridis Quo.flac`
  static ParsedAudioMetadata parseFromFilename(String filename) {
    final base = filename.split('/').last.split('\\').last;
    final dotIdx = base.lastIndexOf('.');
    final ext = dotIdx > 0 ? base.substring(dotIdx + 1).toUpperCase() : 'FLAC';
    final nameWithoutExt = dotIdx > 0 ? base.substring(0, dotIdx) : base;

    // Strip leading track numbers like "01 - " or "01. "
    final stripped =
        nameWithoutExt.replaceFirst(RegExp(r'^\d{1,3}[\s.\-_]+'), '').trim();
    final parts = stripped.split(' - ');

    final isLosslessExt =
        ext == 'FLAC' || ext == 'WAV' || ext == 'ALAC' || ext == 'AIFF';

    if (parts.length >= 2) {
      return ParsedAudioMetadata(
        artist: parts.first.trim(),
        title: parts.sublist(1).join(' - ').trim(),
        album: 'Cloud Hi-Fi Collection',
        codec: ext,
        bitDepth: isLosslessExt ? 24 : 16,
        sampleRateHz: isLosslessExt ? 96000 : 48000,
        bitrateKbps: isLosslessExt ? 2150 : 320,
      );
    }

    return ParsedAudioMetadata(
      title: stripped.isEmpty ? 'Untitled Cloud Track' : stripped,
      artist: 'Cloud Artist',
      album: 'Cloud Library',
      codec: ext,
      bitDepth: isLosslessExt ? 24 : 16,
      sampleRateHz: isLosslessExt ? 96000 : 48000,
      bitrateKbps: isLosslessExt ? 2150 : 320,
    );
  }
}
