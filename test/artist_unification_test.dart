import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/metadata/artist_helper.dart';

void main() {
  group('ArtistHelper Unit Tests', () {
    test('extracts single artist cleanly', () {
      final artists = ArtistHelper.extractArtists('Drake');
      expect(artists, equals(['Drake']));
    });

    test('extracts comma-separated collaborators', () {
      final artists = ArtistHelper.extractArtists('Drake, 21 Savage');
      expect(artists, equals(['Drake', '21 Savage']));
    });

    test('extracts feat. and ft. collaborations', () {
      final feat1 = ArtistHelper.extractArtists('Drake feat. 21 Savage');
      expect(feat1, equals(['Drake', '21 Savage']));

      final feat2 = ArtistHelper.extractArtists('Eminem ft. Rihanna');
      expect(feat2, equals(['Eminem', 'Rihanna']));

      final feat3 = ArtistHelper.extractArtists('Travis Scott featuring Drake');
      expect(feat3, equals(['Travis Scott', 'Drake']));
    });

    test('extracts ampersand & collaborations', () {
      final artists = ArtistHelper.extractArtists('Post Malone & Swae Lee');
      expect(artists, equals(['Post Malone', 'Swae Lee']));
    });

    test('extracts " x " and " with " collaborations', () {
      final collab1 = ArtistHelper.extractArtists('David Guetta x Bebe Rexha');
      expect(collab1, equals(['David Guetta', 'Bebe Rexha']));

      final collab2 = ArtistHelper.extractArtists('Silk Sonic with Thundercat');
      expect(collab2, equals(['Silk Sonic', 'Thundercat']));
    });

    test('preserves AC/DC without splitting by slash', () {
      final acdc = ArtistHelper.extractArtists('AC/DC');
      expect(acdc, equals(['AC/DC']));
    });

    test('splits spaced slashes e.g. Calvin Harris / Dua Lipa', () {
      final artists = ArtistHelper.extractArtists('Calvin Harris / Dua Lipa');
      expect(artists, equals(['Calvin Harris', 'Dua Lipa']));
    });

    test('preserves known ensembles like Simon & Garfunkel', () {
      final artists = ArtistHelper.extractArtists('Simon & Garfunkel');
      expect(artists, equals(['Simon & Garfunkel']));
    });

    test('extracts featured artists from track title', () {
      final artists = ArtistHelper.extractArtists(
        'Drake',
        'Jimmy Cooks (feat. 21 Savage)',
      );
      expect(artists, contains('Drake'));
      expect(artists, contains('21 Savage'));
    });

    test('trackBelongsToArtist matches primary, featured, and collaborative artist', () {
      const track1 = Track(
        id: 't1',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/path/1',
        title: 'Jimmy Cooks',
        artist: 'Drake feat. 21 Savage',
        album: 'Her Loss',
        durationMs: 218000,
        streamUrl: 'https://example.com/stream/1',
      );

      expect(ArtistHelper.trackBelongsToArtist(track1, 'Drake'), isTrue);
      expect(ArtistHelper.trackBelongsToArtist(track1, '21 Savage'), isTrue);
      expect(ArtistHelper.trackBelongsToArtist(track1, 'Future'), isFalse);

      const track2 = Track(
        id: 't2',
        accountId: 'acc_1',
        providerType: CloudProviderType.androidSaf,
        remotePathOrId: '/path/2',
        title: 'Wait For U (feat. Drake & Tems)',
        artist: 'Future',
        album: 'I Never Liked You',
        durationMs: 190000,
        streamUrl: 'https://example.com/stream/2',
      );

      expect(ArtistHelper.trackBelongsToArtist(track2, 'Future'), isTrue);
      expect(ArtistHelper.trackBelongsToArtist(track2, 'Drake'), isTrue);
      expect(ArtistHelper.trackBelongsToArtist(track2, 'Tems'), isTrue);
      expect(ArtistHelper.trackBelongsToArtist(track2, 'Kendrick Lamar'), isFalse);
    });
  });
}
