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
          dominantColorValue: 0xFF1E293B,
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
        id: 'trk_astral_meadow',
        accountId: 'acc_pixel_gdrive',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: '/Music/Lossless/Astral_Meadow_24_96.flac',
        title: 'Astral Meadow',
        artist: 'Fragments',
        album: 'Fragments LP (24-Bit/96kHz)',
        durationMs: 234000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2022/05/27/audio_1808fbf07a.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=800&q=80',
        bitrateKbps: 2840,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'FLAC',
        sizeBytes: 83205760,
        dominantColorValue: 0xFF2A4365,
        isFavorite: true,
        playCount: 78,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_blue_crane',
        accountId: 'acc_jellyfin_home',
        providerType: CloudProviderType.jellyfin,
        remotePathOrId: 'jf_item_crane',
        title: 'Blue Crane',
        artist: 'Help Another',
        album: 'Birds in Flight (Direct Play)',
        durationMs: 198000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2022/01/18/audio_d0a13f69d2.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1579783902614-a3fb3927b675?w=800&q=80',
        bitrateKbps: 4608,
        bitDepth: 24,
        sampleRateHz: 192000,
        codec: 'FLAC',
        sizeBytes: 114800000,
        dominantColorValue: 0xFF4A5568,
        isFavorite: true,
        isPinnedOffline: true,
        playCount: 62,
        syncedLyrics: sampleLyrics2,
      ),
      Track(
        id: 'trk_ladder_moon',
        accountId: 'acc_cloudflare_r2',
        providerType: CloudProviderType.s3,
        remotePathOrId: 'r2_ladder_to_the_moon.flac',
        title: 'Ladder to the Moon',
        artist: 'Summoned to',
        album: 'Summoned to (R2 Audiophile Vault)',
        durationMs: 226000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2022/03/15/audio_c8c7a73cbd.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=800&q=80',
        bitrateKbps: 2120,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'ALAC',
        sizeBytes: 61160000,
        dominantColorValue: 0xFF9F580A,
        playCount: 45,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_down_limbs',
        accountId: 'acc_pixel_gdrive',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: '/Music/Masters/Down_My_Limbs.flac',
        title: 'Down my limbs',
        artist: 'Magdalena',
        album: 'Magdalena (24-Bit Hi-Res)',
        durationMs: 154000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2021/08/04/audio_bb630cc098.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=800&q=80',
        bitrateKbps: 2450,
        bitDepth: 24,
        sampleRateHz: 88200,
        codec: 'FLAC',
        sizeBytes: 48500000,
        dominantColorValue: 0xFF6B46C1,
        isFavorite: true,
        playCount: 94,
        syncedLyrics: sampleLyrics2,
      ),
      Track(
        id: 'trk_summer_air',
        accountId: 'acc_jellyfin_home',
        providerType: CloudProviderType.jellyfin,
        remotePathOrId: 'jf_summer_air',
        title: 'Summer Air',
        artist: 'Water Houses',
        album: 'Water Houses Tape Archive',
        durationMs: 214000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2022/10/14/audio_9939f792cb.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&q=80',
        bitrateKbps: 1411,
        bitDepth: 16,
        sampleRateHz: 44100,
        codec: 'WAV',
        sizeBytes: 37700000,
        dominantColorValue: 0xFF2B6CB0,
        isPinnedOffline: true,
        playCount: 51,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_withering',
        accountId: 'acc_pixel_gdrive',
        providerType: CloudProviderType.subsonic,
        remotePathOrId: 'subsonic_withering',
        title: 'Withering',
        artist: 'Traveler',
        album: 'Traveler Ambient Chronicles',
        durationMs: 239000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2022/01/26/audio_d0c6ff1101.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1518495973542-4542c06a5843?w=800&q=80',
        bitrateKbps: 4608,
        bitDepth: 24,
        sampleRateHz: 192000,
        codec: 'FLAC',
        sizeBytes: 137400000,
        dominantColorValue: 0xFF285E61,
        playCount: 38,
        syncedLyrics: sampleLyrics2,
      ),
      Track(
        id: 'trk_serafina',
        accountId: 'acc_pixel_gdrive',
        providerType: CloudProviderType.googleDrive,
        remotePathOrId: '/Music/Expressive/Serafina_Neon_Horizon.flac',
        title: 'Serafina',
        artist: 'Velvet Sun',
        album: 'Neon Horizon (Material You Master)',
        durationMs: 255000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2022/03/24/audio_34b3e34b9e.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800&q=80',
        bitrateKbps: 3200,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'FLAC',
        sizeBytes: 102000000,
        dominantColorValue: 0xFF7C3AED,
        isFavorite: true,
        playCount: 112,
        syncedLyrics: sampleLyrics1,
      ),
      Track(
        id: 'trk_elena',
        accountId: 'acc_jellyfin_home',
        providerType: CloudProviderType.webdav,
        remotePathOrId: 'webdav_elena_nocturne.flac',
        title: 'Elena',
        artist: 'Nocturne',
        album: 'Material You Expressive Sessions',
        durationMs: 188000,
        streamUrl: 'https://cdn.pixabay.com/download/audio/2021/09/06/audio_92429813c9.mp3',
        artworkUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=800&q=80',
        bitrateKbps: 2840,
        bitDepth: 24,
        sampleRateHz: 96000,
        codec: 'FLAC',
        sizeBytes: 67000000,
        dominantColorValue: 0xFF9333EA,
        isFavorite: true,
        playCount: 88,
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
