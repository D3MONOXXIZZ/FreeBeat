// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/services/audio/missing_track_audio_resolver.dart';
import 'package:freebeat/services/engine/track_resolution_gateway.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    HttpOverrides.global = null;
  });

  test('Verify Where\'d U Go resolves successfully', () async {
    final resolver = MissingTrackAudioResolver();
    final candidate = await resolver.resolveTrackAudio(
      title: "Where'd U Go",
      artist: "ILLENIUM, Said The Sky",
      expectedDurationMs: 184556,
    );

    expect(candidate, isNotNull);
    print('Where\'d U Go -> "${candidate!.sourceTitle}" by "${candidate.channelOrArtist}" [${candidate.bitrateKbps}kbps, ${candidate.format}]');
    expect(candidate.isFullLength, isTrue);
    expect(candidate.durationMs, greaterThan(45000));
    expect(candidate.bitrateKbps, greaterThan(100));
    resolver.close();
  });

  test('Verify all 13 tracks of Awake album resolve via TrackResolutionGateway', () async {
    final albumUrl = 'https://open.spotify.com/album/7A9I9BrNylVCqXzgN3Y6qi';
    final service = PlaylistImportService();
    final res = await service.importFromUrl(albumUrl, []);

    expect(res.missingTracks.length, 13);
    final gateway = TrackResolutionGateway();

    var successCount = 0;
    for (var i = 0; i < res.missingTracks.length; i++) {
      final item = res.missingTracks[i];
      final bundle = await gateway.resolveAudioBundle(
        title: item.title,
        artist: item.artist,
        expectedDurationMs: item.expectedDurationMs,
        preferredArtworkUrl: item.preferredArtworkUrl,
        preferredAlbum: item.album,
      );

      if (bundle != null) {
        successCount++;
        print('[$i/13] SUCCESS: "${bundle.title}" by "${bundle.artist}" -> [${bundle.bitrateKbps}kbps ${bundle.audioCodec}, Master: ${bundle.isStudioMaster}]');
      } else {
        print('[$i/13] FAILED: "${item.displayName}"');
      }
    }

    print('Total Awake album tracks resolved: $successCount / 13');
    expect(successCount, 13);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
