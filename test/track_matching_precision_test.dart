import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/models/track.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';

void main() {
  group('PlaylistImportService.findBestMatch Precision & Anti-Collision Tests', () {
    final trackLostNF = Track(
      id: 't_lost_nf',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/lost_nf.mp3',
      title: 'Lost',
      artist: 'NF',
      album: 'CLOUDS',
      durationMs: 240000,
      streamUrl: 'file:///music/lost_nf.mp3',
    );

    final trackLostTalha = Track(
      id: 't_lost_talha',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/lost.mp3',
      title: 'Lost',
      artist: 'Talha Anjum',
      album: 'Singles',
      durationMs: 210000,
      streamUrl: 'file:///music/lost.mp3',
    );

    final trackLoveLost = Track(
      id: 't_love_lost',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/love_lost.mp3',
      title: 'love lost',
      artist: 'Umair, Talha Anjum',
      album: 'Rockstar Without a Guitar',
      durationMs: 195000,
      streamUrl: 'file:///music/love_lost.mp3',
    );

    final trackHelloLionel = Track(
      id: 't_hello_lionel',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/hello_lionel.mp3',
      title: 'Hello',
      artist: 'Lionel Richie',
      album: 'Can\'t Slow Down',
      durationMs: 240000,
      streamUrl: 'file:///music/hello_lionel.mp3',
    );

    final trackFaasle = Track(
      id: 't_faasle',
      accountId: 'local',
      providerType: CloudProviderType.androidSaf,
      remotePathOrId: '/music/faasle.mp3',
      title: 'Faasle',
      artist: 'Kaavish',
      album: 'Gukash',
      durationMs: 320000,
      streamUrl: 'file:///music/faasle.mp3',
    );

    test('Querying "Love lost" does NOT match library track "Lost" by NF', () {
      final library = [trackLostNF];
      final match = PlaylistImportService.findBestMatch(
        'Love lost',
        'Umair, Talha Anjum',
        library,
      );
      expect(match, isNull, reason: 'Substring "lost" inside "Love lost" must NOT falsely match');
    });

    test('Querying "Love lost" does NOT match library track "Lost" even if artists overlap', () {
      final library = [trackLostTalha];
      final match = PlaylistImportService.findBestMatch(
        'Love lost',
        'Umair, Talha Anjum',
        library,
      );
      expect(match, isNull, reason: '"Lost" is a distinct song title from "Love lost" and must not match');
    });

    test('Querying "Lost" does NOT match library track "Love lost"', () {
      final library = [trackLoveLost];
      final match = PlaylistImportService.findBestMatch(
        'Lost',
        'Talha Anjum',
        library,
      );
      expect(match, isNull, reason: 'Shorter title must not match longer title "Love lost"');
    });

    test('Querying "Love lost" matches authentic "love lost" by Umair, Talha Anjum', () {
      final library = [trackLostNF, trackLostTalha, trackLoveLost];
      final match = PlaylistImportService.findBestMatch(
        'Love lost',
        'Umair, Talha Anjum',
        library,
      );
      expect(match, isNotNull);
      expect(match!.id, equals('t_love_lost'));
    });

    test('Querying "Hello" by Adele does NOT match "Hello" by Lionel Richie', () {
      final library = [trackHelloLionel];
      final match = PlaylistImportService.findBestMatch(
        'Hello',
        'Adele',
        library,
      );
      expect(match, isNull, reason: 'Identical title with completely different artist must not match');
    });

    test('Canonical match: "Faasle - Studio Version" matches "Faasle" by Kaavish', () {
      final library = [trackFaasle];
      final match = PlaylistImportService.findBestMatch(
        'Faasle - Studio Version',
        'Kaavish',
        library,
      );
      expect(match, isNotNull);
      expect(match!.id, equals('t_faasle'));
    });
  });
}
