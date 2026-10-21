import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/cloud_account.dart';
import '../models/playlist.dart';
import '../models/poweramp_dsp_state.dart';
import '../models/track.dart';

/// Unified SQLite catalog storing connected cloud account metadata, indexed tracks,
/// offline pinned files, and custom user playlists.
class LibraryDatabase {
  Database? _db;
  final List<CloudAccount> _memoryAccounts = [];
  final List<Track> _memoryTracks = [];
  final List<Playlist> _memoryPlaylists = [];
  final List<DspPreset> _memoryCustomPresets = [];
  final Map<String, String> _memoryDeviceProfiles = {
    'BLUETOOTH': 'harman_target',
    'USB_DAC': 'flat',
    'WIRED_HEADPHONES': 'hifi_warm_tube',
    'BUILTIN_SPEAKER': 'vocal',
  };

  bool _initAttempted = false;

  Future<void> init() async {
    _initAttempted = true;
    try {
      final dbPath = await getDatabasesPath();
      final fullPath = p.join(dbPath, 'freebeat_catalog.db');
      _db = await openDatabase(
        fullPath,
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE cloud_accounts (
              id TEXT PRIMARY KEY,
              providerType TEXT NOT NULL,
              displayName TEXT NOT NULL,
              endpointOrFolder TEXT NOT NULL,
              usernameOrEmail TEXT,
              bucketOrShareName TEXT,
              region TEXT,
              isConnected INTEGER DEFAULT 1,
              lastSyncedAt INTEGER,
              indexedTrackCount INTEGER DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE tracks (
              id TEXT PRIMARY KEY,
              accountId TEXT NOT NULL,
              providerType TEXT NOT NULL,
              remotePathOrId TEXT NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              durationMs INTEGER NOT NULL,
              streamUrl TEXT NOT NULL,
              artworkUrl TEXT,
              bitrateKbps INTEGER,
              bitDepth INTEGER,
              sampleRateHz INTEGER,
              codec TEXT,
              channels INTEGER,
              sizeBytes INTEGER,
              dominantColorValue INTEGER,
              isPinnedOffline INTEGER DEFAULT 0,
              localCachePath TEXT,
              isFavorite INTEGER DEFAULT 0,
              playCount INTEGER DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS playlists (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT,
              trackIdsJson TEXT,
              createdAt INTEGER NOT NULL,
              updatedAt INTEGER NOT NULL,
              isSmart INTEGER DEFAULT 0,
              smartType TEXT,
              customArtworkUrl TEXT,
              colorSeedValue INTEGER DEFAULT 6770852,
              syncSourceUrl TEXT,
              lastSyncedAt INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS custom_dsp_presets (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              category TEXT NOT NULL,
              preampDb REAL NOT NULL,
              bandGainsJson TEXT NOT NULL,
              bassTone REAL NOT NULL,
              trebleTone REAL NOT NULL,
              stereoExpansion REAL NOT NULL,
              qFactorsJson TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS device_preset_profiles (
              routeKey TEXT PRIMARY KEY,
              presetId TEXT NOT NULL
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS playlists (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                description TEXT,
                trackIdsJson TEXT,
                createdAt INTEGER NOT NULL,
                updatedAt INTEGER NOT NULL,
                isSmart INTEGER DEFAULT 0,
                smartType TEXT,
                customArtworkUrl TEXT,
                colorSeedValue INTEGER DEFAULT 6770852
              )
            ''');
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS custom_dsp_presets (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                preampDb REAL NOT NULL,
                bandGainsJson TEXT NOT NULL,
                bassTone REAL NOT NULL,
                trebleTone REAL NOT NULL,
                stereoExpansion REAL NOT NULL,
                qFactorsJson TEXT
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS device_preset_profiles (
                routeKey TEXT PRIMARY KEY,
                presetId TEXT NOT NULL
              )
            ''');
          }
          if (oldVersion < 4) {
            try {
              await db.execute('ALTER TABLE playlists ADD COLUMN syncSourceUrl TEXT');
            } catch (_) {}
            try {
              await db.execute('ALTER TABLE playlists ADD COLUMN lastSyncedAt INTEGER');
            } catch (_) {}
          }
        },
      );
    } catch (_) {
      // Runs with in-memory store in test environments without native sqflite platform channels
      _db = null;
    }
  }

  Future<void> _ensureInitialized() async {
    if (_db == null && !_initAttempted) {
      await init();
    }
  }

  Future<List<CloudAccount>> loadAccounts() async {
    await _ensureInitialized();
    if (_db == null) return List.unmodifiable(_memoryAccounts);
    final rows = await _db!.query('cloud_accounts');
    return rows.map(CloudAccount.fromMap).toList();
  }

  Future<void> upsertAccount(CloudAccount account) async {
    await _ensureInitialized();
    _memoryAccounts.removeWhere((a) => a.id == account.id);
    _memoryAccounts.add(account);
    if (_db != null) {
      await _db!.insert(
        'cloud_accounts',
        account.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> removeAccount(String accountId) async {
    await _ensureInitialized();
    _memoryAccounts.removeWhere((a) => a.id == accountId);
    _memoryTracks.removeWhere((t) => t.accountId == accountId);
    if (_db != null) {
      await _db!.delete('cloud_accounts', where: 'id = ?', whereArgs: [accountId]);
      await _db!.delete('tracks', where: 'accountId = ?', whereArgs: [accountId]);
    }
  }

  Future<List<Track>> loadTracks() async {
    await _ensureInitialized();
    if (_db == null) return List.unmodifiable(_memoryTracks);
    final rows = await _db!.query('tracks');
    return rows.map(Track.fromMap).toList();
  }

  Future<void> upsertTracks(List<Track> tracks) async {
    await _ensureInitialized();
    for (final track in tracks) {
      final idx = _memoryTracks.indexWhere((t) => t.id == track.id);
      if (idx >= 0) {
        _memoryTracks[idx] = track;
      } else {
        _memoryTracks.add(track);
      }
    }
    if (_db != null) {
      final batch = _db!.batch();
      for (final track in tracks) {
        batch.insert(
          'tracks',
          track.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 2: Playlist Operations
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<Playlist>> loadPlaylists() async {
    await _ensureInitialized();
    if (_db == null) return List.unmodifiable(_memoryPlaylists);
    final rows = await _db!.query('playlists', orderBy: 'updatedAt DESC');
    return rows.map(Playlist.fromMap).toList();
  }

  Future<void> upsertPlaylist(Playlist playlist) async {
    await _ensureInitialized();
    _memoryPlaylists.removeWhere((p) => p.id == playlist.id);
    _memoryPlaylists.insert(0, playlist);
    if (_db != null) {
      await _db!.insert(
        'playlists',
        playlist.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _ensureInitialized();
    _memoryPlaylists.removeWhere((p) => p.id == playlistId);
    if (_db != null) {
      await _db!.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    }
  }

  Future<void> deleteTracks(List<String> trackIds) async {
    await _ensureInitialized();
    _memoryTracks.removeWhere((t) => trackIds.contains(t.id));
    if (_db != null) {
      final batch = _db!.batch();
      for (final id in trackIds) {
        batch.delete('tracks', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 3: Custom Audiophile DSP Presets & Hardware Device Routing Profiles
  // ───────────────────────────────────────────────────────────────────────────

  Future<List<DspPreset>> loadCustomPresets() async {
    await _ensureInitialized();
    if (_db == null) return List.unmodifiable(_memoryCustomPresets);
    final rows = await _db!.query('custom_dsp_presets');
    return rows.map((r) {
      final bandGains = (jsonDecode(r['bandGainsJson'] as String) as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList();
      List<double>? qFactors;
      if (r['qFactorsJson'] != null) {
        qFactors = (jsonDecode(r['qFactorsJson'] as String) as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
      }
      return DspPreset(
        id: r['id'] as String,
        name: r['name'] as String,
        category: r['category'] as String,
        preampDb: (r['preampDb'] as num).toDouble(),
        bandGainsDb: bandGains,
        bassTone: (r['bassTone'] as num).toDouble(),
        trebleTone: (r['trebleTone'] as num).toDouble(),
        stereoExpansion: (r['stereoExpansion'] as num).toDouble(),
        isCustom: true,
        qFactors: qFactors,
      );
    }).toList();
  }

  Future<void> saveCustomPreset(DspPreset preset) async {
    await _ensureInitialized();
    _memoryCustomPresets.removeWhere((p) => p.id == preset.id);
    _memoryCustomPresets.add(preset);
    if (_db != null) {
      await _db!.insert(
        'custom_dsp_presets',
        {
          'id': preset.id,
          'name': preset.name,
          'category': preset.category,
          'preampDb': preset.preampDb,
          'bandGainsJson': jsonEncode(preset.bandGainsDb),
          'bassTone': preset.bassTone,
          'trebleTone': preset.trebleTone,
          'stereoExpansion': preset.stereoExpansion,
          'qFactorsJson': jsonEncode(preset.effectiveQFactors),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> deleteCustomPreset(String id) async {
    await _ensureInitialized();
    _memoryCustomPresets.removeWhere((p) => p.id == id);
    if (_db != null) {
      await _db!.delete('custom_dsp_presets', where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<Map<String, String>> loadDeviceProfiles() async {
    await _ensureInitialized();
    if (_db == null) return Map.unmodifiable(_memoryDeviceProfiles);
    final rows = await _db!.query('device_preset_profiles');
    if (rows.isEmpty) {
      return Map.unmodifiable(_memoryDeviceProfiles);
    }
    final map = <String, String>{};
    for (final r in rows) {
      String pid = r['presetId'] as String;
      if (pid == 'vocal_clarity') pid = 'vocal';
      if (pid == 'poweramp_bass_treble') pid = 'smart_eq_bass_treble';
      if (pid == 'concert_hall') pid = 'concert';
      if (pid == 'rock_metal') pid = 'rock';
      if (pid == 'bass') pid = 'bass_boost';
      map[r['routeKey'] as String] = pid;
    }
    return map;
  }

  Future<void> saveDeviceProfile(String routeKey, String presetId) async {
    await _ensureInitialized();
    _memoryDeviceProfiles[routeKey] = presetId;
    if (_db != null) {
      await _db!.insert(
        'device_preset_profiles',
        {'routeKey': routeKey, 'presetId': presetId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }
}

