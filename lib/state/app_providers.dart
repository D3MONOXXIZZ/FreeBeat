import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../core/models/audio_quality_settings.dart';
import '../core/models/cloud_account.dart';
import '../core/models/playlist.dart';
import '../core/models/poweramp_dsp_state.dart';
import '../core/models/track.dart';
import '../core/storage/library_database.dart';
import '../core/storage/secure_credential_store.dart';
import '../providers/implementations/network_and_saf_connectors.dart';
import '../services/audio/cloud_audio_cache_service.dart';
import '../services/audio/cloud_stream_proxy.dart';
import '../services/audio/poweramp_dsp_service.dart';
import '../services/auth/native_cloud_auth_service.dart';
import '../services/discovery/local_media_server_discovery_service.dart';
import '../services/haptics/pixel_haptics.dart';
import '../services/metadata/artwork_and_lyrics_service.dart';
import '../services/metadata/range_tag_parser.dart';

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

final cloudAudioCacheServiceProvider =
    ChangeNotifierProvider<CloudAudioCacheService>((ref) {
  return CloudAudioCacheService(
    credentialStore: ref.watch(credentialStoreProvider),
  );
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
// Cloud Accounts & Unified Track Catalog State
// ─────────────────────────────────────────────────────────────────────────────

class CloudAccountsNotifier extends StateNotifier<List<CloudAccount>> {
  CloudAccountsNotifier(this._db, this._credStore) : super(const []) {
    _loadFromDb();
  }

  final LibraryDatabase _db;
  final SecureCredentialStore _credStore;

  Future<void> _loadFromDb() async {
    final loaded = await _db.loadAccounts();
    if (loaded.isNotEmpty) {
      state = loaded;
    }
  }

  void loadSampleDemoAccounts() {
    state = DemoCloudConnector.defaultShowcaseAccounts();
  }

  Future<void> addAccount(
    CloudAccount account,
    Map<String, String> secrets,
  ) async {
    await _credStore.saveSecrets(account.id, secrets);
    await _db.upsertAccount(account);
    state = [...state.where((a) => a.id != account.id), account];
    await PixelHaptics.hifiConfirm();
  }

  Future<void> removeAccount(String accountId) async {
    await _credStore.deleteSecrets(accountId);
    await _db.removeAccount(accountId);
    state = state.where((a) => a.id != accountId).toList();
    await PixelHaptics.tick();
  }
}

final cloudAccountsProvider =
    StateNotifierProvider<CloudAccountsNotifier, List<CloudAccount>>((ref) {
  return CloudAccountsNotifier(
    ref.watch(libraryDatabaseProvider),
    ref.watch(credentialStoreProvider),
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

  Future<void> _loadFromDb() async {
    if (_db == null) return;
    final loaded = await _db.loadTracks();
    if (loaded.isNotEmpty) {
      final sanitized = <Track>[];
      for (final t in loaded) {
        var clean = t;
        if (clean.dominantColorValue == 0xFF3DDC84 ||
            clean.dominantColorValue == 0xFF1DB954) {
          clean = clean.copyWith(dominantColorValue: 0xFF1E293B);
        }
        if (clean.artist == 'Cloud Artist' || clean.album == 'Cloud Library') {
          final file = File(clean.streamUrl);
          if (file.existsSync()) {
            try {
              final parsed = await RangeTagParser.parseLocalFile(file);
              if (parsed.artist != null && parsed.artist!.isNotEmpty) {
                clean = clean.copyWith(
                  artist: parsed.artist,
                  album: parsed.album ?? clean.album,
                  title: (parsed.title != null && parsed.title!.isNotEmpty)
                      ? parsed.title
                      : clean.title,
                );
                await _db.upsertTracks([clean]);
              }
            } catch (_) {}
          }
        }
        sanitized.add(clean);
      }

      state = sanitized;
      if (_ref != null) {
        final playback = _ref.read(playbackProvider);
        if (playback.queue.isEmpty) {
          _ref.read(playbackProvider.notifier).setQueue(sanitized);
        }
        _enrichMissingArtwork(sanitized);
      }
    }
  }

  void loadSampleDemoTracks() {
    state = DemoCloudConnector.defaultShowcaseTracks();
  }

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

  void _enrichMissingArtwork(List<Track> tracks) {
    if (_ref == null) return;
    unawaited(() async {
      final artworkSvc = _ref.read(artworkAndLyricsServiceProvider);
      for (final t in tracks) {
        final needsPalette = t.dominantColorValue == 0xFF1E293B ||
            t.dominantColorValue == 0xFF3DDC84 ||
            t.dominantColorValue == 0xFF1DB954;
        final needsMetadata = t.artist == 'Cloud Artist' ||
            t.artist == 'Unknown Artist' ||
            t.artist.isEmpty ||
            t.album == 'Cloud Library';
        if (t.artworkUrl == null ||
            t.artworkUrl!.isEmpty ||
            needsPalette ||
            needsMetadata) {
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
    if (newTracks.isEmpty) return;
    if (_db != null) {
      await _db.upsertTracks(newTracks);
    }
    final map = {for (final t in state) t.id: t};
    for (final t in newTracks) {
      map[t.id] = t;
    }
    state = map.values.toList();
    if (_ref != null) {
      final playback = _ref.read(playbackProvider);
      if (playback.queue.isEmpty || playback.currentTrack.id.isEmpty) {
        _ref.read(playbackProvider.notifier).setQueue(state);
      }
      _enrichMissingArtwork(newTracks);
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
      final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
      if (target!.isPinnedOffline) {
        unawaited(cacheSvc.cacheTrack(target!, onComplete: (cachedTrack) {
          updateTrack(cachedTrack);
        }));
      } else {
        await cacheSvc.removeCachedTrack(target!);
      }
    }
  }

  Future<void> removeTracks(List<String> trackIds) async {
    await PixelHaptics.tick();
    state = state.where((t) => !trackIds.contains(t.id)).toList();
    if (_db != null) {
      await _db.deleteTracks(trackIds);
    }
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

/// Dynamic list of artists discovered in the user's catalog
final availableArtistsProvider = Provider<List<ArtistInfo>>((ref) {
  final tracks = ref.watch(tracksCatalogProvider);
  final map = <String, List<Track>>{};
  for (final t in tracks) {
    final artist = t.artist.trim().isEmpty ? 'Unknown Artist' : t.artist.trim();
    map.putIfAbsent(artist, () => []).add(t);
  }
  final list = map.entries.map((e) {
    return ArtistInfo(
      name: e.key,
      trackCount: e.value.length,
      representativeTrack: e.value.first,
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
    return AlbumInfo(
      title: e.key,
      artist: e.value.first.artist,
      trackCount: e.value.length,
      representativeTrack: e.value.first,
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
            : track.providerType.id == cloudFilter;
    if (!matchesCloud) return false;

    // 2. Artist filter
    if (artistFilter != null && artistFilter.isNotEmpty) {
      if (track.artist.toLowerCase() != artistFilter.toLowerCase()) return false;
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
  AudioQualityNotifier() : super(const AudioQualityConfig());

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
    state = state.copyWith(crossfadeDurationMs: ms.clamp(0, 12000));
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
  PowerampDspNotifier(this._dspService) : super(PowerampDspState.initial()) {
    _dspService.applyDspState(state);
  }

  final PowerampDspService _dspService;
  final List<DspPreset> _customPresets = [];

  List<DspPreset> get allPresets => [...kBuiltInDspPresets, ..._customPresets];

  void _syncToHardware() {
    _dspService.applyDspState(state);
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
    _syncToHardware();
  }

  void setTempo(double tempo) {
    state = state.copyWith(tempo: tempo);
    _syncToHardware();
  }

  void setPitchSemitones(double semitones) {
    state = state.copyWith(pitchSemitones: semitones);
    _syncToHardware();
  }

  void setReverbPreset(ReverbPresetType preset) {
    PixelHaptics.tick();
    state = state.copyWith(
      reverbPreset: preset,
      reverbMix: preset == ReverbPresetType.none ? 0.0 : 0.35,
    );
    _syncToHardware();
  }

  void applyPreset(DspPreset preset) {
    PixelHaptics.hifiConfirm();
    final updatedBands = List<EqBandConfig>.generate(
      10,
      (i) => state.bands[i].copyWith(
        frequencyHz: kPoweramp10BandFrequencies[i],
        gainDb: i < preset.bandGainsDb.length ? preset.bandGainsDb[i] : 0.0,
        qFactor: 1.41,
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
    final match = allPresets.firstWhere(
      (p) => p.id == id,
      orElse: () => allPresets.firstWhere(
        (p) => p.id.contains(id) || id.contains(p.id),
        orElse: () => kBuiltInDspPresets.first,
      ),
    );
    applyPreset(match);
  }

  void resetFlat() {
    applyPreset(kBuiltInDspPresets.first);
  }

  void saveCustomPreset(String name) {
    final custom = DspPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      category: 'User Custom',
      preampDb: state.preampDb,
      bandGainsDb: state.bands.map((b) => b.gainDb).toList(),
      bassTone: state.bassGain,
      trebleTone: state.trebleGain,
      stereoExpansion: state.stereoExpansion,
      isCustom: true,
    );
    _customPresets.add(custom);
    state = state.copyWith(activePresetId: custom.id);
    PixelHaptics.hifiConfirm();
  }
}

final powerampDspProvider =
    StateNotifierProvider<PowerampDspNotifier, PowerampDspState>((ref) {
  return PowerampDspNotifier(ref.watch(powerampDspServiceProvider));
});

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
    int idx = 0;
    for (int i = 0; i < lyrics.length; i++) {
      if (positionMs >= lyrics[i].timestampMs) {
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
  }

  final Ref _ref;
  AudioPlayer? _audioPlayer;
  Timer? _progressTicker;
  Timer? _sleepTimer;
  DateTime? _sleepTimerTarget;
  bool _sleepTimerEndAfterTrack = false;
  bool _isInitializingPlayer = false;

  Future<void> _initAudioPlayer() async {
    if (_audioPlayer != null || _isInitializingPlayer) return;
    _isInitializingPlayer = true;
    try {
      final proxy = _ref.read(cloudStreamProxyProvider);
      await proxy.start();

      // Configure system AudioSession for USAGE_MEDIA & CONTENT_TYPE_MUSIC to guarantee speaker output
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      } catch (e) {
        debugPrint('AudioSession configuration notice: $e');
      }

      final player = AudioPlayer();
      await player.setVolume(1.0);

      player.androidAudioSessionIdStream.listen((sessionId) {
        if (sessionId != null && sessionId > 0) {
          final dspSvc = _ref.read(powerampDspServiceProvider);
          dspSvc.attachAudioSession(sessionId);
          dspSvc.applyDspState(_ref.read(powerampDspProvider));
        }
      });

      player.playerStateStream.listen((playerState) {
        if (!mounted) return;
        final playing = playerState.playing;
        final proc = playerState.processingState;
        if (proc == ProcessingState.completed) {
          skipNext();
        } else if (state.isPlaying != playing) {
          state = state.copyWith(isPlaying: playing);
        }
      });

      int lastEmittedPosMs = -1000;
      player.positionStream.listen((pos) {
        if (mounted && state.isPlaying) {
          final posMs = pos.inMilliseconds;
          if (state.isLoopActive &&
              state.loopPointA != null &&
              state.loopPointB != null) {
            if (posMs >= state.loopPointB!) {
              seekToMs(state.loopPointA!);
              return;
            }
          }
          if ((posMs - lastEmittedPosMs).abs() >= 150 || posMs == 0) {
            lastEmittedPosMs = posMs;
            state = state.copyWith(positionMs: posMs);
          }
        }
      });

      player.bufferedPositionStream.listen((buf) {
        if (mounted) {
          state = state.copyWith(bufferedPositionMs: buf.inMilliseconds);
        }
      });

      _audioPlayer = player;
    } catch (_) {
      // Headless widget test environment fallback uses smooth internal ticker
      _audioPlayer = null;
    } finally {
      _isInitializingPlayer = false;
    }
  }

  Future<void> _ensureAudioPlayerInitialized() async {
    if (_audioPlayer == null) {
      await _initAudioPlayer();
    }
  }

  void _startTicker() {
    _progressTicker?.cancel();
    _progressTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !state.isPlaying) return;
      if (_audioPlayer != null) return;
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

  Future<void> togglePlayPause() async {
    await PixelHaptics.playPauseToggle();
    final nextPlaying = !state.isPlaying;
    state = state.copyWith(isPlaying: nextPlaying);

    if (nextPlaying) {
      _startTicker();
      await _ensureAudioPlayerInitialized();
      try {
        final proxy = _ref.read(cloudStreamProxyProvider);
        final quality = _ref.read(audioQualityProvider).effectiveStreamingTier;
        proxy.updateCatalog(
          tracks: _ref.read(tracksCatalogProvider),
          accounts: _ref.read(cloudAccountsProvider),
          activeTier: quality,
        );
        if (_audioPlayer != null) {
          await _audioPlayer!.setVolume(1.0);
          if (_audioPlayer!.audioSource == null) {
            await _loadAndPlayTrack(state.currentTrack);
          } else {
            await _audioPlayer!.play();
          }
        }
      } catch (e) {
        debugPrint('Toggle play error: $e');
      }
    } else {
      _progressTicker?.cancel();
      try {
        await _audioPlayer?.pause();
      } catch (_) {}
    }
  }

  Future<void> _loadAndPlayTrack(Track track) async {
    if (_audioPlayer == null || track.id.isEmpty) return;
    try {
      final cacheSvc = _ref.read(cloudAudioCacheServiceProvider);
      final cachedPath = await cacheSvc.getCachedFilePath(track);
      final effectiveSource = cachedPath ?? track.streamUrl;

      // Always guarantee 100% full hardware output volume
      await _audioPlayer!.setVolume(1.0);

      if (state.playbackSpeed != 1.0) {
        try {
          await _audioPlayer!.setSpeed(state.playbackSpeed);
        } catch (_) {}
      }
      if (state.pitch != 1.0) {
        try {
          await _audioPlayer!.setPitch(state.pitch);
        } catch (_) {}
      }

      if (cachedPath != null && File(cachedPath).existsSync()) {
        await _audioPlayer!.setFilePath(cachedPath);
        await _audioPlayer!.setVolume(1.0);
        await _audioPlayer!.play();
        return;
      }

      if (effectiveSource.startsWith('http://') ||
          effectiveSource.startsWith('https://')) {
        Map<String, String>? headers;
        if (track.providerType == CloudProviderType.googleDrive) {
          final secrets = await _ref
              .read(credentialStoreProvider)
              .readSecrets(track.accountId);
          final token = secrets['accessToken'] ?? '';
          if (token.isNotEmpty) {
            headers = {'Authorization': 'Bearer $token'};
          }
        }

        await _audioPlayer!.setAudioSource(
          AudioSource.uri(Uri.parse(effectiveSource), headers: headers),
        );
        await _audioPlayer!.setVolume(1.0);
        await _audioPlayer!.play();

        // Stream directly while caching in background
        unawaited(cacheSvc.cacheTrack(track, onComplete: (cachedTrack) {
          _ref.read(tracksCatalogProvider.notifier).updateTrack(cachedTrack);
        }));
      } else if (effectiveSource.startsWith('content://')) {
        await _audioPlayer!.setAudioSource(
          AudioSource.uri(Uri.parse(effectiveSource)),
        );
        await _audioPlayer!.setVolume(1.0);
        await _audioPlayer!.play();
      } else if (effectiveSource.startsWith('file://')) {
        await _audioPlayer!.setAudioSource(
          AudioSource.uri(Uri.parse(effectiveSource)),
        );
        await _audioPlayer!.setVolume(1.0);
        await _audioPlayer!.play();
      } else {
        if (File(effectiveSource).existsSync()) {
          await _audioPlayer!.setFilePath(effectiveSource);
        } else {
          try {
            await _audioPlayer!.setFilePath(effectiveSource);
          } catch (_) {
            await _audioPlayer!.setAudioSource(
              AudioSource.uri(Uri.file(effectiveSource)),
            );
          }
        }
        await _audioPlayer!.setVolume(1.0);
        await _audioPlayer!.play();
      }
    } catch (e, st) {
      debugPrint('Error playing track "${track.title}": $e\n$st');
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

    final current = startTrack ??
        (sanitizedTracks.any((t) => t.id == state.currentTrack.id)
            ? state.currentTrack
            : sanitizedTracks.first);
    state = state.copyWith(queue: sanitizedTracks, currentTrack: current);
  }

  void updateCurrentTrack(Track updated) {
    if (state.currentTrack.id == updated.id) {
      state = state.copyWith(currentTrack: updated);
    }
  }

  Future<void> playTrack(Track track, {List<Track>? newQueue}) async {
    await PixelHaptics.playPauseToggle();
    final effectiveTrack = (track.dominantColorValue == 0xFF3DDC84 ||
            track.dominantColorValue == 0xFF1DB954)
        ? track.copyWith(dominantColorValue: 0xFF1E293B)
        : track;

    final List<Track> effectiveQueue = newQueue ??
        (state.queue.isEmpty ? _ref.read(tracksCatalogProvider) : state.queue);
    final hasTrack = effectiveQueue.any((t) => t.id == effectiveTrack.id);
    final queueToUse =
        hasTrack ? effectiveQueue : [effectiveTrack, ...effectiveQueue];

    // Record session history
    final prevTrack = state.currentTrack;
    List<Track> updatedHistory = state.sessionHistory;
    if (prevTrack.id.isNotEmpty && prevTrack.id != effectiveTrack.id) {
      updatedHistory = [
        prevTrack,
        ...state.sessionHistory.where((t) => t.id != prevTrack.id)
      ].take(50).toList();
    }

    state = state.copyWith(
      currentTrack: effectiveTrack,
      queue: queueToUse,
      sessionHistory: updatedHistory,
      positionMs: 0,
      bufferedPositionMs: (effectiveTrack.durationMs * 0.35).round(),
      isPlaying: true,
    );
    _startTicker();

    await _ensureAudioPlayerInitialized();
    try {
      if (_audioPlayer != null) {
        await _loadAndPlayTrack(effectiveTrack);
      }
    } catch (_) {}

    final needsPalette = effectiveTrack.dominantColorValue == 0xFF1E293B ||
        effectiveTrack.dominantColorValue == 0xFF3DDC84 ||
        effectiveTrack.dominantColorValue == 0xFF1DB954;
    if (effectiveTrack.artworkUrl == null ||
        effectiveTrack.artworkUrl!.isEmpty ||
        needsPalette) {
      _ref.read(tracksCatalogProvider.notifier).enrichTrackArtwork(effectiveTrack);
    }
  }

  Future<void> seekToMs(int targetMs, {bool withHaptic = false}) async {
    if (withHaptic) {
      await PixelHaptics.lowTick(intensity: 0.35);
    }
    final clamped = targetMs.clamp(0, state.currentTrack.durationMs);
    state = state.copyWith(positionMs: clamped);
    try {
      unawaited(_audioPlayer?.seek(Duration(milliseconds: clamped)));
    } catch (_) {}
  }

  Future<void> skipNext() async {
    await PixelHaptics.tick(intensity: 0.8);

    if (_sleepTimerEndAfterTrack) {
      _sleepTimerEndAfterTrack = false;
      state = state.copyWith(
        isPlaying: false,
        clearSleepTimer: true,
      );
      try {
        await _audioPlayer?.pause();
      } catch (_) {}
      return;
    }

    if (state.repeatMode == 2) {
      // Repeat current track
      await seekToMs(0);
      try {
        await _audioPlayer?.play();
      } catch (_) {}
      return;
    }

    final idx = state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (idx != -1 && idx < state.queue.length - 1) {
      await playTrack(state.queue[idx + 1]);
    } else if (state.repeatMode == 1 && state.queue.isNotEmpty) {
      await playTrack(state.queue.first);
    } else if (state.isAutoplay) {
      _triggerAutoplayNext();
    } else if (state.queue.isNotEmpty) {
      state = state.copyWith(isPlaying: false, positionMs: 0);
      try {
        await _audioPlayer?.pause();
      } catch (_) {}
    }
  }

  Future<void> skipPrevious() async {
    await PixelHaptics.tick(intensity: 0.8);
    if (state.positionMs > 4000) {
      await seekToMs(0);
      return;
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
    state = state.copyWith(isShuffle: !state.isShuffle);
  }

  void cycleRepeatMode() {
    PixelHaptics.tick();
    state = state.copyWith(repeatMode: (state.repeatMode + 1) % 3);
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
    state = state.copyWith(queue: newQueue);
  }

  void removeFromQueue(String trackId) {
    PixelHaptics.tick();
    final newQueue = state.queue
        .where((t) => t.id != trackId || t.id == state.currentTrack.id)
        .toList();
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
    state = state.copyWith(queue: newQueue);
  }

  void addToQueue(Track track) {
    PixelHaptics.tick();
    final withoutTrack = state.queue.where((t) => t.id != track.id).toList();
    state = state.copyWith(queue: [...withoutTrack, track]);
  }

  void clearUpNext() {
    PixelHaptics.tick();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (currentIdx == -1) return;
    state = state.copyWith(queue: [state.currentTrack]);
  }

  void shuffleRemaining() {
    PixelHaptics.medium();
    final currentIdx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    if (currentIdx == -1) return;
    final remaining =
        List<Track>.from(state.queue.sublist(currentIdx + 1))..shuffle();
    state = state.copyWith(queue: [
      ...state.queue.sublist(0, currentIdx + 1),
      ...remaining,
    ]);
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
      await _audioPlayer?.setSpeed(speed);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    PixelHaptics.tick();
    state = state.copyWith(pitch: pitch);
    try {
      await _audioPlayer?.setPitch(pitch);
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
    state = state.copyWith(crossfadeSeconds: seconds.clamp(0, 12));
  }

  @override
  void dispose() {
    _progressTicker?.cancel();
    _sleepTimer?.cancel();
    _audioPlayer?.dispose();
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
  });

  final bool isImporting;
  final int current;
  final int total;
  final String currentItemName;
  final List<PendingImportTrack> pendingTracks;

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
    );
  }

  void startWithFiles(List<String> filenames) {
    final pending = filenames.asMap().entries.map((entry) {
      final idx = entry.key;
      final fn = entry.value;
      final cleanTitle = fn.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      return PendingImportTrack(
        id: 'pending_${idx}_$fn',
        filename: fn,
        title: cleanTitle,
        artist: 'Queued for import...',
        progress: 0.0,
        isCompleted: false,
      );
    }).toList();

    state = ImportProgressState(
      isImporting: true,
      current: 0,
      total: filenames.length,
      pendingTracks: pending,
    );
  }

  void update({
    required int current,
    required int total,
    String name = '',
    Track? track,
  }) {
    final updatedPending = List<PendingImportTrack>.from(state.pendingTracks);
    if (updatedPending.isNotEmpty) {
      for (int i = 0; i < updatedPending.length; i++) {
        final item = updatedPending[i];
        if (i < current - 1) {
          if (!item.isCompleted) {
            updatedPending[i] = item.copyWith(
              progress: 1.0,
              isCompleted: true,
            );
          }
        } else if (i == current - 1) {
          updatedPending[i] = item.copyWith(
            title: track?.title.isNotEmpty == true ? track!.title : item.title,
            artist:
                track?.artist.isNotEmpty == true ? track!.artist : 'Imported',
            progress: 1.0,
            isCompleted: true,
          );
        } else if (i == current) {
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
    );
    state = [newPlaylist, ...state];
    if (_db != null) {
      await _db.upsertPlaylist(newPlaylist);
    }
    return newPlaylist;
  }

  Future<void> renamePlaylist(
    String playlistId,
    String newTitle, {
    String? description,
  }) async {
    await PixelHaptics.tick();
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          title: newTitle.trim().isEmpty ? p.title : newTitle.trim(),
          description: description ?? p.description,
          updatedAt: DateTime.now(),
        );
        if (_db != null) {
          _db.upsertPlaylist(updated);
        }
        return updated;
      }
      return p;
    }).toList();
  }

  Future<void> deletePlaylist(String playlistId) async {
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

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    await PixelHaptics.tick();
    state = state.map((p) {
      if (p.id == playlistId) {
        if (!p.trackIds.contains(trackId)) {
          final updated = p.copyWith(
            trackIds: [...p.trackIds, trackId],
            updatedAt: DateTime.now(),
          );
          if (_db != null) {
            _db.upsertPlaylist(updated);
          }
          return updated;
        }
      }
      return p;
    }).toList();
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    await PixelHaptics.tick();
    state = state.map((p) {
      if (p.id == playlistId) {
        final updated = p.copyWith(
          trackIds: p.trackIds.where((id) => id != trackId).toList(),
          updatedAt: DateTime.now(),
        );
        if (_db != null) {
          _db.upsertPlaylist(updated);
        }
        return updated;
      }
      return p;
    }).toList();
  }

  Future<void> reorderTracks(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await PixelHaptics.tick();
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
        if (_db != null) {
          _db.upsertPlaylist(updated);
        }
        return updated;
      }
      return p;
    }).toList();
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


