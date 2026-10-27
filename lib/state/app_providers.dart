import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/audio_quality_settings.dart';
import '../core/models/cloud_account.dart';
import '../core/models/playlist.dart';
import '../core/models/power_saver_settings.dart';
import '../core/models/poweramp_dsp_state.dart';
import '../core/models/track.dart';
import '../core/storage/library_database.dart';
import '../core/storage/secure_credential_store.dart';
import '../providers/implementations/network_and_saf_connectors.dart';
import '../services/audio/cloud_audio_cache_service.dart';
import '../services/audio/cloud_stream_proxy.dart';
import '../services/audio/poweramp_dsp_service.dart';
import '../services/auth/native_cloud_auth_service.dart';
import '../services/audio/download_queue_manager.dart';
import '../services/audio/universal_audio_transcoder_service.dart';
import '../services/discovery/local_media_server_discovery_service.dart';
import '../services/haptics/pixel_haptics.dart';
import '../services/metadata/artwork_and_lyrics_service.dart';
import '../services/metadata/artwork_extractor.dart';
import '../services/metadata/artist_helper.dart';
import '../services/metadata/range_tag_parser.dart';
import '../services/metadata/track_tag_writer_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Core Infrastructure Providers
// ─────────────────────────────────────────────────────────────────────────────

final credentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  return SecureCredentialStore();
});

final libraryDatabaseProvider = Provider<LibraryDatabase>((ref) {
  return LibraryDatabase();
});

final connectorRegistryProvider = Provider<CloudConnectorRegistry>((ref) {
  return CloudConnectorRegistry();
});

final nativeCloudAuthServiceProvider = Provider<NativeCloudAuthService>((ref) {
  return NativeCloudAuthService();
});

final localMediaServerDiscoveryServiceProvider =
    Provider<LocalMediaServerDiscoveryService>((ref) {
  return LocalMediaServerDiscoveryService();
});

final powerampDspServiceProvider = Provider<PowerampDspService>((ref) {
  return PowerampDspService();
});

final universalAudioTranscoderServiceProvider =
    Provider<UniversalAudioTranscoderService>((ref) {
  return UniversalAudioTranscoderService();
});

final cloudStreamProxyProvider = Provider<CloudStreamProxy>((ref) {
  final proxy = CloudStreamProxy(
    connectorRegistry: ref.watch(connectorRegistryProvider),
    credentialStore: ref.watch(credentialStoreProvider),
  );
  ref.onDispose(proxy.dispose);
  return proxy;
});

final artworkAndLyricsServiceProvider =
    Provider<ArtworkAndLyricsService>((ref) {
  return ArtworkAndLyricsService();
});

final trackTagWriterServiceProvider = Provider<TrackTagWriterService>((ref) {
  return const TrackTagWriterService();
});

final cloudAudioCacheServiceProvider =
    ChangeNotifierProvider<CloudAudioCacheService>((ref) {
  return CloudAudioCacheService(
    credentialStore: ref.watch(credentialStoreProvider),
  );
});

final downloadQueueManagerProvider =
    ChangeNotifierProvider<DownloadQueueManager>((ref) {
  final cacheSvc = ref.watch(cloudAudioCacheServiceProvider);
  final db = ref.watch(libraryDatabaseProvider);
  return DownloadQueueManager(
    cacheService: cacheSvc,
    database: db,
    onTrackPinned: (updated) {
      ref.read(tracksCatalogProvider.notifier).updateTrack(updated);
    },
  );
});

final storageUsageFutureProvider = FutureProvider<StorageUsageInfo>((ref) async {
  final cacheSvc = ref.watch(cloudAudioCacheServiceProvider);
  final tracks = ref.watch(tracksCatalogProvider);
  return cacheSvc.getStorageUsage(tracks);
});

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic System Theme Mode & Brightness Providers
// ─────────────────────────────────────────────────────────────────────────────

/// System theme mode provider bound to ThemeMode.system by default.
/// Automatically reacts to system dark/light mode preference changes and permits user override.
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier([super.initial = ThemeMode.system]);

  void setMode(ThemeMode mode) {
    state = mode;
  }

  void toggle() {
    if (state == ThemeMode.system) {
      state = ThemeMode.dark;
    } else if (state == ThemeMode.dark) {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.system;
    }
  }
}

/// Provider tracking system-level platform brightness in real time.
final systemBrightnessProvider =
    StateNotifierProvider<SystemBrightnessNotifier, Brightness>((ref) {
  return SystemBrightnessNotifier();
});

class SystemBrightnessNotifier extends StateNotifier<Brightness> {
  SystemBrightnessNotifier()
      : super(WidgetsBinding.instance.platformDispatcher.platformBrightness);

  void updateBrightness(Brightness brightness) {
    if (state != brightness) {
      state = brightness;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Power Saver Mode & Device Battery Providers
// ─────────────────────────────────────────────────────────────────────────────

/// Master Power Saver configuration notifier with SharedPreferences persistence.
final powerSaverProvider =
    StateNotifierProvider<PowerSaverNotifier, PowerSaverSettings>((ref) {
  return PowerSaverNotifier();
});

class PowerSaverNotifier extends StateNotifier<PowerSaverSettings> {
  PowerSaverNotifier() : super(const PowerSaverSettings()) {
    _loadFromPrefs();
  }

  static const String _prefsKey = 'freebeat_power_saver_settings_v1';

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        state = PowerSaverSettings.fromJson(jsonStr);
      }
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, state.toJson());
    } catch (_) {}
  }

  void toggleMaster() {
    state = state.copyWith(isEnabled: !state.isEnabled);
    _saveToPrefs();
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(isEnabled: enabled);
    _saveToPrefs();
  }

  void setAutoOnSystemSaver(bool value) {
    state = state.copyWith(autoOnSystemSaver: value);
    _saveToPrefs();
  }

  void setAutoBelowBatteryPercent(int percent) {
    state = state.copyWith(autoBelowBatteryPercent: percent);
    _saveToPrefs();
  }

  void setAmoledPitchBlack(bool value) {
    state = state.copyWith(amoledPitchBlack: value);
    _saveToPrefs();
  }

  void setDisableBlurAndAura(bool value) {
    state = state.copyWith(disableBlurAndAura: value);
    _saveToPrefs();
  }

  void setPauseVisualizers(bool value) {
    state = state.copyWith(pauseVisualizers: value);
    _saveToPrefs();
  }

  void setCapRefreshRate60Hz(bool value) {
    state = state.copyWith(capRefreshRate60Hz: value);
    _saveToPrefs();
  }

  void setSmartWifiLock(bool value) {
    state = state.copyWith(smartWifiLock: value);
    _saveToPrefs();
  }

  void setReducePreloadCount(bool value) {
    state = state.copyWith(reducePreloadCount: value);
    _saveToPrefs();
  }

  void setDisableHaptics(bool value) {
    state = state.copyWith(disableHaptics: value);
    _saveToPrefs();
  }

  void setThrottleBackgroundTicks(bool value) {
    state = state.copyWith(throttleBackgroundTicks: value);
    _saveToPrefs();
  }
}

/// Real-time native battery state provider.
final deviceBatteryStatusProvider =
    StateNotifierProvider<DeviceBatteryStatusNotifier, DeviceBatteryStatus>((ref) {
  final dspSvc = ref.watch(powerampDspServiceProvider);
  return DeviceBatteryStatusNotifier(dspSvc);
});

class DeviceBatteryStatusNotifier extends StateNotifier<DeviceBatteryStatus> {
  DeviceBatteryStatusNotifier([this._dspSvc]) : super(const DeviceBatteryStatus()) {
    _initNativeChannel();
  }

  final PowerampDspService? _dspSvc;
  static const MethodChannel _dspChannel = MethodChannel('com.freebeat.app/dsp');

  Future<void> _initNativeChannel() async {
    if (!Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final map = await _dspChannel.invokeMethod<Map<dynamic, dynamic>>('getBatteryStatus');
      final isIgnoring = await isIgnoringBatteryOptimizations();
      if (map != null) {
        final m = Map<String, dynamic>.from(map);
        m['isIgnoringBatteryOptimizations'] = isIgnoring;
        _updateFromMap(m);
      }
    } catch (_) {}

    _dspSvc?.setBatteryStateListener((map) async {
      final isIgnoring = await isIgnoringBatteryOptimizations();
      final m = Map<String, dynamic>.from(map);
      m['isIgnoringBatteryOptimizations'] = isIgnoring;
      _updateFromMap(m);
    });
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      final res = await _dspChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) return true;
    try {
      final res = await _dspChannel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      final isIgnoring = await isIgnoringBatteryOptimizations();
      state = state.copyWith(isIgnoringBatteryOptimizations: isIgnoring);
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  void _updateFromMap(Map<String, dynamic> map) {
    state = DeviceBatteryStatus(
      batteryLevel: map['batteryLevel'] as int? ?? 100,
      isCharging: map['isCharging'] as bool? ?? false,
      isPowerSaveMode: map['isPowerSaveMode'] as bool? ?? false,
      isIgnoringBatteryOptimizations:
          map['isIgnoringBatteryOptimizations'] as bool? ?? state.isIgnoringBatteryOptimizations,
    );
  }

  void updateMockState(DeviceBatteryStatus status) {
    state = status;
  }
}

/// Evaluates whether Power Saver Mode should actively apply across UI and Audio engine.
final effectivePowerSaverActiveProvider = Provider<bool>((ref) {
  final settings = ref.watch(powerSaverProvider);
  bool isActive = false;
  if (settings.isEnabled) {
    isActive = true;
  } else {
    final battery = ref.watch(deviceBatteryStatusProvider);
    if (settings.autoOnSystemSaver && battery.isPowerSaveMode) {
      isActive = true;
    } else if (settings.autoBelowBatteryPercent > 0 &&
        battery.batteryLevel > 0 &&
        battery.batteryLevel <= settings.autoBelowBatteryPercent &&
        !battery.isCharging) {
      isActive = true;
    }
  }

  PixelHaptics.powerSaverEnabled = isActive && settings.disableHaptics;

  if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('com.freebeat.app/dsp');
      final targetRate = (isActive && settings.capRefreshRate60Hz) ? 60.0 : 0.0;
      channel.invokeMethod('setPreferredRefreshRate', {'rate': targetRate});
    } catch (_) {}
  }

  return isActive;
});

// ─────────────────────────────────────────────────────────────────────────────
// Cloud Accounts & Unified Track Catalog State
// ─────────────────────────────────────────────────────────────────────────────

class CloudAccountsNotifier extends StateNotifier<List<CloudAccount>> {
  CloudAccountsNotifier(this._db, this._credStore, [this._ref]) : super(const []) {
    _loadFromDb();
  }

  final LibraryDatabase _db;
  final SecureCredentialStore _credStore;
  final Ref? _ref;
  static const String _prefsKey = 'freebeat_persisted_cloud_accounts';

  Future<void> _loadFromDb() async {
    // 1. Immediately restore from SharedPreferences for zero-latency UI persistence
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as List<dynamic>;
        final prefAccounts = decoded
            .map((item) => CloudAccount.fromMap(item as Map<String, dynamic>))
            .where((a) =>
                a.id != 'acc_pixel_gdrive' &&
                a.id != 'acc_jellyfin_home' &&
                a.id != 'acc_cloudflare_r2' &&
                a.providerType != CloudProviderType.demoCloud)
            .toList();
        if (prefAccounts.isNotEmpty && state.isEmpty) {
          state = prefAccounts;
        }
      }
    } catch (e) {
      debugPrint('Error loading cloud accounts from SharedPreferences: $e');
    }

    // 2. Synchronize and merge with SQLite database
    try {
      final loaded = await _db.loadAccounts();
      final sanitizedAccounts = loaded.where((a) {
        final isDemo = a.id == 'acc_pixel_gdrive' ||
            a.id == 'acc_jellyfin_home' ||
            a.id == 'acc_cloudflare_r2' ||
            a.providerType == CloudProviderType.demoCloud;
        if (isDemo) {
          unawaited(_db.removeAccount(a.id));
        }
        return !isDemo;
      }).toList();

      if (sanitizedAccounts.isNotEmpty) {
        final mergedMap = <String, CloudAccount>{};
        for (final a in state) {
          mergedMap[a.id] = a;
        }
        for (final a in sanitizedAccounts) {
          mergedMap[a.id] = a;
        }
        state = mergedMap.values.toList();
        _saveToPrefs();
      } else if (state.isNotEmpty) {
        // SQLite was empty on clean boot or test, backfill from SharedPreferences
        for (final a in state) {
          await _db.upsertAccount(a);
        }
      }
    } catch (e) {
      debugPrint('Error loading cloud accounts from SQLite: $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.map((a) => a.toMap()).toList();
      await prefs.setString(_prefsKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving cloud accounts to SharedPreferences: $e');
    }
  }

  void loadSampleDemoAccounts() {}

  Future<void> addAccount(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    await _credStore.saveSecrets(account.id, secrets);
    await _db.upsertAccount(account);
    state = [...state.where((a) => a.id != account.id), account];
    await _saveToPrefs();
    await PixelHaptics.hifiConfirm();
  }

  Future<void> removeAccount(String accountId) async {
    await _credStore.deleteSecrets(accountId);
    await _db.removeAccount(accountId);
    state = state.where((a) => a.id != accountId).toList();
    if (_ref != null) {
      await _ref.read(tracksCatalogProvider.notifier).removeTracksForAccount(accountId);
    }
    await _saveToPrefs();
    await PixelHaptics.tick();
  }
}

final cloudAccountsProvider =
    StateNotifierProvider<CloudAccountsNotifier, List<CloudAccount>>((ref) {
  return CloudAccountsNotifier(
    ref.watch(libraryDatabaseProvider),
    ref.watch(credentialStoreProvider),
    ref,
  );
});

class TracksCatalogNotifier extends StateNotifier<List<Track>> {
  TracksCatalogNotifier([this._db, this._ref]) : super(const []) {
    if (_db != null) {
      _loadFromDb();
    }
  }

  final LibraryDatabase? _db;
  final Ref? _ref;

  static final RegExp _nonAudioExtensionRegex = RegExp(
    r'\.(pdf|doc|docx|xls|xlsx|ppt|pptx|txt|rtf|csv|json|xml|html|htm|zip|rar|tar|gz|7z|apk|exe|dmg|iso|jpg|jpeg|png|gif|webp|svg|bmp|mp4|mkv|avi|mov|wmv|flv)$',
    caseSensitive: false,
  );

  static final RegExp _audioExtensionRegex = RegExp(
    r'\.(mp3|flac|m4a|wav|ogg|opus|aac|alac|aiff|aif|wma|asf|ape|dsd|dsf|dff|mka)$',
    caseSensitive: false,
  );

  /// Validates whether a track represents authentic, playable audio and rejects documents, images, and non-audio files.
  static bool isValidAudioTrack(Track track) {
    final title = track.title.toLowerCase().trim();
    final url = track.streamUrl.toLowerCase().trim();
    final path = track.remotePathOrId.toLowerCase().trim();

    // Explicitly reject non-audio documents, images, and archives
    if (_nonAudioExtensionRegex.hasMatch(title) ||
        _nonAudioExtensionRegex.hasMatch(url) ||
        _nonAudioExtensionRegex.hasMatch(path)) {
      return false;
    }

    // If it has a recognized audio extension, accept
    if (_audioExtensionRegex.hasMatch(title) ||
        _audioExtensionRegex.hasMatch(url) ||
        _audioExtensionRegex.hasMatch(path)) {
      return true;
    }

    // For stream URLs with no extensions (e.g. JioSaavn / iTunes / Google Drive alt=media):
    // Accept if the codec is a known valid audio codec
    final codec = track.codec.toUpperCase();
    const validCodecs = {
      'MP3', 'FLAC', 'AAC', 'M4A', 'OGG', 'OPUS', 'WAV', 'ALAC', 'AIFF', 'WMA', 'APE', 'DSD'
    };
    if (validCodecs.contains(codec)) {
      return true;
    }

    return false;
  }

  Future<void> _loadFromDb() async {
    if (_db == null) return;
    final loaded = await _db.loadTracks();
    if (loaded.isNotEmpty) {
      final nonAudioIds = <String>[];
      final sanitized = <Track>[];
      for (final t in loaded) {
        // Automatically purge any legacy sample/demo showcase tracks
        if (t.accountId == 'acc_pixel_gdrive' ||
            t.accountId == 'acc_jellyfin_home' ||
            t.accountId == 'acc_cloudflare_r2' ||
            t.id == 'trk_astral_meadow' ||
            t.id == 'trk_blue_crane' ||
            t.id.startsWith('trk_demo_') ||
            t.providerType == CloudProviderType.demoCloud) {
          nonAudioIds.add(t.id);
          continue;
        }
        if (!isValidAudioTrack(t)) {
          nonAudioIds.add(t.id);
          continue;
        }
        var clean = t;
        if (clean.dominantColorValue == 0xFF3DDC84 ||
            clean.dominantColorValue == 0xFF1DB954) {
          clean = clean.copyWith(dominantColorValue: 0xFF1E293B);
        }
        if (ArtworkAndLyricsService.isInvalidOrGenericArtist(clean.artist) ||
            clean.album == 'Cloud Library' ||
            clean.artist == 'Cloud Artist') {
          final file = File(clean.streamUrl);
          if (file.existsSync()) {
            try {
              final parsed = await RangeTagParser.parseLocalFile(file);
              if (parsed.artist != null &&
                  !ArtworkAndLyricsService.isInvalidOrGenericArtist(parsed.artist)) {
                clean = clean.copyWith(
                  artist: parsed.artist,
                  album: parsed.album ?? clean.album,
                  title: (parsed.title != null && parsed.title!.isNotEmpty)
                      ? parsed.title
                      : clean.title,
                );
              }
            } catch (_) {}
          }
          if (ArtworkAndLyricsService.isInvalidOrGenericArtist(clean.artist)) {
            clean = clean.copyWith(artist: 'Unknown Artist');
          }
        }

        // Self-heal tracks with ephemeral or legacy /cache/file_picker/ paths
        // 1. If streamUrl or localCachePath points into /cache/file_picker/, restore to direct content:// URI or local file.
        if (clean.streamUrl.contains('/cache/file_picker/') ||
            (clean.localCachePath != null && clean.localCachePath!.contains('/cache/file_picker/'))) {
          if (clean.remotePathOrId.startsWith('content://')) {
            clean = clean.copyWith(
              streamUrl: clean.remotePathOrId,
              clearLocalCachePath: true,
              isPinnedOffline: false,
            );
          } else {
            clean = clean.copyWith(
              clearLocalCachePath: true,
              isPinnedOffline: false,
            );
          }
        }

        // 2. Self-heal non-HTTP / non-content tracks whose file was moved or deleted
        if (!clean.streamUrl.startsWith('http://') &&
            !clean.streamUrl.startsWith('https://') &&
            !clean.streamUrl.startsWith('content://')) {
          final streamFile = File(clean.streamUrl);
          if (!streamFile.existsSync()) {
            if (clean.remotePathOrId.startsWith('content://')) {
              clean = clean.copyWith(
                streamUrl: clean.remotePathOrId,
                clearLocalCachePath: true,
                isPinnedOffline: false,
              );
            } else {
              try {
                final appDir = await getApplicationDocumentsDirectory();
                for (final folder in ['FreeBeat Music', 'imported_music']) {
                  final musicDir = Directory(p.join(appDir.path, folder));
                  if (musicDir.existsSync()) {
                    final baseName = p.basename(clean.streamUrl);
                    final match = musicDir.listSync(recursive: true).whereType<File>().firstWhere(
                      (f) => p.basename(f.path) == baseName || f.path.contains(clean.id),
                      orElse: () => File(''),
                    );
                    if (match.path.isNotEmpty && match.existsSync()) {
                      clean = clean.copyWith(
                        streamUrl: match.path,
                        localCachePath: match.path,
                        isPinnedOffline: false,
                      );
                      break;
                    }
                  }
                }
              } catch (_) {}
            }
          }
        }

        // 3. Ensure imported and cloud tracks are NOT automatically marked as pinned offline
        // Tracks should only be in the Offline Vault on explicit user demand (via pin/download).
        if (clean.isPinnedOffline) {
          if (clean.providerType != CloudProviderType.androidSaf) {
            // Remote cloud track: only pinned if locally cached file actually exists
            if (clean.localCachePath == null || !File(clean.localCachePath!).existsSync()) {
              clean = clean.copyWith(isPinnedOffline: false, clearLocalCachePath: true);
            }
          } else if (clean.id.startsWith('local_')) {
            // Local fallback import: unpin so it streams on demand and doesn't clutter Offline Vault
            clean = clean.copyWith(isPinnedOffline: false);
          }
        }

        // 4. If localCachePath points to a non-existent file on disk, clear it so streaming falls back smoothly
        if (clean.localCachePath != null &&
            clean.localCachePath!.isNotEmpty &&
            !File(clean.localCachePath!).existsSync()) {
          clean = clean.copyWith(clearLocalCachePath: true, isPinnedOffline: false);
        }

        if (clean != t) {
          await _db.upsertTracks([clean]);
        }
        sanitized.add(clean);
      }

      if (nonAudioIds.isNotEmpty) {
        await _db.removeTracks(nonAudioIds);
      }

      if (!mounted) return;
      state = sanitized;
      if (_ref != null) {
        _ref.read(playbackProvider.notifier).syncWithLoadedCatalog(sanitized);
        _enrichMissingArtwork(sanitized);
      }
    }
  }

  void loadSampleDemoTracks() {}

  Future<void> updateTrack(Track updated) async {
    state = state.map((t) => t.id == updated.id ? updated : t).toList();
    if (_db != null) {
      await _db.upsertTracks([updated]);
    }
    if (_ref != null) {
      _ref.read(playbackProvider.notifier).updateCurrentTrack(updated);
    }
  }

  Future<void> enrichTrackArtwork(Track track) async {
    if (_ref == null) return;
    try {
      final artworkSvc = _ref.read(artworkAndLyricsServiceProvider);
      final enriched = await artworkSvc.enrichTrackArtwork(track);
      if (enriched != track) {
        await updateTrack(enriched);
      }
    } catch (_) {}
  }

  void enrichLibraryArtwork(List<Track> tracks) => _enrichMissingArtwork(tracks);

  void _enrichMissingArtwork(List<Track> tracks) {
    if (_ref == null) return;
    unawaited(() async {
      final artworkSvc = _ref.read(artworkAndLyricsServiceProvider);
      for (final t in tracks) {
        final needsArtwork = t.artworkUrl == null || t.artworkUrl!.isEmpty;
        final needsArtist = ArtworkAndLyricsService.isInvalidOrGenericArtist(t.artist);
        if (needsArtwork || needsArtist) {
          try {
            final enriched = await artworkSvc.enrichTrackArtwork(t);
            if (enriched != t) {
              await updateTrack(enriched);
            }
          } catch (_) {}
        }
      }
    }());
  }

  Future<void> addIndexedTracks(List<Track> newTracks) async {
    final validTracks = newTracks.where(isValidAudioTrack).toList();
    if (validTracks.isEmpty) return;
    if (_db != null) {
      await _db.upsertTracks(validTracks);
    }
    final map = {for (final t in state) t.id: t};
    for (final t in validTracks) {
      map[t.id] = t;
    }
    state = map.values.toList();
    if (_ref != null) {
      final playback = _ref.read(playbackProvider);
      if (playback.queue.isEmpty || playback.currentTrack.id.isEmpty) {
        _ref.read(playbackProvider.notifier).setQueue(state);
      }
      final importProgress = _ref.read(importProgressProvider);
      if (!importProgress.isImporting) {
        _enrichMissingArtwork(validTracks);
      }
    }
  }

  /// Purges dead localCachePaths and restores ephemeral cache streamUrls when cache is cleared.
  /// Prevents previously cached tracks from becoming unplayable.
  Future<void> purgeDeletedLocalCachePaths() async {
    final updatedList = <Track>[];
    final changedTracks = <Track>[];

    for (final t in state) {
      var clean = t;
      // 1. If localCachePath points to a deleted file, clear it so proxy and audio player stream on demand
      if (clean.localCachePath != null &&
          clean.localCachePath!.isNotEmpty &&
          !File(clean.localCachePath!).existsSync()) {
        clean = clean.copyWith(
          clearLocalCachePath: true,
          isPinnedOffline: false,
        );
      }

      // 2. If streamUrl was an ephemeral or temporary cache file that no longer exists:
      if (!clean.streamUrl.startsWith('http://') &&
          !clean.streamUrl.startsWith('https://') &&
          !clean.streamUrl.startsWith('content://')) {
        if (!File(clean.streamUrl).existsSync()) {
          if (clean.remotePathOrId.startsWith('content://')) {
            clean = clean.copyWith(
              streamUrl: clean.remotePathOrId,
              clearLocalCachePath: true,
              isPinnedOffline: false,
            );
          } else if (clean.remotePathOrId.startsWith('http://') ||
              clean.remotePathOrId.startsWith('https://')) {
            clean = clean.copyWith(
              streamUrl: clean.remotePathOrId,
              clearLocalCachePath: true,
              isPinnedOffline: false,
            );
          }
        }
      }

      if (clean != t) {
        changedTracks.add(clean);
      }
      updatedList.add(clean);
    }

    if (changedTracks.isNotEmpty) {
      if (_db != null) {
        await _db.upsertTracks(changedTracks);
      }
      state = updatedList;
      if (_ref != null) {
        await _ref.read(playbackProvider.notifier).syncWithLoadedCatalog(updatedList);
      }
    }
  }

  Future<void> toggleFavorite(String trackId) async {
    await PixelHaptics.tick(intensity: 0.75);
    Track? target;
    state = state.map((t) {
      if (t.id == trackId) {
        final updated = t.copyWith(isFavorite: !t.isFavorite);
        target = updated;
        if (_db != null) {
          _db.upsertTracks([updated]);
        }
        return updated;
      }
      return t;
    }).toList();

    if (_ref != null && target != null) {
      _ref.read(playbackProvider.notifier).updateCurrentTrack(target!);
    }
  }

  Future<void> togglePinOffline(String trackId) async {
    await PixelHaptics.hifiConfirm();
    Track? target;
    state = state.map((t) {
      if (t.id == trackId) {
        target = t.copyWith(isPinnedOffline: !t.isPinnedOffline);
        if (_db != null) {
          _db.upsertTracks([target!]);
        }
        return target!;
      }
      return t;
    }).toList();

    if (_ref != null && target != null) {
      _ref.read(playbackProvider.notifier).updateCurrentTrack(target!);
      final queueMgr = _ref.read(downloadQueueManagerProvider);
      final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
      if (target!.isPinnedOffline) {
        queueMgr.enqueue(target!);
      } else {
        queueMgr.cancel(target!.id);
        await cacheSvc.removeCachedTrack(target!);
      }
    }
  }

  Future<void> pinTracksOffline(List<String> trackIds) async {
    await PixelHaptics.hifiConfirm();
    final updated = <Track>[];
    state = state.map((t) {
      if (trackIds.contains(t.id)) {
        final u = t.copyWith(isPinnedOffline: true);
        updated.add(u);
        return u;
      }
      return t;
    }).toList();

    if (_db != null && updated.isNotEmpty) {
      _db.upsertTracks(updated);
    }

    if (_ref != null && updated.isNotEmpty) {
      _ref.read(downloadQueueManagerProvider).enqueueAll(updated);
    }
  }

  Future<void> unpinTracksOffline(List<String> trackIds) async {
    await PixelHaptics.tick();
    final updated = <Track>[];
    state = state.map((t) {
      if (trackIds.contains(t.id)) {
        final u = t.copyWith(isPinnedOffline: false);
        updated.add(u);
        return u;
      }
      return t;
    }).toList();

    if (_db != null && updated.isNotEmpty) {
      _db.upsertTracks(updated);
    }

    if (_ref != null) {
      final queueMgr = _ref.read(downloadQueueManagerProvider);
      final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
      for (final t in updated) {
        queueMgr.cancel(t.id);
        unawaited(cacheSvc.removeCachedTrack(t));
      }
    }
  }

  Future<void> removeTracks(List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await PixelHaptics.tick();
    final toRemove = state.where((t) => trackIds.contains(t.id)).toList();
    state = state.where((t) => !trackIds.contains(t.id)).toList();
    if (_db != null) {
      await _db.deleteTracks(trackIds);
    }

    if (_ref != null) {
      final queueMgr = _ref.read(downloadQueueManagerProvider);
      final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
      for (final t in toRemove) {
        queueMgr.cancel(t.id);
        unawaited(cacheSvc.removeCachedTrack(t));
      }

      await _ref
          .read(playlistsProvider.notifier)
          .removeTracksFromAllPlaylists(trackIds);
      await _ref.read(playbackProvider.notifier).handleTracksRemoved(trackIds);
    }
  }

  /// Scans current catalog in memory and SQLite, permanently purging any non-audio files (PDFs, docs, images).
  Future<int> purgeNonAudioTracks() async {
    final nonAudio = state.where((t) => !isValidAudioTrack(t)).toList();
    if (nonAudio.isEmpty) return 0;
    final idsToRemove = nonAudio.map((t) => t.id).toList();
    if (_db != null) {
      await _db.removeTracks(idsToRemove);
    }
    state = state.where(isValidAudioTrack).toList();
    if (_ref != null) {
      final playback = _ref.read(playbackProvider);
      if (playback.queue.isNotEmpty) {
        final cleanQueue = playback.queue.where(isValidAudioTrack).toList();
        _ref.read(playbackProvider.notifier).setQueue(cleanQueue);
      }
    }
    return idsToRemove.length;
  }

  /// Removes all indexed tracks belonging to a specific cloud account.
  Future<void> removeTracksForAccount(String accountId) async {
    final toRemove = state.where((t) => t.accountId == accountId).map((t) => t.id).toList();
    if (toRemove.isEmpty) return;
    if (_db != null) {
      await _db.removeTracks(toRemove);
    }
    state = state.where((t) => t.accountId != accountId).toList();
    if (_ref != null) {
      final playback = _ref.read(playbackProvider);
      if (playback.queue.isNotEmpty) {
        final cleanQueue = playback.queue.where((t) => t.accountId != accountId).toList();
        _ref.read(playbackProvider.notifier).setQueue(cleanQueue);
      }
    }
  }

  Future<void> removeTrack(String trackId) async {
    await removeTracks([trackId]);
  }
}

final tracksCatalogProvider =
    StateNotifierProvider<TracksCatalogNotifier, List<Track>>((ref) {
  return TracksCatalogNotifier(ref.watch(libraryDatabaseProvider), ref);
});

/// Selected Cloud Filter on Home / Library ('all' or CloudProviderType.id or 'offline')
final selectedCloudFilterProvider = StateProvider<String>((ref) => 'all');

/// Selected Artist Filter on Home ('all' / null or specific artist name)
final selectedArtistFilterProvider = StateProvider<String?>((ref) => null);

/// Selected Album Filter on Home ('all' / null or specific album name)
final selectedAlbumFilterProvider = StateProvider<String?>((ref) => null);

/// Search query text in the Pixel Search Bar pill
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Represents an artist item discovered in the user's catalog
class ArtistInfo {
  final String name;
  final int trackCount;
  final Track representativeTrack;

  const ArtistInfo({
    required this.name,
    required this.trackCount,
    required this.representativeTrack,
  });
}

/// Represents an album item discovered in the user's catalog
class AlbumInfo {
  final String title;
  final String artist;
  final int trackCount;
  final Track representativeTrack;

  const AlbumInfo({
    required this.title,
    required this.artist,
    required this.trackCount,
    required this.representativeTrack,
  });
}

/// Dynamic list of artists discovered in the user's catalog.
/// Unifies collaborations, features, and solo tracks into distinct artist profiles.
final availableArtistsProvider = Provider<List<ArtistInfo>>((ref) {
  final tracks = ref.watch(tracksCatalogProvider);
  final map = <String, List<Track>>{};
  final canonicalNames = <String, String>{};

  for (final t in tracks) {
    final artists = ArtistHelper.extractArtists(t.artist, t.title);
    if (artists.isEmpty) {
      final fallback = t.artist.trim().isEmpty ? 'Unknown Artist' : t.artist.trim();
      final lower = fallback.toLowerCase();
      canonicalNames.putIfAbsent(lower, () => fallback);
      final canonical = canonicalNames[lower]!;
      map.putIfAbsent(canonical, () => []).add(t);
    } else {
      for (final a in artists) {
        final lower = a.toLowerCase();
        canonicalNames.putIfAbsent(lower, () => a);
        final canonical = canonicalNames[lower]!;
        final list = map.putIfAbsent(canonical, () => []);
        if (!list.contains(t)) {
          list.add(t);
        }
      }
    }
  }

  final list = map.entries.map((e) {
    final representative = e.value.firstWhere(
      (t) => t.artworkUrl != null && t.artworkUrl!.isNotEmpty,
      orElse: () => e.value.first,
    );
    return ArtistInfo(
      name: e.key,
      trackCount: e.value.length,
      representativeTrack: representative,
    );
  }).toList();

  list.sort((a, b) => b.trackCount.compareTo(a.trackCount));
  return list;
});

/// Dynamic list of albums discovered in the user's catalog
final availableAlbumsProvider = Provider<List<AlbumInfo>>((ref) {
  final tracks = ref.watch(tracksCatalogProvider);
  final map = <String, List<Track>>{};
  for (final t in tracks) {
    final album = t.album.trim().isEmpty ? 'Unknown Album' : t.album.trim();
    map.putIfAbsent(album, () => []).add(t);
  }
  final list = map.entries.map((e) {
    final representative = e.value.firstWhere(
      (t) => t.artworkUrl != null && t.artworkUrl!.isNotEmpty,
      orElse: () => e.value.first,
    );
    return AlbumInfo(
      title: e.key,
      artist: representative.artist.isNotEmpty ? representative.artist : e.value.first.artist,
      trackCount: e.value.length,
      representativeTrack: representative,
    );
  }).toList();
  list.sort((a, b) => b.trackCount.compareTo(a.trackCount));
  return list;
});

/// Seed for daily Top Picks shuffle
final topPicksSeedProvider = StateProvider<int>((ref) => DateTime.now().day);

/// Top Picks for Today: Curated randomized selection from user's library
final topPicksProvider = Provider<List<Track>>((ref) {
  final allTracks = ref.watch(tracksCatalogProvider);
  if (allTracks.isEmpty) return const [];
  if (allTracks.length <= 6) return allTracks;

  final seed = ref.watch(topPicksSeedProvider);
  final random = Random(seed);
  final copy = List<Track>.from(allTracks);
  copy.shuffle(random);
  return copy.take(8).toList();
});

final filteredTracksProvider = Provider<List<Track>>((ref) {
  final allTracks = ref.watch(tracksCatalogProvider);
  final cloudFilter = ref.watch(selectedCloudFilterProvider);
  final artistFilter = ref.watch(selectedArtistFilterProvider);
  final albumFilter = ref.watch(selectedAlbumFilterProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();

  return allTracks.where((track) {
    // 1. Cloud filter
    final matchesCloud = cloudFilter == 'all'
        ? true
        : cloudFilter == 'offline'
            ? track.isPinnedOffline
            : cloudFilter == 'hifi'
                ? track.isHiRes
                : track.providerType.id == cloudFilter;
    if (!matchesCloud) return false;

    // 2. Artist filter (unifies solo, collaborative, and featured tracks)
    if (artistFilter != null && artistFilter.isNotEmpty) {
      if (!ArtistHelper.trackBelongsToArtist(track, artistFilter)) return false;
    }

    // 3. Album filter
    if (albumFilter != null && albumFilter.isNotEmpty) {
      if (track.album.toLowerCase() != albumFilter.toLowerCase()) return false;
    }

    // 4. Search query
    if (query.isEmpty) return true;
    return track.title.toLowerCase().contains(query) ||
        track.artist.toLowerCase().contains(query) ||
        track.album.toLowerCase().contains(query) ||
        track.codec.toLowerCase().contains(query);
  }).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
// Audio Quality & Bitrate Tier Controller (96k -> 320k -> 24-bit/192kHz Hi-Fi)
// ─────────────────────────────────────────────────────────────────────────────

class AudioQualityNotifier extends StateNotifier<AudioQualityConfig> {
  AudioQualityNotifier() : super(const AudioQualityConfig()) {
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMs = prefs.getInt('playback_crossfade_duration_ms') ??
          (prefs.getInt('playback_crossfade_seconds') != null
              ? prefs.getInt('playback_crossfade_seconds')! * 1000
              : null);
      if (savedMs != null && mounted) {
        state = state.copyWith(crossfadeDurationMs: savedMs.clamp(0, 12000));
      }
    } catch (_) {}
  }

  Future<void> setWifiTier(AudioQualityTier tier) async {
    await PixelHaptics.tick();
    state = state.copyWith(wifiTier: tier, clearOverride: true);
  }

  Future<void> setCellularTier(AudioQualityTier tier) async {
    await PixelHaptics.tick();
    state = state.copyWith(cellularTier: tier, clearOverride: true);
  }

  Future<void> setOfflineDownloadTier(AudioQualityTier tier) async {
    await PixelHaptics.tick();
    state = state.copyWith(offlineDownloadTier: tier);
  }

  /// On-the-fly bitrate switch from the Now Playing Signal Path Sheet.
  Future<void> setLiveStreamTierOverride(AudioQualityTier tier) async {
    if (tier.isLossless) {
      await PixelHaptics.hifiConfirm();
    } else {
      await PixelHaptics.tick();
    }
    state = state.copyWith(activeOverrideTier: tier);
  }

  void setCrossfadeDuration(int ms) {
    final clamped = ms.clamp(0, 12000);
    state = state.copyWith(crossfadeDurationMs: clamped);
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('playback_crossfade_duration_ms', clamped);
      } catch (_) {}
    }());
  }

  void setStreamBufferSizeMb(int mb) {
    state = state.copyWith(streamBufferSizeMb: mb.clamp(16, 256));
  }

  void toggleHiResDirectOutput(bool val) {
    PixelHaptics.tick();
    state = state.copyWith(enableHiResDirectOutput: val);
  }

  void toggleBluetoothIspProtection(bool val) {
    PixelHaptics.tick();
    state = state.copyWith(bluetoothIspProtection: val);
  }

  void toggleDisableDvcOnBluetooth(bool val) {
    PixelHaptics.tick();
    state = state.copyWith(disableDvcOnBluetoothAbsoluteVolume: val);
  }
}

final audioQualityProvider =
    StateNotifierProvider<AudioQualityNotifier, AudioQualityConfig>((ref) {
  return AudioQualityNotifier();
});

final audioOutputRouteProvider = FutureProvider<AudioOutputRouteInfo>((ref) async {
  final dspService = ref.watch(powerampDspServiceProvider);
  return dspService.fetchAudioRouteInfo();
});

final audioRouteInfoProvider = Provider<AudioOutputRouteInfo>((ref) {
  final asyncVal = ref.watch(audioOutputRouteProvider);
  return asyncVal.valueOrNull ?? const AudioOutputRouteInfo();
});

// ─────────────────────────────────────────────────────────────────────────────
// Poweramp 10-Band EQ + Preamp + Rotary Tone + Spatial DSP Controller
// ─────────────────────────────────────────────────────────────────────────────

class PowerampDspNotifier extends StateNotifier<PowerampDspState> {
  PowerampDspNotifier(this._dspService, [this._db, this._ref])
      : super(PowerampDspState.initial()) {
    _dspService.applyDspState(state);
    _loadPersistedState();
  }

  final PowerampDspService _dspService;
  final LibraryDatabase? _db;
  final Ref? _ref;
  final List<DspPreset> _customPresets = [];

  List<DspPreset> get allPresets => [...kBuiltInDspPresets, ..._customPresets];
  List<DspPreset> get customPresets => List.unmodifiable(_customPresets);

  Future<void> _loadPersistedState() async {
    if (_db == null) return;
    try {
      final savedPresets = await _db.loadCustomPresets();
      if (savedPresets.isNotEmpty) {
        _customPresets.clear();
        _customPresets.addAll(savedPresets);
      }
      final savedProfiles = await _db.loadDeviceProfiles();
      if (savedProfiles.isNotEmpty) {
        state = state.copyWith(deviceProfiles: savedProfiles);
      }
    } catch (_) {}
  }

  Timer? _dspThrottleTimer;
  bool _dspSyncPending = false;

  void _syncToHardware({bool immediate = false}) {
    if (immediate) {
      _dspThrottleTimer?.cancel();
      _dspThrottleTimer = null;
      _dspSyncPending = false;
      _dspService.applyDspState(state);
      return;
    }

    if (_dspThrottleTimer != null && _dspThrottleTimer!.isActive) {
      _dspSyncPending = true;
      return;
    }

    _dspService.applyDspState(state);
    _dspThrottleTimer = Timer(const Duration(milliseconds: 24), () {
      if (_dspSyncPending) {
        _dspSyncPending = false;
        _dspService.applyDspState(state);
      }
    });
  }

  void setVisualizerMode(VisualizerMode mode) {
    PixelHaptics.tick();
    state = state.copyWith(visualizerMode: mode);
  }

  void setBs2bCrossfeedMode(Bs2bCrossfeedMode mode) {
    PixelHaptics.tick();
    state = state.copyWith(bs2bCrossfeedMode: mode);
    _syncToHardware();
  }

  void setDvcHeadroomDb(double db) {
    state = state.copyWith(dvcHeadroomDb: db.clamp(-6.0, 0.0));
    _syncToHardware();
  }

  void toggleBitPerfectDirectMode(bool enabled) {
    if (enabled) {
      PixelHaptics.hifiConfirm();
    } else {
      PixelHaptics.tick();
    }
    state = state.copyWith(bitPerfectDirectMode: enabled);
    _syncToHardware();
  }

  void toggleEq(bool enabled) {
    PixelHaptics.playPauseToggle();
    state = state.copyWith(eqEnabled: enabled);
    _syncToHardware();
  }

  void toggleTone(bool enabled) {
    PixelHaptics.tick();
    state = state.copyWith(toneEnabled: enabled);
    _syncToHardware();
  }

  void toggleLimiter(bool enabled) {
    PixelHaptics.tick();
    state = state.copyWith(limiterEnabled: enabled);
    _syncToHardware();
  }

  void toggleDvc(bool enabled) {
    PixelHaptics.tick();
    state = state.copyWith(dvcEnabled: enabled);
    _syncToHardware();
  }

  void toggleParametricMode(bool isParametric) {
    PixelHaptics.tick();
    state = state.copyWith(isParametricMode: isParametric);
  }

  void setPreampDb(double newDb) {
    final clamped = newDb.clamp(-15.0, 15.0);
    if (clamped.abs() < 0.25 && state.preampDb.abs() >= 0.25) {
      PixelHaptics.centerDetentSnap();
      state = state.copyWith(preampDb: 0.0, activePresetId: 'custom');
    } else if (clamped.abs() >= 14.9 && state.preampDb.abs() < 14.9) {
      PixelHaptics.railLimitThud();
      state = state.copyWith(preampDb: clamped, activePresetId: 'custom');
    } else {
      if ((clamped - state.preampDb).abs() >= 0.4) {
        PixelHaptics.lowTick(intensity: 0.4);
      }
      state = state.copyWith(preampDb: clamped, activePresetId: 'custom');
    }
    _syncToHardware();
  }

  void setBandGain(int index, double gainDb) {
    if (index < 0 || index >= state.bands.length) return;
    final clamped = gainDb.clamp(-15.0, 15.0);
    final oldGain = state.bands[index].gainDb;

    double finalGain = clamped;
    if (clamped.abs() < 0.25 && oldGain.abs() >= 0.25) {
      PixelHaptics.centerDetentSnap();
      finalGain = 0.0;
    } else if (clamped.abs() >= 14.9 && oldGain.abs() < 14.9) {
      PixelHaptics.railLimitThud();
    } else if ((clamped - oldGain).abs() >= 0.4) {
      PixelHaptics.lowTick(intensity: 0.35 + (clamped.abs() / 30.0));
    }

    final updated = List<EqBandConfig>.from(state.bands);
    updated[index] = updated[index].copyWith(gainDb: finalGain);
    state = state.copyWith(bands: updated, activePresetId: 'custom');
    _syncToHardware();
  }

  void setBandParametric(int index, {double? frequencyHz, double? qFactor}) {
    if (index < 0 || index >= state.bands.length) return;
    final updated = List<EqBandConfig>.from(state.bands);
    updated[index] = updated[index].copyWith(
      frequencyHz: frequencyHz,
      qFactor: qFactor,
    );
    state = state.copyWith(bands: updated, activePresetId: 'custom');
    _syncToHardware();
  }

  void setBassTone(double value) {
    state = state.copyWith(bassGain: value, activePresetId: 'custom');
    _syncToHardware();
  }

  void setTrebleTone(double value) {
    state = state.copyWith(trebleGain: value, activePresetId: 'custom');
    _syncToHardware();
  }

  void setStereoExpansion(double value) {
    state = state.copyWith(stereoExpansion: value, activePresetId: 'custom');
    _syncToHardware();
  }

  void setBalance(double val) {
    final clamped = val.clamp(-1.0, 1.0);
    if (clamped.abs() < 0.04 && state.balance.abs() >= 0.04) {
      PixelHaptics.centerDetentSnap();
      state = state.copyWith(balance: 0.0);
    } else {
      state = state.copyWith(balance: clamped);
    }
    _syncToHardware();
  }

  void toggleMonoMix(bool mono) {
    PixelHaptics.tick();
    state = state.copyWith(monoMix: mono);
    _syncToHardware(immediate: true);
  }

  void setTempo(double tempo) {
    final clamped = tempo.clamp(0.5, 2.0);
    state = state.copyWith(tempo: clamped);
    _ref?.read(playbackProvider.notifier).setPlaybackSpeed(clamped);
    _syncToHardware();
  }

  void setPitchSemitones(double semitones) {
    final clamped = semitones.clamp(-12.0, 12.0);
    state = state.copyWith(pitchSemitones: clamped);
    final ratio = pow(2.0, clamped / 12.0).toDouble();
    _ref?.read(playbackProvider.notifier).setPitch(ratio);
    _syncToHardware();
  }

  void setReverbPreset(ReverbPresetType preset) {
    PixelHaptics.tick();
    state = state.copyWith(
      reverbPreset: preset,
      reverbMix: preset == ReverbPresetType.none ? 0.0 : (state.reverbMix > 0.05 ? state.reverbMix : 0.50),
    );
    _syncToHardware(immediate: true);
  }

  void setReverbMix(double mix) {
    state = state.copyWith(reverbMix: mix.clamp(0.0, 1.0));
    _syncToHardware();
  }

  void applyPreset(DspPreset preset) {
    PixelHaptics.hifiConfirm();
    final updatedBands = List<EqBandConfig>.generate(
      10,
      (i) => state.bands[i].copyWith(
        frequencyHz: kPoweramp10BandFrequencies[i],
        gainDb: i < preset.bandGainsDb.length ? preset.bandGainsDb[i] : 0.0,
        qFactor: preset.qFactors != null && i < preset.qFactors!.length
            ? preset.qFactors![i]
            : 1.41,
      ),
    );
    state = state.copyWith(
      preampDb: preset.preampDb,
      bands: updatedBands,
      bassGain: preset.bassTone,
      trebleGain: preset.trebleTone,
      stereoExpansion: preset.stereoExpansion,
      activePresetId: preset.id,
    );
    _syncToHardware();
  }

  void setBassGain(double db) {
    final normalized = ((db + 10.0) / 20.0).clamp(0.0, 1.0);
    setBassTone(normalized);
  }

  void setTrebleGain(double db) {
    final normalized = ((db + 10.0) / 20.0).clamp(0.0, 1.0);
    setTrebleTone(normalized);
  }

  void setStereoXAmount(double amount) {
    setStereoExpansion(amount.clamp(0.0, 1.0));
  }

  void loadPresetById(String id) {
    // 1. Direct exact ID match
    DspPreset? match = allPresets.where((p) => p.id == id).firstOrNull;

    // 2. Comprehensive legacy & friendly alias map
    if (match == null) {
      const aliasMap = {
        'bass_boost': 'bass_boost',
        'bass': 'bass_boost',
        'sub_bass': 'bass_extreme',
        'poweramp_bass_treble': 'smart_eq_bass_treble',
        'smart_eq': 'smart_eq_bass_treble',
        'smart_eq_bass_treble': 'smart_eq_bass_treble',
        'vocal_clarity': 'vocal',
        'vocal_air': 'vocal',
        'vocal': 'vocal',
        'concert_hall': 'concert',
        'concert': 'concert',
        'rock_metal': 'rock',
        'rock': 'rock',
        'audiophile_flat': 'flat',
        'flat': 'flat',
        'harman': 'harman_target',
        'tube': 'hifi_warm_tube',
        'club': 'electronic_edm',
        'edm': 'electronic_edm',
      };
      final mappedId = aliasMap[id];
      if (mappedId != null) {
        match = allPresets.where((p) => p.id == mappedId).firstOrNull;
      }
    }

    // 3. Normalized fuzzy matching
    if (match == null) {
      final normalizedId = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      match = allPresets.where((p) {
        final pNorm = p.id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final pNameNorm = p.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        return pNorm == normalizedId ||
            pNorm.contains(normalizedId) ||
            normalizedId.contains(pNorm) ||
            pNameNorm.contains(normalizedId);
      }).firstOrNull;
    }

    match ??= kBuiltInDspPresets.first;
    applyPreset(match);
  }

  void resetFlat() {
    final flatPreset = allPresets.firstWhere(
      (p) => p.id == 'flat',
      orElse: () => kBuiltInDspPresets.first,
    );
    applyPreset(flatPreset);
  }

  Future<DspPreset> saveCustomPreset(String name, {List<double>? customQs}) async {
    final custom = DspPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'My Custom EQ' : name.trim(),
      category: 'User Custom',
      preampDb: state.preampDb,
      bandGainsDb: state.bands.map((b) => b.gainDb).toList(),
      bassTone: state.bassGain,
      trebleTone: state.trebleGain,
      stereoExpansion: state.stereoExpansion,
      isCustom: true,
      qFactors: customQs ?? state.bands.map((b) => b.qFactor).toList(),
    );
    _customPresets.removeWhere((p) => p.id == custom.id);
    _customPresets.add(custom);
    await _db?.saveCustomPreset(custom);
    state = state.copyWith(activePresetId: custom.id);
    PixelHaptics.hifiConfirm();
    return custom;
  }

  Future<void> renameCustomPreset(String id, String newName) async {
    final idx = _customPresets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    final old = _customPresets[idx];
    final updated = DspPreset(
      id: old.id,
      name: newName.trim().isEmpty ? old.name : newName.trim(),
      category: old.category,
      preampDb: old.preampDb,
      bandGainsDb: old.bandGainsDb,
      bassTone: old.bassTone,
      trebleTone: old.trebleTone,
      stereoExpansion: old.stereoExpansion,
      isCustom: true,
      qFactors: old.qFactors,
    );
    _customPresets[idx] = updated;
    await _db?.saveCustomPreset(updated);
    PixelHaptics.tick();
  }

  Future<void> deleteCustomPreset(String id) async {
    _customPresets.removeWhere((p) => p.id == id);
    await _db?.deleteCustomPreset(id);
    if (state.activePresetId == id) {
      applyPreset(kBuiltInDspPresets.first);
    }
    PixelHaptics.tick();
  }

  String exportPresetJson(String id) {
    final match = allPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => kBuiltInDspPresets.first,
    );
    return jsonEncode(match.toMap());
  }

  Future<DspPreset?> importPresetFromJson(String jsonStr) async {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final preset = DspPreset.fromMap(map);
      final uniquePreset = DspPreset(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: preset.name,
        category: 'Imported',
        preampDb: preset.preampDb,
        bandGainsDb: preset.bandGainsDb,
        bassTone: preset.bassTone,
        trebleTone: preset.trebleTone,
        stereoExpansion: preset.stereoExpansion,
        isCustom: true,
        qFactors: preset.qFactors,
      );
      _customPresets.add(uniquePreset);
      await _db?.saveCustomPreset(uniquePreset);
      applyPreset(uniquePreset);
      return uniquePreset;
    } catch (_) {
      return null;
    }
  }

  Future<void> setDeviceProfile(String routeKey, String presetId) async {
    final updated = Map<String, String>.from(state.deviceProfiles);
    updated[routeKey] = presetId;
    state = state.copyWith(deviceProfiles: updated);
    await _db?.saveDeviceProfile(routeKey, presetId);
    PixelHaptics.tick();
  }

  void handleAudioRouteChanged(AudioOutputRouteInfo route) {
    String routeKey;
    if (route.isUsbDac || route.routeType.contains('USB')) {
      routeKey = 'USB_DAC';
    } else if (route.isBluetooth || route.routeType.contains('BLUETOOTH') || route.routeType.contains('BLE')) {
      routeKey = 'BLUETOOTH';
    } else if (route.routeType.contains('HEADSET') || route.routeType.contains('HEADPHONES')) {
      routeKey = 'WIRED_HEADPHONES';
    } else {
      routeKey = 'BUILTIN_SPEAKER';
    }

    final targetPresetId = state.deviceProfiles[routeKey];
    if (targetPresetId != null && targetPresetId != state.activePresetId) {
      loadPresetById(targetPresetId);
    }
  }
}

final powerampDspProvider =
    StateNotifierProvider<PowerampDspNotifier, PowerampDspState>((ref) {
  final notifier = PowerampDspNotifier(
    ref.watch(powerampDspServiceProvider),
    ref.watch(libraryDatabaseProvider),
    ref,
  );
  ref.listen<AudioOutputRouteInfo>(audioRouteInfoProvider, (prev, next) {
    if (prev?.deviceName != next.deviceName ||
        prev?.routeType != next.routeType ||
        prev?.isUsbDac != next.isUsbDac ||
        prev?.isBluetooth != next.isBluetooth) {
      notifier.handleAudioRouteChanged(next);
      try {
        ref.read(powerampDspServiceProvider).updatePlaybackNotification(
              outputDevice: next.deviceName,
            );
      } catch (_) {}
    }
  });
  return notifier;
});

/// Smart EQ Aliases
typedef SmartEqNotifier = PowerampDspNotifier;
final smartEqProvider = powerampDspProvider;
final smartEqServiceProvider = powerampDspServiceProvider;


// ─────────────────────────────────────────────────────────────────────────────
// Playback Engine State & Controller (just_audio + Loopback Proxy)
// ─────────────────────────────────────────────────────────────────────────────

class PlaybackViewState {
  const PlaybackViewState({
    required this.currentTrack,
    required this.queue,
    this.sessionHistory = const [],
    this.isPlaying = false,
    this.positionMs = 42000,
    this.bufferedPositionMs = 165000,
    this.isShuffle = false,
    this.repeatMode = 0, // 0: Off, 1: All, 2: One
    this.playbackSpeed = 1.0,
    this.pitch = 1.0,
    this.isAutoplay = true,
    this.crossfadeSeconds = 0,
    this.isGapless = true,
    this.sleepTimerDuration,
    this.sleepTimerRemaining,
    this.loopPointA,
    this.loopPointB,
    this.isLoopActive = false,
  });

  final Track currentTrack;
  final List<Track> queue;
  final List<Track> sessionHistory;
  final bool isPlaying;
  final int positionMs;
  final int bufferedPositionMs;
  final bool isShuffle;
  final int repeatMode;
  final double playbackSpeed;
  final double pitch;
  final bool isAutoplay;
  final int crossfadeSeconds;
  final bool isGapless;
  final Duration? sleepTimerDuration;
  final Duration? sleepTimerRemaining;
  final int? loopPointA;
  final int? loopPointB;
  final bool isLoopActive;

  double get progressFraction {
    if (currentTrack.durationMs <= 0) return 0.0;
    return (positionMs / currentTrack.durationMs).clamp(0.0, 1.0);
  }

  bool get isSleepTimerActive =>
      sleepTimerRemaining != null && sleepTimerRemaining!.inSeconds > 0;

  String get formattedSleepTimerRemaining {
    if (sleepTimerRemaining == null) return '';
    final m = sleepTimerRemaining!.inMinutes;
    final s = sleepTimerRemaining!.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  List<Track> get upNextQueue {
    final idx = queue.indexWhere((t) => t.id == currentTrack.id);
    if (idx == -1 || idx >= queue.length - 1) return const [];
    return queue.sublist(idx + 1);
  }

  int get activeLyricIndex {
    final lyrics = currentTrack.syncedLyrics;
    if (lyrics.isEmpty) return -1;
    final effectivePositionMs = positionMs + currentTrack.lyricsOffsetMs;
    int idx = 0;
    for (int i = 0; i < lyrics.length; i++) {
      if (effectivePositionMs >= lyrics[i].timestampMs) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  static final Track emptyTrack = Track(
    id: '',
    accountId: '',
    providerType: CloudProviderType.androidSaf,
    remotePathOrId: '',
    title: 'No track playing',
    artist: 'Connect cloud storage or import songs',
    album: 'FreeBeat',
    durationMs: 0,
    streamUrl: '',
    codec: 'FLAC',
    bitDepth: 24,
    sampleRateHz: 96000,
    bitrateKbps: 1411,
    sizeBytes: 0,
    dominantColorValue: 0xFF6750A4,
  );

  PlaybackViewState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    List<Track>? sessionHistory,
    bool? isPlaying,
    int? positionMs,
    int? bufferedPositionMs,
    bool? isShuffle,
    int? repeatMode,
    double? playbackSpeed,
    double? pitch,
    bool? isAutoplay,
    int? crossfadeSeconds,
    bool? isGapless,
    Duration? sleepTimerDuration,
    Duration? sleepTimerRemaining,
    bool clearSleepTimer = false,
    int? loopPointA,
    int? loopPointB,
    bool clearLoop = false,
    bool? isLoopActive,
  }) {
    return PlaybackViewState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      sessionHistory: sessionHistory ?? this.sessionHistory,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      bufferedPositionMs: bufferedPositionMs ?? this.bufferedPositionMs,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      pitch: pitch ?? this.pitch,
      isAutoplay: isAutoplay ?? this.isAutoplay,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      isGapless: isGapless ?? this.isGapless,
      sleepTimerDuration: clearSleepTimer
          ? null
          : (sleepTimerDuration ?? this.sleepTimerDuration),
      sleepTimerRemaining: clearSleepTimer
          ? null
          : (sleepTimerRemaining ?? this.sleepTimerRemaining),
      loopPointA: clearLoop ? null : (loopPointA ?? this.loopPointA),
      loopPointB: clearLoop ? null : (loopPointB ?? this.loopPointB),
      isLoopActive: clearLoop ? false : (isLoopActive ?? this.isLoopActive),
    );
  }
}

class PlaybackNotifier extends StateNotifier<PlaybackViewState> {
  PlaybackNotifier(
    this._ref, [
    List<Track> initialTracks = const [],
  ]) : super(
          PlaybackViewState(
            currentTrack: initialTracks.isNotEmpty
                ? initialTracks.first
                : PlaybackViewState.emptyTrack,
            queue: initialTracks,
            positionMs: 0,
            bufferedPositionMs: 0,
          ),
        ) {
    _initAudioPlayer();
    _restoreLastPlaybackState();
  }

  final Ref _ref;
  AudioPlayer? _playerA;
  AudioPlayer? _playerB;
  bool _isPlayerAActive = true;
  AudioPlayer? get _activePlayer => _isPlayerAActive ? _playerA : _playerB;
  AudioPlayer? get _inactivePlayer => _isPlayerAActive ? _playerB : _playerA;
  AudioPlayer? get _audioPlayer => _activePlayer;
  bool _isCrossfading = false;
  Timer? _crossfadeTimer;
  int? _crossfadeStartTimeMs;
  int? _crossfadeFadeMs;
  Timer? _progressTicker;
  Timer? _sleepTimer;
  DateTime? _sleepTimerTarget;
  bool _sleepTimerEndAfterTrack = false;
  bool _isInitializingPlayer = false;
  bool _playerInitFailed = false;
  bool _isPlayPending = false;
  bool _isTransitioningTrack = false;
  ConcatenatingAudioSource? _playlistSource;
  String? _loadedQueueSignature;
  String? _preloadedTrackId;
  bool _isPreloadingNext = false;
  List<Track>? _unshuffledQueue;

  int _lastSavedPosMs = -1;
  int _lastSavedPosTimestamp = 0;

  void _savePlaybackPosition({bool force = false}) {
    if (state.currentTrack.id.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final currentPos = state.positionMs;
    if (!force &&
        (now - _lastSavedPosTimestamp < 2500) &&
        (currentPos - _lastSavedPosMs).abs() < 3000) {
      return;
    }
    _lastSavedPosTimestamp = now;
    _lastSavedPosMs = currentPos;
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('playback_last_pos_ms', currentPos);
      } catch (_) {}
    }());
  }

  void _savePlaybackState() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (state.currentTrack.id.isEmpty) {
          await prefs.remove('playback_last_track_id');
          await prefs.remove('playback_last_track_json');
          await prefs.remove('playback_last_pos_ms');
          return;
        }
        await prefs.setString('playback_last_track_id', state.currentTrack.id);
        await prefs.setString(
            'playback_last_track_json', jsonEncode(state.currentTrack.toMap()));
        await prefs.setInt('playback_last_pos_ms', state.positionMs);
        await prefs.setBool('playback_last_shuffle', state.isShuffle);
        await prefs.setInt('playback_last_repeat_mode', state.repeatMode);
        if (state.queue.isNotEmpty) {
          final queueIds = state.queue.map((t) => t.id).take(100).toList();
          await prefs.setStringList('playback_last_queue_ids', queueIds);
        }
      } catch (_) {}
    }());
  }

  Future<void> _restoreLastPlaybackState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final lastTrackJson = prefs.getString('playback_last_track_json');
      final lastPosMs = prefs.getInt('playback_last_pos_ms') ?? 0;
      final lastShuffle = prefs.getBool('playback_last_shuffle');
      final lastRepeat = prefs.getInt('playback_last_repeat_mode');
      final savedCrossfade = prefs.getInt('playback_crossfade_seconds') ??
          (prefs.getInt('playback_crossfade_duration_ms') != null
              ? (prefs.getInt('playback_crossfade_duration_ms')! / 1000).round()
              : null);

      if (savedCrossfade != null && mounted) {
        state = state.copyWith(crossfadeSeconds: savedCrossfade.clamp(0, 12));
      }

      if (lastTrackJson != null && lastTrackJson.isNotEmpty) {
        final map = jsonDecode(lastTrackJson) as Map<String, dynamic>;
        final track = Track.fromMap(map);
        if (track.id.isNotEmpty && !state.isPlaying && mounted) {
          state = state.copyWith(
            currentTrack: track,
            positionMs: lastPosMs,
            isShuffle: lastShuffle ?? state.isShuffle,
            repeatMode: lastRepeat ?? state.repeatMode,
          );
          _syncForegroundNotification(track: track, isPlaying: false);
        }
      }
    } catch (e) {
      debugPrint('Error restoring last playback state: $e');
    }
  }

  Future<void> syncWithLoadedCatalog(List<Track> catalog) async {
    if (catalog.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final savedTrackId = prefs.getString('playback_last_track_id');
      final savedPosMs = prefs.getInt('playback_last_pos_ms') ?? state.positionMs;
      final savedQueueIds = prefs.getStringList('playback_last_queue_ids') ?? [];

      Track? targetTrack;
      // Prioritize currently active/paused track in memory
      final effectiveId = state.currentTrack.id.isNotEmpty
          ? state.currentTrack.id
          : (savedTrackId != null && savedTrackId.isNotEmpty ? savedTrackId : '');

      if (effectiveId.isNotEmpty) {
        targetTrack = catalog.firstWhere(
          (t) => t.id == effectiveId,
          orElse: () => PlaybackViewState.emptyTrack,
        );
        if (targetTrack.id.isEmpty) {
          targetTrack = null;
        }
      }

      List<Track> restoredQueue = catalog;
      if (state.queue.isNotEmpty) {
        // Retain the active queue in memory, refreshing track metadata
        final catalogMap = {for (final t in catalog) t.id: t};
        restoredQueue = state.queue.map((t) => catalogMap[t.id] ?? t).toList();
      } else if (savedQueueIds.isNotEmpty) {
        final catalogMap = {for (final t in catalog) t.id: t};
        final orderedQueue = <Track>[];
        for (final qId in savedQueueIds) {
          final found = catalogMap[qId];
          if (found != null) {
            orderedQueue.add(found);
          }
        }
        if (orderedQueue.isNotEmpty) {
          final orderedIds = orderedQueue.map((t) => t.id).toSet();
          for (final t in catalog) {
            if (!orderedIds.contains(t.id)) {
              orderedQueue.add(t);
            }
          }
          restoredQueue = orderedQueue;
        }
      }

      final current = targetTrack ??
          (state.currentTrack.id.isNotEmpty
              ? state.currentTrack
              : restoredQueue.first);
      final finalPos = (state.currentTrack.id == current.id)
          ? state.positionMs
          : (targetTrack != null ? savedPosMs : 0);

      if (!state.isPlaying) {
        state = state.copyWith(
          currentTrack: current,
          queue: restoredQueue,
          positionMs: finalPos,
        );
        _syncForegroundNotification(track: current, isPlaying: false);
      } else {
        final updatedCurrent = restoredQueue.firstWhere(
          (t) => t.id == state.currentTrack.id,
          orElse: () => state.currentTrack,
        );
        state = state.copyWith(
          queue: restoredQueue,
          currentTrack: updatedCurrent,
        );
      }
    } catch (e) {
      debugPrint('Error syncing playback with catalog: $e');
      if (state.queue.isEmpty) {
        setQueue(catalog);
      }
    }
  }

  Future<void> _initAudioPlayer() async {
    if (_playerA != null || _isInitializingPlayer || _playerInitFailed) return;
    _isInitializingPlayer = true;
    try {
      final proxy = _ref.read(cloudStreamProxyProvider);
      await proxy.start();

      // Configure system AudioSession for USAGE_MEDIA & CONTENT_TYPE_MUSIC to guarantee speaker output
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());

        session.becomingNoisyEventStream.listen((_) {
          if (!mounted) return;
          if (state.isPlaying) {
            togglePlayPause(forcePlay: false);
          }
        });

        session.interruptionEventStream.listen((event) {
          if (!mounted) return;
          if (event.begin) {
            switch (event.type) {
              case AudioInterruptionType.duck:
                _activePlayer?.setVolume(0.25);
                break;
              case AudioInterruptionType.pause:
              case AudioInterruptionType.unknown:
                if (state.isPlaying) {
                  togglePlayPause(forcePlay: false);
                }
                break;
            }
          } else {
            switch (event.type) {
              case AudioInterruptionType.duck:
                _activePlayer?.setVolume(1.0);
                break;
              case AudioInterruptionType.pause:
                if (!state.isPlaying) {
                  togglePlayPause(forcePlay: true);
                }
                break;
              case AudioInterruptionType.unknown:
                break;
            }
          }
        });
      } catch (e) {
        debugPrint('AudioSession configuration notice: $e');
      }

      final dspSvc = _ref.read(powerampDspServiceProvider);
      dspSvc.setNotificationActionListener((action, extras) {
        if (!mounted) return;
        switch (action) {
          case 'onPlayPause':
            final playingExtra = extras['isPlaying'] as bool?;
            final isPhysicallyPlaying =
                (_playerA?.playing ?? false) || (_playerB?.playing ?? false);
            final shouldPlay =
                isPhysicallyPlaying ? false : (playingExtra ?? !state.isPlaying);
            togglePlayPause(forcePlay: shouldPlay);
            break;
          case 'onNext':
            skipNext();
            break;
          case 'onPrevious':
            skipPrevious();
            break;
          case 'onSeek':
            final pos = extras['positionMs'] as num?;
            if (pos != null) {
              seekToMs(pos.toInt());
            }
            break;
          case 'onVolume':
            final vol = extras['volume'] as num?;
            if (vol != null && _activePlayer != null) {
              _activePlayer!.setVolume(vol.toDouble());
            }
            break;
          case 'onShuffle':
            toggleShuffle();
            break;
          case 'onRepeat':
            cycleRepeatMode();
            break;
        }
      });

      _playerA = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );
      _playerB = AudioPlayer(
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );
      await _playerA!.setVolume(1.0);
      await _playerB!.setVolume(0.0);

      _setupPlayerStreams(_playerA!, isPlayerA: true);
      _setupPlayerStreams(_playerB!, isPlayerA: false);

      // Proactively purge orphaned cache copies on startup without touching user downloads
      unawaited(_ref.read(cloudAudioCacheServiceProvider).autoPurgeOrphanedCache());
    } catch (_) {
      // Headless widget test environment fallback uses smooth internal ticker
      _playerA = null;
      _playerB = null;
      _playerInitFailed = true;
    } finally {
      _isInitializingPlayer = false;
    }
  }

  void _setupPlayerStreams(AudioPlayer player, {required bool isPlayerA}) {
    int lastEmittedPosMs = -1000;
    int lastEmittedBufMs = -1000;

    player.androidAudioSessionIdStream.listen((sessionId) {
      if (sessionId != null && sessionId > 0) {
        if (_isPlayerAActive == isPlayerA) {
          final dsp = _ref.read(powerampDspServiceProvider);
          dsp.attachAudioSession(sessionId);
          dsp.applyDspState(_ref.read(powerampDspProvider));
        }
      }
    });

    player.playerStateStream.listen((playerState) {
      if (!mounted) return;
      final isCurrentActive = _isPlayerAActive == isPlayerA;
      final playing = playerState.playing;
      final proc = playerState.processingState;

      if (proc == ProcessingState.completed) {
        if (_isCrossfading) {
          // If a player completes during crossfade, conclude crossfade cleanly.
          final outgoing = _inactivePlayer;
          final incoming = _activePlayer;
          if (outgoing != null && incoming != null) {
            _completeCrossfade(outgoing, incoming);
          }
          return;
        }

        if (isCurrentActive) {
          final queueSig = state.queue.map((t) => t.id).join(',');
          final isPlaylistAligned = _playlistSource != null && _loadedQueueSignature == queueSig;
          if (isPlaylistAligned && player.hasNext && state.repeatMode == 0) {
            // Gapless playlist transitioning in ExoPlayer
          } else if (isPlaylistAligned && !player.hasNext && state.repeatMode == 0) {
            state = state.copyWith(isPlaying: false);
            _syncForegroundNotification(isPlaying: false);
            _savePlaybackState();
          } else {
            skipNext();
          }
        }
      } else if (isCurrentActive &&
          !_isCrossfading &&
          !_isPlayPending &&
          !_isTransitioningTrack &&
          state.isPlaying != playing &&
          proc != ProcessingState.loading &&
          proc != ProcessingState.buffering) {
        state = state.copyWith(isPlaying: playing);
        try {
          _ref.read(powerampDspServiceProvider).updatePlaybackNotification(
                isPlaying: playing,
                positionMs: state.positionMs,
              );
        } catch (_) {}
        _savePlaybackState();
      }
    });

    player.positionStream.listen((pos) {
      if (!mounted) return;
      final isCurrentActive = _isPlayerAActive == isPlayerA;
      if (!isCurrentActive || !state.isPlaying) return;

      final posMs = pos.inMilliseconds;

      // Crossfade Watchdog: finalize crossfade if elapsed time exceeded even if timer was throttled by Android deep sleep
      if (_isCrossfading && _crossfadeStartTimeMs != null && _crossfadeFadeMs != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - _crossfadeStartTimeMs!;
        if (elapsed >= _crossfadeFadeMs!) {
          final outgoing = _inactivePlayer;
          final incoming = _activePlayer;
          if (outgoing != null && incoming != null) {
            _completeCrossfade(outgoing, incoming);
          }
        }
      }

      // Reconcile current playing track with actual ExoPlayer index on position ticks
      // Only reconcile when using a ConcatenatingAudioSource gapless playlist, NOT during track transitions or crossfades!
      final currentIdx = player.currentIndex;
      final queueSig = state.queue.map((t) => t.id).join(',');
      final isPlaylistAligned = _playlistSource != null && _loadedQueueSignature == queueSig;
      if (!_isTransitioningTrack &&
          !_isCrossfading &&
          isPlaylistAligned &&
          player.audioSource == _playlistSource &&
          currentIdx != null &&
          currentIdx >= 0 &&
          currentIdx < state.queue.length &&
          state.queue[currentIdx].id != state.currentTrack.id) {
        final currentTag = player.sequenceState?.currentSource?.tag as Track?;
        final newTrack = state.queue[currentIdx];
        if (currentTag == null || currentTag.id == newTrack.id) {
          state = state.copyWith(
            currentTrack: newTrack,
            positionMs: posMs,
          );
          _syncForegroundNotification(track: newTrack, isPlaying: true);
          _savePlaybackState();
          _savePlaybackPosition(force: true);
          unawaited(_preloadUpcomingQueueTracks());
        }
      }

      // Loop point check
      if (state.isLoopActive &&
          state.loopPointA != null &&
          state.loopPointB != null) {
        if (posMs >= state.loopPointB!) {
          seekToMs(state.loopPointA!);
          return;
        }
      }

      // True Overlapping Crossfade Trigger & Pre-buffering
      final crossfadeSec = state.crossfadeSeconds;
      final durationMs = max(
        state.currentTrack.durationMs,
        player.duration?.inMilliseconds ?? 0,
      );

      if (crossfadeSec > 0 && durationMs > 0 && !_isCrossfading) {
        final maxFadeMs = (durationMs / 2.5).floor();
        final fadeMs = (crossfadeSec * 1000).clamp(0, maxFadeMs);
        if (fadeMs >= 1000) {
          final nextTrack = _getNextTrackInQueue();
          if (nextTrack != null && nextTrack.id.isNotEmpty) {
            // Pre-buffer 8 seconds prior to crossfade threshold into inactive player
            final preloadThresholdMs = durationMs - fadeMs - 8000;
            if (posMs >= preloadThresholdMs &&
                _preloadedTrackId != nextTrack.id &&
                !_isPreloadingNext) {
              unawaited(_preloadNextCrossfadeTrack(nextTrack));
            }

            // Trigger true overlapping crossfade
            if (posMs >= (durationMs - fadeMs)) {
              final remainingMs = durationMs - posMs;
              final effectiveFadeMs =
                  remainingMs > 1000 ? min(fadeMs, remainingMs) : fadeMs;
              _triggerCrossfade(effectiveFadeMs, nextTrack);
              return;
            }
          }
        }
      }

      final isPowerSaver = _ref.read(effectivePowerSaverActiveProvider);
      final throttleMs = isPowerSaver ? 1000 : 200;
      if (((posMs - lastEmittedPosMs).abs() >= throttleMs || posMs == 0) &&
          state.positionMs != posMs) {
        lastEmittedPosMs = posMs;
        state = state.copyWith(positionMs: posMs);
        _savePlaybackPosition();
      }
    });

    player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      final isCurrentActive = _isPlayerAActive == isPlayerA;
      if (!isCurrentActive) return;
      final durMs = duration.inMilliseconds;
      if (durMs > 0 &&
          durMs != state.currentTrack.durationMs &&
          state.currentTrack.id.isNotEmpty) {
        final updated = state.currentTrack.copyWith(durationMs: durMs);
        state = state.copyWith(currentTrack: updated);
      }
    });

    player.bufferedPositionStream.listen((buf) {
      if (!mounted) return;
      final isCurrentActive = _isPlayerAActive == isPlayerA;
      if (!isCurrentActive) return;
      final bufMs = buf.inMilliseconds;
      if ((bufMs - lastEmittedBufMs).abs() >= 1000 || bufMs == 0) {
        lastEmittedBufMs = bufMs;
        state = state.copyWith(bufferedPositionMs: bufMs);
      }
    });

    // Primary Gapless Transition Listener via ExoPlayer direct currentIndex
    player.currentIndexStream.listen((index) {
      if (!mounted || index == null) return;
      final isCurrentActive = _isPlayerAActive == isPlayerA;
      final queueSig = state.queue.map((t) => t.id).join(',');
      final isPlaylistAligned = _playlistSource != null && _loadedQueueSignature == queueSig;
      if (!isCurrentActive ||
          !state.isPlaying ||
          !isPlaylistAligned ||
          _isCrossfading ||
          _isTransitioningTrack ||
          player.audioSource != _playlistSource) {
        return;
      }

      if (index >= 0 && index < state.queue.length) {
        final newTrack = state.queue[index];
        final currentTag = player.sequenceState?.currentSource?.tag as Track?;
        if (currentTag != null && currentTag.id != newTrack.id) {
          return;
        }
        if (newTrack.id != state.currentTrack.id) {
          state = state.copyWith(
            currentTrack: newTrack,
            positionMs: 0,
          );
          _syncForegroundNotification(track: newTrack, isPlaying: true);
          _savePlaybackState();
          _savePlaybackPosition(force: true);
          unawaited(_preloadUpcomingQueueTracks());
        }
      }
    });

    player.sequenceStateStream.listen((sequenceState) {
      if (!mounted || sequenceState == null) return;
      final isCurrentActive = _isPlayerAActive == isPlayerA;
      if (!isCurrentActive || !state.isPlaying || _isCrossfading || _isTransitioningTrack) return;
      final currentSource = sequenceState.currentSource;
      final playingTrack = currentSource?.tag as Track?;

      if (playingTrack != null && playingTrack.id.isNotEmpty) {
        // Discard events from a previous queue or audio source
        if (state.queue.isNotEmpty && !state.queue.any((t) => t.id == playingTrack.id)) {
          return;
        }
        if (playingTrack.id != state.currentTrack.id) {
          final foundTrack = state.queue.firstWhere(
            (t) => t.id == playingTrack.id,
            orElse: () => playingTrack,
          );
          state = state.copyWith(
            currentTrack: foundTrack,
            positionMs: 0,
          );
          _syncForegroundNotification(track: foundTrack, isPlaying: true);
          _savePlaybackState();
          _savePlaybackPosition(force: true);
          unawaited(_preloadUpcomingQueueTracks());
        }
      }
    });
  }

  Future<void> _preloadNextCrossfadeTrack(Track nextTrack) async {
    if (_isPreloadingNext || _isCrossfading || !mounted) return;
    final inactive = _inactivePlayer;
    if (inactive == null) return;
    _isPreloadingNext = true;
    _preloadedTrackId = nextTrack.id;
    try {
      final catalog = _ref.read(tracksCatalogProvider);
      final freshNext =
          catalog.firstWhere((t) => t.id == nextTrack.id, orElse: () => nextTrack);

      // Preload next track's artwork into Android cache 8 seconds ahead of crossfade!
      final art = freshNext.artworkUrl ?? ArtworkExtractor.getCachedArtworkPath(freshNext.id);
      if (art != null && art.isNotEmpty) {
        unawaited(_ref.read(powerampDspServiceProvider).preloadArtwork(art));
      } else {
        unawaited(_ref.read(tracksCatalogProvider.notifier).enrichTrackArtwork(freshNext));
      }

      final source = await _createAudioSource(freshNext);
      if (!_isCrossfading && _preloadedTrackId == nextTrack.id && mounted) {
        await inactive.setAudioSource(source);
        await inactive.setVolume(0.0);
      }
    } catch (e) {
      debugPrint('Preload crossfade track error: $e');
      if (_preloadedTrackId == nextTrack.id) {
        _preloadedTrackId = null;
      }
    } finally {
      _isPreloadingNext = false;
    }
  }

  Future<void> _triggerCrossfade(int fadeMs, Track nextTrack) async {
    if (_isCrossfading || !mounted || !state.isPlaying) return;

    final outgoingPlayer = _activePlayer;
    final incomingPlayer = _inactivePlayer;
    if (outgoingPlayer == null || incomingPlayer == null) return;

    final catalog = _ref.read(tracksCatalogProvider);
    final freshNextTrack = catalog.firstWhere(
      (t) => t.id == nextTrack.id,
      orElse: () => nextTrack,
    );

    _isCrossfading = true;

    try {
      if (_isPreloadingNext) {
        int waited = 0;
        while (_isPreloadingNext && waited < 1000) {
          await Future.delayed(const Duration(milliseconds: 50));
          waited += 50;
        }
      }

      final wasPreloaded = _preloadedTrackId == freshNextTrack.id &&
          incomingPlayer.audioSource != null &&
          incomingPlayer.playerState.processingState != ProcessingState.idle;

      if (!wasPreloaded) {
        final source = await _createAudioSource(freshNextTrack);
        await incomingPlayer.setAudioSource(source);
      }
      _preloadedTrackId = null;

      await incomingPlayer.setVolume(0.0);
      if (state.playbackSpeed != 1.0) {
        try {
          await incomingPlayer.setSpeed(state.playbackSpeed);
        } catch (_) {}
      }
      if (state.pitch != 1.0) {
        try {
          await incomingPlayer.setPitch(state.pitch);
        } catch (_) {}
      }

      _crossfadeStartTimeMs = DateTime.now().millisecondsSinceEpoch;
      _crossfadeFadeMs = fadeMs;

      // Concurrently start playback of incoming track without blocking
      unawaited(incomingPlayer.play());

      // Immediately flip the active player flag so incomingPlayer is now _activePlayer,
      // and outgoingPlayer is _inactivePlayer!
      _isPlayerAActive = !_isPlayerAActive;

      // Update state to the new track so that NowPlayingScreen, MiniPlayer,
      // and Android notification immediately show the new track and progress from 0:00:
      state = state.copyWith(
        currentTrack: freshNextTrack,
        positionMs: 0,
      );
      _syncForegroundNotification(track: freshNextTrack, isPlaying: true);
      _savePlaybackState();

      if (freshNextTrack.artworkUrl == null || freshNextTrack.artworkUrl!.isEmpty) {
        unawaited(_ref.read(tracksCatalogProvider.notifier).enrichTrackArtwork(freshNextTrack));
      }

      final startMs = DateTime.now().millisecondsSinceEpoch;
      double lastVolOut = 1.0;
      double lastVolIn = 0.0;
      _crossfadeTimer?.cancel();
      _crossfadeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!_isCrossfading || !mounted) {
          timer.cancel();
          return;
        }
        final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
        final progress = (elapsed / fadeMs).clamp(0.0, 1.0);

        // Constant equal-power loudness curves
        final volOut = cos(progress * (pi / 2)).clamp(0.0, 1.0);
        final volIn = sin(progress * (pi / 2)).clamp(0.0, 1.0);

        if ((volOut - lastVolOut).abs() >= 0.01) {
          lastVolOut = volOut;
          outgoingPlayer.setVolume(volOut);
        }
        if ((volIn - lastVolIn).abs() >= 0.01) {
          lastVolIn = volIn;
          incomingPlayer.setVolume(volIn);
        }

        if (progress >= 1.0) {
          timer.cancel();
          _crossfadeTimer = null;
          _completeCrossfade(outgoingPlayer, incomingPlayer);
        }
      });
    } catch (e) {
      debugPrint('Crossfade setup error: $e');
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _crossfadeStartTimeMs = null;
      _crossfadeFadeMs = null;
      _isCrossfading = false;
      if (_activePlayer != outgoingPlayer) {
        _isPlayerAActive = !_isPlayerAActive;
      }
      await outgoingPlayer.setVolume(1.0);
    }
  }

  Future<void> _completeCrossfade(AudioPlayer outgoingPlayer, AudioPlayer incomingPlayer) async {
    if (!_isCrossfading) return;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _crossfadeStartTimeMs = null;
    _crossfadeFadeMs = null;
    _isCrossfading = false;
    try {
      await outgoingPlayer.pause();
      await outgoingPlayer.stop();
      await outgoingPlayer.setVolume(0.0);
      await incomingPlayer.setVolume(1.0);
    } catch (_) {}

    // Attach hardware DSP effects to the newly active player's session
    final sessionId = _activePlayer?.androidAudioSessionId;
    if (sessionId != null && sessionId > 0) {
      _ref.read(powerampDspServiceProvider).attachAudioSession(sessionId);
      _ref.read(powerampDspServiceProvider).applyDspState(_ref.read(powerampDspProvider));
    }
    _syncForegroundNotification(track: state.currentTrack, isPlaying: true);
    unawaited(_preloadUpcomingQueueTracks());
  }

  Track? _getNextTrackInQueue() {
    if (state.queue.isEmpty) return null;
    if (state.repeatMode == 2) {
      return state.currentTrack;
    }
    final currentId = state.currentTrack.id;
    final idx = state.queue.indexWhere((t) => t.id == currentId);
    if (idx != -1 && idx < state.queue.length - 1) {
      return state.queue[idx + 1];
    } else if (state.repeatMode == 1 && state.queue.isNotEmpty) {
      return state.queue.first;
    }
    return null;
  }

  Future<void> _ensureAudioPlayerInitialized() async {
    if (_playerA == null && !_playerInitFailed) {
      await _initAudioPlayer();
    }
  }

  void _startTicker() {
    _progressTicker?.cancel();
    if (_audioPlayer != null) return;
    _progressTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !state.isPlaying) return;
      if (_audioPlayer != null) {
        _progressTicker?.cancel();
        return;
      }
      final nextPos = state.positionMs + 250;
      if (nextPos >= state.currentTrack.durationMs) {
        skipNext();
      } else {
        state = state.copyWith(
          positionMs: nextPos,
          bufferedPositionMs:
              (nextPos + 90000).clamp(0, state.currentTrack.durationMs),
        );
      }
    });
  }

  void _syncForegroundNotification({Track? track, bool? isPlaying}) {
    final t = track ?? state.currentTrack;
    if (t.id.isEmpty) return;
    final playing = isPlaying ?? state.isPlaying;
    final routeInfo = _ref.read(audioRouteInfoProvider);
    final isPowerSaver = _ref.read(effectivePowerSaverActiveProvider);
    final isLocal = (t.localCachePath != null && File(t.localCachePath!).existsSync()) ||
        (!t.streamUrl.startsWith('http://') && !t.streamUrl.startsWith('https://'));
    final effectiveArtwork = (t.artworkUrl != null && t.artworkUrl!.isNotEmpty)
        ? t.artworkUrl
        : ArtworkExtractor.getCachedArtworkPath(t.id);
    try {
      final dspSvc = _ref.read(powerampDspServiceProvider);
      dspSvc.startForegroundPlayback(
        title: t.title,
        artist: t.artist,
        album: t.album,
        artworkPath: effectiveArtwork,
        durationMs: t.durationMs,
        positionMs: state.positionMs,
        isPlaying: playing,
        volume: 1.0,
        dominantColor: t.dominantColorValue,
        outputDevice: routeInfo.deviceName,
        isShuffle: state.isShuffle,
        repeatMode: state.repeatMode,
        isPowerSaver: isPowerSaver,
        isCurrentTrackLocal: isLocal,
      );
    } catch (_) {}
  }

  Future<void> togglePlayPause({bool? forcePlay}) async {
    await PixelHaptics.playPauseToggle();
    final isPhysicallyPlaying =
        (_playerA?.playing ?? false) || (_playerB?.playing ?? false);
    final nextPlaying =
        forcePlay ?? (isPhysicallyPlaying ? false : !state.isPlaying);
    state = state.copyWith(isPlaying: nextPlaying);

    if (nextPlaying) {
      _isPlayPending = true;
      _startTicker();
      await _ensureAudioPlayerInitialized();
      try {
        final session = await AudioSession.instance;
        await session.setActive(true);
      } catch (_) {}
      try {
        final proxy = _ref.read(cloudStreamProxyProvider);
        final quality = _ref.read(audioQualityProvider).effectiveStreamingTier;
        proxy.updateCatalog(
          tracks: _ref.read(tracksCatalogProvider),
          accounts: _ref.read(cloudAccountsProvider),
          activeTier: quality,
        );
        if (_audioPlayer != null) {
          final currentLoadedTrack = _audioPlayer!.sequenceState?.currentSource?.tag as Track?;
          final sameTrackLoaded = currentLoadedTrack != null &&
              currentLoadedTrack.id == state.currentTrack.id;
          final needsReload = !sameTrackLoaded ||
              _audioPlayer!.audioSource == null ||
              _audioPlayer!.playerState.processingState == ProcessingState.idle ||
              _audioPlayer!.playerState.processingState == ProcessingState.completed;

          if (needsReload) {
            final trackToPlay = state.currentTrack.id.isNotEmpty
                ? state.currentTrack
                : (state.queue.isNotEmpty ? state.queue.first : PlaybackViewState.emptyTrack);
            if (trackToPlay.id.isNotEmpty) {
              if (state.currentTrack.id != trackToPlay.id) {
                state = state.copyWith(currentTrack: trackToPlay);
              }
              final idx = state.queue.indexWhere((t) => t.id == trackToPlay.id);
              if (idx != -1) {
                await _loadAndPlayPlaylist(state.queue, initialIndex: idx, initialPositionMs: state.positionMs);
              } else {
                await _loadAndPlayTrack(trackToPlay, initialPositionMs: state.positionMs);
              }
            }
          } else {
            try {
              if (state.crossfadeSeconds <= 0) {
                await _audioPlayer!.setVolume(1.0);
              }
              await _audioPlayer!.play();
            } catch (playErr) {
              debugPrint('Direct play error, falling back to reload: $playErr');
              final idx = state.queue.indexWhere((t) => t.id == state.currentTrack.id);
              if (idx != -1) {
                await _loadAndPlayPlaylist(state.queue, initialIndex: idx, initialPositionMs: state.positionMs);
              } else {
                await _loadAndPlayTrack(state.currentTrack, initialPositionMs: state.positionMs);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Toggle play error: $e');
      } finally {
        _isPlayPending = false;
      }
      _syncForegroundNotification(isPlaying: true);
      _savePlaybackState();
      unawaited(_preloadUpcomingQueueTracks());
    } else {
      _isPlayPending = false;
      _progressTicker?.cancel();
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _crossfadeStartTimeMs = null;
      _crossfadeFadeMs = null;
      _isCrossfading = false;

      // Unconditionally pause BOTH physical players to eliminate ghost background audio
      try {
        await Future.wait([
          if (_playerA != null) _playerA!.pause(),
          if (_playerB != null) _playerB!.pause(),
        ]);
        if (_inactivePlayer != null) {
          await _inactivePlayer!.stop();
          await _inactivePlayer!.setVolume(0.0);
        }
      } catch (_) {}
      _syncForegroundNotification(isPlaying: false);
      _savePlaybackPosition(force: true);
      _savePlaybackState();
    }
  }

  Future<AudioSource> _createAudioSource(Track track) async {
    Track effectiveTrack = track;

    // Self-healing: if localCachePath points to a file deleted when clearing cache, clear it immediately
    if (effectiveTrack.localCachePath != null &&
        effectiveTrack.localCachePath!.isNotEmpty &&
        !File(effectiveTrack.localCachePath!).existsSync()) {
      effectiveTrack = effectiveTrack.copyWith(
        clearLocalCachePath: true,
        isPinnedOffline: false,
      );
      unawaited(_ref.read(tracksCatalogProvider.notifier).updateTrack(effectiveTrack));
    }

    // Self-healing: if streamUrl points to an ephemeral or cache file that was deleted:
    if (!effectiveTrack.streamUrl.startsWith('http://') &&
        !effectiveTrack.streamUrl.startsWith('https://') &&
        !effectiveTrack.streamUrl.startsWith('content://')) {
      if (!File(effectiveTrack.streamUrl).existsSync()) {
        if (effectiveTrack.remotePathOrId.startsWith('content://')) {
          effectiveTrack = effectiveTrack.copyWith(
            streamUrl: effectiveTrack.remotePathOrId,
            clearLocalCachePath: true,
            isPinnedOffline: false,
          );
          unawaited(_ref.read(tracksCatalogProvider.notifier).updateTrack(effectiveTrack));
        } else if (effectiveTrack.remotePathOrId.startsWith('http://') ||
            effectiveTrack.remotePathOrId.startsWith('https://')) {
          effectiveTrack = effectiveTrack.copyWith(
            streamUrl: effectiveTrack.remotePathOrId,
            clearLocalCachePath: true,
            isPinnedOffline: false,
          );
          unawaited(_ref.read(tracksCatalogProvider.notifier).updateTrack(effectiveTrack));
        }
      }
    }

    final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
    final cachedPath = await cacheSvc.getCachedFilePath(effectiveTrack);

    // 0. Transcode check (WMA, AIFF, etc.)
    final pathLower = (cachedPath ?? effectiveTrack.localCachePath ?? effectiveTrack.streamUrl).toLowerCase();
    if (UniversalAudioTranscoderService.requiresTranscoding(effectiveTrack, pathLower)) {
      try {
        final transcoder = _ref.read(universalAudioTranscoderServiceProvider);
        String? src = cachedPath ?? effectiveTrack.localCachePath;
        if (src == null || !File(src).existsSync()) {
          src = effectiveTrack.streamUrl;
        }
        if (src.isNotEmpty && File(src).existsSync()) {
          final transcoded = await transcoder.transcodeToWav(track: effectiveTrack, sourcePath: src);
          if (transcoded != null && File(transcoded).existsSync()) {
            return AudioSource.file(transcoded, tag: effectiveTrack);
          }
        }
      } catch (_) {}
    }

    // 1. Cached offline on disk
    if (cachedPath != null && File(cachedPath).existsSync()) {
      return AudioSource.file(cachedPath, tag: effectiveTrack);
    }
    if (effectiveTrack.localCachePath != null && File(effectiveTrack.localCachePath!).existsSync()) {
      return AudioSource.file(effectiveTrack.localCachePath!, tag: effectiveTrack);
    }

    // 2. Local device storage file
    if (!effectiveTrack.streamUrl.startsWith('http://') &&
        !effectiveTrack.streamUrl.startsWith('https://') &&
        !effectiveTrack.streamUrl.startsWith('content://')) {
      if (File(effectiveTrack.streamUrl).existsSync()) {
        return AudioSource.file(effectiveTrack.streamUrl, tag: effectiveTrack);
      } else if (effectiveTrack.remotePathOrId.startsWith('content://')) {
        return AudioSource.uri(Uri.parse(effectiveTrack.remotePathOrId), tag: effectiveTrack);
      } else {
        return AudioSource.uri(Uri.file(effectiveTrack.streamUrl), tag: effectiveTrack);
      }
    }

    // 3. Android SAF content URI
    if (effectiveTrack.streamUrl.startsWith('content://')) {
      return AudioSource.uri(Uri.parse(effectiveTrack.streamUrl), tag: effectiveTrack);
    }

    // 4. Remote cloud stream through loopback proxy (127.0.0.1)
    final proxy = _ref.read(cloudStreamProxyProvider);
    final quality = _ref.read(audioQualityProvider).effectiveStreamingTier;
    proxy.registerTrack(effectiveTrack);
    final playbackUrl = proxy.buildPlaybackUrl(effectiveTrack, quality);

    if (playbackUrl.startsWith('http://127.0.0.1')) {
      return AudioSource.uri(Uri.parse(playbackUrl), tag: effectiveTrack);
    } else {
      Map<String, String>? headers;
      if (effectiveTrack.providerType == CloudProviderType.googleDrive) {
        final secrets = await _ref
            .read(credentialStoreProvider)
            .readSecrets(effectiveTrack.accountId);
        final token = secrets['accessToken'] ?? '';
        if (token.isNotEmpty) {
          headers = {'Authorization': 'Bearer $token'};
        }
      }
      return AudioSource.uri(Uri.parse(playbackUrl), headers: headers, tag: effectiveTrack);
    }
  }

  Future<void> _loadAndPlayPlaylist(
    List<Track> queue, {
    required int initialIndex,
    int? initialPositionMs,
  }) async {
    final active = _activePlayer;
    if (active == null || queue.isEmpty) return;

    if (_isCrossfading) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _isCrossfading = false;
      try {
        await _inactivePlayer?.stop();
        await _inactivePlayer?.setVolume(0.0);
      } catch (_) {}
    }
    _preloadedTrackId = null;

    final targetTrack = (initialIndex >= 0 && initialIndex < queue.length)
        ? queue[initialIndex]
        : queue.first;

    final wasTransitioning = _isTransitioningTrack;
    _isTransitioningTrack = true;
    _isPlayPending = true;

    try {
      // When crossfade is enabled (crossfadeSeconds > 0):
      // Play tracks via the true dual-player crossfade engine!
      if (state.crossfadeSeconds > 0) {
        _playlistSource = null;
        _loadedQueueSignature = null;
        await _loadAndPlayTrack(targetTrack, initialPositionMs: initialPositionMs);
        return;
      }

      // When crossfade is 0 (True Gapless Playback):
      // Use ExoPlayer's ConcatenatingAudioSource for 0ms transition gap between tracks!
      final initPos = (initialPositionMs != null &&
              initialPositionMs > 0 &&
              initialIndex >= 0 &&
              initialIndex < queue.length &&
              initialPositionMs < (queue[initialIndex].durationMs - 2000))
          ? Duration(milliseconds: initialPositionMs)
          : null;

      final queueSig = queue.map((t) => t.id).join(',');

      // If the same playlist is already loaded in ExoPlayer, just seek to the track index gaplessly!
      if (_playlistSource != null &&
          _loadedQueueSignature == queueSig &&
          active.audioSource != null &&
          active.playerState.processingState != ProcessingState.idle) {
        try {
          state = state.copyWith(
            currentTrack: targetTrack,
            positionMs: initialPositionMs ?? 0,
            isPlaying: true,
          );
          _syncForegroundNotification(track: targetTrack, isPlaying: true);
          await active.seek(initPos ?? Duration.zero, index: initialIndex);
          await active.setVolume(1.0);
          await active.play();
          state = state.copyWith(
            currentTrack: targetTrack,
            positionMs: initialPositionMs ?? 0,
            isPlaying: true,
          );
          _savePlaybackState();
          _savePlaybackPosition(force: true);
          unawaited(_preloadUpcomingQueueTracks());
          return;
        } catch (e) {
          debugPrint('Seek within playlist failed, rebuilding: $e');
        }
      }

      // Immediately pause old track to eliminate ghost background audio while building playlist
      if (active.playing) {
        try {
          await active.pause();
        } catch (_) {}
      }

      // Build the ConcatenatingAudioSource for gapless playback in parallel
      final sources = await Future.wait(queue.map((t) => _createAudioSource(t)));

      _playlistSource = ConcatenatingAudioSource(
        children: sources,
        useLazyPreparation: true, // Seamless ExoPlayer gapless pre-buffering
      );
      _loadedQueueSignature = queueSig;

      // Apply repeat and shuffle
      final loopMode = state.repeatMode == 2
          ? LoopMode.one
          : (state.repeatMode == 1 ? LoopMode.all : LoopMode.off);
      try {
        await active.setLoopMode(loopMode);
        await active.setShuffleModeEnabled(state.isShuffle);
      } catch (_) {}

      try {
        await active.setAudioSource(
          _playlistSource!,
          initialIndex: initialIndex.clamp(0, sources.length - 1),
          initialPosition: initPos,
        );
        await active.setVolume(1.0);
        await active.play();
      } catch (e) {
        debugPrint('setAudioSource playlist error: $e');
      }

      // Ensure state and notification firmly reflect the target track
      state = state.copyWith(
        currentTrack: targetTrack,
        positionMs: initialPositionMs ?? 0,
        isPlaying: true,
      );
      _syncForegroundNotification(track: targetTrack, isPlaying: true);
      _savePlaybackState();
      _savePlaybackPosition(force: true);

      // Preload at least 5 upcoming songs in the queue into stream cache
      unawaited(_preloadUpcomingQueueTracks());
    } finally {
      if (!wasTransitioning) {
        _isTransitioningTrack = false;
        _isPlayPending = false;
      }
    }
  }

  Future<void> _preloadUpcomingQueueTracks() async {
    final queue = state.queue;
    final currentId = state.currentTrack.id;
    if (queue.isEmpty || currentId.isEmpty) return;

    final isPowerSaver = _ref.read(effectivePowerSaverActiveProvider);
    final count = isPowerSaver ? 1 : 5;
    final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
    unawaited(cacheSvc.preloadQueueTracks(
      queue,
      currentTrackId: currentId,
      preloadCount: count,
      onTrackCached: (updatedTrack) {
        if (!mounted) return;
        _ref.read(tracksCatalogProvider.notifier).updateTrack(updatedTrack);
      },
    ));
  }

  Future<void> _loadAndPlayTrack(Track track, {int? initialPositionMs}) async {
    final active = _activePlayer;
    if (active == null || track.id.isEmpty) return;

    if (_isCrossfading) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _isCrossfading = false;
      try {
        await _inactivePlayer?.stop();
        await _inactivePlayer?.setVolume(0.0);
      } catch (_) {}
    }
    _preloadedTrackId = null;

    final wasTransitioning = _isTransitioningTrack;
    _isTransitioningTrack = true;
    _isPlayPending = true;

    try {
      await active.setVolume(1.0);

      if (state.playbackSpeed != 1.0) {
        try {
          await active.setSpeed(state.playbackSpeed);
        } catch (_) {}
      }
      if (state.pitch != 1.0) {
        try {
          await active.setPitch(state.pitch);
        } catch (_) {}
      }

      final initPos = (initialPositionMs != null &&
              initialPositionMs > 0 &&
              initialPositionMs < (track.durationMs - 2000))
          ? Duration(milliseconds: initialPositionMs)
          : null;

      try {
        final source = await _createAudioSource(track);
        await active.setAudioSource(source, initialPosition: initPos);
        await active.setVolume(1.0);
        await active.play();
      } catch (e) {
        debugPrint('setAudioSource single error: $e');
      }

      state = state.copyWith(
        currentTrack: track,
        positionMs: initialPositionMs ?? 0,
        isPlaying: true,
      );
      _syncForegroundNotification(track: track, isPlaying: true);
      _savePlaybackState();
      _savePlaybackPosition(force: true);
      unawaited(_preloadUpcomingQueueTracks());
    } catch (e, st) {
      debugPrint('Error playing track "${track.title}": $e\n$st');
    } finally {
      if (!wasTransitioning) {
        _isTransitioningTrack = false;
        _isPlayPending = false;
      }
    }
  }

  void setQueue(List<Track> tracks, {Track? startTrack}) {
    if (tracks.isEmpty) return;
    final sanitizedTracks = tracks.map((t) {
      if (t.dominantColorValue == 0xFF3DDC84 ||
          t.dominantColorValue == 0xFF1DB954) {
        return t.copyWith(dominantColorValue: 0xFF1E293B);
      }
      return t;
    }).toList();

    _unshuffledQueue = null;
    final current = startTrack ??
        (sanitizedTracks.any((t) => t.id == state.currentTrack.id)
            ? state.currentTrack
            : sanitizedTracks.first);
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    state = state.copyWith(queue: sanitizedTracks, currentTrack: current);
    _savePlaybackState();
  }

  void updateCurrentTrack(Track updated) {
    final newQueue =
        state.queue.map((t) => t.id == updated.id ? updated : t).toList();
    if (state.currentTrack.id == updated.id) {
      state = state.copyWith(currentTrack: updated, queue: newQueue);
      try {
        _ref.read(powerampDspServiceProvider).updatePlaybackNotification(
              title: updated.title,
              artist: updated.artist,
              artworkPath: updated.artworkUrl,
              dominantColor: updated.dominantColorValue,
            );
      } catch (_) {}
    } else {
      state = state.copyWith(queue: newQueue);
    }
  }

  void setLyricsOffsetMs(int offsetMs) {
    if (state.currentTrack.id.isEmpty) return;
    final updated = state.currentTrack.copyWith(lyricsOffsetMs: offsetMs);
    state = state.copyWith(currentTrack: updated);
    _ref.read(tracksCatalogProvider.notifier).updateTrack(updated);
  }

  void updateCurrentTrackLyrics(List<LyricLine> lyrics) {
    if (state.currentTrack.id.isEmpty) return;
    final updated = state.currentTrack.copyWith(syncedLyrics: lyrics);
    state = state.copyWith(currentTrack: updated);
    _ref.read(tracksCatalogProvider.notifier).updateTrack(updated);
  }

  Future<void> playTrack(
    Track track, {
    List<Track>? newQueue,
    bool? isShuffle,
  }) async {
    await PixelHaptics.playPauseToggle();
    if (_isCrossfading) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _isCrossfading = false;
      try {
        await _activePlayer?.stop();
        await _inactivePlayer?.stop();
        await _activePlayer?.setVolume(1.0);
        await _inactivePlayer?.setVolume(0.0);
      } catch (_) {}
    }
    _preloadedTrackId = null;

    final catalog = _ref.read(tracksCatalogProvider);
    final freshTrack =
        catalog.firstWhere((t) => t.id == track.id, orElse: () => track);
    final effectiveTrack = (freshTrack.dominantColorValue == 0xFF3DDC84 ||
            freshTrack.dominantColorValue == 0xFF1DB954)
        ? freshTrack.copyWith(dominantColorValue: 0xFF1E293B)
        : freshTrack;

    final bool targetShuffle = isShuffle ?? state.isShuffle;
    List<Track> baseQueue = newQueue ??
        (state.queue.isEmpty ? _ref.read(tracksCatalogProvider) : state.queue);

    if (newQueue != null) {
      if (targetShuffle) {
        _unshuffledQueue = List<Track>.from(newQueue);
      } else {
        _unshuffledQueue = null;
      }
    }

    final hasTrack = baseQueue.any((t) => t.id == effectiveTrack.id);
    List<Track> queueToUse =
        hasTrack ? baseQueue : [effectiveTrack, ...baseQueue];

    if (targetShuffle && newQueue != null && (isShuffle == null || !isShuffle)) {
      // User tapped a specific track while in shuffle mode: keep that track first, shuffle the remaining
      final remaining = baseQueue.where((t) => t.id != effectiveTrack.id).toList()..shuffle();
      queueToUse = [effectiveTrack, ...remaining];
    }

    // Record session history
    final prevTrack = state.currentTrack;
    List<Track> updatedHistory = state.sessionHistory;
    if (prevTrack.id.isNotEmpty && prevTrack.id != effectiveTrack.id) {
      updatedHistory = [
        prevTrack,
        ...state.sessionHistory.where((t) => t.id != prevTrack.id)
      ].take(50).toList();
    }

    _isTransitioningTrack = true;
    _isPlayPending = true;

    state = state.copyWith(
      currentTrack: effectiveTrack,
      queue: queueToUse,
      sessionHistory: updatedHistory,
      positionMs: 0,
      bufferedPositionMs: (effectiveTrack.durationMs * 0.35).round(),
      isPlaying: true,
      isShuffle: targetShuffle,
    );
    _startTicker();
    _savePlaybackState();
    _savePlaybackPosition(force: true);

    await _ensureAudioPlayerInitialized();
    try {
      if (_activePlayer != null) {
        final idx = queueToUse.indexWhere((t) => t.id == effectiveTrack.id);
        await _loadAndPlayPlaylist(queueToUse, initialIndex: idx >= 0 ? idx : 0);
      }
    } catch (_) {
      try {
        if (_activePlayer != null) {
          await _loadAndPlayTrack(effectiveTrack);
        }
      } catch (_) {}
    } finally {
      state = state.copyWith(
        currentTrack: effectiveTrack,
        queue: queueToUse,
        isPlaying: true,
        isShuffle: targetShuffle,
      );
      _syncForegroundNotification(track: effectiveTrack, isPlaying: true);
      _savePlaybackState();
      _isTransitioningTrack = false;
      _isPlayPending = false;
    }

    unawaited(_preloadUpcomingQueueTracks());

    if (effectiveTrack.artworkUrl == null ||
        effectiveTrack.artworkUrl!.isEmpty) {
      _ref.read(tracksCatalogProvider.notifier).enrichTrackArtwork(effectiveTrack);
    }
  }

  Future<void> seekToMs(int targetMs, {bool withHaptic = false}) async {
    if (withHaptic) {
      await PixelHaptics.lowTick(intensity: 0.35);
    }
    if (_isCrossfading) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _isCrossfading = false;
      try {
        await _inactivePlayer?.stop();
        await _inactivePlayer?.setVolume(0.0);
        await _activePlayer?.setVolume(1.0);
      } catch (_) {}
    }
    _preloadedTrackId = null;
    final clamped = targetMs.clamp(0, state.currentTrack.durationMs);
    state = state.copyWith(positionMs: clamped);
    _savePlaybackPosition(force: true);
    try {
      unawaited(_activePlayer?.seek(Duration(milliseconds: clamped)));
    } catch (_) {}
  }

  Future<void> skipNext() async {
    await PixelHaptics.tick(intensity: 0.8);

    if (_isCrossfading) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _crossfadeStartTimeMs = null;
      _crossfadeFadeMs = null;
      _isCrossfading = false;
      try {
        await Future.wait([
          if (_playerA != null) _playerA!.pause(),
          if (_playerB != null) _playerB!.pause(),
        ]);
        await _activePlayer?.stop();
        await _inactivePlayer?.stop();
        await _activePlayer?.setVolume(1.0);
        await _inactivePlayer?.setVolume(0.0);
      } catch (_) {}
    }
    _preloadedTrackId = null;

    if (_sleepTimerEndAfterTrack) {
      _sleepTimerEndAfterTrack = false;
      state = state.copyWith(
        isPlaying: false,
        clearSleepTimer: true,
      );
      try {
        await _activePlayer?.pause();
        _ref.read(powerampDspServiceProvider).stopForegroundPlayback();
      } catch (_) {}
      return;
    }

    if (state.repeatMode == 2) {
      // Repeat current track
      await seekToMs(0);
      try {
        await _activePlayer?.play();
      } catch (_) {}
      return;
    }

    // In gapless mode with ConcatenatingAudioSource:
    final queueSig = state.queue.map((t) => t.id).join(',');
    final isPlaylistAligned = _playlistSource != null && _loadedQueueSignature == queueSig;
    if (state.crossfadeSeconds == 0 && isPlaylistAligned && _activePlayer != null && _activePlayer!.hasNext) {
      try {
        final nextIdx = _activePlayer!.nextIndex;
        if (nextIdx != null && nextIdx >= 0 && nextIdx < state.queue.length) {
          final nextTrack = state.queue[nextIdx];
          state = state.copyWith(currentTrack: nextTrack, positionMs: 0);
          _syncForegroundNotification(track: nextTrack, isPlaying: true);
          _savePlaybackState();
        }
        _isTransitioningTrack = true;
        try {
          await _activePlayer!.seekToNext();
        } finally {
          _isTransitioningTrack = false;
        }
        return;
      } catch (_) {}
    }

    final idx = state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (idx != -1 && idx < state.queue.length - 1) {
      await playTrack(state.queue[idx + 1]);
    } else if (state.repeatMode == 1 && state.queue.isNotEmpty) {
      if (state.isShuffle && state.queue.length > 1) {
        final reshuffled = List<Track>.from(state.queue)..shuffle();
        state = state.copyWith(queue: reshuffled);
        _loadedQueueSignature = null;
        await playTrack(reshuffled.first);
      } else {
        await playTrack(state.queue.first);
      }
    } else if (state.isAutoplay) {
      _triggerAutoplayNext();
    } else if (state.queue.isNotEmpty) {
      state = state.copyWith(isPlaying: false, positionMs: 0);
      try {
        await Future.wait([
          if (_playerA != null) _playerA!.pause(),
          if (_playerB != null) _playerB!.pause(),
        ]);
        if (_inactivePlayer != null) {
          await _inactivePlayer!.stop();
          await _inactivePlayer!.setVolume(0.0);
        }
        _ref.read(powerampDspServiceProvider).stopForegroundPlayback();
      } catch (_) {}
    }
  }

  Future<void> skipPrevious() async {
    await PixelHaptics.tick(intensity: 0.8);
    if (_isCrossfading) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _crossfadeStartTimeMs = null;
      _crossfadeFadeMs = null;
      _isCrossfading = false;
      try {
        await Future.wait([
          if (_playerA != null) _playerA!.pause(),
          if (_playerB != null) _playerB!.pause(),
        ]);
        await _activePlayer?.stop();
        await _inactivePlayer?.stop();
        await _activePlayer?.setVolume(1.0);
        await _inactivePlayer?.setVolume(0.0);
      } catch (_) {}
    }
    _preloadedTrackId = null;
    if (state.positionMs > 4000) {
      await seekToMs(0);
      return;
    }
    final queueSig = state.queue.map((t) => t.id).join(',');
    final isPlaylistAligned = _playlistSource != null && _loadedQueueSignature == queueSig;
    if (state.crossfadeSeconds == 0 && isPlaylistAligned && _activePlayer != null && _activePlayer!.hasPrevious) {
      try {
        final prevIdx = _activePlayer!.previousIndex;
        if (prevIdx != null && prevIdx >= 0 && prevIdx < state.queue.length) {
          final prevTrack = state.queue[prevIdx];
          state = state.copyWith(currentTrack: prevTrack, positionMs: 0);
          _syncForegroundNotification(track: prevTrack, isPlaying: true);
          _savePlaybackState();
        }
        _isTransitioningTrack = true;
        try {
          await _activePlayer!.seekToPrevious();
        } finally {
          _isTransitioningTrack = false;
        }
        return;
      } catch (_) {}
    }
    final idx = state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (idx > 0) {
      await playTrack(state.queue[idx - 1]);
    } else if (state.queue.isNotEmpty) {
      await seekToMs(0);
    }
  }

  void toggleShuffle() {
    PixelHaptics.tick();
    final newShuffle = !state.isShuffle;

    if (newShuffle) {
      if (state.queue.isNotEmpty) {
        _unshuffledQueue ??= List<Track>.from(state.queue);
        final current = state.currentTrack;
        final remaining = state.queue.where((t) => t.id != current.id).toList()..shuffle();
        final newQueue = current.id.isNotEmpty ? [current, ...remaining] : (List<Track>.from(state.queue)..shuffle());
        _loadedQueueSignature = null;
        _preloadedTrackId = null;
        state = state.copyWith(queue: newQueue, isShuffle: true);
      } else {
        state = state.copyWith(isShuffle: true);
      }
    } else {
      if (_unshuffledQueue != null && _unshuffledQueue!.isNotEmpty) {
        final restoredQueue = List<Track>.from(_unshuffledQueue!);
        _unshuffledQueue = null;
        _loadedQueueSignature = null;
        _preloadedTrackId = null;
        state = state.copyWith(queue: restoredQueue, isShuffle: false);
      } else {
        state = state.copyWith(isShuffle: false);
      }
    }

    try {
      _playerA?.setShuffleModeEnabled(newShuffle);
      _playerB?.setShuffleModeEnabled(newShuffle);
    } catch (_) {}
    _syncForegroundNotification();
    _savePlaybackState();
  }

  void cycleRepeatMode() {
    PixelHaptics.tick();
    final newRepeat = (state.repeatMode + 1) % 3;
    state = state.copyWith(repeatMode: newRepeat);
    _preloadedTrackId = null;
    final loopMode = newRepeat == 2
        ? LoopMode.one
        : (newRepeat == 1 ? LoopMode.all : LoopMode.off);
    try {
      _playerA?.setLoopMode(loopMode);
      _playerB?.setLoopMode(loopMode);
    } catch (_) {}
    _syncForegroundNotification();
    _savePlaybackState();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 1: Up Next Reorderable Queue & Queue Operations
  // ───────────────────────────────────────────────────────────────────────────

  void reorderUpNext(int oldIndex, int newIndex) {
    PixelHaptics.lowTick();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (currentIdx == -1) return;
    final upNext = List<Track>.from(state.upNextQueue);
    if (oldIndex < 0 || oldIndex >= upNext.length) return;
    final item = upNext.removeAt(oldIndex);
    final targetIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    upNext.insert(targetIdx.clamp(0, upNext.length), item);

    final newQueue = [
      ...state.queue.sublist(0, currentIdx + 1),
      ...upNext,
    ];
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    state = state.copyWith(queue: newQueue);
  }

  void removeFromQueue(String trackId) {
    PixelHaptics.tick();
    final newQueue = state.queue
        .where((t) => t.id != trackId || t.id == state.currentTrack.id)
        .toList();
    if (_unshuffledQueue != null) {
      _unshuffledQueue = _unshuffledQueue!
          .where((t) => t.id != trackId || t.id == state.currentTrack.id)
          .toList();
    }
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    state = state.copyWith(queue: newQueue);
  }

  void playNext(Track track) {
    PixelHaptics.tick();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    final withoutTrack = state.queue.where((t) => t.id != track.id).toList();
    final insertIdx = currentIdx == -1
        ? 0
        : (currentIdx + 1).clamp(0, withoutTrack.length);
    final newQueue = List<Track>.from(withoutTrack)..insert(insertIdx, track);
    if (_unshuffledQueue != null) {
      _unshuffledQueue = [..._unshuffledQueue!.where((t) => t.id != track.id), track];
    }
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    state = state.copyWith(queue: newQueue);
  }

  void addToQueue(Track track) {
    PixelHaptics.tick();
    final withoutTrack = state.queue.where((t) => t.id != track.id).toList();
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    if (_unshuffledQueue != null) {
      _unshuffledQueue = [..._unshuffledQueue!.where((t) => t.id != track.id), track];
    }
    state = state.copyWith(queue: [...withoutTrack, track]);
  }

  void playNextMultiple(List<Track> tracks) {
    if (tracks.isEmpty) return;
    PixelHaptics.tick();
    final trackIds = tracks.map((t) => t.id).toSet();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    final withoutTracks =
        state.queue.where((t) => !trackIds.contains(t.id)).toList();
    final insertIdx = currentIdx == -1
        ? 0
        : (currentIdx + 1).clamp(0, withoutTracks.length);
    final newQueue = List<Track>.from(withoutTracks)..insertAll(insertIdx, tracks);
    if (_unshuffledQueue != null) {
      _unshuffledQueue = [..._unshuffledQueue!.where((t) => !trackIds.contains(t.id)), ...tracks];
    }
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    state = state.copyWith(queue: newQueue);
  }

  void addToQueueMultiple(List<Track> tracks) {
    if (tracks.isEmpty) return;
    PixelHaptics.tick();
    final trackIds = tracks.map((t) => t.id).toSet();
    final withoutTracks =
        state.queue.where((t) => !trackIds.contains(t.id)).toList();
    _loadedQueueSignature = null;
    _preloadedTrackId = null;
    if (_unshuffledQueue != null) {
      _unshuffledQueue = [..._unshuffledQueue!.where((t) => !trackIds.contains(t.id)), ...tracks];
    }
    state = state.copyWith(queue: [...withoutTracks, ...tracks]);
  }

  void clearUpNext() {
    PixelHaptics.tick();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (currentIdx == -1) return;
    _loadedQueueSignature = null;
    if (_unshuffledQueue != null) {
      _unshuffledQueue = [state.currentTrack];
    }
    state = state.copyWith(queue: [state.currentTrack]);
  }

  void shuffleRemaining() {
    PixelHaptics.medium();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (currentIdx == -1) return;
    final remaining =
        List<Track>.from(state.queue.sublist(currentIdx + 1))..shuffle();
    _loadedQueueSignature = null;
    state = state.copyWith(queue: [
      ...state.queue.sublist(0, currentIdx + 1),
      ...remaining,
    ]);
  }

  Future<void> handleTracksRemoved(List<String> trackIds) async {
    final idSet = trackIds.toSet();
    final newQueue = state.queue.where((t) => !idSet.contains(t.id)).toList();
    if (idSet.contains(state.currentTrack.id)) {
      if (newQueue.isNotEmpty) {
        if (state.isPlaying) {
          try {
            await playTrack(newQueue.first);
          } catch (_) {}
        } else {
          state = state.copyWith(
            currentTrack: newQueue.first,
            queue: newQueue,
            positionMs: 0,
            bufferedPositionMs: 0,
          );
          _savePlaybackState();
        }
      } else {
        _progressTicker?.cancel();
        try {
          await _audioPlayer?.pause();
          _ref.read(powerampDspServiceProvider).stopForegroundPlayback();
        } catch (_) {}
        state = state.copyWith(
          isPlaying: false,
          currentTrack: PlaybackViewState.emptyTrack,
          queue: const [],
          positionMs: 0,
          bufferedPositionMs: 0,
        );
        _syncForegroundNotification(isPlaying: false);
        _savePlaybackState();
      }
    } else {
      state = state.copyWith(queue: newQueue);
      _savePlaybackState();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 1: Smart Autoplay
  // ───────────────────────────────────────────────────────────────────────────

  void toggleAutoplay() {
    PixelHaptics.tick();
    state = state.copyWith(isAutoplay: !state.isAutoplay);
  }

  void _triggerAutoplayNext() {
    if (!state.isAutoplay) return;
    final allTracks = _ref.read(tracksCatalogProvider);
    if (allTracks.isEmpty) return;

    final current = state.currentTrack;
    final sameArtist = allTracks
        .where((t) => t.id != current.id && t.artist == current.artist)
        .toList();
    Track next;
    if (sameArtist.isNotEmpty) {
      sameArtist.shuffle();
      next = sameArtist.first;
    } else {
      final unplayed = allTracks
          .where((t) =>
              t.id != current.id &&
              !state.sessionHistory.any((h) => h.id == t.id))
          .toList();
      if (unplayed.isNotEmpty) {
        unplayed.shuffle();
        next = unplayed.first;
      } else {
        final copy = List<Track>.from(allTracks)..shuffle();
        next = copy.first;
      }
    }
    state = state.copyWith(queue: [...state.queue, next]);
    playTrack(next);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 1: Variable Playback Speed & Pitch Shifter
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> setPlaybackSpeed(double speed) async {
    PixelHaptics.tick();
    state = state.copyWith(playbackSpeed: speed);
    try {
      await _playerA?.setSpeed(speed);
      await _playerB?.setSpeed(speed);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    PixelHaptics.tick();
    state = state.copyWith(pitch: pitch);
    try {
      await _playerA?.setPitch(pitch);
      await _playerB?.setPitch(pitch);
    } catch (_) {}
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 1: M3 Sleep Timer with Gentle 30s Fade-Out
  // ───────────────────────────────────────────────────────────────────────────

  void setSleepTimer(Duration? duration) {
    PixelHaptics.tick();
    _sleepTimer?.cancel();
    if (duration == null) {
      _sleepTimer = null;
      _sleepTimerTarget = null;
      _sleepTimerEndAfterTrack = false;
      state = state.copyWith(clearSleepTimer: true);
      _audioPlayer?.setVolume(1.0);
      return;
    }

    _sleepTimerTarget = DateTime.now().add(duration);
    _sleepTimerEndAfterTrack = false;
    state = state.copyWith(
      sleepTimerDuration: duration,
      sleepTimerRemaining: duration,
    );

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining =
          _sleepTimerTarget?.difference(DateTime.now()) ?? Duration.zero;
      if (remaining.isNegative || remaining.inSeconds <= 0) {
        timer.cancel();
        _sleepTimer = null;
        _sleepTimerTarget = null;
        state = state.copyWith(
          clearSleepTimer: true,
          isPlaying: false,
        );
        _audioPlayer?.pause();
        _audioPlayer?.setVolume(1.0);
        PixelHaptics.railLimitThud();
      } else {
        if (remaining.inSeconds <= 30) {
          final vol = (remaining.inSeconds / 30.0).clamp(0.05, 1.0);
          _audioPlayer?.setVolume(vol);
        } else {
          _audioPlayer?.setVolume(1.0);
        }
        state = state.copyWith(sleepTimerRemaining: remaining);
      }
    });
  }

  void setSleepTimerAfterCurrentTrack() {
    PixelHaptics.tick();
    _sleepTimer?.cancel();
    _sleepTimerEndAfterTrack = true;
    final remainingMs =
        (state.currentTrack.durationMs - state.positionMs).clamp(0, 86400000);
    state = state.copyWith(
      sleepTimerDuration: Duration(milliseconds: remainingMs),
      sleepTimerRemaining: Duration(milliseconds: remainingMs),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 1: A-B Loop Section Repeater
  // ───────────────────────────────────────────────────────────────────────────

  void setLoopPointA([int? customPosMs]) {
    PixelHaptics.tick();
    final pos = customPosMs ?? state.positionMs;
    final isActive =
        state.loopPointB != null && pos < state.loopPointB!;
    state = state.copyWith(
      loopPointA: pos,
      isLoopActive: isActive,
    );
  }

  void setLoopPointB([int? customPosMs]) {
    PixelHaptics.tick();
    final pos = customPosMs ?? state.positionMs;
    final isActive =
        state.loopPointA != null && pos > state.loopPointA!;
    state = state.copyWith(
      loopPointB: pos,
      isLoopActive: isActive,
    );
  }

  void clearLoop() {
    PixelHaptics.tick();
    state = state.copyWith(clearLoop: true);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Phase 1: Crossfade Duration Setting
  // ───────────────────────────────────────────────────────────────────────────

  void setCrossfadeSeconds(int seconds) {
    PixelHaptics.tick();
    final clamped = seconds.clamp(0, 12);
    if (clamped == 0) {
      if (_isCrossfading) {
        _crossfadeTimer?.cancel();
        _crossfadeTimer = null;
        _isCrossfading = false;
        try {
          _activePlayer?.setVolume(1.0);
          _inactivePlayer?.stop();
          _inactivePlayer?.setVolume(0.0);
        } catch (_) {}
      }
    } else {
      _playlistSource = null;
      _loadedQueueSignature = null;
    }
    _preloadedTrackId = null;
    state = state.copyWith(crossfadeSeconds: clamped);
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('playback_crossfade_seconds', clamped);
        await prefs.setInt('playback_crossfade_duration_ms', clamped * 1000);
      } catch (_) {}
    }());
    _ref.read(audioQualityProvider.notifier).setCrossfadeDuration(clamped * 1000);
  }

  /// Reconciles FreeBeat's reactive state with the underlying physical ExoPlayer instances.
  /// Called on AppLifecycleState.resumed and whenever the UI returns to foreground.
  Future<void> resyncWithActivePlayer() async {
    if (!mounted) return;
    try {
      // 1. Resolve any interrupted or stalled crossfades
      if (_isCrossfading) {
        final outgoing = _inactivePlayer;
        final incoming = _activePlayer;
        if (outgoing != null && incoming != null) {
          await _completeCrossfade(outgoing, incoming);
        }
      }

      // 2. Detect which physical player is actually active/playing
      final aPlaying = _playerA?.playing ?? false;
      final bPlaying = _playerB?.playing ?? false;
      if (aPlaying && !bPlaying) {
        _isPlayerAActive = true;
      } else if (bPlaying && !aPlaying) {
        _isPlayerAActive = false;
      }

      // Ensure any rogue secondary player is silenced
      if (_inactivePlayer != null && _inactivePlayer!.playing && !_isCrossfading) {
        try {
          await _inactivePlayer!.pause();
          await _inactivePlayer!.stop();
          await _inactivePlayer!.setVolume(0.0);
        } catch (_) {}
      }

      final active = _activePlayer;
      if (active == null) return;

      final isActuallyPlaying = active.playing;
      final currentIdx = active.currentIndex;
      final actualPos = active.position.inMilliseconds;

      Track effectiveTrack = state.currentTrack;
      if (isActuallyPlaying) {
        if (_playlistSource != null &&
            active.audioSource == _playlistSource &&
            currentIdx != null &&
            currentIdx >= 0 &&
            currentIdx < state.queue.length) {
          final candidate = state.queue[currentIdx];
          if (candidate.id.isNotEmpty) {
            effectiveTrack = candidate;
          }
        } else if (active.sequenceState?.currentSource?.tag is Track) {
          final tagTrack = active.sequenceState!.currentSource!.tag as Track;
          if (tagTrack.id.isNotEmpty &&
              (state.queue.isEmpty || state.queue.any((t) => t.id == tagTrack.id))) {
            effectiveTrack = tagTrack;
          }
        }
      }

      final posToSet = (actualPos > 0) ? actualPos : state.positionMs;

      state = state.copyWith(
        currentTrack: effectiveTrack,
        isPlaying: isActuallyPlaying,
        positionMs: posToSet,
      );

      _syncForegroundNotification(track: effectiveTrack, isPlaying: isActuallyPlaying);
      _savePlaybackState();
      _savePlaybackPosition();
    } catch (e) {
      debugPrint('Error resyncing with active player: $e');
    }
  }

  @override
  void dispose() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _progressTicker?.cancel();
    _sleepTimer?.cancel();
    try {
      _playerA?.dispose();
      _playerB?.dispose();
    } catch (_) {}
    try {
      _ref.read(powerampDspServiceProvider).stopForegroundPlayback();
    } catch (_) {}
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackViewState>((ref) {
  return PlaybackNotifier(ref, const []);
});

// ─────────────────────────────────────────────────────────────────────────────
// Real-Time Track Import Progress State & Provider
// ─────────────────────────────────────────────────────────────────────────────

class PendingImportTrack {
  const PendingImportTrack({
    required this.id,
    required this.filename,
    required this.title,
    this.artist = 'Importing metadata...',
    this.progress = 0.0,
    this.isCompleted = false,
  });

  final String id;
  final String filename;
  final String title;
  final String artist;
  final double progress;
  final bool isCompleted;

  PendingImportTrack copyWith({
    String? id,
    String? filename,
    String? title,
    String? artist,
    double? progress,
    bool? isCompleted,
  }) {
    return PendingImportTrack(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      progress: progress ?? this.progress,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

class ImportProgressState {
  const ImportProgressState({
    this.isImporting = false,
    this.current = 0,
    this.total = 0,
    this.currentItemName = '',
    this.pendingTracks = const [],
    this.batchIndex = 0,
    this.batchSize = 10,
  });

  final bool isImporting;
  final int current;
  final int total;
  final String currentItemName;
  final List<PendingImportTrack> pendingTracks;
  final int batchIndex;
  final int batchSize;

  double get progressFraction =>
      total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
  String get progressPercentage => '${(progressFraction * 100).round()}%';
}

class ImportProgressNotifier extends StateNotifier<ImportProgressState> {
  ImportProgressNotifier() : super(const ImportProgressState());

  void start({required int total}) {
    state = ImportProgressState(
      isImporting: true,
      current: 0,
      total: total,
      pendingTracks: state.pendingTracks,
      batchIndex: 0,
      batchSize: 10,
    );
  }

  void startBatch({
    required List<String> batchFilenames,
    required int batchStartIndex,
    required int totalFiles,
  }) {
    final pending = batchFilenames.asMap().entries.map((entry) {
      final idx = entry.key;
      final fn = entry.value;
      final cleanTitle = fn.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      return PendingImportTrack(
        id: 'pending_${batchStartIndex + idx}_$fn',
        filename: fn,
        title: cleanTitle,
        artist: 'Queued for import...',
        progress: 0.0,
        isCompleted: false,
      );
    }).toList();

    state = ImportProgressState(
      isImporting: true,
      current: batchStartIndex,
      total: totalFiles,
      pendingTracks: pending,
      batchIndex: batchStartIndex,
      batchSize: batchFilenames.length,
    );
  }

  void startWithFiles(List<String> filenames) {
    final batch = filenames.take(10).toList();
    startBatch(
      batchFilenames: batch,
      batchStartIndex: 0,
      totalFiles: filenames.length,
    );
  }

  void update({
    required int current,
    required int total,
    String name = '',
    Track? track,
  }) {
    final updatedPending = List<PendingImportTrack>.from(state.pendingTracks);
    final localIndex = current - 1 - state.batchIndex;

    if (updatedPending.isNotEmpty) {
      for (int i = 0; i < updatedPending.length; i++) {
        final item = updatedPending[i];
        if (i < localIndex) {
          if (!item.isCompleted) {
            updatedPending[i] = item.copyWith(
              progress: 1.0,
              isCompleted: true,
            );
          }
        } else if (i == localIndex) {
          updatedPending[i] = item.copyWith(
            title: track?.title.isNotEmpty == true ? track!.title : item.title,
            artist:
                track?.artist.isNotEmpty == true ? track!.artist : 'Imported',
            progress: 1.0,
            isCompleted: true,
          );
        } else if (i == localIndex + 1) {
          updatedPending[i] = item.copyWith(
            artist: 'Importing & analyzing audio...',
            progress: 0.5,
          );
        }
      }
    }

    state = ImportProgressState(
      isImporting: true,
      current: current,
      total: total,
      currentItemName: name,
      pendingTracks: updatedPending,
      batchIndex: state.batchIndex,
      batchSize: state.batchSize,
    );
  }

  void complete() {
    final completedPending = state.pendingTracks
        .map((p) => p.copyWith(
              progress: 1.0,
              isCompleted: true,
            ))
        .toList();

    state = ImportProgressState(
      isImporting: false,
      current: state.total,
      total: state.total,
      pendingTracks: completedPending,
    );

    // Keep visible briefly for visual gratification, then clear
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!state.isImporting) {
        state = const ImportProgressState(isImporting: false);
      }
    });
  }

  void clearPending() {
    state = const ImportProgressState(isImporting: false);
  }
}

final importProgressProvider =
    StateNotifierProvider<ImportProgressNotifier, ImportProgressState>(
  (ref) => ImportProgressNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2: Playlist Providers & Smart Playlist Engine
// ─────────────────────────────────────────────────────────────────────────────

class PlaylistsNotifier extends StateNotifier<List<Playlist>> {
  PlaylistsNotifier(this._db) : super([]) {
    _loadPlaylists();
  }

  final LibraryDatabase? _db;
  Timer? _reorderDebounceTimer;
  Playlist? _pendingReorderedPlaylist;

  @override
  void dispose() {
    _reorderDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _flushPendingReorder() async {
    _reorderDebounceTimer?.cancel();
    _reorderDebounceTimer = null;
    final toSave = _pendingReorderedPlaylist;
    _pendingReorderedPlaylist = null;
    if (toSave != null && _db != null) {
      await _db.upsertPlaylist(toSave);
    }
  }

  Future<void> _loadPlaylists() async {
    if (_db != null) {
      final loaded = await _db.loadPlaylists();
      state = loaded;
    }
  }

  Future<Playlist> createPlaylist(
    String title, {
    String description = '',
    List<String> initialTrackIds = const [],
    String? syncSourceUrl,
    DateTime? lastSyncedAt,
    String? customArtworkUrl,
  }) async {
    await PixelHaptics.hifiConfirm();
    final now = DateTime.now();
    // Derives an expressive seed from the title string hash
    final colorSeed = 0xFF000000 | (title.hashCode & 0x00FFFFFF);
    final newPlaylist = Playlist(
      id: 'playlist_${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}',
      title: title.trim().isEmpty ? 'Untitled Playlist' : title.trim(),
      description: description.trim(),
      trackIds: List.from(initialTrackIds),
      createdAt: now,
      updatedAt: now,
      colorSeedValue: colorSeed,
      syncSourceUrl: syncSourceUrl,
      lastSyncedAt: lastSyncedAt,
      customArtworkUrl: customArtworkUrl,
    );
    state = [newPlaylist, ...state];
    if (_db != null) {
      await _db.upsertPlaylist(newPlaylist);
    }
    return newPlaylist;
  }

  Future<void> updatePlaylistArtwork(String playlistId, String artworkUrl) async {
    if (artworkUrl.isEmpty) return;
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        if (p.customArtworkUrl == null || p.customArtworkUrl!.isEmpty) {
          final updated = p.copyWith(customArtworkUrl: artworkUrl);
          targetUpdated = updated;
          return updated;
        }
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
  }

  Future<void> updatePlaylistSyncSource(
    String playlistId,
    String? syncSourceUrl,
  ) async {
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          syncSourceUrl: syncSourceUrl,
          clearSyncSourceUrl: syncSourceUrl == null,
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
  }

  Future<void> updatePlaylistLastSynced(
    String playlistId,
    DateTime syncedAt,
  ) async {
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          lastSyncedAt: syncedAt,
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
  }

  Future<void> renamePlaylist(
    String playlistId,
    String newTitle, {
    String? description,
    String? syncSourceUrl,
  }) async {
    await PixelHaptics.tick();
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          title: newTitle.trim().isEmpty ? p.title : newTitle.trim(),
          description: description ?? p.description,
          syncSourceUrl: syncSourceUrl ?? p.syncSourceUrl,
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _flushPendingReorder();
    await PixelHaptics.tick();
    state = state.where((p) => p.id != playlistId).toList();
    if (_db != null) {
      await _db.deletePlaylist(playlistId);
    }
  }

  Future<bool> toggleTrackInPlaylist(String playlistId, String trackId) async {
    final playlist = state.firstWhere(
      (p) => p.id == playlistId,
      orElse: () => throw StateError('Playlist not found'),
    );
    final isPresent = playlist.trackIds.contains(trackId);
    if (isPresent) {
      await removeTrackFromPlaylist(playlistId, trackId);
      return false;
    } else {
      await addTrackToPlaylist(playlistId, trackId);
      return true;
    }
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    if (trackIds.isEmpty) return;
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final newIds = trackIds.where((id) => !p.trackIds.contains(id)).toList();
        if (newIds.isEmpty) return p;
        final updated = p.copyWith(
          trackIds: [...p.trackIds, ...newIds],
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
    unawaited(PixelHaptics.tick());
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        if (!p.trackIds.contains(trackId)) {
          final updated = p.copyWith(
            trackIds: [...p.trackIds, trackId],
            updatedAt: DateTime.now(),
          );
          targetUpdated = updated;
          return updated;
        }
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
    unawaited(PixelHaptics.tick());
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    await PixelHaptics.tick();
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          trackIds: p.trackIds.where((id) => id != trackId).toList(),
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
  }

  Future<void> removeTracksFromPlaylist(
    String playlistId,
    List<String> trackIds,
  ) async {
    if (trackIds.isEmpty) return;
    await PixelHaptics.tick();
    final removeSet = trackIds.toSet();
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          trackIds: p.trackIds.where((id) => !removeSet.contains(id)).toList(),
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      await _db.upsertPlaylist(targetUpdated!);
    }
  }

  Future<void> reorderTracks(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await PixelHaptics.tick();
    Playlist? targetUpdated;
    state = state.map((p) {
      if (p.id == playlistId) {
        final list = List<String>.from(p.trackIds);
        if (oldIndex < newIndex) {
          newIndex -= 1;
        }
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        final updated = p.copyWith(
          trackIds: list,
          updatedAt: DateTime.now(),
        );
        targetUpdated = updated;
        return updated;
      }
      return p;
    }).toList();
    if (targetUpdated != null && _db != null) {
      _pendingReorderedPlaylist = targetUpdated;
      _reorderDebounceTimer?.cancel();
      _reorderDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
        await _flushPendingReorder();
      });
    }
  }

  Future<void> removeTracksFromAllPlaylists(List<String> trackIds) async {
    if (trackIds.isEmpty) return;
    await _flushPendingReorder();
    final idSet = trackIds.toSet();
    final updatedList = <Playlist>[];
    state = state.map((p) {
      if (p.trackIds.any(idSet.contains)) {
        final updated = p.copyWith(
          trackIds: p.trackIds.where((id) => !idSet.contains(id)).toList(),
          updatedAt: DateTime.now(),
        );
        updatedList.add(updated);
        return updated;
      }
      return p;
    }).toList();
    if (_db != null) {
      for (final updated in updatedList) {
        await _db.upsertPlaylist(updated);
      }
    }
  }

  String exportPlaylistM3u8(Playlist playlist, List<Track> allTracks) {
    final trackMap = {for (final t in allTracks) t.id: t};
    final buffer = StringBuffer();
    buffer.writeln('#EXTM3U');
    buffer.writeln('#PLAYLIST:${playlist.title}');
    for (final id in playlist.trackIds) {
      final track = trackMap[id];
      if (track != null) {
        final seconds = (track.durationMs / 1000).round();
        buffer.writeln('#EXTINF:$seconds,${track.artist} - ${track.title}');
        buffer.writeln(track.streamUrl);
      }
    }
    return buffer.toString();
  }
}

final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, List<Playlist>>((ref) {
  final db = ref.watch(libraryDatabaseProvider);
  return PlaylistsNotifier(db);
});

/// Smart dynamic playlists calculated on-the-fly from library track metadata
final smartPlaylistsProvider = Provider<List<Playlist>>((ref) {
  final allTracks = ref.watch(tracksCatalogProvider);
  final customPlaylists = ref.watch(playlistsProvider);

  final hiresTracks =
      allTracks.where((t) => t.isHiRes).map((t) => t.id).toList();
  final offlineTracks =
      allTracks.where((t) => t.isPinnedOffline).map((t) => t.id).toList();
  final favTracks =
      allTracks.where((t) => t.isFavorite).map((t) => t.id).toList();

  final sortedByPlays = List<Track>.from(allTracks)
    ..sort((a, b) => b.playCount.compareTo(a.playCount));
  final heavyRotationIds = sortedByPlays.take(50).map((t) => t.id).toList();

  final recentlyAddedIds =
      allTracks.reversed.take(50).map((t) => t.id).toList();

  // Mood & Energy Auto-Clustering
  final energyKeywords = RegExp(
    r'\b(energy|workout|rock|dance|beat|fast|heavy|metal|power|run|remix|electro|synth|fire|party|club|rave|drop)\b',
    caseSensitive: false,
  );
  final chillKeywords = RegExp(
    r'\b(chill|ambient|lofi|lo-fi|slow|relax|sleep|calm|quiet|acoustic|piano|cloud|breeze|sea|rain|soft|dream|haze)\b',
    caseSensitive: false,
  );
  final focusKeywords = RegExp(
    r'\b(focus|study|instrumental|soundtrack|ost|score|theme|wave|synthwave|space|orbit|deep|ambient|work)\b',
    caseSensitive: false,
  );

  final energyTracks = allTracks.where((t) {
    final text = '${t.title} ${t.artist} ${t.album}';
    return energyKeywords.hasMatch(text) || (t.isHiRes && t.playCount > 5);
  }).map((t) => t.id).toList();

  final chillTracks = allTracks.where((t) {
    final text = '${t.title} ${t.artist} ${t.album}';
    return chillKeywords.hasMatch(text) || t.durationMs > 270000;
  }).map((t) => t.id).toList();

  final focusTracks = allTracks.where((t) {
    final text = '${t.title} ${t.artist} ${t.album}';
    return focusKeywords.hasMatch(text) ||
        t.title.toLowerCase().contains('instrumental');
  }).map((t) => t.id).toList();

  final smarts = [
    Playlist(
      id: 'smart_hires',
      title: 'Hi-Res Master Vault',
      description: '24-Bit / 96kHz+ studio master resolution',
      trackIds: hiresTracks,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'hires',
      colorSeedValue: 0xFF006782,
    ),
    Playlist(
      id: 'smart_offline',
      title: 'Offline Vault',
      description: 'Zero-data offline cached & stored music',
      trackIds: offlineTracks,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'offline',
      colorSeedValue: 0xFF006E1C,
    ),
    Playlist(
      id: 'smart_favorites',
      title: 'Favorite Jams',
      description: 'Tracks marked with heart',
      trackIds: favTracks,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'favorites',
      colorSeedValue: 0xFFB3261E,
    ),
    Playlist(
      id: 'smart_heavy_rotation',
      title: 'Heavy Rotation',
      description: 'Your top 50 most frequently played tracks',
      trackIds: heavyRotationIds,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'heavy_rotation',
      colorSeedValue: 0xFF984061,
    ),
    Playlist(
      id: 'smart_recently_added',
      title: 'Recently Added',
      description: 'The latest tracks ingested from clouds & storage',
      trackIds: recentlyAddedIds,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'recently_added',
      colorSeedValue: 0xFF7D5260,
    ),
    Playlist(
      id: 'smart_energy',
      title: 'High Energy & Workout',
      description: 'Upbeat tempos, hard-hitting transients & dynamic rhythm',
      trackIds: energyTracks,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'energy',
      colorSeedValue: 0xFFE25507,
    ),
    Playlist(
      id: 'smart_chill',
      title: 'Chill & Ambient Vibe',
      description: 'Mellow acoustic warmth, relaxed tempos & soothing atmosphere',
      trackIds: chillTracks,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'chill',
      colorSeedValue: 0xFF006874,
    ),
    Playlist(
      id: 'smart_focus',
      title: 'Late Night & Focus',
      description: 'Deep synthwave, soundtracks & uninterrupted instrumental flow',
      trackIds: focusTracks,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime.now(),
      isSmart: true,
      smartType: 'focus',
      colorSeedValue: 0xFF5B45BA,
    ),
  ];

  return [...customPlaylists, ...smarts];
});

/// Grouping of detected duplicate tracks (same title + artist case-insensitive)
final duplicateTracksProvider = Provider<Map<String, List<Track>>>((ref) {
  final allTracks = ref.watch(tracksCatalogProvider);
  final map = <String, List<Track>>{};
  for (final t in allTracks) {
    final key =
        '${t.title.trim().toLowerCase()}__${t.artist.trim().toLowerCase()}';
    map.putIfAbsent(key, () => []).add(t);
  }
  // Retain only groups with more than 1 track
  map.removeWhere((key, list) => list.length <= 1);
  return map;
});

/// Memoized list of distinct unified artists across all indexed library tracks
final allArtistsProvider = Provider<List<String>>((ref) {
  final available = ref.watch(availableArtistsProvider);
  return available.map((a) => a.name).toList();
});


