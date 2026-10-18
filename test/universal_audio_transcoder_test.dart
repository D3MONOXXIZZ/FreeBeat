import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/audio/universal_audio_transcoder_service.dart';

Track makeTestTrack({
  required String id,
  required String title,
  String artist = 'Test Artist',
  String album = 'Test Album',
  String streamUrl = '',
  String codec = 'WMA',
}) {
  return Track(
    id: id,
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'path/$id',
    title: title,
    artist: artist,
    album: album,
    durationMs: 180000,
    streamUrl: streamUrl,
    codec: codec,
  );
}

void main() {
  group('UniversalAudioTranscoderService Tests', () {
    test('requiresTranscoding accurately detects WMA and ASF formats across all fields', () {
      final wmaTrackByCodec = makeTestTrack(
        id: 'wma_1',
        title: 'Only Time',
        artist: 'Enya',
        album: 'A Day Without Rain',
        streamUrl: 'https://cloud.example.com/stream/track1',
        codec: 'WMA',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(wmaTrackByCodec), isTrue);

      final asfTrackByCodec = makeTestTrack(
        id: 'asf_1',
        title: 'Ambient Flow',
        artist: 'Brian Eno',
        streamUrl: 'https://cloud.example.com/stream/track2',
        codec: 'ASF',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(asfTrackByCodec), isTrue);

      final wmaTrackByStreamUrl = makeTestTrack(
        id: 'wma_2',
        title: 'Song',
        artist: 'Artist',
        streamUrl: '/storage/emulated/0/Music/MySong.wma',
        codec: '',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(wmaTrackByStreamUrl), isTrue);

      final wmaTrackBySafUri = makeTestTrack(
        id: 'wma_3',
        title: 'Document.wma',
        artist: 'Artist',
        streamUrl: 'content://com.android.providers.media.documents/document/audio%3A999',
        codec: '',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(wmaTrackBySafUri), isTrue);

      final wmaTrackByEffectivePath = makeTestTrack(
        id: 'wma_4',
        title: 'Local File',
        artist: 'Artist',
        streamUrl: 'content://generic/id',
        codec: '',
      );
      expect(
        UniversalAudioTranscoderService.requiresTranscoding(
          wmaTrackByEffectivePath,
          '/data/user/0/com.freebeat.freebeat/cache/song.wma',
        ),
        isTrue,
      );

      // Verify non-WMA formats do not trigger transcoding
      final flacTrack = makeTestTrack(
        id: 'flac_1',
        title: 'Olson',
        artist: 'Boards of Canada',
        streamUrl: '/music/olson.flac',
        codec: 'FLAC',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(flacTrack), isFalse);

      final mp3Track = makeTestTrack(
        id: 'mp3_1',
        title: 'Get Lucky',
        artist: 'Daft Punk',
        streamUrl: 'https://drive.google.com/get_lucky.mp3',
        codec: 'MP3',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(mp3Track), isFalse);

      final m4aTrack = makeTestTrack(
        id: 'm4a_1',
        title: 'Starboy',
        artist: 'The Weeknd',
        streamUrl: 'content://media/audio/1234.m4a',
        codec: 'AAC',
      );
      expect(UniversalAudioTranscoderService.requiresTranscoding(m4aTrack), isFalse);
    });

    test('Transcoder handles empty sourcePath gracefully', () async {
      final transcoder = UniversalAudioTranscoderService();
      final track = makeTestTrack(
        id: 'empty_track',
        title: 'Empty',
        streamUrl: '',
        codec: 'WMA',
      );

      final res = await transcoder.transcodeToWav(track: track, sourcePath: '');
      expect(res, isNull);
    });
  });
}
