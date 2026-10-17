import 'dart:convert';
import 'package:flutter/material.dart';

/// Represents a user-curated or smart dynamic playlist in FreeBeat.
class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    this.description = '',
    this.trackIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isSmart = false,
    this.smartType,
    this.customArtworkUrl,
    this.colorSeedValue = 0xFF6750A4,
  });

  final String id;
  final String title;
  final String description;
  final List<String> trackIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSmart;
  final String? smartType; // 'hires', 'offline', 'favorites', 'heavy_rotation', 'recently_added'
  final String? customArtworkUrl;
  final int colorSeedValue;

  Color get colorSeed => Color(colorSeedValue);
  int get trackCount => trackIds.length;

  Playlist copyWith({
    String? id,
    String? title,
    String? description,
    List<String>? trackIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSmart,
    String? smartType,
    String? customArtworkUrl,
    int? colorSeedValue,
  }) {
    return Playlist(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      trackIds: trackIds ?? this.trackIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSmart: isSmart ?? this.isSmart,
      smartType: smartType ?? this.smartType,
      customArtworkUrl: customArtworkUrl ?? this.customArtworkUrl,
      colorSeedValue: colorSeedValue ?? this.colorSeedValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'trackIdsJson': jsonEncode(trackIds),
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'isSmart': isSmart ? 1 : 0,
      'smartType': smartType,
      'customArtworkUrl': customArtworkUrl,
      'colorSeedValue': colorSeedValue,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    List<String> parsedIds = [];
    if (map['trackIdsJson'] != null) {
      try {
        final decoded = jsonDecode(map['trackIdsJson'] as String);
        if (decoded is List) {
          parsedIds = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return Playlist(
      id: map['id'] as String,
      title: map['title'] as String,
      description: (map['description'] as String?) ?? '',
      trackIds: parsedIds,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['createdAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updatedAt'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isSmart: (map['isSmart'] as int?) == 1,
      smartType: map['smartType'] as String?,
      customArtworkUrl: map['customArtworkUrl'] as String?,
      colorSeedValue: (map['colorSeedValue'] as int?) ?? 0xFF6750A4,
    );
  }
}
