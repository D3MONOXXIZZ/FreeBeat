import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testDir = Directory.systemTemp.createTempSync('freebeat_playlist_sync_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => testDir.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/pixel_haptics'),
      (MethodCall methodCall) async => null,
    );
  });

  tearDown(() {
    try {
      if (testDir.existsSync()) {
        testDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Track createSampleTrack(String id, String title) {
    return Track(
      id: id,
      title: title,
      artist: 'Test Artist',
      album: 'Test Album',
      durationMs: 180000,
      streamUrl: 'http://example.com/$id.mp3',
      remotePathOrId: 'cloud_files/$id.mp3',
      accountId: 'acc1',
      providerType: CloudProviderType.googleDrive,
      sizeBytes: 5000000,
      dominantColorValue: 0xFF1E293B,
    );
  }

  test('Playing a track from a playlist updates currentTrack to the chosen track and queue to playlist', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final trackA = createSampleTrack('track_outside', 'Outside Song');
    final playlistTrack1 = createSampleTrack('pl_1', 'Playlist Song 1');
    final playlistTrack2 = createSampleTrack('pl_2', 'Playlist Song 2');
    final playlistTrack3 = createSampleTrack('pl_3', 'Playlist Song 3');
    final playlistTracks = [playlistTrack1, playlistTrack2, playlistTrack3];

    final notifier = container.read(playbackProvider.notifier);

    // 1. Initially play a track outside the playlist
    await notifier.playTrack(trackA);
    expect(container.read(playbackProvider).currentTrack.id, 'track_outside');

    // 2. Tap track #2 from the playlist
    await notifier.playTrack(playlistTrack2, newQueue: playlistTracks);

    final state = container.read(playbackProvider);
    // currentTrack must immediately and firmly be Playlist Song 2!
    expect(state.currentTrack.id, 'pl_2');
    expect(state.currentTrack.title, 'Playlist Song 2');
    expect(state.queue.map((t) => t.id).toList(), ['pl_1', 'pl_2', 'pl_3']);
    expect(state.isPlaying, isTrue);

    // 3. Tap track #3 from the same playlist
    await notifier.playTrack(playlistTrack3, newQueue: playlistTracks);
    final state2 = container.read(playbackProvider);
    expect(state2.currentTrack.id, 'pl_3');
    expect(state2.currentTrack.title, 'Playlist Song 3');
  });

  test('resyncWithActivePlayer does not clobber currentTrack with queue[0] when not playing concatenating source', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final playlistTrack1 = createSampleTrack('pl_1', 'Playlist Song 1');
    final playlistTrack2 = createSampleTrack('pl_2', 'Playlist Song 2');
    final playlistTracks = [playlistTrack1, playlistTrack2];

    final notifier = container.read(playbackProvider.notifier);
    await notifier.playTrack(playlistTrack2, newQueue: playlistTracks);

    // Simulate resync when app returns to foreground
    await notifier.resyncWithActivePlayer();

    final state = container.read(playbackProvider);
    expect(state.currentTrack.id, 'pl_2');
  });
}
