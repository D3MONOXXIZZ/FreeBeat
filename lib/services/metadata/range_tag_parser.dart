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

    // 3. Check for M4A / MP4 / AAC / ALAC: 'ftyp' at bytes[4..7]
    if (bytes.length >= 8 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return _parseM4aHeader(bytes, fallback);
    }

    // 4. Check for ASF / WMA: Header Object GUID 30 26 B2 75 8E 66 CF 11 A6 D9 00 AA 00 62 CE 6C
    if (bytes.length >= 16 &&
        bytes[0] == 0x30 &&
        bytes[1] == 0x26 &&
        bytes[2] == 0xB2 &&
        bytes[3] == 0x75 &&
        bytes[4] == 0x8E &&
        bytes[5] == 0x66 &&
        bytes[6] == 0xCF &&
        bytes[7] == 0x11) {
      return _parseAsfWmaHeader(bytes, fallback);
    }

    // 5. Check for WAV: 'RIFF' .... 'WAVE'
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45) {
      return _parseWavHeader(bytes, fallback);
    }

    // 6. Check for Ogg / Opus: 'OggS'
    if (bytes.length >= 4 &&
        bytes[0] == 0x4F &&
        bytes[1] == 0x67 &&
        bytes[2] == 0x67 &&
        bytes[3] == 0x53) {
      return _parseOggHeader(bytes, fallback);
    }

    // 7. Check for AIFF: 'FORM' .... 'AIFF' or 'AIFC'
    if (bytes.length >= 12 &&
        bytes[0] == 0x46 &&
        bytes[1] == 0x4F &&
        bytes[2] == 0x52 &&
        bytes[3] == 0x4D &&
        bytes[8] == 0x41 &&
        bytes[9] == 0x49 &&
        bytes[10] == 0x46) {
      return _parseAiffHeader(bytes, fallback);
    }

    // 8. Fallback to ID3v1 if present
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

  static int _findSubsequence(Uint8List data, List<int> pattern, {int start = 0, int? end}) {
    final limit = (end ?? data.length) - pattern.length;
    for (int i = start; i <= limit; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  static String _decodeUtf16LE(Uint8List bytes) {
    if (bytes.length < 2) return '';
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final cu = bytes[i] | (bytes[i + 1] << 8);
      if (cu == 0) break;
      codeUnits.add(cu);
    }
    return String.fromCharCodes(codeUnits).trim();
  }

  static ParsedAudioMetadata _parseM4aHeader(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;
    int? durationMs;
    int sampleRate = 44100;
    int bitDepth = 16;
    int channels = 2;
    Uint8List? artwork;
    String codec = 'AAC';

    // 1. Detect if ALAC
    if (_findSubsequence(bytes, [0x61, 0x6C, 0x61, 0x63]) != -1) {
      codec = 'ALAC';
      bitDepth = 24;
    } else if (fallback.codec == 'ALAC' || fallback.codec == 'M4A') {
      codec = fallback.codec!;
    }

    // 2. Parse mvhd for duration & timescale
    final mvhdPos = _findSubsequence(bytes, [0x6D, 0x76, 0x68, 0x64]);
    if (mvhdPos != -1 && mvhdPos + 24 <= bytes.length) {
      final version = bytes[mvhdPos + 4];
      if (version == 1 && mvhdPos + 36 <= bytes.length) {
        final timescale = (bytes[mvhdPos + 24] << 24) |
            (bytes[mvhdPos + 25] << 16) |
            (bytes[mvhdPos + 26] << 8) |
            bytes[mvhdPos + 27];
        final durHigh = (bytes[mvhdPos + 28] << 24) |
            (bytes[mvhdPos + 29] << 16) |
            (bytes[mvhdPos + 30] << 8) |
            bytes[mvhdPos + 31];
        final durLow = (bytes[mvhdPos + 32] << 24) |
            (bytes[mvhdPos + 33] << 16) |
            (bytes[mvhdPos + 34] << 8) |
            bytes[mvhdPos + 35];
        final dur = (durHigh * 4294967296) + durLow;
        if (timescale > 0 && dur > 0) {
          durationMs = ((dur / timescale) * 1000).round();
        }
      } else if (version == 0 && mvhdPos + 20 <= bytes.length) {
        final timescale = (bytes[mvhdPos + 16] << 24) |
            (bytes[mvhdPos + 17] << 16) |
            (bytes[mvhdPos + 18] << 8) |
            bytes[mvhdPos + 19];
        final dur = (bytes[mvhdPos + 20] << 24) |
            (bytes[mvhdPos + 21] << 16) |
            (bytes[mvhdPos + 22] << 8) |
            bytes[mvhdPos + 23];
        if (timescale > 0 && dur > 0) {
          durationMs = ((dur / timescale) * 1000).round();
        }
      }
    }

    // 3. Parse ilst metadata tags
    final ilstPos = _findSubsequence(bytes, [0x69, 0x6C, 0x73, 0x74]);
    if (ilstPos != -1 && ilstPos >= 4) {
      final ilstSize = (bytes[ilstPos - 4] << 24) |
          (bytes[ilstPos - 3] << 16) |
          (bytes[ilstPos - 2] << 8) |
          bytes[ilstPos - 1];
      final ilstEnd = (ilstPos - 4 + ilstSize).clamp(ilstPos + 4, bytes.length);

      int pos = ilstPos + 4;
      while (pos + 8 <= ilstEnd) {
        final atomSize = (bytes[pos] << 24) |
            (bytes[pos + 1] << 16) |
            (bytes[pos + 2] << 8) |
            bytes[pos + 3];
        if (atomSize <= 0 || pos + atomSize > ilstEnd) break;
        final atomEnd = pos + atomSize;

        final tagByte0 = bytes[pos + 4];
        final tagByte1 = bytes[pos + 5];
        final tagByte2 = bytes[pos + 6];
        final tagByte3 = bytes[pos + 7];

        final dataPos = _findSubsequence(
          bytes,
          [0x64, 0x61, 0x74, 0x61],
          start: pos + 8,
          end: atomEnd,
        );

        if (dataPos != -1 && dataPos + 16 <= atomEnd) {
          final payloadStart = dataPos + 12;
          if (payloadStart < atomEnd) {
            // ©nam: [0xA9, 0x6E, 0x61, 0x6D]
            if (tagByte0 == 0xA9 && tagByte1 == 0x6E && tagByte2 == 0x61 && tagByte3 == 0x6D) {
              final str = utf8.decode(bytes.sublist(payloadStart, atomEnd), allowMalformed: true).trim();
              if (str.isNotEmpty) title = str;
            }
            // ©ART: [0xA9, 0x41, 0x52, 0x54]
            else if (tagByte0 == 0xA9 && tagByte1 == 0x41 && tagByte2 == 0x52 && tagByte3 == 0x54) {
              final str = utf8.decode(bytes.sublist(payloadStart, atomEnd), allowMalformed: true).trim();
              if (str.isNotEmpty) artist = str;
            }
            // aART: [0x61, 0x41, 0x52, 0x54]
            else if (tagByte0 == 0x61 && tagByte1 == 0x41 && tagByte2 == 0x52 && tagByte3 == 0x54) {
              final str = utf8.decode(bytes.sublist(payloadStart, atomEnd), allowMalformed: true).trim();
              if (artist == null && str.isNotEmpty) artist = str;
            }
            // ©alb: [0xA9, 0x61, 0x6C, 0x62]
            else if (tagByte0 == 0xA9 && tagByte1 == 0x61 && tagByte2 == 0x6C && tagByte3 == 0x62) {
              final str = utf8.decode(bytes.sublist(payloadStart, atomEnd), allowMalformed: true).trim();
              if (str.isNotEmpty) album = str;
            }
            // covr: [0x63, 0x6F, 0x76, 0x72]
            else if (tagByte0 == 0x63 && tagByte1 == 0x6F && tagByte2 == 0x76 && tagByte3 == 0x72) {
              artwork = bytes.sublist(payloadStart, atomEnd);
            }
          }
        }
        pos += atomSize;
      }
    }

    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      sampleRateHz: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      durationMs: durationMs,
      bitrateKbps: codec == 'ALAC' ? 1411 : 256,
      codec: codec,
      embeddedArtworkBytes: artwork,
    );
  }

  static ParsedAudioMetadata _parseAsfWmaHeader(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;
    int? durationMs;
    int? bitrateKbps;

    int pos = 30;
    while (pos + 24 <= bytes.length) {
      final b0 = bytes[pos];
      final b1 = bytes[pos + 1];
      final b2 = bytes[pos + 2];
      final b3 = bytes[pos + 3];

      final objSize = _readUint32LE(bytes, pos + 16);
      if (objSize <= 0 || pos + objSize > bytes.length) break;
      final payloadPos = pos + 24;
      final payloadEnd = pos + objSize;

      // Content Description Object GUID: 75 B2 26 33 66 8E CF 11 A6 D9 00 AA 00 62 CE 6C
      if (b0 == 0x33 && b1 == 0x26 && b2 == 0xB2 && b3 == 0x75 && payloadPos + 10 <= payloadEnd) {
        final titleLen = bytes[payloadPos] | (bytes[payloadPos + 1] << 8);
        final authorLen = bytes[payloadPos + 2] | (bytes[payloadPos + 3] << 8);
        int dPos = payloadPos + 10;
        if (titleLen > 0 && dPos + titleLen <= payloadEnd) {
          final t = _decodeUtf16LE(bytes.sublist(dPos, dPos + titleLen));
          if (t.isNotEmpty) title = t;
          dPos += titleLen;
        }
        if (authorLen > 0 && dPos + authorLen <= payloadEnd) {
          final a = _decodeUtf16LE(bytes.sublist(dPos, dPos + authorLen));
          if (a.isNotEmpty) artist = a;
        }
      }
      // Extended Content Description Object GUID: D2 D0 A2 40 E0 56 CF 11 A6 D9 00 AA 00 62 CE 6C
      else if (b0 == 0x40 && b1 == 0xA2 && b2 == 0xD0 && b3 == 0xD2 && payloadPos + 2 <= payloadEnd) {
        final count = bytes[payloadPos] | (bytes[payloadPos + 1] << 8);
        int dPos = payloadPos + 2;
        for (int i = 0; i < count && dPos + 4 <= payloadEnd; i++) {
          final nameLen = bytes[dPos] | (bytes[dPos + 1] << 8);
          dPos += 2;
          if (dPos + nameLen > payloadEnd) break;
          final name = _decodeUtf16LE(bytes.sublist(dPos, dPos + nameLen));
          dPos += nameLen;
          if (dPos + 4 > payloadEnd) break;
          final valLen = bytes[dPos + 2] | (bytes[dPos + 3] << 8);
          dPos += 4;
          if (dPos + valLen > payloadEnd) break;
          final valBytes = bytes.sublist(dPos, dPos + valLen);
          dPos += valLen;

          if (name == 'WM/AlbumTitle') {
            final al = _decodeUtf16LE(valBytes);
            if (al.isNotEmpty) album = al;
          } else if ((name == 'WM/AlbumArtist' || name == 'Author') && artist == null) {
            final ar = _decodeUtf16LE(valBytes);
            if (ar.isNotEmpty) artist = ar;
          }
        }
      }
      // File Properties Object GUID: A1 DC AB 8C 47 A9 CF 11 8E E4 00 C0 0C 20 53 65
      else if (b0 == 0x8C && b1 == 0xAB && b2 == 0xDC && b3 == 0xA1 && payloadPos + 80 <= payloadEnd) {
        final playDurLow = _readUint32LE(bytes, payloadPos + 40);
        final playDurHigh = _readUint32LE(bytes, payloadPos + 44);
        final playDur = (playDurHigh * 4294967296) + playDurLow;
        if (playDur > 0) {
          durationMs = (playDur / 10000).round();
        }
        final maxBitrate = _readUint32LE(bytes, payloadPos + 72);
        if (maxBitrate > 0) {
          bitrateKbps = (maxBitrate / 1000).round();
        }
      }

      pos += objSize;
    }

    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      sampleRateHz: 44100,
      bitDepth: 16,
      channels: 2,
      durationMs: durationMs,
      bitrateKbps: bitrateKbps ?? 192,
      codec: 'WMA',
    );
  }

  static ParsedAudioMetadata _parseWavHeader(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;
    int sampleRate = 44100;
    int channels = 2;
    int bitDepth = 16;
    int? durationMs;
    int? byteRate;

    int pos = 12;
    while (pos + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(pos, pos + 4));
      final chunkSize = _readUint32LE(bytes, pos + 4);
      pos += 8;
      if (chunkSize <= 0 || pos + chunkSize > bytes.length) break;

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        channels = bytes[pos + 2] | (bytes[pos + 3] << 8);
        sampleRate = _readUint32LE(bytes, pos + 4);
        byteRate = _readUint32LE(bytes, pos + 8);
        bitDepth = bytes[pos + 14] | (bytes[pos + 15] << 8);
      } else if (chunkId == 'data') {
        if (byteRate != null && byteRate > 0) {
          durationMs = ((chunkSize / byteRate) * 1000).round();
        }
      } else if (chunkId == 'id3 ' || chunkId == 'ID3 ') {
        final id3 = _parseId3v2Header(bytes.sublist(pos, pos + chunkSize), fallback);
        title = id3.title ?? title;
        artist = id3.artist ?? artist;
        album = id3.album ?? album;
      } else if (chunkId == 'LIST' && pos + 4 <= bytes.length) {
        final listType = String.fromCharCodes(bytes.sublist(pos, pos + 4));
        if (listType == 'INFO') {
          int infoPos = pos + 4;
          while (infoPos + 8 <= pos + chunkSize) {
            final infoTag = String.fromCharCodes(bytes.sublist(infoPos, infoPos + 4));
            final infoLen = _readUint32LE(bytes, infoPos + 4);
            infoPos += 8;
            if (infoLen <= 0 || infoPos + infoLen > pos + chunkSize) break;
            final text = latin1.decode(bytes.sublist(infoPos, infoPos + infoLen), allowInvalid: true).replaceAll('\u0000', '').trim();
            if (infoTag == 'INAM' && text.isNotEmpty) title = text;
            if (infoTag == 'IART' && text.isNotEmpty) artist = text;
            if (infoTag == 'IPRD' && text.isNotEmpty) album = text;
            infoPos += (infoLen + 1) & ~1;
          }
        }
      }

      pos += (chunkSize + 1) & ~1;
    }

    final bitrate = (sampleRate * bitDepth * channels / 1000).round();
    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      sampleRateHz: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      durationMs: durationMs,
      bitrateKbps: bitrate,
      codec: 'WAV',
    );
  }

  static ParsedAudioMetadata _parseOggHeader(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;
    String codec = 'OGG';
    int sampleRate = 44100;

    if (_findSubsequence(bytes, [0x4F, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64]) != -1) {
      codec = 'OPUS';
      sampleRate = 48000;
    }

    try {
      final textContent = latin1.decode(bytes, allowInvalid: true);
      final titleMatch = RegExp(r'TITLE=([^\r\n\x00]+)', caseSensitive: false).firstMatch(textContent);
      if (titleMatch != null) title = titleMatch.group(1)?.trim();

      final artistMatch = RegExp(r'ARTIST=([^\r\n\x00]+)', caseSensitive: false).firstMatch(textContent);
      if (artistMatch != null) artist = artistMatch.group(1)?.trim();

      final albumMatch = RegExp(r'ALBUM=([^\r\n\x00]+)', caseSensitive: false).firstMatch(textContent);
      if (albumMatch != null) album = albumMatch.group(1)?.trim();
    } catch (_) {}

    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      sampleRateHz: sampleRate,
      bitDepth: 16,
      channels: 2,
      bitrateKbps: codec == 'OPUS' ? 160 : 320,
      codec: codec,
    );
  }

  static ParsedAudioMetadata _parseAiffHeader(
    Uint8List bytes,
    ParsedAudioMetadata fallback,
  ) {
    String? title = fallback.title;
    String? artist = fallback.artist;
    String? album = fallback.album;
    int sampleRate = 44100;
    int channels = 2;
    int bitDepth = 16;
    int? durationMs;

    final id3Pos = _findSubsequence(bytes, [0x49, 0x44, 0x33, 0x20]);
    if (id3Pos != -1 && id3Pos + 12 <= bytes.length) {
      final id3 = _parseId3v2Header(bytes.sublist(id3Pos + 4), fallback);
      title = id3.title ?? title;
      artist = id3.artist ?? artist;
      album = id3.album ?? album;
    }

    final commPos = _findSubsequence(bytes, [0x43, 0x4F, 0x4D, 0x4D]);
    if (commPos != -1 && commPos + 18 <= bytes.length) {
      channels = (bytes[commPos + 4] << 8) | bytes[commPos + 5];
      bitDepth = (bytes[commPos + 10] << 8) | bytes[commPos + 11];
      final exp = ((bytes[commPos + 12] & 0x7F) << 8) | bytes[commPos + 13];
      final mantissa = (bytes[commPos + 14] << 24) |
          (bytes[commPos + 15] << 16) |
          (bytes[commPos + 16] << 8) |
          bytes[commPos + 17];
      if (exp > 16382) {
        sampleRate = (mantissa >> (16414 - exp)).clamp(8000, 192000);
      }
    }

    return ParsedAudioMetadata(
      title: title,
      artist: artist,
      album: album,
      sampleRateHz: sampleRate,
      bitDepth: bitDepth,
      channels: channels,
      durationMs: durationMs,
      bitrateKbps: (sampleRate * bitDepth * channels / 1000).round(),
      codec: 'AIFF',
    );
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
        ext == 'FLAC' || ext == 'WAV' || ext == 'ALAC' || ext == 'AIFF' || ext == 'APE' || ext == 'DSD' || ext == 'DSF' || ext == 'DFF';

    int sampleRate = isLosslessExt ? 96000 : 48000;
    int bitDepth = isLosslessExt ? 24 : 16;
    int bitrate = isLosslessExt ? 2150 : 320;
    if (ext == 'M4A' || ext == 'AAC') {
      sampleRate = 44100;
      bitDepth = 16;
      bitrate = 256;
    } else if (ext == 'WMA' || ext == 'ASF') {
      sampleRate = 44100;
      bitDepth = 16;
      bitrate = 192;
    } else if (ext == 'OPUS') {
      sampleRate = 48000;
      bitDepth = 16;
      bitrate = 160;
    } else if (ext == 'OGG') {
      sampleRate = 44100;
      bitDepth = 16;
      bitrate = 256;
    } else if (ext == 'DSD' || ext == 'DSF' || ext == 'DFF') {
      sampleRate = 2822400;
      bitDepth = 1;
      bitrate = 5645;
    }

    if (parts.length >= 2) {
      return ParsedAudioMetadata(
        artist: parts.first.trim(),
        title: parts.sublist(1).join(' - ').trim(),
        album: null,
        codec: ext,
        bitDepth: bitDepth,
        sampleRateHz: sampleRate,
        bitrateKbps: bitrate,
      );
    }

    return ParsedAudioMetadata(
      title: stripped.isEmpty ? 'Unknown Track' : stripped,
      artist: null,
      album: null,
      codec: ext,
      bitDepth: bitDepth,
      sampleRateHz: sampleRate,
      bitrateKbps: bitrate,
    );
  }
}
