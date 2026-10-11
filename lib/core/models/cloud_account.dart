import 'package:flutter/material.dart';

/// All 12 supported cloud storage, media server, network, and OS provider types.
enum CloudProviderType {
  googleDrive(
    id: 'google_drive',
    displayName: 'Google Drive',
    subtitle: 'OAuth2 PKCE • Lossless FLAC/MP3/WAV Stream',
    category: CloudProviderCategory.oauthConsumer,
    icon: Icons.add_to_drive_rounded,
    accentColorValue: 0xFF4285F4,
  ),
  oneDrive(
    id: 'onedrive',
    displayName: 'Microsoft OneDrive',
    subtitle: 'MS Graph OAuth2 • Personal & Business Cloud',
    category: CloudProviderCategory.oauthConsumer,
    icon: Icons.cloud_queue_rounded,
    accentColorValue: 0xFF0078D4,
  ),
  dropbox(
    id: 'dropbox',
    displayName: 'Dropbox',
    subtitle: 'OAuth2 v2 API • Direct Byte-Range Streaming',
    category: CloudProviderCategory.oauthConsumer,
    icon: Icons.inventory_2_rounded,
    accentColorValue: 0xFF0061FF,
  ),
  box(
    id: 'box',
    displayName: 'Box Cloud',
    subtitle: 'OAuth2 Enterprise & Personal Storage',
    category: CloudProviderCategory.oauthConsumer,
    icon: Icons.folder_copy_rounded,
    accentColorValue: 0xFF0061D5,
  ),
  jellyfin(
    id: 'jellyfin',
    displayName: 'Jellyfin / Emby',
    subtitle: 'Self-Hosted Media Server • Hi-Fi Direct & Transcode',
    category: CloudProviderCategory.mediaServer,
    icon: Icons.dns_rounded,
    accentColorValue: 0xFFAA5CC3,
  ),
  subsonic(
    id: 'subsonic',
    displayName: 'Navidrome / Subsonic',
    subtitle: 'OpenSubsonic API • Lyrics, Artwork & Bitrate Control',
    category: CloudProviderCategory.mediaServer,
    icon: Icons.surround_sound_rounded,
    accentColorValue: 0xFF1DB954,
  ),
  webdav(
    id: 'webdav',
    displayName: 'WebDAV / Nextcloud',
    subtitle: 'Nextcloud, ownCloud, Koofr, Synology WebDAV',
    category: CloudProviderCategory.openProtocol,
    icon: Icons.language_rounded,
    accentColorValue: 0xFF0082C9,
  ),
  s3(
    id: 's3',
    displayName: 'S3 / Cloudflare R2 / MinIO',
    subtitle: 'AWS SigV4 • S3, Cloudflare R2, Backblaze B2, MinIO',
    category: CloudProviderCategory.openProtocol,
    icon: Icons.storage_rounded,
    accentColorValue: 0xFFFF9900,
  ),
  sftp(
    id: 'sftp',
    displayName: 'SFTP / SSH NAS',
    subtitle: 'Encrypted SSH File Transfer • Home Lab & NAS',
    category: CloudProviderCategory.localAndOs,
    icon: Icons.terminal_rounded,
    accentColorValue: 0xFF26A69A,
  ),
  smb(
    id: 'smb',
    displayName: 'SMB / LAN Share',
    subtitle: 'Windows / Samba / TrueNAS Local Network Share',
    category: CloudProviderCategory.localAndOs,
    icon: Icons.lan_rounded,
    accentColorValue: 0xFF5C6BC0,
  ),
  androidSaf(
    id: 'android_saf',
    displayName: 'Android Cloud Mount (SAF)',
    subtitle: 'Mount Any Cloud App Installed on Your Phone',
    category: CloudProviderCategory.localAndOs,
    icon: Icons.phone_android_rounded,
    accentColorValue: 0xFF3DDC84,
  ),
  demoCloud(
    id: 'demo_cloud',
    displayName: 'Pixel Hi-Fi Demo Cloud',
    subtitle: '24-Bit/96kHz Lossless & Synced Lyrics Showcase',
    category: CloudProviderCategory.oauthConsumer,
    icon: Icons.auto_awesome_rounded,
    accentColorValue: 0xFFD0BCFF,
  );

  const CloudProviderType({
    required this.id,
    required this.displayName,
    required this.subtitle,
    required this.category,
    required this.icon,
    required this.accentColorValue,
  });

  final String id;
  final String displayName;
  final String subtitle;
  final CloudProviderCategory category;
  final IconData icon;
  final int accentColorValue;

  Color get accentColor => Color(accentColorValue);

  static CloudProviderType fromId(String id) {
    return CloudProviderType.values.firstWhere(
      (e) => e.id == id,
      orElse: () => CloudProviderType.demoCloud,
    );
  }
}

enum CloudProviderCategory {
  oauthConsumer('Consumer Clouds (OAuth2 PKCE)'),
  mediaServer('Self-Hosted Media Servers'),
  openProtocol('Open & Object Storage Protocols'),
  localAndOs('NAS & Android OS Cloud Mounts');

  const CloudProviderCategory(this.title);
  final String title;
}

class CloudAccount {
  const CloudAccount({
    required this.id,
    required this.providerType,
    required this.displayName,
    required this.endpointOrFolder,
    this.usernameOrEmail = '',
    this.bucketOrShareName = '',
    this.region = 'auto',
    this.isConnected = true,
    this.lastSyncedAt,
    this.indexedTrackCount = 0,
  });

  final String id;
  final CloudProviderType providerType;
  final String displayName;
  final String endpointOrFolder;
  final String usernameOrEmail;
  final String bucketOrShareName;
  final String region;
  final bool isConnected;
  final DateTime? lastSyncedAt;
  final int indexedTrackCount;

  CloudAccount copyWith({
    String? id,
    CloudProviderType? providerType,
    String? displayName,
    String? endpointOrFolder,
    String? usernameOrEmail,
    String? bucketOrShareName,
    String? region,
    bool? isConnected,
    DateTime? lastSyncedAt,
    int? indexedTrackCount,
  }) {
    return CloudAccount(
      id: id ?? this.id,
      providerType: providerType ?? this.providerType,
      displayName: displayName ?? this.displayName,
      endpointOrFolder: endpointOrFolder ?? this.endpointOrFolder,
      usernameOrEmail: usernameOrEmail ?? this.usernameOrEmail,
      bucketOrShareName: bucketOrShareName ?? this.bucketOrShareName,
      region: region ?? this.region,
      isConnected: isConnected ?? this.isConnected,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      indexedTrackCount: indexedTrackCount ?? this.indexedTrackCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'providerType': providerType.id,
      'displayName': displayName,
      'endpointOrFolder': endpointOrFolder,
      'usernameOrEmail': usernameOrEmail,
      'bucketOrShareName': bucketOrShareName,
      'region': region,
      'isConnected': isConnected ? 1 : 0,
      'lastSyncedAt': lastSyncedAt?.millisecondsSinceEpoch,
      'indexedTrackCount': indexedTrackCount,
    };
  }

  factory CloudAccount.fromMap(Map<String, dynamic> map) {
    return CloudAccount(
      id: map['id'] as String,
      providerType: CloudProviderType.fromId(map['providerType'] as String? ?? ''),
      displayName: map['displayName'] as String? ?? 'Cloud Drive',
      endpointOrFolder: map['endpointOrFolder'] as String? ?? '/',
      usernameOrEmail: map['usernameOrEmail'] as String? ?? '',
      bucketOrShareName: map['bucketOrShareName'] as String? ?? '',
      region: map['region'] as String? ?? 'auto',
      isConnected: (map['isConnected'] as int? ?? 1) == 1,
      lastSyncedAt: map['lastSyncedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSyncedAt'] as int)
          : null,
      indexedTrackCount: map['indexedTrackCount'] as int? ?? 0,
    );
  }
}
