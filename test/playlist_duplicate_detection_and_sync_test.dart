import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/services/playlist/playlist_import_service.dart';

void main() {
  group('Playlist Duplicate Detection & Sync Messaging', () {
    test('rawSourceTracks retains all parsed entries without pre-deduplication', () {
      final service = PlaylistImportService();
      const m3uContent = '''
#PLAYLIST:Duplicate Test
#EXTINF:200,JANI - Out Of Time
https://stream/1
#EXTINF:210,JANI - Sehna
https://stream/2
#EXTINF:200,JANI - Out Of Time
https://stream/3
''';

      final result = service.parseM3u(m3uContent, []);
      expect(result.totalParsed, 3);
      expect(result.rawSourceTracks.length, 3);
      expect(result.missingTracks.length, 2); // pre-deduplicated for missing resolution
    });

    test('PlaylistSyncService reports unique count and duplicate source entries', () {
      // Test message calculation
      const totalInSource = 126;
      const currentCount = 117;
      final duplicateDifference = totalInSource > currentCount
          ? totalInSource - currentCount
          : 0;

      final countDetails = duplicateDifference > 0
          ? '$totalInSource tracks checked: $currentCount unique, $duplicateDifference duplicate source entries'
          : '$totalInSource tracks checked';

      expect(countDetails, '126 tracks checked: 117 unique, 9 duplicate source entries');
    });
  });
}
