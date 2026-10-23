import 'package:flutter/services.dart';

/// Google Pixel X-Axis LRA Custom Haptics Service (`VibrationEffect.Composition`).
/// Dispatches rich hardware haptic primitives on Pixel / Android 11+ devices
/// with velocity throttling and universal fallback for all Android devices.
class PixelHaptics {
  static const MethodChannel _channel = MethodChannel('com.freebeat.app/dsp');
  static DateTime _lastMicroTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// When true (Power Saver Mode active), suppresses high-frequency micro-ticks
  /// and motor vibrations to cut battery current spikes.
  static bool powerSaverEnabled = false;

  /// Subtle micro-tick when rotating Bass/Treble/StereoX knobs, dragging 10-band EQ faders,
  /// or scrubbing the Squiggly Seekbar (`PRIMITIVE_LOW_TICK`).
  static Future<void> lowTick({double intensity = 0.45}) async {
    if (powerSaverEnabled) return;
    final now = DateTime.now();
    if (now.difference(_lastMicroTick).inMilliseconds < 24) return;
    _lastMicroTick = now;
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'low_tick',
        'intensity': intensity.clamp(0.2, 1.0),
      });
    } catch (_) {
      await HapticFeedback.selectionClick();
    }
  }

  /// Crisp tactile tick for filter chips, navigation tabs, and lyric line taps (`PRIMITIVE_TICK`).
  static Future<void> tick({double intensity = 0.70}) async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'tick',
        'intensity': intensity,
      });
    } catch (_) {
      await HapticFeedback.selectionClick();
    }
  }

  /// Medium impact feedback for long-press and secondary selections.
  static Future<void> medium() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'tick',
        'intensity': 0.85,
      });
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }

  /// Mechanical notch snap when crossing `0.0 dB` on Preamp/EQ faders or center L/R balance
  /// (`PRIMITIVE_CLICK` + `PRIMITIVE_TICK`).
  static Future<void> centerDetentSnap() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'detent_snap',
        'intensity': 0.90,
      });
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }

  /// Physical stop thud when hitting `±15.0 dB` EQ rail or `100%` rotary knob limit (`PRIMITIVE_THUD`).
  static Future<void> railLimitThud() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'rail_thud',
        'intensity': 0.85,
      });
    } catch (_) {
      await HapticFeedback.heavyImpact();
    }
  }

  /// Expressive Play/Pause morphing button click (`PRIMITIVE_CLICK` + `PRIMITIVE_QUICK_RISE`).
  static Future<void> playPauseToggle() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'play_toggle',
        'intensity': 0.80,
      });
    } catch (_) {
      await HapticFeedback.lightImpact();
    }
  }

  /// Rising spring sweep when expanding the MiniPlayer or opening the Signal Path Sheet
  /// (`PRIMITIVE_QUICK_RISE` + `PRIMITIVE_TICK`).
  static Future<void> sheetExpand() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'sheet_expand',
        'intensity': 0.75,
      });
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }

  /// Signature Pixel confirmation sweep when activating Hi-Fi Lossless mode or pinning offline
  /// (`PRIMITIVE_SLOW_RISE` + `PRIMITIVE_CLICK`).
  static Future<void> hifiConfirm() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'hifi_confirm',
        'intensity': 0.95,
      });
    } catch (_) {
      await HapticFeedback.heavyImpact();
    }
  }

  static DateTime _lastSwipeTick = DateTime.fromMillisecondsSinceEpoch(0);

  /// Progressive tactile load-up tick during horizontal swipe gestures.
  /// Throttled to ~28ms to prevent vibration engine saturation while scaling intensity
  /// proportionally to swipe progress (0.0 -> 1.0) for an authentic physical tension feel.
  static Future<void> swipeLoadTick({required double progress}) async {
    final now = DateTime.now();
    if (now.difference(_lastSwipeTick).inMilliseconds < 28) return;
    _lastSwipeTick = now;
    final clamped = progress.clamp(0.0, 1.0);
    final intensity = (0.22 + (0.48 * clamped)).clamp(0.20, 0.75);
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'low_tick',
        'intensity': intensity,
      });
    } catch (_) {
      await HapticFeedback.selectionClick();
    }
  }

  /// Sharp, satisfying mechanical "click" triggered the moment a track item
  /// is fully swiped past the activation threshold.
  static Future<void> swipeClick() async {
    try {
      await _channel.invokeMethod('triggerPixelHaptic', {
        'type': 'swipe_click',
        'intensity': 0.95,
      });
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }
}
