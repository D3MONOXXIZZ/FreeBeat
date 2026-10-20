import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freebeat/core/models/cloud_account.dart';
import 'package:freebeat/core/storage/library_database.dart';
import 'package:freebeat/providers/implementations/oauth_cloud_connectors.dart';
import 'package:freebeat/services/auth/native_cloud_auth_service.dart';
import 'package:freebeat/core/storage/secure_credential_store.dart';
import 'package:freebeat/services/discovery/local_media_server_discovery_service.dart';
import 'package:freebeat/state/app_providers.dart';
import 'package:freebeat/ui/screens/clouds_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:freebeat/providers/implementations/network_and_saf_connectors.dart';
import 'package:freebeat/services/audio/cloud_stream_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('1-Tap Cloud Auth & Native Google Sign-In Contract', () {
    test('NativeGoogleAuthResult encapsulates account details and tokens cleanly', () {
      const account = CloudAccount(
        id: 'gdrive_user123',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Test Audiophile (Drive)',
        endpointOrFolder: 'Google Drive • test@gmail.com',
        usernameOrEmail: 'test@gmail.com',
      );

      const result = NativeGoogleAuthResult(
        isSuccess: true,
        email: 'test@gmail.com',
        displayName: 'Test Audiophile',
        accessToken: 'ya29.sample_oauth_token_123',
        idToken: 'sample_id_token_xyz',
        account: account,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isCancelled, isFalse);
      expect(result.email, 'test@gmail.com');
      expect(result.accessToken, 'ya29.sample_oauth_token_123');
      expect(result.account?.providerType, CloudProviderType.googleDrive);
      expect(result.account?.displayName, 'Test Audiophile (Drive)');
    });

    test('OAuth2PkceHelper builds valid authorization URIs for Google Drive, OneDrive & Dropbox', () {
      final driveUri = OAuth2PkceHelper.buildAuthorizationUri(
        provider: CloudProviderType.googleDrive,
        clientId: 'drive_client_id_123',
        codeChallenge: 'challenge_xyz',
      );
      expect(driveUri.host, 'accounts.google.com');
      expect(driveUri.queryParameters['client_id'], 'drive_client_id_123');
      expect(driveUri.queryParameters['scope'], contains('https://www.googleapis.com/auth/drive.file'));
      expect(driveUri.queryParameters['scope'], contains('https://www.googleapis.com/auth/drive.readonly'));
      expect(driveUri.queryParameters['code_challenge'], 'challenge_xyz');

      final oneDriveUri = OAuth2PkceHelper.buildAuthorizationUri(
        provider: CloudProviderType.oneDrive,
        clientId: 'onedrive_client_123',
        codeChallenge: 'challenge_abc',
      );
      expect(oneDriveUri.host, 'login.microsoftonline.com');
      expect(oneDriveUri.queryParameters['client_id'], 'onedrive_client_123');
      expect(oneDriveUri.queryParameters['scope'], contains('Files.ReadWrite'));

      final dropboxUri = OAuth2PkceHelper.buildAuthorizationUri(
        provider: CloudProviderType.dropbox,
        clientId: 'dropbox_client_123',
        codeChallenge: 'challenge_drop',
      );
      expect(dropboxUri.host, 'www.dropbox.com');
      expect(dropboxUri.queryParameters['client_id'], 'dropbox_client_123');
    });

    test('NativeCloudAuthService supports comprehensive hi-fi audio extensions for SAF picker', () {
      expect(NativeCloudAuthService.supportedAudioExtensions, containsAll(['mp3', 'flac', 'm4a', 'wav', 'aac', 'ogg', 'opus', 'alac', 'wma', 'aiff', 'ape', 'dsf']));
    });

    test('GoogleDriveConnector scans audio files with query filtering', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'www.googleapis.com' && request.url.path == '/drive/v3/files') {
          final q = request.url.queryParameters['q'] ?? '';
          expect(q, contains('.flac'));
          expect(q, contains('.mp3'));
          return http.Response(
            '{"files": [{"id": "file123", "name": "Artist - Song.flac", "size": "15000000"}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final connector = GoogleDriveConnector(client: mockClient);
      const account = CloudAccount(
        id: 'acc_1',
        providerType: CloudProviderType.googleDrive,
        displayName: 'My Drive',
        endpointOrFolder: 'root',
      );
      final tracks = await connector.scanLibrary(account, {'accessToken': 'test_token'});
      expect(tracks.length, 1);
      expect(tracks.first.title, 'Song');
      expect(tracks.first.artist, 'Artist');
      expect(tracks.first.codec, 'FLAC');
    });
  });

  group('Local Media Server Wi-Fi Auto-Discovery', () {
    test('LocalMediaServerDiscoveryService probes and finds simulated Jellyfin server', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/System/Info/Public') {
          return http.Response(
            '{"ServerName": "Living Room Jellyfin", "Version": "10.8.13"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final discovery = LocalMediaServerDiscoveryService(client: mockClient);
      final discovered = await discovery.discoverAll(
        timeout: const Duration(milliseconds: 100),
      );

      expect(discovered, isNotEmpty);
      final jf = discovered.firstWhere((s) => s.type == CloudProviderType.jellyfin);
      expect(jf.name, 'Living Room Jellyfin');
      expect(jf.type, CloudProviderType.jellyfin);
      expect(jf.discoveredVia, 'LAN Auto-Detect');
    });

    test('DiscoveredMediaServer equality and unique deduplication', () {
      const server1 = DiscoveredMediaServer(
        id: 'jf_1',
        name: 'Jellyfin 1',
        url: 'http://192.168.1.100:8096',
        type: CloudProviderType.jellyfin,
        discoveredVia: 'UDP 7359 Broadcast',
      );

      const server2 = DiscoveredMediaServer(
        id: 'jf_2',
        name: 'Jellyfin 1',
        url: 'http://192.168.1.100:8096',
        type: CloudProviderType.jellyfin,
        discoveredVia: 'LAN Auto-Detect',
      );

      expect(server1, equals(server2));
      expect({server1, server2}.length, 1);
    });
  });

  group('Clouds Screen & Add Cloud Wizard Widget Tests', () {
    testWidgets('Opens Add Cloud Wizard and switches between 1-Tap Cloud, Wi-Fi Servers, and Installed Apps', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: CloudsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Add Cloud' button to open modal bottom sheet
      await tester.tap(find.text('Add Cloud'));
      await tester.pumpAndSettle();

      // Check header and 1-Tap Google Drive Card (only sign-in button is displayed)
      expect(find.text('Add Cloud & Media Drive'), findsOneWidget);
      expect(find.text('Google Drive'), findsWidgets);
      expect(find.text('Cloud Sign-In'), findsOneWidget);
      expect(find.text('Pick Audio Files from Google Drive'), findsNothing);
      expect(find.text('Import Folder'), findsNothing);
      expect(find.text('Microsoft OneDrive'), findsWidgets);
      expect(find.text('Dropbox'), findsWidgets);

      // Switch to 'Wi-Fi Servers' mode
      await tester.tap(find.text('Wi-Fi Servers'));
      await tester.pumpAndSettle();
      expect(find.text('Auto-Detect Local Media Servers'), findsOneWidget);
      expect(find.text('Scan Wi-Fi for Media Servers'), findsOneWidget);
      expect(find.text('Quick Host Presets:'), findsOneWidget);

      // Switch to 'Installed Apps' mode
      await tester.ensureVisible(find.text('Installed Apps'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Installed Apps'));
      await tester.pumpAndSettle();
      expect(find.text('Mount Any Installed Cloud App'), findsOneWidget);
      expect(find.text('Pick Music Files from Installed App'), findsOneWidget);
      expect(find.text('Import Entire Folder'), findsOneWidget);
      expect(find.text('Device & SD Card Storage'), findsOneWidget);
      expect(find.text('Pick Music from Device Storage'), findsOneWidget);
      expect(find.text('Installed Cloud Apps'), findsOneWidget);

      // Switch to 'Manual / S3' mode
      await tester.ensureVisible(find.text('Manual / S3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual / S3'));
      await tester.pumpAndSettle();
      expect(find.text('Server URL / Endpoint / IP Address'), findsOneWidget);
      expect(find.text('Mount Cloud Drive'), findsOneWidget);
    });

    test('NativeCloudAuthService.createGoogleDriveAccount creates direct Google Drive account', () {
      final auth = NativeCloudAuthService();
      final res = auth.createGoogleDriveAccount(
        email: 'audiophile@gmail.com',
        displayName: 'Studio Master',
        accessToken: 'ya29.direct_test_token',
      );

      expect(res.isSuccess, isTrue);
      expect(res.email, 'audiophile@gmail.com');
      expect(res.account, isNotNull);
      expect(res.account!.providerType, CloudProviderType.googleDrive);
      expect(res.account!.displayName, 'Studio Master (Drive)');
      expect(res.account!.isConnected, isTrue);
    });

    test('CloudAccountsNotifier restores accounts from SharedPreferences across app restart', () async {
      SharedPreferences.setMockInitialValues({
        'freebeat_persisted_cloud_accounts': jsonEncode([
          {
            'id': 'gdrive_persisted_1',
            'providerType': 'googleDrive',
            'displayName': 'Persistent Drive',
            'endpointOrFolder': 'Google Drive • user@gmail.com',
            'usernameOrEmail': 'user@gmail.com',
            'isConnected': 1,
            'lastSyncedAt': DateTime.now().millisecondsSinceEpoch,
            'indexedTrackCount': 42,
          }
        ]),
      });

      final notifier = CloudAccountsNotifier(LibraryDatabase(), SecureCredentialStore());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(notifier.state, isNotEmpty);
      expect(notifier.state.first.id, 'gdrive_persisted_1');
      expect(notifier.state.first.providerType, CloudProviderType.googleDrive);
      expect(notifier.state.first.displayName, 'Persistent Drive');
    });

    testWidgets('CloudsScreen displays connected Google Drive account with active badge', (WidgetTester tester) async {
      const persistedAccount = CloudAccount(
        id: 'gdrive_active_1',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Studio Master (Drive)',
        endpointOrFolder: 'Google Drive • master@studio.com',
        usernameOrEmail: 'master@studio.com',
        isConnected: true,
      );

      final container = ProviderContainer(
        overrides: [
          cloudStreamProxyProvider.overrideWithValue(_FakeCloudStreamProxy()),
          cloudAccountsProvider.overrideWith((ref) {
            final acc = CloudAccountsNotifier(LibraryDatabase(), SecureCredentialStore());
            acc.state = [persistedAccount];
            return acc;
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CloudsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connected Cloud Drives (1)'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Studio Master (Drive)'), findsOneWidget);
      expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });
  });
}

class _FakeCloudStreamProxy extends CloudStreamProxy {
  _FakeCloudStreamProxy()
      : super(
          connectorRegistry: CloudConnectorRegistry(),
          credentialStore: SecureCredentialStore(),
        );

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {}
}
