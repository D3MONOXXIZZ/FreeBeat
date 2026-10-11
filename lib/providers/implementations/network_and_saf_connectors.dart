import 'package:file_picker/file_picker.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../core/models/cloud_account.dart';
import '../../core/models/track.dart';
import '../../services/metadata/artwork_and_lyrics_service.dart';
import '../../services/metadata/range_tag_parser.dart';
import '../cloud_provider_connector.dart';
import 'media_server_connectors.dart';
import 'oauth_cloud_connectors.dart';
import 'open_protocol_connectors.dart';

/// 9. SFTP / SSH Home Lab & NAS Connector
class SftpNasConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.sftp;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    return account.endpointOrFolder.isNotEmpty &&
        account.usernameOrEmail.isNotEmpty;
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      [];

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// 10. SMB / LAN NAS Share Connector
class SmbNasConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.smb;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      account.endpointOrFolder.isNotEmpty;

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      [];

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// 11. Android Native Storage Access Framework (SAF) Connector
/// Allows mounting any cloud provider app installed on the Android phone
/// (Google Drive, OneDrive, Nextcloud, Proton Drive, MEGA, SD Card) via DocumentsContract.
class AndroidSafConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.androidSaf;

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      true;

  /// Launches the native Android SAF multi-file audio picker to mount cloud/local tracks.
  Future<List<Track>> pickSafAudioFiles(CloudAccount account) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null) return [];
      return result.files.where((f) => f.path != null).map((file) {
        final parsed = RangeTagParser.parseFromFilename(file.name);
        return Track(
          id: 'saf_${file.name.hashCode.abs()}',
          accountId: account.id,
          providerType: type,
          remotePathOrId: file.path!,
          title: parsed.title ?? file.name,
          artist: parsed.artist ?? 'Mounted Cloud Drive',
          album: parsed.album ?? account.displayName,
          durationMs: 210000,
          streamUrl: file.path!,
          codec: parsed.codec ?? 'FLAC',
          bitDepth: parsed.bitDepth ?? 24,
          sampleRateHz: parsed.sampleRateHz ?? 96000,
          bitrateKbps: parsed.bitrateKbps ?? 1411,
          sizeBytes: file.size,
          dominantColorValue: type.accentColorValue,
          isPinnedOffline: true,
          localCachePath: file.path,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      [];

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      activeQualityTier: targetQuality,
      effectiveBitrateKbps: track.bitrateKbps,
      effectiveCodec: track.codec,
      isDirectLocalFile: true,
    );
  }
}

/// 12. Pixel Hi-Fi Demo Cloud Showcase Connector
/// Pre-indexed multi-cloud showcase tracks with real streaming audio, vibrant cover art,
/// 24-bit/96kHz Hi-Fi metadata, and millisecond-accurate synced LRC lyrics.
class DemoCloudConnector implements CloudProviderConnector {
  @override
  CloudProviderType get type => CloudProviderType.demoCloud;

  static List<CloudAccount> defaultShowcaseAccounts() {
    return [
      CloudAccount(
        id: 'acc_pixel_gdrive',
        providerType: CloudProviderType.googleDrive,
        displayName: 'Personal Google Drive (Hi-Fi Vault)',
        endpointOrFolder: '/Music/24Bit-FLAC-Masters',
        usernameOrEmail: 'pixel.audiophile@gmail.com',
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 4)),
        indexedTrackCount: 3,
      ),
      CloudAccount(
        id: 'acc_jellyfin_home',
        providerType: CloudProviderType.jellyfin,
        displayName: 'Home Lab Jellyfin Hi-Res Server',
        endpointOrFolder: 'https://jellyfin.local.lan:8920',
        usernameOrEmail: 'admin',
        lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        indexedTrackCount: 2,
      ),
      CloudAccount(
        id: 'acc_cloudflare_r2',
        providerType: CloudProviderType.s3,
        displayName: 'Cloudflare R2 S3 Lossless Bucket',
        endpointOrFolder: 'https://s3.r2.cloudflarestorage.com',
        bucketOrShareName: 'lossless-vinyl-rips',
        region: 'auto',
        lastSyncedAt: DateTime.now().subtract(const Duration(hours: 1)),
        indexedTrackCount: 2,
      ),
    ];
  }

  static List<Track> defaultShowcaseTracks() {
    final sampleLyrics1 = ArtworkAndLyricsService.parseLrcContent('''
[00:00.00] ♪ 24-Bit / 96 kHz Hi-Fi Cloud Stream Initialized ♪
[00:04.20] Neon reflections across the obsidian glass
[00:08.80] Streaming lossless waves through the midnight sky
[00:13.50] Every harmonic preserved in pure studio master
[00:18.20] Ten bands of precision shaping the soundstage
[00:23.00] Sub-bass resonating deep inside the pocket
[00:28.40] Zero compression, zero compromise in the cloud
[00:34.10] Floating across servers at the speed of light
[00:40.00] ♪ Instrumental Synth Solo (Stereo X Expanded) ♪
''');

    final sampleLyrics2 = ArtworkAndLyricsService.parseLrcContent('''
[00:00.00] ♪ Jellyfin Direct Play • Bit-Perfect Master ♪
[00:05.00] Warm analog tape meets digital horizon
[00:10.50] Golden transients dancing on the squiggly line
[00:16.00] Turn the rotary bass dial, feel the Pixel haptics
[00:21.50] Crystal treble air at sixteen kilohertz
[00:27.00] Your private library, anywhere on earth
''');

    return [
      Track(
        id: 'trk_1',
        accountId: 'acc_pixel_gdrive',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: '/Music/24Bit-FLAC-Masters/01 - Carbon Based Lifeforms - Midnight Obsidian.flac',
        title: 'Midnight Obsidian (Studio Master)',
        artist: 'Aether & The Pixel Synth',
        album: 'Material You Sessions (24-Bit/96kHz)',
        durationMs: 372000,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800&q=80',
        bitrateKbps: 2840,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'FLAC',
        sizeBytes: 132057600,
        dominantColorValue: 0xFF7C4DFF,
        isFavorite: true,
        playCount: 42,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_2',
        accountId: 'acc_jellyfin_home',
        providerType: CloudProviderType.jellyfin,
        remotePathOrId: 'jf_item_99201',
        title: 'Velvet Horizon (Direct Play)',
        artist: 'Kyoto Analog Ensemble',
        album: 'Late Night Tape Loops',
        durationMs: 425000,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=800&q=80',
        bitrateKbps: 4608,
        bitDepth: 24,
        sampleRateHz: 192000,
        codec: 'FLAC',
        sizeBytes: 244800000,
        dominantColorValue: 0xFFFF6D00,
        isFavorite: true,
        isPinnedOffline: true,
        playCount: 31,
        syncedLyrics: sampleLyrics2,
      ),
      Track(
        id: 'trk_3',
        accountId: 'acc_cloudflare_r2',
        providerType: CloudProviderType.s3,
        remotePathOrId: 'vinyl-rips/Solaris_Odyssey_24_96.flac',
        title: 'Solaris Odyssey (S3 SigV4 Stream)',
        artist: 'Nova Modular',
        album: 'Cloudflare R2 Audiophile Vault',
        durationMs: 344000,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=800&q=80',
        bitrateKbps: 2120,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'ALAC',
        sizeBytes: 91160000,
        dominantColorValue: 0xFF00BFA5,
        playCount: 19,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_4',
        accountId: 'acc_pixel_gdrive',
        providerType: CloudProviderType.oneDrive,
        remotePathOrId: 'onedrive_item_8821',
        title: 'Sub-Bass Architecture',
        artist: 'Binaural Collective',
        album: 'Poweramp 10-Band Reference Check',
        durationMs: 302000,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=800&q=80',
        bitrateKbps: 1411,
        bitDepth: 16,
        sampleRateHz: 44100,
        codec: 'WAV',
        sizeBytes: 53265000,
        dominantColorValue: 0xFF2979FF,
        isPinnedOffline: true,
        playCount: 64,
        syncedLyrics: sampleLyrics2,
      ),
      Track(
        id: 'trk_5',
        accountId: 'acc_jellyfin_home',
        providerType: CloudProviderType.subsonic,
        remotePathOrId: 'navidrome_774',
        title: 'Tokyo Rain (OpenSubsonic Master)',
        artist: 'Shibuya Quartet',
        album: 'Acoustic Reflections in 24-Bit',
        durationMs: 355000,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800&q=80',
        bitrateKbps: 3100,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'FLAC',
        sizeBytes: 137560000,
        dominantColorValue: 0xFFE91E63,
        isFavorite: true,
        playCount: 27,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_6',
        accountId: 'acc_cloudflare_r2',
        providerType: CloudProviderType.webdav,
        remotePathOrId: '/Nextcloud/Music/Aurora_Borealis.flac',
        title: 'Aurora Borealis (Nextcloud WebDAV)',
        artist: 'Nordic Ambient Guild',
        album: 'Self-Hosted Sanctuary',
        durationMs: 390000,
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?w=800&q=80',
        bitrateKbps: 2650,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'FLAC',
        sizeBytes: 129180000,
        dominantColorValue: 0xFF00E5FF,
        playCount: 15,
        syncedLyrics: sampleLyrics2,
      ),
    ];
  }

  @override
  Future<bool> testConnection(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      true;

  @override
  Future<List<Track>> scanLibrary(
    CloudAccount account,
    Map<String, String> secrets,
  ) async =>
      defaultShowcaseTracks();

  @override
  Future<StreamRequestSpec> resolveStream(
    Track track,
    CloudAccount account,
    Map<String, String> secrets, {
    required AudioQualityTier targetQuality,
    int? startByte,
    int? endByte,
  }) async {
    return StreamRequestSpec(
      url: track.streamUrl,
      headers: {
        if (startByte != null) 'Range': 'bytes=$startByte-${endByte ?? ''}',
      },
      activeQualityTier: targetQuality,
      effectiveBitrateKbps:
          targetQuality.isLossless ? track.bitrateKbps : targetQuality.kbps,
      effectiveCodec:
          targetQuality.isLossless ? track.codec : targetQuality.codec,
    );
  }
}

/// Central registry resolving any of the 12 [CloudProviderType] values to its connector.
class CloudConnectorRegistry {
  CloudConnectorRegistry() {
    _connectors = {
      CloudProviderType.googleDrive: GoogleDriveConnector(),
      CloudProviderType.oneDrive: OneDriveConnector(),
      CloudProviderType.dropbox: DropboxConnector(),
      CloudProviderType.box: BoxConnector(),
      CloudProviderType.jellyfin: JellyfinConnector(),
      CloudProviderType.subsonic: SubsonicConnector(),
      CloudProviderType.webdav: WebDavConnector(),
      CloudProviderType.s3: S3CompatibleConnector(),
      CloudProviderType.sftp: SftpNasConnector(),
      CloudProviderType.smb: SmbNasConnector(),
      CloudProviderType.androidSaf: AndroidSafConnector(),
      CloudProviderType.demoCloud: DemoCloudConnector(),
    };
  }

  late final Map<CloudProviderType, CloudProviderConnector> _connectors;

  CloudProviderConnector forType(CloudProviderType type) {
    return _connectors[type] ?? DemoCloudConnector();
  }
}
