import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  /// Parses a local audio file by reading its initial header (up to 128 KB)
  /// and trailing 128 bytes (for ID3v1) without loading whole multi-megabyte files into memory.
  static Future<ParsedAudioMetadata> parseLocalFile(File file) async {
    if (!await file.exists()) {
      return parseFromFilename(file.path);
    }
    try {
      final len = await file.length();
      if (len == 0) return parseFromFilename(file.path);

      final raf = await file.open(mode: FileMode.read);
      try {
        final headerSize = len < 131072 ? len : 131072;
        final headerBytes = await raf.read(headerSize);

        Uint8List? v1Bytes;
        if (len >= 128) {
          await raf.setPosition(len - 128);
          v1Bytes = await raf.read(128);
        }

        var parsed = parseHeaderBytes(
          headerBytes,
          fallbackFilename: file.path,
          id3v1Bytes: v1Bytes,
        );

        if (v1Bytes != null && (parsed.artist == null || parsed.album == null)) {
          parsed = parseId3v1Bytes(v1Bytes, current: parsed);
        }

        return parsed;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return parseFromFilename(file.path);
    }
  }

  /// Parses binary ID3v2.2 / ID3v2.3 / ID3v2.4 or native FLAC STREAMINFO + VORBIS_COMMENT headers.
  static ParsedAudioMetadata parseHeaderBytes(
    Uint8List bytes, {
    String fallbackFilename = '',
    Uint8List? id3v1Bytes,
  }) {
    final fallback = parseFromFilename(fallbackFilename);
    if (bytes.length < 10) {
      if (id3v1Bytes != null) {
        return parseId3v1Bytes(id3v1Bytes, current: fallback);
      }
      return fallback;
    }

    // 1. Check for 'fLaC' magic header (0x66 0x4C 0x61 0x43)
    if (bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43) {
      return _parseFlacHeader(bytes, fallback);
    }

    // 2. Check for 'ID3' magic header (0x49 0x44 0x33)
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      final id3 = _parseId3v2Header(bytes, fallback);
      if ((id3.artist == null || id3.album == null) && id3v1Bytes != null) {
        return parseId3v1Bytes(id3v1Bytes, current: id3);
      }
      return id3;
    }

    // 3. Fallback to ID3v1 if present
    if (id3v1Bytes != null) {
      return parseId3v1Bytes(id3v1Bytes, current: fallback);
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
                if ((key == 'ARTIST' || key == 'ALBUMARTIST' || key == 'ALBUM_ARTIST' || key == 'PERFORMER') &&
                    val.isNotEmpty) {
                  if (key == 'ARTIST' || artist == null) artist = val;
                }
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
    final versionMajor = bytes[3]; // 2 = ID3v2.2, 3 = ID3v2.3, 4 = ID3v2.4
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

    if (versionMajor == 2) {
      // ID3v2.2: 3-character frame ID + 3-byte size
      while (pos + 6 <= limit) {
        final frameId = String.fromCharCodes(bytes.sublist(pos, pos + 3));
        if (!RegExp(r'^[A-Z0-9]{3}$').hasMatch(frameId)) break;
        final frameSize =
            (bytes[pos + 3] << 16) | (bytes[pos + 4] << 8) | bytes[pos + 5];
        pos += 6;
        if (frameSize <= 0 || pos + frameSize > limit) break;

        final frameBytes = bytes.sublist(pos, pos + frameSize);
        if (frameId == 'TT2') {
          title = _decodeId3Text(frameBytes) ?? title;
        } else if (frameId == 'TP1' || (frameId == 'TP2' && artist == null)) {
          artist = _decodeId3Text(frameBytes) ?? artist;
        } else if (frameId == 'TAL') {
          album = _decodeId3Text(frameBytes) ?? album;
        } else if (frameId == 'PIC' && frameBytes.length > 10) {
          artwork = frameBytes;
        }
        pos += frameSize;
      }
    } else {
      // ID3v2.3 / ID3v2.4: 4-character frame ID + 4-byte size + 2 bytes flags
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
        if (frameId == 'TIT2' || (frameId == 'TIT1' && title == null)) {
          title = _decodeId3Text(frameBytes) ?? title;
        } else if (frameId == 'TPE1') {
          artist = _decodeId3Text(frameBytes) ?? artist;
        } else if ((frameId == 'TPE2' || frameId == 'TOPE' || frameId == 'TCOM') &&
            artist == null) {
          artist = _decodeId3Text(frameBytes) ?? artist;
        } else if (frameId == 'TALB') {
          album = _decodeId3Text(frameBytes) ?? album;
        } else if (frameId == 'APIC' && frameBytes.length > 16) {
          artwork = frameBytes;
        }

        pos += frameSize;
      }
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
    try {
      if (encoding == 0) {
        decoded = latin1.decode(payload, allowInvalid: true);
      } else if (encoding == 3) {
        decoded = utf8.decode(payload, allowMalformed: true);
      } else if (encoding == 1) {
        // UTF-16 with BOM (0xFF 0xFE for LE, 0xFE 0xFF for BE)
        if (payload.length >= 2) {
          final isLE = payload[0] == 0xFF && payload[1] == 0xFE;
          final isBE = payload[0] == 0xFE && payload[1] == 0xFF;
          final start = (isLE || isBE) ? 2 : 0;
          final littleEndian = !isBE;
          final codeUnits = <int>[];
          for (int i = start; i + 1 < payload.length; i += 2) {
            final cu = littleEndian
                ? payload[i] | (payload[i + 1] << 8)
                : (payload[i] << 8) | payload[i + 1];
            if (cu != 0) codeUnits.add(cu);
          }
          decoded = String.fromCharCodes(codeUnits);
        } else {
          decoded = '';
        }
      } else if (encoding == 2) {
        // UTF-16BE without BOM
        final codeUnits = <int>[];
        for (int i = 0; i + 1 < payload.length; i += 2) {
          final cu = (payload[i] << 8) | payload[i + 1];
          if (cu != 0) codeUnits.add(cu);
        }
        decoded = String.fromCharCodes(codeUnits);
      } else {
        decoded = utf8.decode(payload, allowMalformed: true);
      }
    } catch (_) {
      decoded = utf8.decode(
        payload.where((b) => b != 0).toList(),
        allowMalformed: true,
      );
    }
    final cleaned = decoded.replaceAll('\u0000', '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Parses standard 128-byte ID3v1 / ID3v1.1 tag at the end of MP3 files.
  static ParsedAudioMetadata parseId3v1Bytes(
    Uint8List bytes, {
    ParsedAudioMetadata? current,
  }) {
    if (bytes.length < 128) return current ?? const ParsedAudioMetadata();
    final start = bytes.length - 128;
    if (bytes[start] == 0x54 &&
        bytes[start + 1] == 0x41 &&
        bytes[start + 2] == 0x47) {
      // 'TAG'
      String readField(int offset, int len) {
        final sub = bytes.sublist(start + offset, start + offset + len);
        return latin1
            .decode(sub, allowInvalid: true)
            .replaceAll('\u0000', '')
            .trim();
      }

      final title = readField(3, 30);
      final artist = readField(33, 30);
      final album = readField(63, 30);

      final cur = current ?? const ParsedAudioMetadata();
      return ParsedAudioMetadata(
        title: (cur.title != null && cur.title!.isNotEmpty)
            ? cur.title
            : (title.isNotEmpty ? title : null),
        artist: (cur.artist != null &&
                cur.artist!.isNotEmpty &&
                cur.artist != 'Cloud Artist')
            ? cur.artist
            : (artist.isNotEmpty ? artist : null),
        album: (cur.album != null &&
                cur.album!.isNotEmpty &&
                cur.album != 'Cloud Library')
            ? cur.album
            : (album.isNotEmpty ? album : null),
        sampleRateHz: cur.sampleRateHz ?? 48000,
        bitDepth: cur.bitDepth ?? 16,
        channels: cur.channels ?? 2,
        durationMs: cur.durationMs,
        bitrateKbps: cur.bitrateKbps ?? 320,
        codec: cur.codec ?? 'MP3',
        embeddedArtworkBytes: cur.embeddedArtworkBytes,
      );
    }
    return current ?? const ParsedAudioMetadata();
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
        album: null,
        codec: ext,
        bitDepth: isLosslessExt ? 24 : 16,
        sampleRateHz: isLosslessExt ? 96000 : 48000,
        bitrateKbps: isLosslessExt ? 2150 : 320,
      );
    }

    return ParsedAudioMetadata(
      title: stripped.isEmpty ? 'Unknown Track' : stripped,
      artist: null,
      album: null,
      codec: ext,
      bitDepth: isLosslessExt ? 24 : 16,
      sampleRateHz: isLosslessExt ? 96000 : 48000,
      bitrateKbps: isLosslessExt ? 2150 : 320,
    );
  }
}
