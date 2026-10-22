import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/library_screen.dart';

class _FakeCloudStreamProxy extends CloudStreamProxy {
  _FakeCloudStreamProxy()
      : super(
          connectorRegistry: CloudConnectorRegistry(),
          credentialStore: SecureCredentialStore(),
        );

  @override
  Future<void> start() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, Object> fakePrefs = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') return Map<String, Object>.from(fakePrefs);
        if (methodCall.method == 'setString') {
          fakePrefs[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as String;
          return true;
        }
        if (methodCall.method == 'setInt') {
          fakePrefs[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as int;
          return true;
        }
        if (methodCall.method == 'setBool') {
          fakePrefs[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as bool;
          return true;
        }
        if (methodCall.method == 'setStringList') {
          fakePrefs[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as List<dynamic>;
          return true;
        }
        if (methodCall.method == 'remove') {
          fakePrefs.remove(methodCall.arguments['key'] as String);
          return true;
        }
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'disposeAllPlayers') return <dynamic>[];
        return <String, dynamic>{};
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async => true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/pixel_haptics'),
      (MethodCall methodCall) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
  });

  setUp(() {
    fakePrefs.clear();
    SharedPreferences.setMockInitialValues(fakePrefs);
  });

  final track1 = const Track(
    id: 'track_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: 'content://audio/1',
    title: 'First Track',
    artist: 'Artist One',
    album: 'Album One',
    durationMs: 240000,
    streamUrl: 'content://audio/1',
  );

  final track2 = const Track(
    id: 'track_2',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: 'content://audio/2',
    title: 'Second Track (Last Played)',
    artist: 'Artist Two',
    album: 'Album Two',
    durationMs: 180000,
    streamUrl: 'content://audio/2',
  );

  final track3 = const Track(
    id: 'track_3',
    accountId: 'acc_1',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: 'content://audio/3',
    title: 'Third Track',
    artist: 'Artist Three',
    album: 'Album Three',
    durationMs: 200000,
    streamUrl: 'content://audio/3',
  );

  test('Playback state persistence and restoration restores last-played track and progress', () async {
    // 1. Simulate last saved playback state in SharedPreferences
    fakePrefs['playback_last_track_id'] = track2.id;
    fakePrefs['playback_last_track_json'] = jsonEncode(track2.toMap());
    fakePrefs['playback_last_pos_ms'] = 45000;
    fakePrefs['playback_last_queue_ids'] = [track2.id, track1.id, track3.id];
    fakePrefs['playback_last_shuffle'] = true;
    fakePrefs['playback_last_repeat_mode'] = 1;
    SharedPreferences.setMockInitialValues(fakePrefs);

    final container = ProviderContainer(
      overrides: [
        cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
      ],
    );

    final playbackNotifier = container.read(playbackProvider.notifier);
    await Future.delayed(const Duration(milliseconds: 100));
    final initialPlayback = container.read(playbackProvider);

    expect(initialPlayback.currentTrack.id, equals(track2.id));
    expect(initialPlayback.positionMs, equals(45000));
    expect(initialPlayback.isShuffle, isTrue);
    expect(initialPlayback.repeatMode, equals(1));

    // 2. Simulate TracksCatalogNotifier completing SQLite load and syncing with playback
    final catalog = [track1, track2, track3];
    await playbackNotifier.syncWithLoadedCatalog(catalog);

    final syncedPlayback = container.read(playbackProvider);
    // MUST NOT default to track 1!
    expect(syncedPlayback.currentTrack.id, equals(track2.id));
    expect(syncedPlayback.positionMs, equals(45000));
    expect(syncedPlayback.queue.map((t) => t.id).toList(), equals([track2.id, track1.id, track3.id]));

    container.dispose();
  });

  testWidgets('LibraryScreen renders Play All button in header and plays all tracks', (tester) async {
    final container = ProviderContainer(
      overrides: [
        cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
      ],
    );

    // Seed tracks
    await container.read(tracksCatalogProvider.notifier).addIndexedTracks([track1, track2, track3]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify "Play All" button is present in track list header next to "Select"
    final playAllFinder = find.widgetWithText(FilledButton, 'Play All');
    expect(playAllFinder, findsOneWidget);

    final selectFinder = find.widgetWithText(TextButton, 'Select');
    expect(selectFinder, findsOneWidget);

    // Tap "Play All"
    await tester.tap(playAllFinder);
    await tester.pump();

    final playback = container.read(playbackProvider);
    expect(playback.isPlaying, isTrue);
    expect(playback.currentTrack.id, equals(track1.id));
    expect(playback.queue.length, equals(3));

    // Clean up timer
    await container.read(playbackProvider.notifier).togglePlayPause();
    container.dispose();
  });

  testWidgets('LibraryScreen hamburger menu contains Play All Tracks option', (tester) async {
    final container = ProviderContainer(
      overrides: [
        cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
      ],
    );

    await container.read(tracksCatalogProvider.notifier).addIndexedTracks([track1, track2, track3]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open hamburger menu (icon: Icons.menu_rounded)
    final menuButton = find.byIcon(Icons.menu_rounded);
    expect(menuButton, findsOneWidget);

    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // Verify "Play All Tracks" menu item is present
    expect(find.text('Play All Tracks'), findsOneWidget);

    // Tap "Play All Tracks"
    await tester.tap(find.text('Play All Tracks'));
    await tester.pump();

    final playback = container.read(playbackProvider);
    expect(playback.isPlaying, isTrue);
    expect(playback.currentTrack.id, equals(track1.id));

    // Clean up timer
    await container.read(playbackProvider.notifier).togglePlayPause();
    container.dispose();
  });
}
