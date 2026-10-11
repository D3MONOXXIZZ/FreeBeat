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
