// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/playlist.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';
import 'package:freebeat/ui/widgets/generative_playlist_cover.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Spotify album import extracts official high-res album cover URL', () async {
    HttpOverrides.global = null;
    final service = PlaylistImportService();
    final res = await service.importFromUrl('https://open.spotify.com/album/7A9I9BrNylVCqXzgN3Y6qi', []);

    print('Imported album title: "${res.title}"');
    print('Imported album artworkUrl: "${res.artworkUrl}"');
    expect(res.artworkUrl, isNotNull);
    expect(res.artworkUrl!.isNotEmpty, isTrue);
    expect(
      res.artworkUrl!.contains('spotifycdn.com') || res.artworkUrl!.contains('scdn.co'),
      isTrue,
    );
  });

  testWidgets('GenerativePlaylistCover renders single full cover for album tracks without 4x4 duplication', (tester) async {
    HttpOverrides.global = _TestHttpOverrides();
    final now = DateTime.now();
    const albumCover = 'https://i.scdn.co/image/ab67616d0000b2734a9e22353a23a31c51db3f05';

    final playlist = Playlist(
      id: 'p_awake',
      title: 'Awake',
      createdAt: now,
      updatedAt: now,
      customArtworkUrl: albumCover,
    );

    // 13 tracks all sharing the same album cover
    final tracks = List.generate(
      13,
      (i) => Track(
        id: 't_$i',
        accountId: 'acc1',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: 'remote_$i',
        title: 'Song $i',
        artist: 'ILLENIUM',
        album: 'Awake',
        durationMs: 180000,
        streamUrl: 'https://example.com/stream_$i.mp4',
        artworkUrl: albumCover,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GenerativePlaylistCover(
              playlist: playlist,
              tracks: tracks,
              size: 200,
            ),
          ),
        ),
      ),
    );

    // Should render single full cover, NEVER a Column with multiple Rows (4-quadrant mosaic)
    expect(find.byType(Column), findsNothing);
    expect(find.byType(GenerativePlaylistCover), findsOneWidget);
  });
}

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();
  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _kTransparentImage.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final Uint8List _kTransparentImage = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);
