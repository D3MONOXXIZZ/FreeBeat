import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/services/cloud/universal_cloud_upload_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Concurrent folder creation calls only create ONE folder in Google Drive', () async {
    var folderCreateCount = 0;
    var folderQueryCount = 0;

    final mockClient = MockClient((request) async {
      final uri = request.url;
      // Google Drive query
      if (uri.path == '/drive/v3/files' && request.method == 'GET') {
        folderQueryCount++;
        // Simulate network latency so concurrent callers overlap
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'files': []}), 200);
      }

      // Google Drive folder create
      if (uri.path == '/drive/v3/files' && request.method == 'POST') {
        folderCreateCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'id': 'single_folder_id_123'}), 200);
      }

      return http.Response('{}', 200);
    });

    final uploader = UniversalCloudUploadService(httpClient: mockClient);

    // Run 3 concurrent worker calls for "Awake"
    final futures = [
      uploader.findExistingCloudTrack(
        account: const CloudAccount(
          id: 'acc1',
          providerType: CloudProviderType.googleDrive,
          displayName: 'Drive',
          endpointOrFolder: '/',
        ),
        secrets: {'accessToken': 'test_token'},
        playlistName: 'Awake',
        title: 'Track 1',
        artist: 'Illenium',
      ),
      uploader.findExistingCloudTrack(
        account: const CloudAccount(
          id: 'acc1',
          providerType: CloudProviderType.googleDrive,
          displayName: 'Drive',
          endpointOrFolder: '/',
        ),
        secrets: {'accessToken': 'test_token'},
        playlistName: 'Awake',
        title: 'Track 2',
        artist: 'Illenium',
      ),
      uploader.findExistingCloudTrack(
        account: const CloudAccount(
          id: 'acc1',
          providerType: CloudProviderType.googleDrive,
          displayName: 'Drive',
          endpointOrFolder: '/',
        ),
        secrets: {'accessToken': 'test_token'},
        playlistName: 'Awake',
        title: 'Track 3',
        artist: 'Illenium',
      ),
    ];

    await Future.wait(futures);

    // 1 folder created for "FreeBeat Music" root + 1 folder created for "Awake" playlist = 2 total
    // NOT 6 or 9!
    expect(folderCreateCount, equals(2));
    expect(folderQueryCount, greaterThan(0));
  });

  test('Auto-cleans duplicate folders in Google Drive when multiple exist', () async {
    var trashedFolderCount = 0;

    final mockClient = MockClient((request) async {
      final uri = request.url;

      // Query returns 2 duplicate folders for "Awake"
      if (uri.path == '/drive/v3/files' && request.method == 'GET') {
        if (uri.queryParameters['q']?.contains("name = 'Awake'") == true) {
          return http.Response(
            jsonEncode({
              'files': [
                {'id': 'awake_primary_folder', 'name': 'Awake', 'createdTime': '2026-10-22T10:00:00Z'},
                {'id': 'awake_duplicate_copy', 'name': 'Awake', 'createdTime': '2026-10-22T10:00:05Z'},
              ]
            }),
            200,
          );
        }
        // Root container query
        return http.Response(
          jsonEncode({
            'files': [
              {'id': 'root_music_folder', 'name': 'FreeBeat Music'}
            ]
          }),
          200,
        );
      }

      // Trashing duplicate folder
      if (request.method == 'PATCH') {
        if (uri.path == '/drive/v3/files/awake_duplicate_copy') {
          trashedFolderCount++;
          return http.Response('{}', 200);
        }
      }

      return http.Response('{}', 200);
    });

    final uploader = UniversalCloudUploadService(httpClient: mockClient);

    await uploader.findExistingCloudTrack(
      account: const CloudAccount(
        id: 'acc1',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Drive',
        endpointOrFolder: '/',
      ),
      secrets: {'accessToken': 'test_token'},
      playlistName: 'Awake',
      title: 'Track 1',
      artist: 'Illenium',
    );

    // Give background cleanup task a moment to fire
    await Future.delayed(const Duration(milliseconds: 100));

    expect(trashedFolderCount, equals(1));
  });
}
