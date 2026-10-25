import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/metadata/artist_helper.dart';
import 'package:freebeat/state/app_providers.dart';

void main() {
  group('Artist Catalogue & Collaboration Unification Tests', () {
    const trackSoloDrake = Track(
      id: 'drake_solo',
      accountId: 'acc_test',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/gods_plan.flac',
      title: "God's Plan",
      artist: 'Drake',
      album: 'Scorpion',
      durationMs: 198000,
      streamUrl: 'https://example.com/drake_solo.flac',
    );

    const trackCollabDrake21 = Track(
      id: 'drake_21_collab',
      accountId: 'acc_test',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/jimmy_cooks.flac',
      title: 'Jimmy Cooks',
      artist: 'Drake feat. 21 Savage',
      album: 'Her Loss',
      durationMs: 218000,
      streamUrl: 'https://example.com/jimmy_cooks.flac',
    );

    const trackSolo21Savage = Track(
      id: '21_solo',
      accountId: 'acc_test',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/bank_account.flac',
      title: 'Bank Account',
      artist: '21 Savage',
      album: 'Issa Album',
      durationMs: 220000,
      streamUrl: 'https://example.com/bank_account.flac',
    );

    const trackFeaturedInTitle = Track(
      id: 'future_feat_drake',
      accountId: 'acc_test',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/wait_for_u.flac',
      title: 'Wait For U (feat. Drake & Tems)',
      artist: 'Future',
      album: 'I Never Liked You',
      durationMs: 195000,
      streamUrl: 'https://example.com/wait_for_u.flac',
    );

    test('availableArtistsProvider unifies collaborations into distinct individual artists', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith((ref) {
            final cat = TracksCatalogNotifier(null, null);
            cat.state = [
              trackSoloDrake,
              trackCollabDrake21,
              trackSolo21Savage,
              trackFeaturedInTitle,
            ];
            return cat;
          }),
        ],
      );
      addTearDown(container.dispose);

      final artists = container.read(availableArtistsProvider);
      final artistNames = artists.map((a) => a.name).toList();

      // Individual unified names exist
      expect(artistNames, contains('Drake'));
      expect(artistNames, contains('21 Savage'));
      expect(artistNames, contains('Future'));
      expect(artistNames, contains('Tems'));

      // Compound artist names MUST NOT exist
      expect(artistNames.contains('Drake feat. 21 Savage'), isFalse);
      expect(artistNames.contains('Future feat. Drake & Tems'), isFalse);

      // Track counts:
      // Drake appears in: trackSoloDrake, trackCollabDrake21, trackFeaturedInTitle => 3
      final drakeInfo = artists.firstWhere((a) => a.name == 'Drake');
      expect(drakeInfo.trackCount, equals(3));

      // 21 Savage appears in: trackCollabDrake21, trackSolo21Savage => 2
      final savageInfo = artists.firstWhere((a) => a.name == '21 Savage');
      expect(savageInfo.trackCount, equals(2));
    });

    test('collaboration tracks appear under both participating artists catalogues', () {
      final container = ProviderContainer(
        overrides: [
          tracksCatalogProvider.overrideWith((ref) {
            final cat = TracksCatalogNotifier(null, null);
            cat.state = [
              trackSoloDrake,
              trackCollabDrake21,
              trackSolo21Savage,
              trackFeaturedInTitle,
            ];
            return cat;
          }),
        ],
      );
      addTearDown(container.dispose);

      // Filter by Drake
      container.read(selectedArtistFilterProvider.notifier).state = 'Drake';
      final drakeFiltered = container.read(filteredTracksProvider);
      final drakeTrackIds = drakeFiltered.map((t) => t.id).toList();

      expect(drakeTrackIds, contains('drake_solo'));
      expect(drakeTrackIds, contains('drake_21_collab'));
      expect(drakeTrackIds, contains('future_feat_drake'));
      expect(drakeTrackIds.contains('21_solo'), isFalse);

      // Filter by 21 Savage
      container.read(selectedArtistFilterProvider.notifier).state = '21 Savage';
      final savageFiltered = container.read(filteredTracksProvider);
      final savageTrackIds = savageFiltered.map((t) => t.id).toList();

      // Jimmy Cooks must show up in 21 Savage's catalogue too!
      expect(savageTrackIds, contains('21_solo'));
      expect(savageTrackIds, contains('drake_21_collab'));
      expect(savageTrackIds.contains('drake_solo'), isFalse);
    });
  });
}
