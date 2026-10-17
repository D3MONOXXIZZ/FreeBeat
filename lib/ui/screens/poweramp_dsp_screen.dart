import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/poweramp_dsp_state.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/rotary_knob.dart';

/// Poweramp-Grade 10-Band Equalizer, Preamp, Rotary Tone & Spatial DSP Studio.
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
    final playback = ref.watch(playbackProvider);
    final route = ref.watch(audioRouteInfoProvider);

    if (widget.isActive && playback.isPlaying && _animatedSpectrum) {
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
              'Poweramp DSP Studio',
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
                    kBuiltInDspPresets
                            .where((p) => p.id == dsp.activePresetId)
                            .map((p) => p.name)
                            .firstOrNull ??
                        'Custom Preset',
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
          // 2. Screen 8 Header Card: Connected Device & Animated Spectrum Toggle
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
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    // Connected Route Device Pill
                    Expanded(
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
                                color: cs.primary,
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
                            color: dsp.eqEnabled
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Transform.scale(
                          scale: 0.8,
                          child: Switch(
                            value: dsp.eqEnabled,
                            onChanged: notifier.toggleEq,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ───────────────────────────────────────────────────────────────────
          // 3. Dynamic Multi-Colored Rainbow Spectrum Visualizer Bars
          // ───────────────────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverToBoxAdapter(
              child: Container(
                height: 160,
                width: double.infinity,
                padding: const EdgeInsets.all(16),
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
                    AnimatedBuilder(
                      animation: _spectrumAnimController,
                      builder: (context, _) {
                        return CustomPaint(
                          size: Size.infinite,
                          painter: _MaterialYouSpectrumBarsPainter(
                            dsp: dsp,
                            isPlaying: playback.isPlaying,
                            isAnimated: _animatedSpectrum,
                            animVal: _spectrumAnimController.value,
                            trackPositionMs: playback.positionMs,
                            colorScheme: cs,
                            gridColor:
                                cs.outlineVariant.withValues(alpha: 0.20),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Text(
                        'PREAMP ${dsp.preampDb >= 0 ? "+" : ""}${dsp.preampDb.toStringAsFixed(1)} dB • 10-BAND DSP',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                    ),
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
                  ],
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ───────────────────────────────────────────────────────────────────
          // 4. Quick Presets Stadium Bar (Figma Screen 8)
          // ───────────────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _PresetChip(
                    label: 'Bass Boost',
                    isSelected: dsp.activePresetId == 'bass_boost',
                    onTap: () {
                      notifier.loadPresetById('bass_boost');
                    },
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'Vocal Air',
                    isSelected: dsp.activePresetId == 'vocal',
                    onTap: () {
                      notifier.loadPresetById('vocal');
                    },
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'Concert Hall',
                    isSelected: dsp.activePresetId == 'concert',
                    onTap: () {
                      notifier.loadPresetById('concert');
                    },
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'Audiophile Flat',
                    isSelected: dsp.activePresetId == 'flat',
                    onTap: () {
                      notifier.resetFlat();
                    },
                  ),
                  const SizedBox(width: 8),
                  _PresetChip(
                    label: 'Rock & Metal',
                    isSelected: dsp.activePresetId == 'rock',
                    onTap: () {
                      notifier.loadPresetById('rock');
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
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: SizedBox(
        height: 290,
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
                  const Expanded(
                    child: Text(
                      'Rotary Tone & Spatial Stage',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${dsp.toneFrequencyHz.toInt()} Hz Cutoff',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
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
                    child: Text(
                      'L/R Balance (${dsp.balance == 0 ? "Center" : dsp.balance.toStringAsFixed(2)})',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
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
              Text(
                'Playback Tempo / Speed (${dsp.tempo.toStringAsFixed(2)}x)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Slider(
                value: dsp.tempo,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                onChanged: notifier.setTempo,
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
                onChanged: (v) => ref
                    .read(audioQualityProvider.notifier)
                    .setCrossfadeDuration(v.round()),
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final presets = notifier.allPresets;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Poweramp & Audiophile EQ Presets',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final preset in presets)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  leading: Icon(
                    preset.id == dsp.activePresetId
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: preset.id == dsp.activePresetId
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    preset.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    preset.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () {
                    PixelHaptics.tick();
                    notifier.loadPresetById(preset.id);
                    Navigator.of(ctx).pop();
                  },
                ),
            ],
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
  });

  final String label;
  final bool isSelected;
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
          ),
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
    this.isPreamp = false,
    this.qFactor,
  });

  final String label;
  final double gainDb;
  final Color accentColor;
  final ValueChanged<double> onChanged;
  final VoidCallback onDoubleTapReset;
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
            Text(
              formattedDb,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: gainDb.abs() > 0.1 ? accentColor : cs.onSurfaceVariant,
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
            Text(
              label,
              style: TextStyle(
                fontSize: isPreamp ? 11 : 11.5,
                fontWeight: FontWeight.w800,
                color: isPreamp ? accentColor : cs.onSurface,
              ),
            ),
            if (qFactor != null)
              Text(
                'Q ${qFactor!.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurfaceVariant,
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
  const _MaterialYouSpectrumBarsPainter({
    required this.dsp,
    required this.isPlaying,
    required this.isAnimated,
    required this.animVal,
    required this.trackPositionMs,
    required this.colorScheme,
    required this.gridColor,
  });

  final PowerampDspState dsp;
  final bool isPlaying;
  final bool isAnimated;
  final double animVal;
  final int trackPositionMs;
  final ColorScheme colorScheme;
  final Color gridColor;

  Color _getBarColor(double t) {
    // Follow Material You dynamic color scheme across the frequency spectrum:
    // Bass (0.0 - 0.33): Primary -> Tertiary
    // Mids (0.33 - 0.66): Tertiary -> Secondary
    // Highs (0.66 - 1.0): Secondary -> PrimaryContainer
    if (t < 0.33) {
      final ratio = t / 0.33;
      return Color.lerp(colorScheme.primary, colorScheme.tertiary, ratio)!;
    } else if (t < 0.66) {
      final ratio = (t - 0.33) / 0.33;
      return Color.lerp(colorScheme.tertiary, colorScheme.secondary, ratio)!;
    } else {
      final ratio = (t - 0.66) / 0.34;
      return Color.lerp(
        colorScheme.secondary,
        colorScheme.primaryContainer,
        ratio,
      )!;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 24;
    final totalWidth = size.width;
    const barSpacing = 4.0;
    final barWidth = (totalWidth - (barSpacing * (barCount - 1))) / barCount;
    final cornerRadius = Radius.circular(barWidth / 2);

    // Draw subtle 0 dB reference line
    final midY = size.height * 0.55;
    final zeroPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), zeroPaint);

    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);

    for (int i = 0; i < barCount; i++) {
      final t = i / (barCount - 1);
      final color = _getBarColor(t);

      // Map frequency logarithmically (20Hz to 20,000Hz)
      final freq = math.exp(minLog + t * (maxLog - minLog));
      final db = dsp.evaluateResponseAtFrequency(freq);

      // Base normalized height from dB (-15dB to +15dB)
      // When EQ is flat (0 dB across all bands), db == 0 -> normalized == 0.5
      double normalized = ((db + 15.0) / 30.0).clamp(0.08, 0.95);

      // Follow playing frequencies rather than a random animation loop:
      if (isPlaying && isAnimated) {
        final posSec = trackPositionMs / 1000.0;
        double dynamicEnergy = 0.0;

        if (t < 0.25) {
          // Sub-bass & Bass region (< 250Hz):
          // Pulsing rhythmic energy synchronized with musical beat & bass boost
          final beat =
              math.sin((posSec * 2.2 * math.pi) + (i * 0.2)) * 0.5 + 0.5;
          final bassWeight =
              1.0 + (dsp.bassGainDb > 0 ? (dsp.bassGainDb / 12.0) : 0.0);
          dynamicEnergy = math.pow(beat, 1.8) * 0.16 * bassWeight;
        } else if (t < 0.65) {
          // Midrange vocal & instrument fundamental region (250Hz - 2500Hz):
          // Harmonic wave motion across musical phrases
          final phase = (posSec * 3.4) + (i * 0.65);
          final midMotion =
              (math.sin(phase) * 0.07) + (math.cos(phase * 1.7) * 0.05);
          dynamicEnergy = midMotion;
        } else {
          // Treble, Presence & Air region (> 2500Hz):
          // High frequency transients and cymbal sparkle
          final treblePhase = (posSec * 5.2) + (i * 1.3);
          final trebleWeight =
              1.0 + (dsp.trebleGainDb > 0 ? (dsp.trebleGainDb / 12.0) : 0.0);
          final trebleFlutter = (math.sin(treblePhase * 1.8) * 0.06 +
              math.cos(treblePhase * 2.5) * 0.04);
          dynamicEnergy = trebleFlutter * trebleWeight;
        }

        // Modulate by user's EQ response: boost in this frequency amplifies the dynamic bar
        final gainMultiplier = math.pow(10.0, db / 35.0);
        normalized =
            (normalized + (dynamicEnergy * gainMultiplier)).clamp(0.06, 1.0);
      }

      final barHeight = normalized * (size.height * 0.84);
      final x = i * (barWidth + barSpacing);
      final y = size.height - barHeight;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        cornerRadius,
      );

      final barPaint = Paint()..color = color;
      canvas.drawRRect(rrect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MaterialYouSpectrumBarsPainter oldDelegate) {
    return oldDelegate.dsp != dsp ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.isAnimated != isAnimated ||
        oldDelegate.animVal != animVal ||
        oldDelegate.trackPositionMs != trackPositionMs ||
        oldDelegate.colorScheme != colorScheme;
  }
}
