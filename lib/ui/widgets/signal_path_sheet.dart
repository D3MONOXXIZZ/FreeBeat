import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/audio_quality_settings.dart';
import '../../state/app_providers.dart';

/// Smart EQ Live Audio Signal Path Inspector & On-the-Fly Bitrate Switcher Sheet.
/// Shows the real-time 4-stage audio pipeline:
/// 1. Cloud Source -> 2. Stream Decoder/Bitrate -> 3. 64-bit Smart EQ DSP -> 4. Android / Bluetooth Output
class SignalPathSheet extends ConsumerWidget {
  const SignalPathSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final track = playback.currentTrack;
    final qualityConfig = ref.watch(audioQualityProvider);
    final activeTier = qualityConfig.effectiveStreamingTier;
    final dsp = ref.watch(powerampDspProvider);
    final routeAsync = ref.watch(audioOutputRouteProvider);
    final route = routeAsync.valueOrNull ?? const AudioOutputRouteInfo();

    final effectiveCodec =
        activeTier.isLossless ? track.codec : activeTier.codec;
    final effectiveKbps =
        activeTier.isLossless ? track.bitrateKbps : activeTier.kbps;
    final effectiveDepth =
        activeTier.isLossless ? track.bitDepth : activeTier.bitDepth;
    final effectiveRateKhz =
        ((activeTier.isLossless ? track.sampleRateHz : activeTier.sampleRateHz) /
                1000.0)
            .toStringAsFixed(1);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.graphic_eq_rounded, color: cs.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Audio Signal Path & Bitrate',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        activeTier.isLossless
                            ? 'Bit-Perfect Lossless Pipeline Active'
                            : 'Adaptive Cloud Transcode Pipeline (${activeTier.label})',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    activeTier.shortBadge,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 4-Stage Signal Chain Nodes
            _SignalNodeCard(
              stepNumber: '1',
              title: 'Cloud Storage Source',
              subtitle:
                  '${track.providerType.displayName} • ${track.isPinnedOffline ? "Pinned Local Cache (0ms)" : "Loopback Proxy 127.0.0.1 (Range 206)"}',
              badge: track.providerType.displayName.toUpperCase(),
              icon: track.providerType.icon,
              accentColor: track.providerType.accentColor,
            ),
            _SignalConnectorLine(color: cs.primary),
            _SignalNodeCard(
              stepNumber: '2',
              title: 'Stream Container & Decoder',
              subtitle:
                  '$effectiveCodec • $effectiveDepth-bit / $effectiveRateKhz kHz • $effectiveKbps kbps Stereo',
              badge: activeTier.isLossless ? 'HI-RES LOSSLESS' : '$effectiveKbps KBPS',
              icon: Icons.high_quality_rounded,
              accentColor: cs.tertiary,
            ),
            _SignalConnectorLine(color: cs.primary),
            _SignalNodeCard(
              stepNumber: '3',
              title: 'Smart EQ 64-Bit DSP Engine',
              subtitle: dsp.bitPerfectDirectMode
                  ? 'Bit-Perfect Direct Hardware Mode\nAll DSP filters, tone shelves, and limiters bypassed for pure bit-for-bit PCM audio output to DAC.'
                  : '${route.dspEngineMode}\nPreamp: ${dsp.preampDb >= 0 ? "+" : ""}${dsp.preampDb.toStringAsFixed(1)} dB • 10-Band EQ: ${dsp.eqEnabled ? "ON" : "BYPASS"} • Crossfeed: ${dsp.bs2bCrossfeedMode.label} • Headroom: ${dsp.dvcHeadroomDb.toStringAsFixed(1)} dB',
              badge: dsp.bitPerfectDirectMode
                  ? 'BIT-PERFECT DIRECT'
                  : (dsp.eqEnabled ? '10-BAND EQ' : 'DIRECT BYPASS'),
              icon: dsp.bitPerfectDirectMode
                  ? Icons.album_rounded
                  : Icons.tune_rounded,
              accentColor: dsp.bitPerfectDirectMode
                  ? const Color(0xFFFFB74D)
                  : cs.primary,
            ),
            _SignalConnectorLine(color: cs.primary),
            _SignalNodeCard(
              stepNumber: '4',
              title: 'Hardware Output & Bluetooth Codec',
              subtitle:
                  '${route.deviceName}\nCodec: ${route.bluetoothCodecName} • ${route.hardwareBitDepth}-bit / ${route.formattedSampleRate} (${route.hardwareBufferFrames} frames)',
              badge: route.routeType,
              icon: route.isBluetooth
                  ? Icons.bluetooth_audio_rounded
                  : route.isUsbDac
                      ? Icons.album_rounded
                      : Icons.speaker_group_rounded,
              accentColor: cs.secondary,
            ),

            const SizedBox(height: 20),

            // 1-Tap Bit-Perfect Direct Hardware DAC Mode Switch
            Card(
              elevation: 0,
              color: dsp.bitPerfectDirectMode
                  ? const Color(0xFFFFB74D).withValues(alpha: 0.15)
                  : cs.surfaceContainerHigh,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: dsp.bitPerfectDirectMode
                      ? const Color(0xFFFFB74D)
                      : Colors.transparent,
                  width: 1.2,
                ),
              ),
              child: SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  'Bit-Perfect Direct USB DAC Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: dsp.bitPerfectDirectMode
                        ? const Color(0xFFFFB74D)
                        : cs.onSurface,
                  ),
                ),
                subtitle: Text(
                  'Bypasses all DSP filtering, tone shelves, and limiters for pure bit-for-bit master PCM DAC output.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                value: dsp.bitPerfectDirectMode,
                activeThumbColor: const Color(0xFFFFB74D),
                activeTrackColor: const Color(0xFFFFB74D).withValues(alpha: 0.45),
                onChanged: (val) {
                  ref
                      .read(powerampDspProvider.notifier)
                      .toggleBitPerfectDirectMode(val);
                },
              ),
            ),

            const SizedBox(height: 24),
            Text(
              'Switch Live Streaming Bitrate Tier',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AudioQualityTier.values.map((tier) {
                final selected = tier == activeTier;
                return ChoiceChip(
                  selected: selected,
                  label: Text(
                    tier.isLossless
                        ? 'Hi-Fi Lossless (24-Bit/192kHz)'
                        : '${tier.label} (${tier.kbps}k ${tier.codec})',
                  ),
                  onSelected: (_) {
                    ref
                        .read(audioQualityProvider.notifier)
                        .setLiveStreamTierOverride(tier);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalNodeCard extends StatelessWidget {
  const _SignalNodeCard({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.accentColor,
  });

  final String stepNumber;
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accentColor.withValues(alpha: 0.2),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalConnectorLine extends StatelessWidget {
  const _SignalConnectorLine({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 33),
      child: Container(
        width: 2.5,
        height: 14,
        color: color.withValues(alpha: 0.45),
      ),
    );
  }
}
