import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../core/models/audio_quality_settings.dart';
import '../core/models/cloud_account.dart';
import '../core/models/poweramp_dsp_state.dart';
import '../core/models/track.dart';
import '../core/storage/library_database.dart';
import '../core/storage/secure_credential_store.dart';
import '../providers/implementations/network_and_saf_connectors.dart';
import '../services/audio/cloud_stream_proxy.dart';
import '../services/audio/poweramp_dsp_service.dart';
import '../services/haptics/pixel_haptics.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
// Cloud Accounts & Unified Track Catalog State
// ─────────────────────────────────────────────────────────────────────────────

class CloudAccountsNotifier extends StateNotifier<List<CloudAccount>> {
  CloudAccountsNotifier(this._db, this._credStore)
      : super(DemoCloudConnector.defaultShowcaseAccounts());

  final LibraryDatabase _db;
  final SecureCredentialStore _credStore;

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
  TracksCatalogNotifier(this._db)
      : super(DemoCloudConnector.defaultShowcaseTracks());

  final LibraryDatabase _db;

  Future<void> addIndexedTracks(List<Track> newTracks) async {
    if (newTracks.isEmpty) return;
    await _db.upsertTracks(newTracks);
    final map = {for (final t in state) t.id: t};
    for (final t in newTracks) {
      map[t.id] = t;
    }
    state = map.values.toList();
  }

  Future<void> toggleFavorite(String trackId) async {
    await PixelHaptics.tick(intensity: 0.75);
    state = state.map((t) {
      if (t.id == trackId) {
        return t.copyWith(isFavorite: !t.isFavorite);
      }
      return t;
    }).toList();
  }

  Future<void> togglePinOffline(String trackId) async {
    await PixelHaptics.hifiConfirm();
    state = state.map((t) {
      if (t.id == trackId) {
        return t.copyWith(isPinnedOffline: !t.isPinnedOffline);
      }
      return t;
    }).toList();
  }
}

final tracksCatalogProvider =
    StateNotifierProvider<TracksCatalogNotifier, List<Track>>((ref) {
  return TracksCatalogNotifier(ref.watch(libraryDatabaseProvider));
});

/// Selected Cloud Filter on Home / Library ('all' or CloudProviderType.id or 'offline')
final selectedCloudFilterProvider = StateProvider<String>((ref) => 'all');

/// Search query text in the Pixel Search Bar pill
final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredTracksProvider = Provider<List<Track>>((ref) {
  final allTracks = ref.watch(tracksCatalogProvider);
  final filter = ref.watch(selectedCloudFilterProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();

  return allTracks.where((track) {
    final matchesFilter = filter == 'all'
        ? true
        : filter == 'offline'
            ? track.isPinnedOffline
            : track.providerType.id == filter;
    if (!matchesFilter) return false;
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
    this.isPlaying = false,
    this.positionMs = 42000,
    this.bufferedPositionMs = 165000,
    this.isShuffle = false,
    this.repeatMode = 0, // 0: Off, 1: All, 2: One
  });

  final Track currentTrack;
  final List<Track> queue;
  final bool isPlaying;
  final int positionMs;
  final int bufferedPositionMs;
  final bool isShuffle;
  final int repeatMode;

  double get progressFraction {
    if (currentTrack.durationMs <= 0) return 0.0;
    return (positionMs / currentTrack.durationMs).clamp(0.0, 1.0);
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

  PlaybackViewState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    bool? isPlaying,
    int? positionMs,
    int? bufferedPositionMs,
    bool? isShuffle,
    int? repeatMode,
  }) {
    return PlaybackViewState(
      currentTrack: currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      positionMs: positionMs ?? this.positionMs,
      bufferedPositionMs: bufferedPositionMs ?? this.bufferedPositionMs,
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

class PlaybackNotifier extends StateNotifier<PlaybackViewState> {
  PlaybackNotifier(
    this._ref,
    List<Track> initialTracks,
  ) : super(
          PlaybackViewState(
            currentTrack: initialTracks.first,
            queue: initialTracks,
          ),
        ) {
    _initAudioPlayer();
  }

  final Ref _ref;
  AudioPlayer? _audioPlayer;
  Timer? _progressTicker;

  Future<void> _initAudioPlayer() async {
    try {
      final proxy = _ref.read(cloudStreamProxyProvider);
      await proxy.start();
      _audioPlayer = AudioPlayer();

      _audioPlayer!.androidAudioSessionIdStream.listen((sessionId) {
        if (sessionId != null && sessionId > 0) {
          final dspSvc = _ref.read(powerampDspServiceProvider);
          dspSvc.attachAudioSession(sessionId);
          dspSvc.applyDspState(_ref.read(powerampDspProvider));
        }
      });

      _audioPlayer!.positionStream.listen((pos) {
        if (mounted && state.isPlaying) {
          state = state.copyWith(positionMs: pos.inMilliseconds);
        }
      });
    } catch (_) {
      // Headless widget test environment fallback uses smooth internal ticker
      _audioPlayer = null;
    }
  }

  void _startTicker() {
    _progressTicker?.cancel();
    _progressTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !state.isPlaying) return;
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
      try {
        final proxy = _ref.read(cloudStreamProxyProvider);
        final quality = _ref.read(audioQualityProvider).effectiveStreamingTier;
        proxy.updateCatalog(
          tracks: _ref.read(tracksCatalogProvider),
          accounts: _ref.read(cloudAccountsProvider),
          activeTier: quality,
        );
        if (_audioPlayer != null) {
          if (_audioPlayer!.audioSource == null) {
            await _audioPlayer!.setUrl(state.currentTrack.streamUrl);
          }
          unawaited(_audioPlayer!.play());
        }
      } catch (_) {}
    } else {
      _progressTicker?.cancel();
      try {
        unawaited(_audioPlayer?.pause());
      } catch (_) {}
    }
  }

  Future<void> playTrack(Track track) async {
    await PixelHaptics.playPauseToggle();
    state = state.copyWith(
      currentTrack: track,
      positionMs: 0,
      bufferedPositionMs: (track.durationMs * 0.35).round(),
      isPlaying: true,
    );
    _startTicker();
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.setUrl(track.streamUrl);
        unawaited(_audioPlayer!.play());
      }
    } catch (_) {}
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
    final idx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    final nextIdx = (idx + 1) % state.queue.length;
    await playTrack(state.queue[nextIdx]);
  }

  Future<void> skipPrevious() async {
    await PixelHaptics.tick(intensity: 0.8);
    if (state.positionMs > 4000) {
      await seekToMs(0);
      return;
    }
    final idx =
        state.queue.indexWhere((t) => t.id == state.currentTrack.id);
    final prevIdx = (idx - 1 + state.queue.length) % state.queue.length;
    await playTrack(state.queue[prevIdx]);
  }

  void toggleShuffle() {
    PixelHaptics.tick();
    state = state.copyWith(isShuffle: !state.isShuffle);
  }

  void cycleRepeatMode() {
    PixelHaptics.tick();
    state = state.copyWith(repeatMode: (state.repeatMode + 1) % 3);
  }

  @override
  void dispose() {
    _progressTicker?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackViewState>((ref) {
  final tracks = DemoCloudConnector.defaultShowcaseTracks();
  return PlaybackNotifier(ref, tracks);
});
