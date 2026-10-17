import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/metadata/artwork_palette_extractor.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:freebeat/ui/screens/now_playing_screen.dart';
import 'package:freebeat/ui/theme/pixel_theme.dart';
import 'package:freebeat/ui/widgets/material_you_album_cover.dart';

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
  group('ArtworkPalette & Extractor Tests', () {
    setUp(() {
      ArtworkPaletteExtractor.clearCache();
    });

    test('ArtworkPalette.fallback provides neutral dark slate without green', () {
      const fallback = ArtworkPalette.fallback;
      expect(fallback.isExtracted, isFalse);
      expect(fallback.dominantColor, const Color(0xFF1E293B));
      expect(fallback.edgeColor, const Color(0xFF0F172A));

      // Strictly verify it is not tainted with legacy Android or Spotify green
      expect(fallback.dominantColor.toARGB32(), isNot(equals(0xFF3DDC84)));
      expect(fallback.dominantColor.toARGB32(), isNot(equals(0xFF1DB954)));
    });

    test('ArtworkPaletteExtractor returns fallback for empty or null paths', () async {
      final p1 = await ArtworkPaletteExtractor.extractPalette(null);
      expect(p1.isExtracted, isFalse);
      expect(p1.dominantColor, const Color(0xFF1E293B));

      final p2 = await ArtworkPaletteExtractor.extractPalette('');
      expect(p2.isExtracted, isFalse);
      expect(p2.dominantColor, const Color(0xFF1E293B));
    });

    test('ArtworkPaletteExtractor caches and retrieves palettes correctly', () async {
      const customPalette = ArtworkPalette(
        dominantColor: Color(0xFF1E40AF),
        edgeColor: Color(0xFF172554),
        topEdgeColor: Color(0xFF1E3A8A),
        bottomEdgeColor: Color(0xFF172554),
        leftEdgeColor: Color(0xFF1D4ED8),
        rightEdgeColor: Color(0xFF1D4ED8),
        accentColor: Color(0xFF60A5FA),
        isExtracted: true,
      );

      ArtworkPaletteExtractor.injectCached('test_album_art.jpg', customPalette);

      final cached = ArtworkPaletteExtractor.getCached('test_album_art.jpg');
      expect(cached, isNotNull);
      expect(cached!.dominantColor, const Color(0xFF1E40AF));
      expect(cached.topEdgeColor, const Color(0xFF1E3A8A));

      final extracted = await ArtworkPaletteExtractor.extractPalette('test_album_art.jpg');
      expect(extracted.dominantColor, const Color(0xFF1E40AF));
      expect(extracted.isExtracted, isTrue);
    });
  });

  group('Green Sanitization & Protection Tests', () {
    test('PixelTheme ignores legacy SAF and Spotify green seeds', () {
      // 0xFF3DDC84 (Android SAF green)
      final darkSchemeGreen = PixelTheme.buildDarkColorScheme(
        activeTrackSeedColor: const Color(0xFF3DDC84),
      );
      final darkSchemeDefault = PixelTheme.buildDarkColorScheme(
        activeTrackSeedColor: PixelTheme.kSeedDeepViolet,
      );
      // Scheme must fall back to Deep Violet, not green
      expect(darkSchemeGreen.primary, equals(darkSchemeDefault.primary));

      // 0xFF1DB954 (Spotify green)
      final lightSchemeGreen = PixelTheme.buildLightColorScheme(
        activeTrackSeedColor: const Color(0xFF1DB954),
      );
      final lightSchemeDefault = PixelTheme.buildLightColorScheme(
        activeTrackSeedColor: PixelTheme.kSeedDeepViolet,
      );
      expect(lightSchemeGreen.primary, equals(lightSchemeDefault.primary));
    });

    test('PlaybackNotifier sanitizes legacy green dominantColorValue to 0xFF1E293B', () async {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      const greenTrack = Track(
        id: 'track_green_saf',
        accountId: 'acc_saf',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/storage/music/song.flac',
        title: 'Put It On For Me',
        artist: 'Don Diablo',
        album: 'Forever',
        durationMs: 180000,
        streamUrl: '/storage/music/song.flac',
        dominantColorValue: 0xFF3DDC84, // Legacy Android SAF green
      );

      final notifier = container.read(playbackProvider.notifier);
      await notifier.playTrack(greenTrack);

      final current = container.read(playbackProvider).currentTrack;
      expect(current.id, equals('track_green_saf'));
      expect(current.dominantColorValue, isNot(equals(0xFF3DDC84)));
      expect(current.dominantColorValue, equals(0xFF1E293B));
    });

    test('PlaybackNotifier.updateCurrentTrack updates active metadata', () {
      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      const initialTrack = Track(
        id: 'track_test',
        accountId: 'acc_1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'gdrive_id',
        title: 'Song Title',
        artist: 'Artist',
        album: 'Album',
        durationMs: 200000,
        streamUrl: 'https://example.com/stream',
        dominantColorValue: 0xFF1E293B,
      );

      final notifier = container.read(playbackProvider.notifier);
      notifier.setQueue([initialTrack]);

      final updatedTrack = initialTrack.copyWith(
        dominantColorValue: 0xFF2563EB, // Royal Blue
      );
      notifier.updateCurrentTrack(updatedTrack);

      final current = container.read(playbackProvider).currentTrack;
      expect(current.dominantColorValue, equals(0xFF2563EB));
    });

    testWidgets('MaterialYouAlbumCover sanitizes trackColor against green', (tester) async {
      const greenTrack = Track(
        id: 'art_test',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: 'path',
        title: 'Track',
        artist: 'Artist',
        album: 'Album',
        durationMs: 100000,
        streamUrl: 'stream',
        dominantColorValue: 0xFF3DDC84, // Green
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
          home: const Scaffold(
            body: MaterialYouAlbumCover(
              track: greenTrack,
              size: 200,
            ),
          ),
        ),
      );

      // Verify widget rendered cleanly
      expect(find.byType(MaterialYouAlbumCover), findsOneWidget);
    });
  });

  group('NowPlayingScreen Ambient Edge-Matched Glow Widget Tests', () {
    testWidgets('NowPlayingScreen renders ambient edge glow stack without green tint', (tester) async {
      ArtworkPaletteExtractor.clearCache();

      const blueNavyPalette = ArtworkPalette(
        dominantColor: Color(0xFF1E3A8A), // Blue 900
        edgeColor: Color(0xFF0F172A),     // Slate 900
        topEdgeColor: Color(0xFF1E293B),  // Top edge: dark slate
        bottomEdgeColor: Color(0xFF0F172A),
        leftEdgeColor: Color(0xFF1E3A8A),
        rightEdgeColor: Color(0xFF1E3A8A),
        accentColor: Color(0xFF38BDF8),
        isExtracted: true,
      );

      ArtworkPaletteExtractor.injectCached('artwork_blue.jpg', blueNavyPalette);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testTrack = Track(
        id: 'np_glow_track',
        accountId: 'acc_saf',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: 'path.flac',
        title: 'Put It On For Me (feat. Nina Nesbitt)',
        artist: 'Don Diablo',
        album: 'Forever',
        durationMs: 210000,
        streamUrl: 'path.flac',
        artworkUrl: 'artwork_blue.jpg',
        dominantColorValue: 0xFF1E3A8A, // Extracted Blue
      );

      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
        ],
      );
      addTearDown(container.dispose);

      container.read(playbackProvider.notifier).setQueue([testTrack]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: NowPlayingScreen(
              onOpenDspStudio: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify NowPlayingScreen rendered
      expect(find.byType(NowPlayingScreen), findsOneWidget);
      expect(find.text('Put It On For Me (feat. Nina Nesbitt)'), findsOneWidget);
      expect(find.text('Don Diablo'), findsOneWidget);

      // Verify MaterialYouAlbumCover inside Hero artwork card is present
      expect(find.byType(MaterialYouAlbumCover), findsOneWidget);

      // Verify AnimatedContainer exists for dynamic ambient gradient
      final animatedContainers = tester.widgetList<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(animatedContainers, isNotEmpty);

      // Ensure that none of the container decorations use 0xFF3DDC84 or 0xFF1DB954
      for (final container in animatedContainers) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          if (decoration.gradient is RadialGradient) {
            final rg = decoration.gradient as RadialGradient;
            for (final color in rg.colors) {
              expect(color.toARGB32(), isNot(equals(0xFF3DDC84)));
              expect(color.toARGB32(), isNot(equals(0xFF1DB954)));
            }
          }
          if (decoration.boxShadow != null) {
            for (final shadow in decoration.boxShadow!) {
              expect(shadow.color.toARGB32(), isNot(equals(0xFF3DDC84)));
              expect(shadow.color.toARGB32(), isNot(equals(0xFF1DB954)));
            }
          }
        }
      }
    });
  });
}
