import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/poweramp_dsp_state.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';
import '../widgets/expressive_shapes.dart';
import '../widgets/rotary_knob.dart';

/// Poweramp-Grade 10-Band Equalizer, Preamp, Rotary Tone & Spatial DSP Studio.
class PowerampDspScreen extends ConsumerStatefulWidget {
  const PowerampDspScreen({super.key});

  @override
  ConsumerState<PowerampDspScreen> createState() => _PowerampDspScreenState();
}

class _PowerampDspScreenState extends ConsumerState<PowerampDspScreen> {
  int _subTab = 0; // 0: Preamp + 10-Band EQ, 1: Tone / Stereo X / Balance / Tempo

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dsp = ref.watch(powerampDspProvider);
    final notifier = ref.read(powerampDspProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 140),
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header & Preset Picker Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Poweramp DSP Studio',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    Text(
                      '64-Bit Float • Preamp + 10-Band ISO EQ + Hardware Limiter',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showPresetPickerSheet(context, dsp, notifier),
                icon: const Icon(Icons.bookmarks_rounded, size: 16),
                label: Text(
                  kBuiltInDspPresets
                      .where((p) => p.id == dsp.activePresetId)
                      .map((p) => p.name)
                      .firstOrNull ??
                      'Custom Preset',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Top Hardware Power Toggles: EQ, TONE, LIMITER, DVC, FLAT
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('EQ'),
                  selected: dsp.eqEnabled,
                  onSelected: notifier.toggleEq,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('TONE'),
                  selected: dsp.toneEnabled,
                  onSelected: notifier.toggleTone,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('LIMITER'),
                  selected: dsp.limiterEnabled,
                  onSelected: notifier.toggleLimiter,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('DVC'),
                  selected: dsp.dvcEnabled,
                  onSelected: notifier.toggleDvc,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('Reset Flat'),
                  onPressed: notifier.resetFlat,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Interactive Frequency Response Spline Graph (20 Hz – 20 kHz)
          Container(
            height: 155,
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: dsp.isClippingRisk
                    ? Colors.redAccent
                    : cs.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.infinite,
                  painter: _FrequencyResponseSplinePainter(
                    dsp: dsp,
                    lineColor: cs.primary,
                    gridColor: cs.onSurfaceVariant.withValues(alpha: 0.18),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 4,
                  child: Text(
                    'PREAMP ${dsp.preampDb >= 0 ? "+" : ""}${dsp.preampDb.toStringAsFixed(1)} dB • PEAK ${dsp.maxPeakDb >= 0 ? "+" : ""}${dsp.maxPeakDb.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                    ),
                  ),
                ),
                if (dsp.isClippingRisk)
                  Positioned(
                    top: 0,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'CLIPPING RISK (ENABLE LIMITER)',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 4. Sub-Tab Switcher: [Preamp + 10-Band EQ] vs [Rotary Tone & Stereo X]
          Row(
            children: [
              Expanded(
                child: PixelFilterPill(
                  label: 'Preamp + 10-Band EQ',
                  isSelected: _subTab == 0,
                  icon: Icons.equalizer_rounded,
                  onTap: () => setState(() => _subTab = 0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PixelFilterPill(
                  label: 'Tone Knobs & Stereo X',
                  isSelected: _subTab == 1,
                  icon: Icons.radio_button_checked_rounded,
                  onTap: () => setState(() => _subTab = 1),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (_subTab == 0)
            _buildPreampAnd10BandFaders(context, dsp, notifier)
          else
            _buildRotaryToneAndSpatialControls(context, dsp, notifier),
        ],
      ),
    );
  }

  Widget _buildPreampAnd10BandFaders(
    BuildContext context,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'PREAMP & 10-BAND GRAPHIC / PARAMETRIC EQ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Double-tap: 0 dB',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 270,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dedicated Leftmost PREAMP Fader
                  _VerticalEqFaderColumn(
                    label: 'PREAMP',
                    gainDb: dsp.preampDb,
                    isPreamp: true,
                    accentColor: cs.tertiary,
                    onChanged: notifier.setPreampDb,
                    onDoubleTapReset: () => notifier.setPreampDb(0.0),
                  ),
                  Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 20,
                    ),
                    color: cs.outlineVariant.withValues(alpha: 0.35),
                  ),
                  // 10 ISO Band Faders (31Hz -> 16kHz)
                  for (int i = 0; i < dsp.bands.length; i++)
                    _VerticalEqFaderColumn(
                      label: dsp.bands[i].frequencyLabel,
                      gainDb: dsp.bands[i].gainDb,
                      qFactor: dsp.bands[i].qFactor,
                      accentColor: cs.primary,
                      onChanged: (val) => notifier.setBandGain(i, val),
                      onDoubleTapReset: () => notifier.setBandGain(i, 0.0),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRotaryToneAndSpatialControls(
    BuildContext context,
    PowerampDspState dsp,
    PowerampDspNotifier notifier,
  ) {
    final cs = Theme.of(context).colorScheme;
    final quality = ref.watch(audioQualityProvider);

    return Column(
      children: [
        // 1. Three Poweramp Tactile Rotary Knobs: BASS, TREBLE, STEREO X
        Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              PowerampRotaryKnob(
                label: 'BASS TONE',
                subtitle: '${dsp.bassFreqHz.toInt()} Hz Low-Shelf',
                value: dsp.bassGain,
                accentColor: cs.primary,
                onChanged: notifier.setBassTone,
              ),
              PowerampRotaryKnob(
                label: 'TREBLE AIR',
                subtitle: '${(dsp.trebleFreqHz / 1000).toInt()} kHz High-Shelf',
                value: dsp.trebleGain,
                accentColor: cs.tertiary,
                onChanged: notifier.setTrebleTone,
              ),
              PowerampRotaryKnob(
                label: 'STEREO X',
                subtitle: 'Mid/Side Width',
                value: dsp.stereoExpansion,
                accentColor: cs.secondary,
                onChanged: notifier.setStereoExpansion,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Balance, Mono, Tempo & Crossfade Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'L/R Channel Balance (${dsp.balance == 0 ? "Center" : dsp.balance.toStringAsFixed(2)})',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      const Text('Mono Mix', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Switch(
                        value: dsp.monoMix,
                        onChanged: notifier.toggleMonoMix,
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
              const SizedBox(height: 8),
              Text(
                'Playback Tempo / Speed (${dsp.tempo.toStringAsFixed(2)}x)',
                style: const TextStyle(
                  fontSize: 13.5,
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
              const SizedBox(height: 8),
              Text(
                'Gapless Crossfade (${(quality.crossfadeDurationMs / 1000).toStringAsFixed(1)}s)',
                style: const TextStyle(
                  fontSize: 13.5,
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
              const SizedBox(height: 8),
              const Text(
                'Acoustic Room Reverb',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
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
      builder: (ctx) {
        final presets = notifier.allPresets;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
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
                  ),
                  title: Text(
                    preset.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${preset.category} • Preamp ${preset.preampDb >= 0 ? "+" : ""}${preset.preampDb} dB',
                  ),
                  onTap: () {
                    notifier.applyPreset(preset);
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

class _FrequencyResponseSplinePainter extends CustomPainter {
  _FrequencyResponseSplinePainter({
    required this.dsp,
    required this.lineColor,
    required this.gridColor,
  });

  final PowerampDspState dsp;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;

    // 0 dB center reference line
    final zeroPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), zeroPaint);

    final path = Path();
    final fillPath = Path();
    const steps = 90;
    final minLog = math.log(20.0);
    final maxLog = math.log(20000.0);

    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final freq = math.exp(minLog + t * (maxLog - minLog));
      final db = dsp.evaluateResponseAtFrequency(freq);
      final x = t * size.width;
      final y = (midY - (db / 18.0) * (size.height * 0.44))
          .clamp(4.0, size.height - 4.0);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final gradientPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          lineColor.withValues(alpha: 0.36),
          lineColor.withValues(alpha: 0.02),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);

    canvas.drawPath(fillPath, gradientPaint);

    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _FrequencyResponseSplinePainter oldDelegate) {
    return oldDelegate.dsp != dsp || oldDelegate.lineColor != lineColor;
  }
}
