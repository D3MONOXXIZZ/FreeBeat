import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/providers/implementations/open_protocol_connectors.dart';
import 'package:freebeat/services/metadata/artwork_and_lyrics_service.dart';
import 'package:freebeat/services/metadata/range_tag_parser.dart';

void main() {
  group('RangeTagParser (ID3v2, FLAC & Filename Fallback)', () {
    test('Parses ID3v2.3 header frames (TIT2, TPE1, TALB)', () {
      List<int> makeFrame(String id, String text) {
        final textBytes = [3, ...utf8.encode(text)]; // 3 = UTF-8
        final len = textBytes.length;
        return [
          ...id.codeUnits,
          (len >> 24) & 0xFF,
          (len >> 16) & 0xFF,
          (len >> 8) & 0xFF,
          len & 0xFF,
          0,
          0,
          ...textBytes,
        ];
      }

      final payload = <int>[
        ...makeFrame('TIT2', 'Starlight Symphony'),
        ...makeFrame('TPE1', 'Pixel Orchestra'),
        ...makeFrame('TALB', 'Monet Expressions'),
      ];

      final size = payload.length;
      final header = <int>[
        0x49, 0x44, 0x33, // 'ID3'
        0x03, 0x00, // v2.3
        0x00, // flags
        (size >> 21) & 0x7F,
        (size >> 14) & 0x7F,
        (size >> 7) & 0x7F,
        size & 0x7F,
        ...payload,
      ];

      final meta = RangeTagParser.parseHeaderBytes(Uint8List.fromList(header));
      expect(meta.title, 'Starlight Symphony');
      expect(meta.artist, 'Pixel Orchestra');
      expect(meta.album, 'Monet Expressions');
    });

    test('Parses ID3v2.2 header frames (TT2, TP1, TAL)', () {
      List<int> makeV2Frame(String id, String text) {
        final textBytes = [3, ...utf8.encode(text)]; // UTF-8
        final len = textBytes.length;
        return [
          ...id.codeUnits,
          (len >> 16) & 0xFF,
          (len >> 8) & 0xFF,
          len & 0xFF,
          ...textBytes,
        ];
      }

      final payload = <int>[
        ...makeV2Frame('TT2', 'Retro Synth'),
        ...makeV2Frame('TP1', 'Vintage Wave'),
        ...makeV2Frame('TAL', 'Neon Nights'),
      ];

      final size = payload.length;
      final header = <int>[
        0x49, 0x44, 0x33, // 'ID3'
        0x02, 0x00, // v2.2
        0x00, // flags
        (size >> 21) & 0x7F,
        (size >> 14) & 0x7F,
        (size >> 7) & 0x7F,
        size & 0x7F,
        ...payload,
      ];

      final meta = RangeTagParser.parseHeaderBytes(Uint8List.fromList(header));
      expect(meta.title, 'Retro Synth');
      expect(meta.artist, 'Vintage Wave');
      expect(meta.album, 'Neon Nights');
    });

    test('Parses trailing 128-byte ID3v1 tag accurately', () {
      final v1Bytes = Uint8List(128);
      // 'TAG'
      v1Bytes[0] = 0x54;
      v1Bytes[1] = 0x41;
      v1Bytes[2] = 0x47;
      // Title: "Don Diablo Track" at offset 3 (30 bytes)
      final titleBytes = ascii.encode('Don Diablo Track');
      v1Bytes.setRange(3, 3 + titleBytes.length, titleBytes);
      // Artist: "Don Diablo" at offset 33 (30 bytes)
      final artistBytes = ascii.encode('Don Diablo');
      v1Bytes.setRange(33, 33 + artistBytes.length, artistBytes);
      // Album: "FUTURE" at offset 63 (30 bytes)
      final albumBytes = ascii.encode('FUTURE');
      v1Bytes.setRange(63, 63 + albumBytes.length, albumBytes);

      final meta = RangeTagParser.parseId3v1Bytes(v1Bytes);
      expect(meta.title, 'Don Diablo Track');
      expect(meta.artist, 'Don Diablo');
      expect(meta.album, 'FUTURE');
    });

    test('Filename parser does not hardcode Cloud Artist for non-hyphenated names', () {
      final parsed = RangeTagParser.parseFromFilename(
        '01 Put It On For Me (feat. Nina Nesbitt).mp3',
      );
      expect(parsed.title, 'Put It On For Me (feat. Nina Nesbitt)');
      expect(parsed.artist, isNull);
      expect(parsed.album, isNull);
    });

    test('Parses filename fallback accurately for Hi-Res FLAC', () {
      final parsed = RangeTagParser.parseFromFilename(
        '04 - Boards of Canada - Olson.flac',
      );
      expect(parsed.artist, 'Boards of Canada');
      expect(parsed.title, 'Olson');
      expect(parsed.codec, 'FLAC');
      expect(parsed.bitDepth, 24);
      expect(parsed.sampleRateHz, 96000);
    });

    test('Parses filename fallback accurately for WMA, M4A, ALAC, WAV, OGG, OPUS, AIFF, APE, DSD', () {
      final wma = RangeTagParser.parseFromFilename('01 - Enya - Only Time.wma');
      expect(wma.title, 'Only Time');
      expect(wma.artist, 'Enya');
      expect(wma.codec, 'WMA');
      expect(wma.sampleRateHz, 44100);

      final m4a = RangeTagParser.parseFromFilename('Daft Punk - Get Lucky.m4a');
      expect(m4a.title, 'Get Lucky');
      expect(m4a.artist, 'Daft Punk');
      expect(m4a.codec, 'M4A');

      final alac = RangeTagParser.parseFromFilename('Pink Floyd - Time.alac');
      expect(alac.title, 'Time');
      expect(alac.artist, 'Pink Floyd');
      expect(alac.codec, 'ALAC');
      expect(alac.bitDepth, 24);

      final wav = RangeTagParser.parseFromFilename('Hans Zimmer - Time.wav');
      expect(wav.title, 'Time');
      expect(wav.artist, 'Hans Zimmer');
      expect(wav.codec, 'WAV');
      expect(wav.bitDepth, 24);

      final ogg = RangeTagParser.parseFromFilename('Radiohead - Idioteque.ogg');
      expect(ogg.codec, 'OGG');

      final opus = RangeTagParser.parseFromFilename('Aphex Twin - Avril 14th.opus');
      expect(opus.codec, 'OPUS');
      expect(opus.sampleRateHz, 48000);

      final aiff = RangeTagParser.parseFromFilename('Miles Davis - So What.aiff');
      expect(aiff.codec, 'AIFF');
      expect(aiff.bitDepth, 24);

      final ape = RangeTagParser.parseFromFilename('Queen - Bohemian Rhapsody.ape');
      expect(ape.codec, 'APE');

      final dsd = RangeTagParser.parseFromFilename('Michael Jackson - Thriller.dsf');
      expect(dsd.codec, 'DSF');
      expect(dsd.bitDepth, 1);
      expect(dsd.sampleRateHz, 2822400);
    });

    test('Parses M4A / MP4 ftyp atom metadata correctly', () {
      // Create minimal M4A header with ftyp atom and M4A marker
      final m4aBytes = <int>[
        0x00, 0x00, 0x00, 0x20, // atom size: 32
        0x66, 0x74, 0x79, 0x70, // 'ftyp'
        0x4D, 0x34, 0x41, 0x20, // 'M4A '
        0x00, 0x00, 0x00, 0x00, // minor_version
        0x4D, 0x34, 0x41, 0x20, // compatible_brands: 'M4A '
        0x6D, 0x70, 0x34, 0x32, // 'mp42'
        0x69, 0x73, 0x6F, 0x6D, // 'isom'
        0x00, 0x00, 0x00, 0x00,
      ];
      final meta = RangeTagParser.parseHeaderBytes(Uint8List.fromList(m4aBytes));
      expect(meta.codec, 'AAC');
    });

    test('Parses ASF / WMA header GUID correctly', () {
      // 16-byte ASF Header Object GUID: 30 26 B2 75 8E 66 CF 11 A6 D9 00 AA 00 62 CE 6C
      final asfBytes = <int>[
        0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11,
        0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      ];
      final meta = RangeTagParser.parseHeaderBytes(Uint8List.fromList(asfBytes));
      expect(meta.codec, 'WMA');
    });

    test('Parses WAV RIFF header correctly', () {
      // Minimal RIFF WAVE fmt chunk
      final wavBytes = <int>[
        0x52, 0x49, 0x46, 0x46, // 'RIFF'
        0x24, 0x00, 0x00, 0x00, // file size - 8
        0x57, 0x41, 0x56, 0x45, // 'WAVE'
        0x66, 0x6D, 0x74, 0x20, // 'fmt '
        0x10, 0x00, 0x00, 0x00, // chunk size: 16
        0x01, 0x00,             // audio format: 1 (PCM)
        0x02, 0x00,             // num channels: 2
        0x44, 0xAC, 0x00, 0x00, // sample rate: 44100
        0x10, 0xB1, 0x02, 0x00, // byte rate: 176400
        0x04, 0x00,             // block align: 4
        0x10, 0x00,             // bits per sample: 16
      ];
      final meta = RangeTagParser.parseHeaderBytes(Uint8List.fromList(wavBytes));
      expect(meta.codec, 'WAV');
      expect(meta.sampleRateHz, 44100);
      expect(meta.bitDepth, 16);
    });
  });

  group('S3 SigV4, WebDAV PROPFIND & Synced LRC Lyrics', () {
    test('Generates deterministic AWS SigV4 presigned URL for S3 / R2', () {
      final url = S3CompatibleConnector.generatePresignedGetUrl(
        endpointHost: 'https://s3.r2.cloudflarestorage.com',
        bucket: 'hifi-vault',
        objectKey: 'masters/track01.flac',
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        region: 'auto',
        nowUtc: DateTime.utc(2026, 10, 12, 0, 0, 0),
      );
      expect(url, contains('X-Amz-Algorithm=AWS4-HMAC-SHA256'));
      expect(url, contains('X-Amz-Signature='));
      expect(url, contains('/hifi-vault/masters/track01.flac'));
    });

    test('Parses WebDAV PROPFIND 207 Multi-Status XML into Track catalog', () {
      const xml = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/remote.php/dav/files/user/Music/01%20-%20Tycho%20-%20Awake.flac</d:href>
  </d:response>
</d:multistatus>''';

      const acc = CloudAccount(
        id: 'nc_1',
        providerType: CloudProviderType.webdav,
        displayName: 'Nextcloud Hi-Fi',
        endpointOrFolder: 'https://nextcloud.local/remote.php/dav/files/user/Music',
      );

      final tracks = WebDavConnector.parsePropfindXml(
        xmlBody: xml,
        account: acc,
      );
      expect(tracks.length, 1);
      expect(tracks.first.artist, 'Tycho');
      expect(tracks.first.title, 'Awake');
      expect(tracks.first.codec, 'FLAC');
    });

    test('Parses LRC synchronized lyrics timestamps in milliseconds', () {
      const lrc = '''
[00:05.50] First line of synced lyrics
[01:12.05] Second line after chorus
''';
      final lines = ArtworkAndLyricsService.parseLrcContent(lrc);
      expect(lines.length, 2);
      expect(lines[0].timestampMs, 5500);
      expect(lines[0].text, 'First line of synced lyrics');
      expect(lines[1].timestampMs, 72050);
    });
  });
}
