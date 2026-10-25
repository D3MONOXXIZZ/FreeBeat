import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/audio/poweramp_dsp_service.dart';
import 'package:freebeat/state/app_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> dspCalls = [];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getAll') return <String, dynamic>{};
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async {
        dspCalls.add(methodCall);
        if (methodCall.method == 'getAudioRouteInfo') {
          return {
            'deviceName': 'Google Pixel Buds Pro (LDAC)',
            'routeType': 'BLUETOOTH',
            'bluetoothCodecName': 'LDAC 990kbps 96kHz/24bit',
            'hardwareSampleRateHz': 96000,
            'hardwareBitDepth': 24,
            'hardwareBufferFrames': 256,
            'isBluetooth': true,
            'isUsbDac': false,
            'dspEngineMode': 'DynamicsProcessing 64-bit Hardware',
          };
        }
        return true;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
  });

  setUp(() {
    dspCalls.clear();
  });

  const testTrack = Track(
    id: 'notif_track_1',
    accountId: 'acc_saf',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: 'content://media/external/audio/media/100',
    title: 'Starboy',
    artist: 'The Weeknd',
    album: 'Starboy',
    durationMs: 230000,
    streamUrl: 'content://media/external/audio/media/100',
    codec: 'FLAC',
    bitDepth: 24,
    sampleRateHz: 96000,
    bitrateKbps: 1411,
    sizeBytes: 40000000,
    dominantColorValue: 0xFFEF4444, // Vibrant Red Monet seed
  );

  test('PowerampDspService foreground playback methods invoke platform channel correctly', () async {
    final dspService = PowerampDspService();

    // 1. Start foreground playback
    await dspService.startForegroundPlayback(
      title: testTrack.title,
      artist: testTrack.artist,
      album: testTrack.album,
      durationMs: testTrack.durationMs,
      positionMs: 45000,
      isPlaying: true,
      volume: 0.9,
      dominantColor: testTrack.dominantColorValue,
      outputDevice: 'Google Pixel Buds Pro (LDAC)',
    );

    expect(
      dspCalls.any((call) =>
          call.method == 'startForegroundPlayback' &&
          call.arguments['title'] == 'Starboy' &&
          call.arguments['artist'] == 'The Weeknd' &&
          call.arguments['dominantColor'] == 0xFFEF4444 &&
          call.arguments['outputDevice'] == 'Google Pixel Buds Pro (LDAC)'),
      isTrue,
    );

    // 2. Update notification
    await dspService.updatePlaybackNotification(
      positionMs: 50000,
      isPlaying: false,
      volume: 0.8,
    );

    expect(
      dspCalls.any((call) =>
          call.method == 'updatePlaybackNotification' &&
          call.arguments['positionMs'] == 50000 &&
          call.arguments['isPlaying'] == false &&
          call.arguments['volume'] == 0.8),
      isTrue,
    );

    // 3. Stop foreground playback
    await dspService.stopForegroundPlayback();
    expect(
      dspCalls.any((call) => call.method == 'stopForegroundPlayback'),
      isTrue,
    );
  });

  test('PowerampDspService setNotificationActionListener receives and parses actions cleanly', () async {
    final dspService = PowerampDspService();
    String? receivedAction;
    Map<String, dynamic>? receivedExtras;

    dspService.setNotificationActionListener((action, extras) {
      receivedAction = action;
      receivedExtras = extras;
    });

    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // 1. onPlayPause
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onPlayPause',
          'extras': {'isPlaying': true},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onPlayPause'));
    expect(receivedExtras?['isPlaying'], equals(true));

    // 2. onNext
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onNext',
          'extras': <String, dynamic>{},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onNext'));

    // 3. onPrevious
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onPrevious',
          'extras': <String, dynamic>{},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onPrevious'));

    // 4. onSeek
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onSeek',
          'extras': {'positionMs': 75000},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onSeek'));
    expect(receivedExtras?['positionMs'], equals(75000));

    // 5. onVolume
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onVolume',
          'extras': {'volume': 0.85},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onVolume'));
    expect(receivedExtras?['volume'], equals(0.85));

    // 6. onShuffle
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onShuffle',
          'extras': {'isShuffle': true},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onShuffle'));
    expect(receivedExtras?['isShuffle'], equals(true));

    // 7. onRepeat
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onRepeat',
          'extras': {'repeatMode': 1},
        }),
      ),
      (data) {},
    );
    expect(receivedAction, equals('onRepeat'));
    expect(receivedExtras?['repeatMode'], equals(1));
  });

  test('PowerampDspProvider propagates device output route to notification', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial route check
    final route = container.read(audioRouteInfoProvider);
    expect(route.deviceName, contains('Pixel Built-in Stereo Speakers'));

    // Updating playback notification with route info
    final dspService = container.read(powerampDspServiceProvider);
    await dspService.updatePlaybackNotification(
      outputDevice: 'Sony WH-1000XM5 (LDAC)',
      dominantColor: 0xFFEF4444,
      isPlaying: true,
    );

    expect(
      dspCalls.any((call) =>
          call.method == 'updatePlaybackNotification' &&
          call.arguments['outputDevice'] == 'Sony WH-1000XM5 (LDAC)' &&
          call.arguments['dominantColor'] == 0xFFEF4444 &&
          call.arguments['isPlaying'] == true),
      isTrue,
    );
  });

  test('PowerampDspService allows simultaneous notification and battery listeners without handler collision', () async {
    final dspService = PowerampDspService();
    String? lastAction;
    Map<String, dynamic>? lastBattery;

    dspService.setNotificationActionListener((action, extras) {
      lastAction = action;
    });

    dspService.setBatteryStateListener((batteryMap) {
      lastBattery = batteryMap;
    });

    final binaryMessenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // Send onNotificationAction
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onPlayPause',
          'extras': {'isPlaying': false},
        }),
      ),
      (data) {},
    );
    expect(lastAction, equals('onPlayPause'));

    // Send onBatteryStateChanged
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onBatteryStateChanged', {
          'batteryLevel': 85,
          'isCharging': true,
          'isPowerSaveMode': false,
        }),
      ),
      (data) {},
    );
    expect(lastBattery?['batteryLevel'], equals(85));
    expect(lastBattery?['isCharging'], equals(true));

    // Send another notification action to verify notification handler remains active
    await binaryMessenger.handlePlatformMessage(
      'com.freebeat.app/dsp',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onNotificationAction', {
          'action': 'onNext',
          'extras': <String, dynamic>{},
        }),
      ),
      (data) {},
    );
    expect(lastAction, equals('onNext'));
  });

  test('PlaybackNotifier resyncWithActivePlayer reconciles state safely', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(playbackProvider.notifier);
    notifier.setQueue([testTrack]);

    // Simulate resync
    await notifier.resyncWithActivePlayer();

    final state = container.read(playbackProvider);
    expect(state.queue.length, equals(1));
    expect(state.queue.first.id, equals(testTrack.id));
  });
}
