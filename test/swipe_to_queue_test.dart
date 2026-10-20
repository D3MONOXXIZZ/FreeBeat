import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/artist_details_screen.dart';
import 'package:freebeat/ui/screens/library_screen.dart';
import 'package:freebeat/ui/screens/playlist_details_screen.dart';
import 'package:freebeat/ui/widgets/swipe_to_queue_wrapper.dart';

class _FakeCloudStreamProxy extends CloudStreamProxy {
  _FakeCloudStreamProxy()
      : super(
          connectorRegistry: CloudConnectorRegistry(),
          credentialStore: SecureCredentialStore(),
        );

  @override
  Future<void> start() async {}
}

final List<MethodCall> hapticCalls = [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.freebeat.app/dsp'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'triggerPixelHaptic') {
          hapticCalls.add(methodCall);
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async => null,
    );
  });

  const testTrack1 = Track(
    id: 'test_track_1',
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'file_1',
    title: 'Comfortably Numb',
    artist: 'Pink Floyd',
    album: 'The Wall',
    durationMs: 382000,
    streamUrl: 'https://example.com/numb.flac',
    bitDepth: 24,
    sampleRateHz: 96000,
    codec: 'FLAC',
  );

  const testTrack2 = Track(
    id: 'test_track_2',
    accountId: 'acc_1',
    providerType: CloudProviderType.googleDrive,
    remotePathOrId: 'file_2',
    title: 'Wish You Were Here',
    artist: 'Pink Floyd',
    album: 'Wish You Were Here',
    durationMs: 334000,
    streamUrl: 'https://example.com/wish.flac',
    bitDepth: 24,
    sampleRateHz: 192000,
    codec: 'FLAC',
  );

  Widget createTestWidget({
    required Widget child,
    List<Track> initialTracks = const [testTrack1, testTrack2],
  }) {
    return ProviderScope(
      overrides: [
        cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        tracksCatalogProvider.overrideWith((ref) {
          final notifier = TracksCatalogNotifier(null, null);
          notifier.state = initialTracks;
          return notifier;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: child,
        ),
      ),
    );
  }

  group('SwipeToQueueWrapper Widget Tests', () {
    testWidgets(
      'Swiping right adds track to queue, triggers snackbar, and snaps back into place',
      (tester) async {
        await tester.pumpWidget(
          createTestWidget(
            child: Consumer(
              builder: (context, ref, _) {
                return ListView(
                  children: [
                    SwipeToQueueWrapper(
                      track: testTrack1,
                      child: const ListTile(
                        key: ValueKey('tile_1'),
                        title: Text('Comfortably Numb'),
                        subtitle: Text('Pink Floyd'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially tile is rendered
        expect(find.text('Comfortably Numb'), findsOneWidget);

        // Perform swipe right drag on the tile
        await tester.drag(find.byKey(const ValueKey('tile_1')), const Offset(400, 0));
        await tester.pumpAndSettle();

        // 1. Verify confirmation SnackBar is visible
        expect(find.text('Added "Comfortably Numb" to queue'), findsOneWidget);

        // 2. Verify track tile is STILL present in the list (snapped back, not dismissed)
        expect(find.text('Comfortably Numb'), findsOneWidget);
        expect(find.byKey(const ValueKey('tile_1')), findsOneWidget);
      },
    );

    testWidgets(
      'Swipe right in ArtistDetailsScreen adds track to queue',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          createTestWidget(
            child: const ArtistDetailsScreen(artistName: 'Pink Floyd'),
            initialTracks: [testTrack1, testTrack2],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Comfortably Numb'), findsOneWidget);

        // Drag first track right
        await tester.drag(find.text('Comfortably Numb'), const Offset(350, 0));
        await tester.pumpAndSettle();

        // SnackBar appears
        expect(find.text('Added "Comfortably Numb" to queue'), findsOneWidget);
        // Track still exists
        expect(find.text('Comfortably Numb'), findsOneWidget);
      },
    );

    testWidgets(
      'Swipe gestures in PlaylistDetailsScreen: right adds to queue and left deletes',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
        });

        final playlist = Playlist(
          id: 'test_pl_1',
          title: 'Rock Classics',
          trackIds: [testTrack1.id, testTrack2.id],
          isSmart: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
              tracksCatalogProvider.overrideWith((ref) {
                final notifier = TracksCatalogNotifier(null, null);
                notifier.state = [testTrack1, testTrack2];
                return notifier;
              }),
              playlistsProvider.overrideWith((ref) {
                final notifier = PlaylistsNotifier(null);
                notifier.state = [playlist];
                return notifier;
              }),
            ],
            child: MaterialApp(
              home: PlaylistDetailsScreen(playlist: playlist),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify tracks appear
        expect(find.text('Comfortably Numb'), findsOneWidget);
        expect(find.text('Wish You Were Here'), findsOneWidget);

        // Swipe right on track 1 to queue
        await tester.drag(find.text('Comfortably Numb'), const Offset(350, 0));
        await tester.pumpAndSettle();

        // Should show queue snackbar and remain in playlist
        expect(find.text('Added "Comfortably Numb" to queue'), findsOneWidget);
        expect(find.text('Comfortably Numb'), findsOneWidget);

        // Swipe left on track 2 to remove from playlist
        await tester.drag(find.text('Wish You Were Here'), const Offset(-600, 0));
        await tester.pumpAndSettle();

        // Track 2 should be dismissed/removed from playlist
        expect(find.text('Wish You Were Here'), findsNothing);
      },
    );

    testWidgets(
      'Swipe right in LibraryScreen adds track to queue with snackbar feedback',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
              tracksCatalogProvider.overrideWith((ref) {
                final notifier = TracksCatalogNotifier(null, null);
                notifier.state = [testTrack1, testTrack2];
                return notifier;
              }),
            ],
            child: const MaterialApp(
              home: LibraryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Comfortably Numb'), findsOneWidget);

        // Swipe right on track 1
        await tester.drag(find.text('Comfortably Numb'), const Offset(350, 0));
        await tester.pumpAndSettle();

        // Confirmation SnackBar appears
        expect(find.text('Added "Comfortably Numb" to queue'), findsOneWidget);
        // Track still present in library
        expect(find.text('Comfortably Numb'), findsOneWidget);
      },
    );

    testWidgets(
      'Swipe gesture triggers progressive load-up ticks and click when fully swiped',
      (tester) async {
        hapticCalls.clear();

        await tester.pumpWidget(
          createTestWidget(
            child: ListView(
              children: [
                SwipeToQueueWrapper(
                  track: testTrack1,
                  child: const ListTile(
                    key: ValueKey('haptic_tile'),
                    title: Text('Comfortably Numb'),
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Perform gradual drag
        final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('haptic_tile'))));
        
        // Drag in small increments to trigger progressive milestones
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 40));
        
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump(const Duration(milliseconds: 40));

        await gesture.moveBy(const Offset(80, 0));
        await tester.pump(const Duration(milliseconds: 40));

        // Move past threshold (raw > 180dp)
        await gesture.moveBy(const Offset(100, 0));
        await tester.pump(const Duration(milliseconds: 40));

        await gesture.up();
        await tester.pumpAndSettle();

        // Verify that low_tick (load-up) and swipe_click (full swipe) were called
        final types = hapticCalls.map((c) => c.arguments['type'] as String?).toList();
        expect(types.contains('low_tick'), isTrue, reason: 'Must emit progressive load-up ticks while swiping');
        expect(types.contains('swipe_click'), isTrue, reason: 'Must emit click haptic when fully swiped past threshold');
        expect(types.contains('hifi_confirm'), isTrue, reason: 'Must confirm queued action on release');
      },
    );
  });
}
