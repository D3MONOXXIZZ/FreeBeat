import 'package:flutter/material.dart';
import 'cloud_account.dart';

class LyricLine {
  const LyricLine({
    required this.timestampMs,
    required this.text,
  });

  final int timestampMs;
  final String text;
}

class Track {
  const Track({
    required this.id,
    required this.accountId,
    required this.providerType,
    required this.remotePathOrId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.streamUrl,
    this.artworkUrl,
    this.bitrateKbps = 1411,
    this.bitDepth = 24,
    this.sampleRateHz = 96000,
    this.codec = 'FLAC',
    this.channels = 2,
    this.sizeBytes = 42000000,
    this.dominantColorValue = 0xFF6750A4,
    this.isPinnedOffline = false,
    this.localCachePath,
    this.isFavorite = false,
    this.playCount = 0,
    this.syncedLyrics = const [],
  });

  final String id;
  final String accountId;
  final CloudProviderType providerType;
  final String remotePathOrId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String streamUrl;
  final String? artworkUrl;
  final int bitrateKbps;
  final int bitDepth;
  final int sampleRateHz;
  final String codec;
  final int channels;
  final int sizeBytes;
  final int dominantColorValue;
  final bool isPinnedOffline;
  final String? localCachePath;
  final bool isFavorite;
  final int playCount;
  final List<LyricLine> syncedLyrics;

  Color get dominantColor => Color(dominantColorValue);

  bool get isLossless =>
      codec.toUpperCase() == 'FLAC' ||
      codec.toUpperCase() == 'ALAC' ||
      codec.toUpperCase() == 'WAV' ||
      codec.toUpperCase() == 'AIFF';

  bool get isHiRes => isLossless && (bitDepth >= 24 || sampleRateHz > 48000);

  String get formattedSampleRate {
    final khz = sampleRateHz / 1000.0;
    return khz == khz.roundToDouble()
        ? '${khz.toInt()} kHz'
        : '${khz.toStringAsFixed(1)} kHz';
  }

  String get qualityBadgeText {
    if (isHiRes) {
      return 'HI-RES $bitDepth-BIT / $formattedSampleRate • $codec';
    }
    if (isLossless) {
      return 'LOSSLESS $bitDepth-BIT / $formattedSampleRate • $codec';
    }
    return '$codec • $bitrateKbps kbps';
  }

  Duration get duration => Duration(milliseconds: durationMs);

  Track copyWith({
    String? id,
    String? accountId,
    CloudProviderType? providerType,
    String? remotePathOrId,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? streamUrl,
    String? artworkUrl,
    int? bitrateKbps,
    int? bitDepth,
    int? sampleRateHz,
    String? codec,
    int? channels,
    int? sizeBytes,
    int? dominantColorValue,
    bool? isPinnedOffline,
    String? localCachePath,
    bool clearLocalCachePath = false,
    bool? isFavorite,
    int? playCount,
    List<LyricLine>? syncedLyrics,
  }) {
    return Track(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      providerType: providerType ?? this.providerType,
      remotePathOrId: remotePathOrId ?? this.remotePathOrId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      streamUrl: streamUrl ?? this.streamUrl,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      bitDepth: bitDepth ?? this.bitDepth,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      codec: codec ?? this.codec,
      channels: channels ?? this.channels,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      dominantColorValue: dominantColorValue ?? this.dominantColorValue,
      isPinnedOffline: isPinnedOffline ?? this.isPinnedOffline,
      localCachePath: clearLocalCachePath ? null : (localCachePath ?? this.localCachePath),
      isFavorite: isFavorite ?? this.isFavorite,
      playCount: playCount ?? this.playCount,
      syncedLyrics: syncedLyrics ?? this.syncedLyrics,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'accountId': accountId,
      'providerType': providerType.id,
      'remotePathOrId': remotePathOrId,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'streamUrl': streamUrl,
      'artworkUrl': artworkUrl,
      'bitrateKbps': bitrateKbps,
      'bitDepth': bitDepth,
      'sampleRateHz': sampleRateHz,
      'codec': codec,
      'channels': channels,
      'sizeBytes': sizeBytes,
      'dominantColorValue': dominantColorValue,
      'isPinnedOffline': isPinnedOffline ? 1 : 0,
      'localCachePath': localCachePath,
      'isFavorite': isFavorite ? 1 : 0,
      'playCount': playCount,
    };
  }

  factory Track.fromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      accountId: map['accountId'] as String,
      providerType: CloudProviderType.fromId(map['providerType'] as String? ?? ''),
      remotePathOrId: map['remotePathOrId'] as String? ?? '',
      title: map['title'] as String? ?? 'Unknown Track',
      artist: map['artist'] as String? ?? 'Unknown Artist',
      album: map['album'] as String? ?? 'Unknown Album',
      durationMs: map['durationMs'] as int? ?? 180000,
      streamUrl: map['streamUrl'] as String? ?? '',
      artworkUrl: map['artworkUrl'] as String?,
      bitrateKbps: map['bitrateKbps'] as int? ?? 320,
      bitDepth: map['bitDepth'] as int? ?? 16,
      sampleRateHz: map['sampleRateHz'] as int? ?? 44100,
      codec: map['codec'] as String? ?? 'FLAC',
      channels: map['channels'] as int? ?? 2,
      sizeBytes: map['sizeBytes'] as int? ?? 10000000,
      dominantColorValue: map['dominantColorValue'] as int? ?? 0xFF6750A4,
      isPinnedOffline: (map['isPinnedOffline'] as int? ?? 0) == 1,
      localCachePath: map['localCachePath'] as String?,
      isFavorite: (map['isFavorite'] as int? ?? 0) == 1,
      playCount: map['playCount'] as int? ?? 0,
    );
  }
}
