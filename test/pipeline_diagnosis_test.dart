// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/services/audio/missing_track_audio_resolver.dart';
import 'package:freebeat/services/audio/track_audio_tagger_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null; // Enable real network requests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
  });

  test('LIVE PRODUCTION SERVICE TEST: Resolver + Tagger on Real Playlist Tracks', () async {
    final resolver = MissingTrackAudioResolver();
    final tagger = TrackAudioTaggerService();

    final testSongs = [
      {'title': 'City to City', 'artist': 'PenguKing'},
      {'title': 'Dastaan', 'artist': 'Abdullah Qureshi'},
      {'title': 'Tu Kahan', 'artist': 'umair'},
      {'title': 'Na Milay', 'artist': 'Nescafé Basement'},
    ];

    for (final s in testSongs) {
      final title = s['title']!;
      final artist = s['artist']!;
      print('\n----------------------------------------');
      print('Resolving "$artist - $title"...');

      final candidate = await resolver.resolveTrackAudio(
        title: title,
        artist: artist,
      );

      expect(candidate, isNotNull, reason: 'Candidate should not be null for "$artist - $title"');
      print('  Resolved: "${candidate!.sourceTitle}" by "${candidate.channelOrArtist}"');
      print('  Format: ${candidate.format}, kbps: ${candidate.bitrateKbps}, duration: ${candidate.durationMs}ms');
      print('  Stream URL: ${candidate.streamUrl.substring(0, candidate.streamUrl.length.clamp(0, 60))}...');

      print('  Downloading and tagging audio...');
      final prepared = await tagger.downloadAndPrepareAudio(
        candidate: candidate,
        targetTitle: title,
        targetArtist: artist,
        targetAlbum: 'Test Production Playlist',
        onProgress: (p) => stdout.write('\r    Download: ${(p * 100).toInt()}%'),
      );

      print('\n  Download Success! File size: ${prepared.sizeBytes} bytes (${(prepared.sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB)');
      expect(await prepared.file.exists(), isTrue);
      expect(prepared.sizeBytes, greaterThan(1000000)); // Greater than 1MB

      await prepared.purge();
      expect(await prepared.file.exists(), isFalse);
      print('  Scratch file purged successfully.');
    }

    resolver.close();
    print('\n========================================');
    print('ALL REAL PRODUCTION SERVICE TESTS PASSED!');
    print('========================================');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
