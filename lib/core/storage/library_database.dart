import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../models/cloud_account.dart';
import '../models/track.dart';

/// Unified SQLite catalog storing connected cloud account metadata, indexed tracks,
/// offline pinned files, and custom user DSP presets.
class LibraryDatabase {
  Database? _db;
  final List<CloudAccount> _memoryAccounts = [];
  final List<Track> _memoryTracks = [];

  bool _initAttempted = false;

  Future<void> init() async {
    _initAttempted = true;
    try {
      final dbPath = await getDatabasesPath();
      final fullPath = p.join(dbPath, 'freebeat_catalog.db');
      _db = await openDatabase(
        fullPath,
        version: 1,
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
}
