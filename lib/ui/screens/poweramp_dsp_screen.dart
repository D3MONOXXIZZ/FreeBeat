import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/poweramp_dsp_state.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/rotary_knob.dart';
import '../widgets/signal_path_sheet.dart';

/// Smart EQ 10-Band Equalizer, Preamp, Exact Numeric Tuning, Rotary Tone & Spatial DSP Studio.
/// Strictly implements Screen 8 ("# Equalizer & Audio Settings") in Figma inspiration:
/// 1. Top Device Status Card: `Pixel Buds Pro` / Route Pill + Animated Spectrum switch + Master EQ switch
/// 2. Multi-Colored Rainbow Frequency Spectrum Bars Visualizer (28 animated dancing bars)
/// 3. Quick Presets Stadium Bar: Bass Boost, Vocal Air, Concert, Audiophile Flat, Club Electronic
/// 4. 10-Band vertical faders with Preamp fader and double-tap reset
/// 5. Rotary Tone Knobs & Stereo X spatial expander
class PowerampDspScreen extends ConsumerStatefulWidget {
  const PowerampDspScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  ConsumerState<PowerampDspScreen> createState() => _PowerampDspScreenState();
}

class _PowerampDspScreenState extends ConsumerState<PowerampDspScreen>
    with SingleTickerProviderStateMixin {
  int _subTab = 0; // 0: Preamp + 10-Band EQ, 1: Tone / Stereo X / Balance / Tempo
  bool _animatedSpectrum = true;
  late final AnimationController _spectrumAnimController;
  PowerampDspState? _cachedDsp;
  List<double>? _cachedPrecomputedDb;
  List<double>? _cachedGainMultipliers;
  ColorScheme? _cachedCs;
  List<Color>? _cachedBarColors;

  List<double> _getPrecomputedDb(PowerampDspState dsp) {
    if (_cachedDsp == dsp && _cachedPrecomputedDb != null) {
      return _cachedPrecomputedDb!;
    }
    _cachedDsp = dsp;
    _cachedPrecomputedDb =
        _MaterialYouSpectrumBarsPainter.computeFrequencyResponses(dsp);
    _cachedGainMultipliers =
        _MaterialYouSpectrumBarsPainter.computeGainMultipliers(_cachedPrecomputedDb!);
    return _cachedPrecomputedDb!;
  }

  List<double> _getGainMultipliers(PowerampDspState dsp) {
    _getPrecomputedDb(dsp);
    return _cachedGainMultipliers!;
  }

  List<Color> _getBarColors(ColorScheme cs) {
    if (_cachedCs == cs && _cachedBarColors != null) {
      return _cachedBarColors!;
    }
    _cachedCs = cs;
    _cachedBarColors = _MaterialYouSpectrumBarsPainter.computeBarColors(cs);
    return _cachedBarColors!;
  }

  @override
  void initState() {
    super.initState();
    _spectrumAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _spectrumAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dsp = ref.watch(powerampDspProvider);
    final notifier = ref.read(powerampDspProvider.notifier);
    final isPlaying = ref.watch(playbackProvider.select((p) => p.isPlaying));
    final route = ref.watch(audioRouteInfoProvider);
    final precomputedDb = _getPrecomputedDb(dsp);

    final isPowerSaver = ref.watch(effectivePowerSaverActiveProvider);
    final powerSaver = ref.watch(powerSaverProvider);
    final shouldPauseVis = isPowerSaver && powerSaver.pauseVisualizers;

    if (widget.isActive && isPlaying && _animatedSpectrum && !shouldPauseVis) {
      if (!_spectrumAnimController.isAnimating) {
        _spectrumAnimController.repeat(reverse: true);
      }
    } else {
      if (_spectrumAnimController.isAnimating) {
        _spectrumAnimController.stop();
      }
    }

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ───────────────────────────────────────────────────────────────────
          // 1. M3 Top App Bar
          // ───────────────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            title: Text(
              'Smart EQ Studio',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      _showPresetPickerSheet(context, dsp, notifier),
                  icon: const Icon(Icons.bookmarks_rounded, size: 16),
                  label: Text(
                    notifier.allPresets
                            .where((p) => p.id == dsp.activePresetId)
                            .map((p) => p.shortName)
                            .firstOrNull ??
                        'Custom Curve',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ───────────────────────────────────────────────────────────────────
          // 2. Screen 8 Header Card: Connected Device & Bit-Perfect Direct Mode
          // ───────────────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: dsp.bitPerfectDirectMode
                        ? const Color(0xFFFFB74D) // Audiophile Bit-Perfect Gold
                        : cs.outlineVariant.withValues(alpha: 0.35),
                    width: dsp.bitPerfectDirectMode ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // Connected Route Device Pill (tappable for Signal Path)
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              PixelHaptics.tick();
                              showModalBottomSheet<void>(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: cs.surface,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(28),
                                  ),
                                ),
                                builder: (_) => const SignalPathSheet(),
                              );
                            },
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: dsp.bitPerfectDirectMode
                                          ? const Color(0xFFFFB74D)
                                          : cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      route.deviceName.isNotEmpty
                                          ? route.deviceName
                                          : 'Pixel Buds Pro',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 14,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Bit-Perfect Direct USB DAC Mode Chip
                        InkWell(
                          onTap: () => notifier.toggleBitPerfectDirectMode(
                              !dsp.bitPerfectDirectMode),
                          borderRadius: BorderRadius.circular(100),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: dsp.bitPerfectDirectMode
                                  ? const Color(0xFFFFB74D).withValues(alpha: 0.20)
                                  : cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: dsp.bitPerfectDirectMode
                                    ? const Color(0xFFFFB74D)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.album_rounded,
                                  size: 14,
                                  color: dsp.bitPerfectDirectMode
                                      ? const Color(0xFFFFB74D)
                                      : cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Bit-Perfect',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: dsp.bitPerfectDirectMode
                                        ? const Color(0xFFFFB74D)
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Master EQ Switch
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'EQ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: dsp.eqEnabled && !dsp.bitPerfectDirectMode
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: dsp.eqEnabled && !dsp.bitPerfectDirectMode,
                                onChanged: dsp.bitPerfectDirectMode
                                    ? null
                                    : notifier.toggleEq,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (dsp.bitPerfectDirectMode) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB74D).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.bolt_rounded,
                                size: 14, color: Color(0xFFFFB74D)),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'BIT-PERFECT DIRECT USB DAC ACTIVE • DSP & TONE BYPASSED • RAW PCM OUT',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFFFB74D),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ───────────────────────────────────────────────────────────────────
          // 3. Multi-Mode Real-Time Audio Visualizer Studio
          // ───────────────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Container(
                height: 172,
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: dsp.isClippingRisk
                        ? cs.error
                        : cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Stack(
                  children: [
                    // Dynamic Canvas Visualizer based on visualizerMode
                    Positioned.fill(
                      bottom: 28,
                      top: 22,
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _spectrumAnimController,
                          builder: (context, _) {
                            final animVal = _spectrumAnimController.value;
                            if (dsp.visualizerMode == VisualizerMode.waveformRibbon) {
                              return CustomPaint(
                                size: Size.infinite,
                                painter: _FluidWaveformRibbonPainter(
                                  dsp: dsp,
                                  isPlaying: isPlaying,
                                  isAnimated: _animatedSpectrum,
                                  animVal: animVal,
                                  colorScheme: cs,
                                  gridColor: cs.outlineVariant.withValues(alpha: 0.20),
                                  precomputedDb: precomputedDb,
                                ),
                              );
                            } else if (dsp.visualizerMode == VisualizerMode.vinylPulse) {
                              return CustomPaint(
                                size: Size.infinite,
                                painter: _ConcentricVinylPulsePainter(
                                  dsp: dsp,
                                  isPlaying: isPlaying,
                                  isAnimated: _animatedSpectrum,
                                  animVal: animVal,
                                  colorScheme: cs,
                                  gridColor: cs.outlineVariant.withValues(alpha: 0.20),
                                  precomputedDb: precomputedDb,
                                ),
                              );
                            } else {
                              return CustomPaint(
                                size: Size.infinite,
                                painter: _MaterialYouSpectrumBarsPainter(
                                  dsp: dsp,
                                  isPlaying: isPlaying,
                                  isAnimated: _animatedSpectrum,
                                  animVal: animVal,
                                  precomputedDb: precomputedDb,
                                  barColors: _getBarColors(cs),
                                  gainMultipliers: _getGainMultipliers(dsp),
                                  colorScheme: cs,
                                  gridColor: cs.outlineVariant.withValues(alpha: 0.20),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),

                    // Top Left Status
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Text(
                        dsp.bitPerfectDirectMode
                            ? 'BIT-PERFECT DIRECT PCM • 24/32-BIT DIRECT'
                            : 'PREAMP ${dsp.preampDb >= 0 ? "+" : ""}${dsp.preampDb.toStringAsFixed(1)} dB • 10-BAND DSP',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: dsp.bitPerfectDirectMode
                              ? const Color(0xFFFFB74D)
                              : cs.primary,
                        ),
                      ),
                    ),

                    // Top Right Controls (Clipping Alert + Live/Static)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (dsp.isClippingRisk) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: cs.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'CLIPPING RISK (LIMITER)',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: cs.onErrorContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          InkWell(
                            onTap: () {
                              PixelHaptics.tick();
                              setState(() => _animatedSpectrum = !_animatedSpectrum);
                            },
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _animatedSpectrum
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _animatedSpectrum
                                        ? Icons.auto_awesome_rounded
                                        : Icons.auto_awesome_outlined,
                                    size: 12,
                                    color: _animatedSpectrum
                                        ? cs.onPrimaryContainer
                                        : cs.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _animatedSpectrum ? 'Live' : 'Static',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _animatedSpectrum
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom: Interactive Visualizer Mode Selector
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          for (final mode in VisualizerMode.values) ...[
                            InkWell(
                              onTap: () => notifier.setVisualizerMode(mode),
                              borderRadius: BorderRadius.circular(100),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: dsp.visualizerMode == mode
                                      ? cs.secondaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: dsp.visualizerMode == mode
                                        ? cs.secondary
                                        : cs.outlineVariant.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      mode == VisualizerMode.spectrumBars
                                          ? Icons.equalizer_rounded
                                          : mode == VisualizerMode.waveformRibbon
                                              ? Icons.waves_rounded
                                              : Icons.album_rounded,
                                      size: 12,
                                      color: dsp.visualizerMode == mode
                                          ? cs.onSecondaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      mode == VisualizerMode.spectrumBars
                                          ? 'Bars'
                                          : mode == VisualizerMode.waveformRibbon
                                              ? 'Waveform'
                                              : 'Vinyl Pulse',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: dsp.visualizerMode == mode
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: dsp.visualizerMode == mode
                                            ? cs.onSecondaryContainer
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ───────────────────────────────────────────────────────────────────
          // 4. Quick Presets Stadium Bar (All Curated Presets & Custom EQ)
          // ───────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (final preset in kBuiltInDspPresets) ...[
                    _PresetChip(
                      label: preset.shortName,
                      isSelected: dsp.activePresetId == preset.id,
                      onTap: () {
                        notifier.loadPresetById(preset.id);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final custom in notifier.customPresets) ...[
                    _PresetChip(
                      label: custom.name,
                      isSelected: dsp.activePresetId == custom.id,
                      isCustom: true,
                      onTap: () {
                        notifier.loadPresetById(custom.id);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  _PresetChip(
                    label: 'Presets Hub',
                    icon: Icons.hub_rounded,
                    isSelected: false,
                    onTap: () {
                      _showPresetPickerSheet(context, dsp, notifier);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 14)),

          // ───────────────────────────────────────────────────────────────────
          // 5. Sub-Tab Switcher: [Preamp + 10-Band EQ] vs [Tone Knobs & Stereo X]
          // ───────────────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: _DspSubTabButton(
                      label: 'Preamp + 10-Band EQ',
                      isSelected: _subTab == 0,
                      icon: Icons.equalizer_rounded,
                      onTap: () => setState(() => _subTab = 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DspSubTabButton(
                      label: 'Tone Knobs & Stereo X',
                      isSelected: _subTab == 1,
                      icon: Icons.album_rounded,
                      onTap: () => setState(() => _subTab = 1),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ───────────────────────────────────────────────────────────────────
          // 6. Sub-Tab Content: Vertical Faders OR Rotary Studio
          // ───────────────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 140),
            sliver: SliverToBoxAdapter(
              child: _subTab == 0
                  ? _buildPreampAnd10BandFaders(cs, dsp, notifier)
                  : _buildRotaryToneAndSpatialStudio(context, cs, dsp, notifier),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreampAnd10BandFaders(
    ColorScheme cs,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // EQ Header: Exact Numbers & Reset
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '10-Band EQ',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    PixelHaptics.tick();
                    notifier.toggleParametricMode(!dsp.isParametricMode);
                  },
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: dsp.isParametricMode ? cs.primaryContainer : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: dsp.isParametricMode ? cs.primary : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          dsp.isParametricMode ? Icons.linear_scale_rounded : Icons.graphic_eq_rounded,
                          size: 13,
                          color: dsp.isParametricMode ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dsp.isParametricMode ? 'Parametric' : 'Graphic',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: dsp.isParametricMode ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _showManualAllBandsSheet(context, dsp, notifier),
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 14, color: cs.onSecondaryContainer),
                        const SizedBox(width: 4),
                        Text(
                          'Exact dB',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Reset EQ to Flat (0 dB)',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () {
                    PixelHaptics.centerDetentSnap();
                    notifier.resetFlat();
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            height: 275,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Preamp Column
                  _VerticalEqFaderColumn(
                    label: 'PREAMP',
                    gainDb: dsp.preampDb,
                    accentColor: cs.primary,
                    isPreamp: true,
                    onChanged: notifier.setPreampDb,
                    onTapNumber: () => _showSingleBandNumericDialog(
                      context,
                      'Preamp',
                      dsp.preampDb,
                      notifier.setPreampDb,
                    ),
                    onDoubleTapReset: () {
                      PixelHaptics.centerDetentSnap();
                      notifier.setPreampDb(0.0);
                    },
                  ),
                  VerticalDivider(
                    width: 24,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.25),
                  ),
                  // 10 ISO Octave Bands
                  for (int i = 0; i < dsp.bands.length; i++) ...[
                    _VerticalEqFaderColumn(
                      label: dsp.bands[i].label,
                      gainDb: dsp.bands[i].gainDb,
                      accentColor: dsp.bands[i].gainDb >= 0
                          ? cs.secondary
                          : cs.onSurfaceVariant,
                      qFactor: dsp.isParametricMode ? dsp.bands[i].qFactor : null,
                      onChanged: (val) => notifier.setBandGain(i, val),
                      onTapNumber: () => _showSingleBandNumericDialog(
                        context,
                        dsp.bands[i].label,
                        dsp.bands[i].gainDb,
                        (val) => notifier.setBandGain(i, val),
                      ),
                      onTapFrequency: () {
                        if (dsp.isParametricMode) {
                          _showBandParametricDialog(context, i, dsp.bands[i], notifier);
                        } else {
                          PixelHaptics.tick();
                          notifier.toggleParametricMode(true);
                          _showBandParametricDialog(context, i, dsp.bands[i], notifier);
                        }
                      },
                      onDoubleTapReset: () {
                        PixelHaptics.centerDetentSnap();
                        notifier.setBandGain(i, 0.0);
                      },
                    ),
                    if (i < dsp.bands.length - 1) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotaryToneAndSpatialStudio(
    BuildContext context,
    ColorScheme cs,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    final quality = ref.watch(audioQualityProvider);

    return Column(
      children: [
        // Rotary Knobs Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rotary Tone & Spatial Stage',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          dsp.toneEnabled
                              ? '${dsp.toneFrequencyHz.toInt()} Hz Cutoff • Active'
                              : 'Bypassed',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: dsp.toneEnabled ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: dsp.toneEnabled,
                      onChanged: notifier.toggleTone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  PowerampRotaryKnob(
                    value: dsp.bassGain,
                    label: 'BASS TONE',
                    subtitle: 'Low Shelf',
                    accentColor: cs.primary,
                    onChanged: notifier.setBassTone,
                  ),
                  PowerampRotaryKnob(
                    value: dsp.trebleGain,
                    label: 'TREBLE AIR',
                    subtitle: 'High Shelf',
                    accentColor: cs.secondary,
                    onChanged: notifier.setTrebleTone,
                  ),
                  PowerampRotaryKnob(
                    value: dsp.stereoExpansion,
                    label: 'STEREO X',
                    subtitle: 'Spatial Width',
                    accentColor: cs.tertiary,
                    onChanged: notifier.setStereoExpansion,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Bauer BS2B Binaural Crossfeed Card (Phase 3 Innovation)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.headphones_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Bauer BS2B Binaural Crossfeed',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Simulates acoustic speaker room cross-bleed in headphones, eliminating the "in-head" fatigue of hard-panned stereo recordings.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Bs2bCrossfeedMode.values.map((mode) {
                  final selected = dsp.bs2bCrossfeedMode == mode;
                  return ChoiceChip(
                    label: Text(mode.label),
                    selected: selected,
                    onSelected: (_) => notifier.setBs2bCrossfeedMode(mode),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Direct Volume Control (DVC) & Headroom Card (Phase 3 Innovation)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.shield_rounded, color: cs.secondary, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Direct Volume Control (DVC)',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: dsp.dvcEnabled,
                      onChanged: notifier.toggleDvc,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Unlocks 32-bit floating-point preamp headroom to prevent digital inter-sample distortion when boosting EQ frequencies.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Clean Digital Headroom Guard',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dsp.dvcHeadroomDb.toStringAsFixed(1)} dBFS',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: cs.secondary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: dsp.dvcHeadroomDb,
                min: -6.0,
                max: 0.0,
                divisions: 12,
                onChanged: notifier.setDvcHeadroomDb,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.speed_rounded,
                          color: dsp.limiterEnabled ? cs.primary : cs.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hardware Peak Auto-Limiter',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                dsp.limiterEnabled
                                    ? 'Zero-clipping brickwall guard (DSP dynamic headroom)'
                                    : 'Disabled (True audio fidelity / uncompressed)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: dsp.limiterEnabled,
                      onChanged: notifier.toggleLimiter,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Balance, Tempo, and Reverb Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          'L/R Balance (${dsp.balance == 0 ? "Center" : dsp.balance.toStringAsFixed(2)})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (dsp.balance.abs() > 0.04) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              PixelHaptics.centerDetentSnap();
                              notifier.setBalance(0.0);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Text(
                                'Reset',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Mono Mix',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: 0.85,
                        child: Switch(
                          value: dsp.monoMix,
                          onChanged: notifier.toggleMonoMix,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Slider(
                value: dsp.balance,
                min: -1.0,
                max: 1.0,
                divisions: 40,
                onChanged: notifier.setBalance,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Playback Tempo / Speed (${dsp.tempo.toStringAsFixed(2)}x)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((dsp.tempo - 1.0).abs() > 0.02)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        PixelHaptics.centerDetentSnap();
                        notifier.setTempo(1.0);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Slider(
                value: dsp.tempo,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                onChanged: notifier.setTempo,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pitch Transposition (${dsp.pitchSemitones > 0 ? "+" : ""}${dsp.pitchSemitones.toStringAsFixed(1)} st)',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (dsp.pitchSemitones.abs() > 0.05)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        PixelHaptics.centerDetentSnap();
                        notifier.setPitchSemitones(0.0);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Slider(
                value: dsp.pitchSemitones,
                min: -12.0,
                max: 12.0,
                divisions: 24,
                onChanged: notifier.setPitchSemitones,
              ),
              const SizedBox(height: 10),
              Text(
                'Gapless Crossfade (${(quality.crossfadeDurationMs / 1000).toStringAsFixed(1)}s)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Slider(
                value: quality.crossfadeDurationMs.toDouble(),
                min: 0,
                max: 12000,
                divisions: 24,
                onChanged: (v) {
                  final ms = v.round();
                  ref.read(audioQualityProvider.notifier).setCrossfadeDuration(ms);
                  ref.read(playbackProvider.notifier).setCrossfadeSeconds((ms / 1000).round());
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Acoustic Room Reverb',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReverbPresetType.values.map((rev) {
                  return ChoiceChip(
                    label: Text(rev.label),
                    selected: dsp.reverbPreset == rev,
                    onSelected: (_) => notifier.setReverbPreset(rev),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    PixelHaptics.tick();
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: cs.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      builder: (_) => const SignalPathSheet(),
                    );
                  },
                  icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                  label: const Text('Live Audio Signal Path & Bitrate'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showPresetPickerSheet(
    BuildContext context,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (sheetCtx, ref, _) {
            final activeDsp = ref.watch(powerampDspProvider);
            final activeNotifier = ref.read(powerampDspProvider.notifier);
            final customPresets = activeNotifier.customPresets;
            final builtInPresets = kBuiltInDspPresets;

            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              maxChildSize: 0.94,
              minChildSize: 0.40,
              expand: false,
              builder: (_, scrollController) {
                return SafeArea(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Smart EQ & Audiophile Presets Hub',
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Action buttons: Save EQ, Import, Auto Profiles
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _showSavePresetDialog(context, activeNotifier);
                              },
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Save Current EQ'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _showImportPresetDialog(context, activeNotifier);
                              },
                              icon: const Icon(Icons.file_download_outlined, size: 16),
                              label: const Text('Import JSON'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _showDeviceProfilesModal(context, activeDsp, activeNotifier);
                              },
                              icon: const Icon(Icons.phonelink_setup_rounded, size: 16),
                              label: const Text('Auto Route Profiles'),
                            ),
                          ],
                        ),
                      ),

                      if (customPresets.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'USER CUSTOM PRESETS (${customPresets.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final preset in customPresets)
                          Card(
                            elevation: 0,
                            color: cs.surfaceContainerHigh,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: preset.id == activeDsp.activePresetId
                                    ? cs.primary
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: ListTile(
                              onTap: () {
                                PixelHaptics.tick();
                                activeNotifier.loadPresetById(preset.id);
                                Navigator.of(ctx).pop();
                              },
                              leading: Icon(
                                preset.id == activeDsp.activePresetId
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: preset.id == activeDsp.activePresetId
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(
                                preset.name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                preset.description,
                                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.share_outlined, size: 18),
                                    tooltip: 'Export Preset JSON',
                                    onPressed: () {
                                      final jsonStr = activeNotifier.exportPresetJson(preset.id);
                                      Clipboard.setData(ClipboardData(text: jsonStr));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Preset "${preset.name}" copied to clipboard!'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    tooltip: 'Delete Preset',
                                    onPressed: () {
                                      activeNotifier.deleteCustomPreset(preset.id);
                                      Navigator.of(ctx).pop();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],

                      const SizedBox(height: 20),
                      Text(
                        'CURATED SMART EQ & AUDIOPHILE CURVES',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: cs.secondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final preset in builtInPresets)
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          leading: Icon(
                            preset.id == activeDsp.activePresetId
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: preset.id == activeDsp.activePresetId
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          title: Text(
                            preset.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            preset.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          onTap: () {
                            PixelHaptics.tick();
                            activeNotifier.loadPresetById(preset.id);
                            Navigator.of(ctx).pop();
                          },
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showManualAllBandsSheet(
    BuildContext context,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (sheetCtx, ref, _) {
            final activeDsp = ref.watch(powerampDspProvider);
            final activeNotifier = ref.read(powerampDspProvider.notifier);

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              maxChildSize: 0.95,
              minChildSize: 0.50,
              expand: false,
              builder: (_, scrollController) {
                return SafeArea(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tune_rounded, color: cs.primary, size: 22),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Exact Numeric EQ Tuning',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Set precise decimal decibel gains (-15.0 dB to +15.0 dB) for each frequency band.',
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 14),
                      // Quick actions
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () {
                                PixelHaptics.centerDetentSnap();
                                activeNotifier.resetFlat();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Reset All (0 dB)'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                PixelHaptics.tick();
                                for (int i = 0; i < activeDsp.bands.length; i++) {
                                  activeNotifier.setBandGain(
                                    i,
                                    (activeDsp.bands[i].gainDb + 1.0).clamp(-15.0, 15.0),
                                  );
                                }
                              },
                              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                              label: const Text('+1 dB All'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                PixelHaptics.tick();
                                for (int i = 0; i < activeDsp.bands.length; i++) {
                                  activeNotifier.setBandGain(
                                    i,
                                    (activeDsp.bands[i].gainDb - 1.0).clamp(-15.0, 15.0),
                                  );
                                }
                              },
                              icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                              label: const Text('-1 dB All'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Preamp Card
                      _buildBandNumberInputRow(
                        context,
                        title: 'PREAMP',
                        subtitle: 'Master Input Gain',
                        currentGainDb: activeDsp.preampDb,
                        accentColor: cs.primary,
                        onChanged: (val) => activeNotifier.setPreampDb(val),
                        onReset: () => activeNotifier.setPreampDb(0.0),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      // 10 Bands
                      for (int i = 0; i < activeDsp.bands.length; i++) ...[
                        _buildBandNumberInputRow(
                          context,
                          title: activeDsp.bands[i].label,
                          subtitle: _getBandDescription(i, activeDsp.bands[i].frequencyHz),
                          currentGainDb: activeDsp.bands[i].gainDb,
                          accentColor: activeDsp.bands[i].gainDb >= 0 ? cs.secondary : cs.onSurfaceVariant,
                          onChanged: (val) => activeNotifier.setBandGain(i, val),
                          onReset: () => activeNotifier.setBandGain(i, 0.0),
                        ),
                        if (i < activeDsp.bands.length - 1)
                          const Divider(height: 8, indent: 12, endIndent: 12),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSingleBandNumericDialog(
    BuildContext context,
    String bandLabel,
    double currentGainDb,
    ValueChanged<double> onApplied,
  ) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;
    final initialGain = currentGainDb;
    final controller = TextEditingController(
      text: currentGainDb.toStringAsFixed(1),
    );
    double localVal = currentGainDb;

    showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tune $bandLabel',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter exact gain in decibels (-15.0 dB to +15.0 dB)',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                    ),
                    decoration: InputDecoration(
                      suffixText: 'dB',
                      suffixStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.primary, width: 2),
                      ),
                    ),
                    onChanged: (text) {
                      final parsed = double.tryParse(text.replaceAll('+', '').trim());
                      if (parsed != null) {
                        localVal = parsed.clamp(-15.0, 15.0);
                        onApplied(localVal);
                      }
                    },
                    onSubmitted: (_) {
                      final parsed = double.tryParse(controller.text.replaceAll('+', '').trim());
                      if (parsed != null) {
                        onApplied(parsed.clamp(-15.0, 15.0));
                      }
                      PixelHaptics.tick();
                      Navigator.of(dlgCtx).pop();
                    },
                  ),
                  const SizedBox(height: 14),
                  // Micro Steppers Row (-1.0, -0.1, 0.0, +0.1, +1.0)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepButton(
                          label: '-1 dB',
                          onTap: () {
                            localVal = (localVal - 1.0).clamp(-15.0, 15.0);
                            controller.text = localVal.toStringAsFixed(1);
                            onApplied(localVal);
                            setDlgState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _StepButton(
                          label: '-0.1',
                          onTap: () {
                            localVal = (localVal - 0.1).clamp(-15.0, 15.0);
                            controller.text = localVal.toStringAsFixed(1);
                            onApplied(localVal);
                            setDlgState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _StepButton(
                          label: '0.0',
                          isReset: true,
                          onTap: () {
                            localVal = 0.0;
                            controller.text = '0.0';
                            onApplied(localVal);
                            setDlgState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _StepButton(
                          label: '+0.1',
                          onTap: () {
                            localVal = (localVal + 0.1).clamp(-15.0, 15.0);
                            controller.text = localVal.toStringAsFixed(1);
                            onApplied(localVal);
                            setDlgState(() {});
                          },
                        ),
                        const SizedBox(width: 6),
                        _StepButton(
                          label: '+1 dB',
                          onTap: () {
                            localVal = (localVal + 1.0).clamp(-15.0, 15.0);
                            controller.text = localVal.toStringAsFixed(1);
                            onApplied(localVal);
                            setDlgState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  onApplied(initialGain);
                  Navigator.of(dlgCtx).pop();
                },
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = double.tryParse(controller.text.replaceAll('+', '').trim());
                  if (parsed != null) {
                    onApplied(parsed.clamp(-15.0, 15.0));
                  }
                  PixelHaptics.tick();
                  Navigator.of(dlgCtx).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBandParametricDialog(
    BuildContext context,
    int bandIndex,
    EqBandConfig band,
    PowerampDspNotifier notifier,
  ) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;
    double currentFreq = band.frequencyHz;
    double currentQ = band.qFactor;
    final defaultFreq = kPoweramp10BandFrequencies[bandIndex];

    showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.tune_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Band ${bandIndex + 1} Parametric Tuning',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Customize center frequency and resonance (Q-factor) for precise filter bandwidth.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Frequency: ${currentFreq.toStringAsFixed(0)} Hz',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      TextButton(
                        onPressed: () {
                          PixelHaptics.centerDetentSnap();
                          setDlgState(() => currentFreq = defaultFreq);
                          notifier.setBandParametric(bandIndex, frequencyHz: defaultFreq);
                        },
                        child: const Text('ISO Octave'),
                      ),
                    ],
                  ),
                  Slider(
                    value: currentFreq.clamp(20.0, 20000.0),
                    min: 20.0,
                    max: 20000.0,
                    divisions: 100,
                    onChanged: (val) {
                      setDlgState(() => currentFreq = val);
                      notifier.setBandParametric(bandIndex, frequencyHz: val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Q-Factor: ${currentQ.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      TextButton(
                        onPressed: () {
                          PixelHaptics.centerDetentSnap();
                          setDlgState(() => currentQ = 1.41);
                          notifier.setBandParametric(bandIndex, qFactor: 1.41);
                        },
                        child: const Text('Default 1.41'),
                      ),
                    ],
                  ),
                  Slider(
                    value: currentQ.clamp(0.3, 10.0),
                    min: 0.3,
                    max: 10.0,
                    divisions: 97,
                    onChanged: (val) {
                      setDlgState(() => currentQ = val);
                      notifier.setBandParametric(bandIndex, qFactor: val);
                    },
                  ),
                  Center(
                    child: Text(
                      currentQ < 1.0
                          ? 'Wide Filter (Smoother Transitions)'
                          : currentQ > 3.0
                              ? 'Narrow Notch (Surgical Cut/Boost)'
                              : 'Standard Biquad Resonance',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBandNumberInputRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required double currentGainDb,
    required Color accentColor,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    final cs = Theme.of(context).colorScheme;
    final formattedDb = '${currentGainDb >= 0 ? "+" : ""}${currentGainDb.toStringAsFixed(1)}';

    return GestureDetector(
      onDoubleTap: () {
        PixelHaptics.centerDetentSnap();
        onReset();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (currentGainDb.abs() > 0.05)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                tooltip: 'Reset to 0.0 dB',
                onPressed: () {
                  PixelHaptics.centerDetentSnap();
                  onReset();
                },
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove_rounded, size: 18),
              onPressed: () {
                PixelHaptics.tick();
                onChanged((currentGainDb - 0.5).clamp(-15.0, 15.0));
              },
            ),
            InkWell(
              onTap: () {
                _showSingleBandNumericDialog(context, title, currentGainDb, onChanged);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: currentGainDb.abs() > 0.05 ? accentColor : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  '$formattedDb dB',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: currentGainDb.abs() > 0.05 ? accentColor : cs.onSurface,
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add_rounded, size: 18),
              onPressed: () {
                PixelHaptics.tick();
                onChanged((currentGainDb + 0.5).clamp(-15.0, 15.0));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getBandDescription(int index, double freqHz) {
    switch (index) {
      case 0:
        return 'Sub-Bass (Rumble)';
      case 1:
        return 'Deep Bass';
      case 2:
        return 'Bass Punch & Kick';
      case 3:
        return 'Warmth / Low-Mid';
      case 4:
        return 'Body / Midrange';
      case 5:
        return 'Vocal Clarity (1 kHz)';
      case 6:
        return 'Vocal Presence';
      case 7:
        return 'Attack / Upper-Mid';
      case 8:
        return 'Brightness / Treble';
      case 9:
        return 'Air / Sparkle (16 kHz)';
      default:
        return '${freqHz.toInt()} Hz Band';
    }
  }

  void _showSavePresetDialog(BuildContext context, PowerampDspNotifier notifier) {
    final textController = TextEditingController(text: 'My Custom Curve');
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Save Current EQ as Preset'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Preset Name',
            hintText: 'e.g. Bass Punch, Studio Monitor',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                notifier.saveCustomPreset(name);
              }
              Navigator.of(dlgCtx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showImportPresetDialog(BuildContext context, PowerampDspNotifier notifier) {
    final textController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Import Preset JSON'),
        content: TextField(
          controller: textController,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Paste JSON Curve',
            hintText: '{"name": "...", "bandGainsDb": [...], ...}',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dlgCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final jsonStr = textController.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(dlgCtx).pop();
              if (jsonStr.isNotEmpty) {
                final preset = await notifier.importPresetFromJson(jsonStr);
                if (preset != null) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Imported "${preset.name}" successfully!')),
                  );
                } else {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Failed to parse preset JSON.')),
                  );
                }
              }
            },
            child: const Text('Import & Apply'),
          ),
        ],
      ),
    );
  }

  void _showDeviceProfilesModal(
    BuildContext context,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    PixelHaptics.sheetExpand();
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final allPresets = notifier.allPresets;
        final routes = [
          {
            'key': 'BLUETOOTH',
            'title': 'Bluetooth Headphones / Car',
            'subtitle': 'A2DP / BLE Audio / LDAC route',
            'icon': Icons.bluetooth_audio_rounded,
          },
          {
            'key': 'USB_DAC',
            'title': 'USB-C Direct DAC / Line-Out',
            'subtitle': 'Bit-perfect direct PCM DAC route',
            'icon': Icons.album_rounded,
          },
          {
            'key': 'WIRED_HEADPHONES',
            'title': 'Wired Studio Headphones / AUX',
            'subtitle': '3.5mm analog direct output',
            'icon': Icons.headphones_rounded,
          },
          {
            'key': 'BUILTIN_SPEAKER',
            'title': 'Phone Built-in Stereo Speaker',
            'subtitle': 'Built-in device loudspeaker',
            'icon': Icons.speaker_rounded,
          },
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hardware Route Auto-Switching',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Automatically applies assigned sound profiles whenever an output route connects.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 18),
                for (final r in routes) ...[
                  StatefulBuilder(
                    builder: (context, setTileState) {
                      final currentPresetId = dsp.deviceProfiles[r['key'] as String] ?? 'flat';

                      return Card(
                        elevation: 0,
                        color: cs.surfaceContainerHigh,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(r['icon'] as IconData, color: cs.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['title'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      r['subtitle'] as String,
                                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 135),
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: allPresets.any((p) => p.id == currentPresetId)
                                      ? currentPresetId
                                      : allPresets.first.id,
                                  underline: const SizedBox.shrink(),
                                  icon: const Icon(Icons.arrow_drop_down_rounded),
                                  items: allPresets.map((p) {
                                    return DropdownMenuItem<String>(
                                      value: p.id,
                                      child: Text(
                                        p.shortName,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      notifier.setDeviceProfile(r['key'] as String, val);
                                      setTileState(() {});
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.icon,
    this.isCustom = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData? icon;
  final bool isCustom;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DspSubTabButton extends StatelessWidget {
  const _DspSubTabButton({
    required this.label,
    required this.isSelected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      borderRadius: BorderRadius.circular(100),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? cs.secondaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? cs.secondary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? cs.onSecondaryContainer
                  : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? cs.onSecondaryContainer
                      : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalEqFaderColumn extends StatelessWidget {
  const _VerticalEqFaderColumn({
    required this.label,
    required this.gainDb,
    required this.accentColor,
    required this.onChanged,
    required this.onDoubleTapReset,
    this.onTapNumber,
    this.onTapFrequency,
    this.isPreamp = false,
    this.qFactor,
  });

  final String label;
  final double gainDb;
  final Color accentColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onDoubleTapReset;
  final VoidCallback? onTapNumber;
  final VoidCallback? onTapFrequency;
  final bool isPreamp;
  final double? qFactor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final formattedDb =
        '${gainDb >= 0 ? "+" : ""}${gainDb.toStringAsFixed(1)}';

    return GestureDetector(
      onDoubleTap: onDoubleTapReset,
      child: SizedBox(
        width: isPreamp ? 64 : 52,
        child: Column(
          children: [
            InkWell(
              onTap: onTapNumber,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: gainDb.abs() > 0.05
                        ? accentColor.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Text(
                  formattedDb,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: gainDb.abs() > 0.1 ? accentColor : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accentColor,
                    thumbColor: accentColor,
                    trackHeight: isPreamp ? 6.0 : 4.5,
                  ),
                  child: Slider(
                    value: gainDb.clamp(-15.0, 15.0),
                    min: -15.0,
                    max: 15.0,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
            InkWell(
              onTap: onTapFrequency,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: isPreamp ? 11 : 11.5,
                        fontWeight: FontWeight.w800,
                        color: isPreamp ? accentColor : cs.onSurface,
                      ),
                    ),
                    if (qFactor != null)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Q ${qFactor!.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dynamic Multi-Colored Rainbow Spectrum Bars Painter (Figma Screen 8)
class _MaterialYouSpectrumBarsPainter extends CustomPainter {
  _MaterialYouSpectrumBarsPainter({
    required this.dsp,
    required this.isPlaying,
    required this.isAnimated,
    required this.animVal,
    required this.colorScheme,
    required this.gridColor,
    List<double>? precomputedDb,
    List<Color>? barColors,
    List<double>? gainMultipliers,
  })  : precomputedDb = precomputedDb ?? computeFrequencyResponses(dsp),
        barColors = barColors ?? computeBarColors(colorScheme),
        gainMultipliers = gainMultipliers ??
            computeGainMultipliers(
                precomputedDb ?? computeFrequencyResponses(dsp));

  static const int barCount = 24;

  static List<double> computeFrequencyResponses(PowerampDspState dsp) {
    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);
    return List<double>.generate(barCount, (i) {
      final t = i / (barCount - 1);
      final freq = math.exp(minLog + t * (maxLog - minLog));
      return dsp.evaluateResponseAtFrequency(freq);
    }, growable: false);
  }

  static List<Color> computeBarColors(ColorScheme cs) {
    return List<Color>.generate(barCount, (i) {
      final t = i / (barCount - 1);
      if (t < 0.33) {
        return Color.lerp(cs.primary, cs.tertiary, t / 0.33)!;
      } else if (t < 0.66) {
        return Color.lerp(cs.tertiary, cs.secondary, (t - 0.33) / 0.33)!;
      } else {
        return Color.lerp(cs.secondary, cs.primaryContainer, (t - 0.66) / 0.34)!;
      }
    }, growable: false);
  }

  static List<double> computeGainMultipliers(List<double> dbList) {
    return List<double>.generate(barCount, (i) {
      return math.pow(10.0, dbList[i] / 35.0).toDouble();
    }, growable: false);
  }

  final PowerampDspState dsp;
  final bool isPlaying;
  final bool isAnimated;
  final double animVal;
  final ColorScheme colorScheme;
  final Color gridColor;
  final List<double> precomputedDb;
  final List<Color> barColors;
  final List<double> gainMultipliers;

  static final Paint _barPaint = Paint();
  static final Paint _peakPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _zeroPaint = Paint()..strokeWidth = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final totalWidth = size.width;
    const barSpacing = 4.0;
    final barWidth = (totalWidth - (barSpacing * (barCount - 1))) / barCount;
    final cornerRadius = Radius.circular(barWidth / 2);

    // Subtle 0 dB reference line
    final midY = size.height * 0.55;
    _zeroPaint.color = gridColor;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), _zeroPaint);

    final waveVal = animVal * 2.0 * math.pi;
    final bassWeight = 1.0 + (dsp.bassGainDb > 0 ? (dsp.bassGainDb / 12.0) : 0.0);
    final trebleWeight = 1.0 + (dsp.trebleGainDb > 0 ? (dsp.trebleGainDb / 12.0) : 0.0);

    for (int i = 0; i < barCount; i++) {
      final t = i / (barCount - 1);
      final color = barColors[i];
      final db = precomputedDb[i];
      double normalized = ((db + 15.0) / 30.0).clamp(0.08, 0.95);

      if (isPlaying && isAnimated) {
        double dynamicEnergy = 0.0;
        if (t < 0.25) {
          final beat = math.sin((waveVal * 1.5) + (i * 0.2)) * 0.5 + 0.5;
          dynamicEnergy = beat * beat * 0.16 * bassWeight;
        } else if (t < 0.65) {
          final phase = (waveVal * 2.2) + (i * 0.65);
          dynamicEnergy = (math.sin(phase) * 0.07) + (math.cos(phase * 1.7) * 0.05);
        } else {
          final treblePhase = (waveVal * 3.4) + (i * 1.3);
          dynamicEnergy = (math.sin(treblePhase * 1.8) * 0.06 + math.cos(treblePhase * 2.5) * 0.04) * trebleWeight;
        }

        normalized = (normalized + (dynamicEnergy * gainMultipliers[i])).clamp(0.06, 1.0);
      }

      final barHeight = normalized * (size.height * 0.84);
      final x = i * (barWidth + barSpacing);
      final y = size.height - barHeight;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        cornerRadius,
      );

      _barPaint.color = color;
      canvas.drawRRect(rrect, _barPaint);

      // Peak-hold floating decay indicator cap
      if (isPlaying && isAnimated && normalized > 0.12) {
        final peakY = (y - 3.5).clamp(2.0, size.height - 4.0);
        final peakRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, peakY, barWidth, 2.0),
          const Radius.circular(1.0),
        );
        _peakPaint.color = color.withValues(alpha: 0.90);
        canvas.drawRRect(peakRect, _peakPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaterialYouSpectrumBarsPainter oldDelegate) {
    return oldDelegate.dsp != dsp ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.isAnimated != isAnimated ||
        oldDelegate.animVal != animVal ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.precomputedDb != precomputedDb;
  }
}

/// Fluid Waveform Ribbon Painter (Oscilloscope Ribbon reacting to transients & dynamics)
class _FluidWaveformRibbonPainter extends CustomPainter {
  _FluidWaveformRibbonPainter({
    required this.dsp,
    required this.isPlaying,
    required this.isAnimated,
    required this.animVal,
    required this.colorScheme,
    required this.gridColor,
    required this.precomputedDb,
  });

  final PowerampDspState dsp;
  final bool isPlaying;
  final bool isAnimated;
  final double animVal;
  final ColorScheme colorScheme;
  final Color gridColor;
  final List<double> precomputedDb;

  static final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _zeroPaint = Paint()..strokeWidth = 1.0;
  static final Path _path = Path();
  static final Path _fillPath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height * 0.52;
    _zeroPaint.color = gridColor;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), _zeroPaint);

    final width = size.width;
    const samplePoints = 36;
    final step = width / (samplePoints - 1);

    final wavePhase = animVal * 2.0 * math.pi;
    final bassEnergy = (dsp.bassGainDb > 0 ? dsp.bassGainDb / 10.0 : 0.0) + 1.0;
    final stereoSpread = 1.0 + (dsp.stereoExpansion * 0.5);

    _path.reset();
    _fillPath.reset();

    double firstY = midY;

    for (int i = 0; i < samplePoints; i++) {
      final x = i * step;
      final t = i / (samplePoints - 1);
      final dbIdx = ((t * (precomputedDb.length - 1)).round()).clamp(0, precomputedDb.length - 1);
      final db = precomputedDb[dbIdx];
      final dbFactor = math.pow(10.0, db / 40.0).toDouble().clamp(0.2, 2.5);

      double displacement = 0.0;
      if (isPlaying && isAnimated) {
        final sin1 = math.sin(wavePhase * 2.0 + t * 4.0 * math.pi) * 0.45;
        final sin2 = math.cos(wavePhase * 3.5 + t * 8.0 * math.pi) * 0.25 * stereoSpread;
        final sin3 = math.sin(wavePhase * 5.0 + t * 12.0 * math.pi) * 0.15;
        final transient = (sin1 + sin2 + sin3) * dbFactor * bassEnergy;
        displacement = transient * (size.height * 0.38);
      } else {
        displacement = math.sin(t * 2.0 * math.pi) * (db / 15.0) * (size.height * 0.25);
      }

      final y = (midY - displacement).clamp(8.0, size.height - 8.0);

      if (i == 0) {
        firstY = y;
        _path.moveTo(x, y);
        _fillPath.moveTo(x, y);
      } else {
        final prevX = (i - 1) * step;
        final controlX = (prevX + x) / 2.0;
        _path.cubicTo(controlX, firstY, controlX, y, x, y);
        _fillPath.cubicTo(controlX, firstY, controlX, y, x, y);
        firstY = y;
      }
    }

    _fillPath.lineTo(width, size.height);
    _fillPath.lineTo(0, size.height);
    _fillPath.close();

    // Translucent gradient fill under curve
    _fillPaint.shader = ui.Gradient.linear(
      Offset(0, midY * 0.5),
      Offset(0, size.height),
      [
        colorScheme.primary.withValues(alpha: 0.32),
        colorScheme.tertiary.withValues(alpha: 0.12),
        colorScheme.primary.withValues(alpha: 0.0),
      ],
      [0.0, 0.6, 1.0],
    );
    canvas.drawPath(_fillPath, _fillPaint);

    // Glowing dynamic stroke
    _linePaint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, 0),
      [
        colorScheme.primary,
        colorScheme.tertiary,
        colorScheme.secondary,
        colorScheme.primary,
      ],
      [0.0, 0.33, 0.67, 1.0],
    );
    canvas.drawPath(_path, _linePaint);
  }

  @override
  bool shouldRepaint(covariant _FluidWaveformRibbonPainter oldDelegate) {
    return oldDelegate.dsp != dsp ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.isAnimated != isAnimated ||
        oldDelegate.animVal != animVal ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.precomputedDb != precomputedDb;
  }
}

/// Concentric Vinyl Pulse Painter (Acoustic soundwaves rippling outward from center)
class _ConcentricVinylPulsePainter extends CustomPainter {
  _ConcentricVinylPulsePainter({
    required this.dsp,
    required this.isPlaying,
    required this.isAnimated,
    required this.animVal,
    required this.colorScheme,
    required this.gridColor,
    required this.precomputedDb,
  });

  final PowerampDspState dsp;
  final bool isPlaying;
  final bool isAnimated;
  final double animVal;
  final ColorScheme colorScheme;
  final Color gridColor;
  final List<double> precomputedDb;

  static final Paint _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  static final Paint _spindlePaint = Paint()..style = PaintingStyle.fill;
  static final Paint _holePaint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2.0, size.height / 2.0);
    final maxRadius = math.min(size.width, size.height) * 0.48;

    final bassDb = precomputedDb.isNotEmpty ? precomputedDb.first : 0.0;
    final bassEnergy = 1.0 +
        (dsp.bassGainDb > 0 ? (dsp.bassGainDb / 15.0) : 0.0) +
        (bassDb > 0 ? bassDb / 20.0 : 0.0);

    const ringCount = 6;
    for (int i = 0; i < ringCount; i++) {
      final ringProgress = (animVal + (i / ringCount)) % 1.0;
      final radius = 18.0 +
          (ringProgress *
              (maxRadius - 18.0) *
              (isPlaying && isAnimated ? bassEnergy : 1.0));
      final alpha = (1.0 - ringProgress).clamp(0.0, 1.0) *
          (isPlaying ? 0.85 : 0.25);

      _ringPaint.color = Color.lerp(
        colorScheme.primary,
        colorScheme.tertiary,
        ringProgress,
      )!
          .withValues(alpha: alpha);

      _ringPaint.strokeWidth = 1.2 + ((1.0 - ringProgress) * 2.2);
      canvas.drawCircle(center, radius.clamp(2.0, maxRadius * 1.2), _ringPaint);
    }

    // Vinyl Record Center Label / Core
    _spindlePaint.color = colorScheme.primaryContainer;
    canvas.drawCircle(center, 18.0, _spindlePaint);

    _holePaint.color = colorScheme.surfaceContainerLow;
    canvas.drawCircle(center, 5.0, _holePaint);

    if (isPlaying && isAnimated) {
      _ringPaint.color = colorScheme.primary.withValues(alpha: 0.9);
      _ringPaint.strokeWidth = 2.5;
      final pulseCoreRadius =
          18.0 + (math.sin(animVal * 2.0 * math.pi) * 2.5 * bassEnergy);
      canvas.drawCircle(center, pulseCoreRadius, _ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConcentricVinylPulsePainter oldDelegate) {
    return oldDelegate.dsp != dsp ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.isAnimated != isAnimated ||
        oldDelegate.animVal != animVal ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.precomputedDb != precomputedDb;
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.label,
    required this.onTap,
    this.isReset = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isReset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        PixelHaptics.tick();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isReset ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isReset ? cs.onPrimaryContainer : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Smart EQ Screen Alias
typedef SmartEqScreen = PowerampDspScreen;


