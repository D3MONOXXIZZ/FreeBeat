import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Embedded Artwork Extractor for local and cached audio files.
/// Extracts native ID3v2 APIC (MP3) and Vorbis/FLAC PICTURE blocks,
/// strips header frames, and writes clean JPEG/PNG files to the app's album art cache.
class ArtworkExtractor {
  static Directory? _artDirectory;

  static Future<Directory> _getArtworkDirectory() async {
    if (_artDirectory != null && _artDirectory!.existsSync()) {
      return _artDirectory!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final artDir = Directory(p.join(appDir.path, 'album_art'));
    if (!artDir.existsSync()) {
      artDir.createSync(recursive: true);
    }
    _artDirectory = artDir;
    return artDir;
  }

  /// Extracts embedded album artwork from [audioFile] and writes it to disk.
  /// Returns the absolute path of the extracted image, or null if no embedded art found.
  static Future<String?> extractEmbeddedArtwork(
    File audioFile,
    String trackId,
  ) async {
    try {
      if (!audioFile.existsSync() || audioFile.lengthSync() < 128) {
        return null;
      }

      // Check if already extracted
      final artDir = await _getArtworkDirectory();
      final sanitizedId = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final targetFile = File(p.join(artDir.path, '$sanitizedId.jpg'));
      if (targetFile.existsSync() && targetFile.lengthSync() > 100) {
        return targetFile.path;
      }

      // Read initial 256 KB which contains standard ID3v2 or FLAC metadata blocks
      final raf = await audioFile.open(mode: FileMode.read);
      final readLen = audioFile.lengthSync().clamp(0, 512 * 1024);
      final bytes = await raf.read(readLen);
      await raf.close();

      if (bytes.length < 10) return null;

      Uint8List? rawImageBytes;

      // 1. FLAC magic ('fLaC')
      if (bytes[0] == 0x66 &&
          bytes[1] == 0x4C &&
          bytes[2] == 0x61 &&
          bytes[3] == 0x43) {
        rawImageBytes = _extractFlacPicture(bytes);
      }
      // 2. ID3 magic ('ID3')
      else if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
        rawImageBytes = _extractId3Apic(bytes);
      }

      if (rawImageBytes != null && rawImageBytes.length > 100) {
        await targetFile.writeAsBytes(rawImageBytes);
        return targetFile.path;
      }
    } catch (_) {}
    return null;
  }

  /// Extracts the picture data from FLAC METADATA_BLOCK_PICTURE (block type 6)
  static Uint8List? _extractFlacPicture(Uint8List bytes) {
    try {
      int offset = 4;
      bool isLastBlock = false;

      while (!isLastBlock && offset + 4 <= bytes.length) {
        final headerByte = bytes[offset];
        isLastBlock = (headerByte & 0x80) != 0;
        final blockType = headerByte & 0x7F;
        final blockLen = (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
        offset += 4;

        if (offset + blockLen > bytes.length) break;

        if (blockType == 6 && blockLen >= 32) {
          // PICTURE block
          int pOffset = offset;
          // 4 bytes: picture type
          pOffset += 4;
          // 4 bytes: MIME string length
          final mimeLen = _readUint32BE(bytes, pOffset);
          pOffset += 4 + mimeLen;
          // 4 bytes: description length
          final descLen = _readUint32BE(bytes, pOffset);
          pOffset += 4 + descLen;
          // 4 * 4 = 16 bytes: width, height, bit depth, colors
          pOffset += 16;
          // 4 bytes: picture data length
          final dataLen = _readUint32BE(bytes, pOffset);
          pOffset += 4;

          if (pOffset + dataLen <= offset + blockLen) {
            return bytes.sublist(pOffset, pOffset + dataLen);
          }
        }

        offset += blockLen;
      }
    } catch (_) {}
    return null;
  }

  /// Extracts the image data from ID3v2 APIC frame
  static Uint8List? _extractId3Apic(Uint8List bytes) {
    try {
      final versionMajor = bytes[3]; // 3 = ID3v2.3, 4 = ID3v2.4
      final tagSize = ((bytes[6] & 0x7F) << 21) |
          ((bytes[7] & 0x7F) << 14) |
          ((bytes[8] & 0x7F) << 7) |
          (bytes[9] & 0x7F);

      final limit = (10 + tagSize).clamp(10, bytes.length);
      int pos = 10;

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

        if (frameId == 'APIC' && frameSize > 32) {
          final frame = bytes.sublist(pos, pos + frameSize);
          return _parseApicPayload(frame);
        }

        pos += frameSize;
      }
    } catch (_) {}
    return null;
  }

  static Uint8List? _parseApicPayload(Uint8List frame) {
    try {
      if (frame.length <= 16) return null;
      final encoding = frame[0];
      int p = 1;

      // Find null terminator for MIME type (always 1-byte 0x00)
      while (p < frame.length && frame[p] != 0) {
        p++;
      }
      p++; // skip null terminator

      if (p >= frame.length) return null;
      // Skip picture type byte (1 byte)
      p++;

      // Skip description string
      if (encoding == 0 || encoding == 3) {
        // 1-byte null terminator
        while (p < frame.length && frame[p] != 0) {
          p++;
        }
        p++;
      } else {
        // 2-byte null terminator for UTF-16
        while (p + 1 < frame.length && (frame[p] != 0 || frame[p + 1] != 0)) {
          p += 2;
        }
        p += 2;
      }

      if (p >= frame.length) return null;

      // Locate JPEG (FF D8 FF) or PNG (89 50 4E 47) magic headers
      for (int i = p; i < (p + 32).clamp(0, frame.length - 4); i++) {
        if (frame[i] == 0xFF && frame[i + 1] == 0xD8 && frame[i + 2] == 0xFF) {
          return frame.sublist(i);
        }
        if (frame[i] == 0x89 &&
            frame[i + 1] == 0x50 &&
            frame[i + 2] == 0x4E &&
            frame[i + 3] == 0x47) {
          return frame.sublist(i);
        }
      }

      return frame.sublist(p);
    } catch (_) {}
    return null;
  }

  static int _readUint32BE(Uint8List b, int offset) {
    if (offset + 4 > b.length) return 0;
    return (b[offset] << 24) |
        (b[offset + 1] << 16) |
        (b[offset + 2] << 8) |
        b[offset + 3];
  }
}
