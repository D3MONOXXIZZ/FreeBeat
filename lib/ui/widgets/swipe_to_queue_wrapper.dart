import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/track.dart';
import '../../services/haptics/pixel_haptics.dart';
import '../../state/app_providers.dart';

/// A Material You wrapper that allows swiping horizontally on any track list item
/// to append the track to the playback queue (or perform custom secondary actions)
/// with realistic physical spring resistance, progressive tactile load-up ticks,
/// and a crisp mechanical click haptic when fully swiped.
class SwipeToQueueWrapper extends ConsumerStatefulWidget {
  const SwipeToQueueWrapper({
    super.key,
    required this.track,
    required this.child,
    this.borderRadius,
    this.onQueued,
    this.enableSecondaryAction = false,
    this.secondaryActionTitle = 'Remove',
    this.secondaryActionIcon = Icons.delete_outline_rounded,
    this.onSecondaryAction,
    this.dismissOnSecondaryAction = false,
    this.primaryActionTitle = 'Add to Queue',
    this.primaryActionIcon = Icons.queue_music_rounded,
    this.onPrimaryAction,
    this.dismissOnPrimaryAction = false,
    this.enabled = true,
  });

  final Track track;
  final Widget child;
  final BorderRadius? borderRadius;
  final VoidCallback? onQueued;
  final bool enableSecondaryAction;
  final String secondaryActionTitle;
  final IconData secondaryActionIcon;
  final VoidCallback? onSecondaryAction;
  final bool dismissOnSecondaryAction;
  final String primaryActionTitle;
  final IconData primaryActionIcon;
  final VoidCallback? onPrimaryAction;
  final bool dismissOnPrimaryAction;
  final bool enabled;

  /// Shows a unified Material You floating confirmation SnackBar when a track is queued.
  static void showQueuedSnackBar(BuildContext context, String trackTitle) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.onPrimaryContainer.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.queue_music_rounded,
                color: cs.onPrimaryContainer,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Added "$trackTitle" to queue',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: cs.primaryContainer,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  @override
  ConsumerState<SwipeToQueueWrapper> createState() => _SwipeToQueueWrapperState();
}

class _SwipeToQueueWrapperState extends ConsumerState<SwipeToQueueWrapper>
    with SingleTickerProviderStateMixin {
  AnimationController? _animController;
  Animation<double>? _snapAnimation;

  double _dragOffset = 0.0;
  double _effectiveOffset = 0.0;
  bool _hasTriggeredClick = false;
  int _lastMilestone = 0;
  bool _isDismissed = false;

  static const double _kActivationThreshold = 80.0;

  AnimationController _ensureAnimController() {
    _animController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (_snapAnimation != null) {
          setState(() {
            _effectiveOffset = _snapAnimation!.value;
          });
        }
      });
    return _animController!;
  }

  @override
  void dispose() {
    _animController?.dispose();
    super.dispose();
  }

  /// Calculates smooth, direct finger movement offset without rubber-band spring resistance.
  double _computeResistedOffset(double raw) {
    if (raw == 0) return 0;
    return raw;
  }

  void _handleDragStart(DragStartDetails details) {
    if (_isDismissed) return;
    _animController?.stop();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_isDismissed) return;
    final delta = details.primaryDelta ?? 0;
    _dragOffset += delta;

    // Disallow left swipe if secondary action is not configured
    if (!widget.enableSecondaryAction && _dragOffset < 0) {
      _dragOffset = 0;
    }

    final newEffective = _computeResistedOffset(_dragOffset);
    final absEffective = newEffective.abs();
    final progress = (absEffective / _kActivationThreshold).clamp(0.0, 1.0);

    // 4 Progressive load-up tactile tension milestones: 0.22, 0.45, 0.70, 0.88
    final milestone = progress >= 0.88
        ? 4
        : progress >= 0.70
            ? 3
            : progress >= 0.45
                ? 2
                : progress >= 0.22
                    ? 1
                    : 0;

    if (milestone > _lastMilestone && !_hasTriggeredClick) {
      _lastMilestone = milestone;
      PixelHaptics.swipeLoadTick(progress: progress);
    } else if (milestone < _lastMilestone && progress < 0.80) {
      _lastMilestone = milestone;
    }

    // Crisp mechanical click haptic when fully swiped!
    if (progress >= 1.0 && !_hasTriggeredClick) {
      _hasTriggeredClick = true;
      _lastMilestone = 5;
      PixelHaptics.swipeClick();
    } else if (progress < 0.75 && _hasTriggeredClick) {
      _hasTriggeredClick = false;
      PixelHaptics.lowTick(intensity: 0.20);
    }

    setState(() {
      _effectiveOffset = newEffective;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_isDismissed) return;
    final velocity = details.primaryVelocity ?? 0;

    final wasFlingRight = velocity > 550 && _dragOffset > 30;
    final wasFlingLeft =
        widget.enableSecondaryAction && velocity < -550 && _dragOffset < -30;

    final triggeredRight =
        (_hasTriggeredClick && _effectiveOffset > 0) || wasFlingRight;
    final triggeredLeft = widget.enableSecondaryAction &&
        ((_hasTriggeredClick && _effectiveOffset < 0) || wasFlingLeft);

    if (triggeredRight) {
      if (!_hasTriggeredClick) {
        PixelHaptics.swipeClick();
      }
      if (widget.dismissOnPrimaryAction) {
        _animateDismissOut(isRight: true);
      } else {
        _executePrimaryAction();
        _animateSnapBack();
      }
    } else if (triggeredLeft) {
      if (!_hasTriggeredClick) {
        PixelHaptics.swipeClick();
      }
      if (widget.dismissOnSecondaryAction) {
        _animateDismissOut(isRight: false);
      } else {
        widget.onSecondaryAction?.call();
        _animateSnapBack();
      }
    } else {
      _animateSnapBack();
    }
  }

  void _handleDragCancel() {
    if (_isDismissed) return;
    _animateSnapBack();
  }

  void _executePrimaryAction() {
    if (widget.onPrimaryAction != null) {
      widget.onPrimaryAction!();
    } else {
      ref.read(playbackProvider.notifier).addToQueue(widget.track);
      PixelHaptics.hifiConfirm();
      if (context.mounted) {
        SwipeToQueueWrapper.showQueuedSnackBar(context, widget.track.title);
      }
      widget.onQueued?.call();
    }
  }

  void _animateSnapBack() {
    final controller = _ensureAnimController();
    _snapAnimation = Tween<double>(
      begin: _effectiveOffset,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      ),
    );
    controller.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = 0.0;
          _effectiveOffset = 0.0;
          _hasTriggeredClick = false;
          _lastMilestone = 0;
          _snapAnimation = null;
        });
      }
    });
  }

  void _animateDismissOut({required bool isRight}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final target = isRight ? screenWidth : -screenWidth;
    final controller = _ensureAnimController();
    _snapAnimation = Tween<double>(
      begin: _effectiveOffset,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: controller,
        curve: Curves.easeInCubic,
      ),
    );
    controller.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _isDismissed = true;
        });
        if (isRight) {
          _executePrimaryAction();
        } else {
          widget.onSecondaryAction?.call();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isDismissed) {
      return const SizedBox.shrink();
    }
    if (!widget.enabled) {
      return widget.child;
    }

    final cs = Theme.of(context).colorScheme;
    final isSwipingRight = _effectiveOffset > 0;
    final absOffset = _effectiveOffset.abs();
    final progress = (absOffset / _kActivationThreshold).clamp(0.0, 1.0);

    // Dynamic icon load-up scale: expands from 0.75 -> 1.10, popping to 1.20 when armed
    final iconScale = _hasTriggeredClick ? 1.20 : (0.75 + (0.35 * progress));

    final isIdle = absOffset <= 0.001;

    final content = isIdle
        ? widget.child
        : Stack(
            clipBehavior: Clip.none,
            children: [
              // Background container with load-up visual indicators, clipped strictly to uncovered gap
              if (absOffset > 0.5)
                Positioned.fill(
                  child: ClipRect(
                    clipper: _SwipeBackgroundClipper(offset: _effectiveOffset),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSwipingRight
                            ? cs.primaryContainer.withValues(
                                alpha: (0.40 + (0.60 * progress)).clamp(0.0, 1.0),
                              )
                            : cs.errorContainer.withValues(
                                alpha: (0.40 + (0.60 * progress)).clamp(0.0, 1.0),
                              ),
                        borderRadius: widget.borderRadius,
                      ),
                      alignment: isSwipingRight
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: isSwipingRight
                            ? [
                                Transform.scale(
                                  scale: iconScale,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: cs.onPrimaryContainer.withValues(
                                        alpha: _hasTriggeredClick
                                            ? 0.28
                                            : (0.10 + (0.15 * progress)),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      widget.primaryActionIcon,
                                      color: cs.onPrimaryContainer,
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Opacity(
                                  opacity:
                                      ((progress - 0.20) / 0.70).clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset((1.0 - progress) * -12.0, 0),
                                    child: Text(
                                      widget.primaryActionTitle,
                                      style: TextStyle(
                                        color: cs.onPrimaryContainer,
                                        fontWeight: _hasTriggeredClick
                                            ? FontWeight.w900
                                            : FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ]
                            : [
                                Opacity(
                                  opacity:
                                      ((progress - 0.20) / 0.70).clamp(0.0, 1.0),
                                  child: Transform.translate(
                                    offset: Offset((1.0 - progress) * 12.0, 0),
                                    child: Text(
                                      widget.secondaryActionTitle,
                                      style: TextStyle(
                                        color: cs.onErrorContainer,
                                        fontWeight: _hasTriggeredClick
                                            ? FontWeight.w900
                                            : FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Transform.scale(
                                  scale: iconScale,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: cs.onErrorContainer.withValues(
                                        alpha: _hasTriggeredClick
                                            ? 0.28
                                            : (0.10 + (0.15 * progress)),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      widget.secondaryActionIcon,
                                      color: cs.onErrorContainer,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ],
                      ),
                    ),
                  ),
                ),

              // Sliding track tile child
              Transform.translate(
                offset: Offset(_effectiveOffset, 0),
                child: widget.child,
              ),
            ],
          );

    return GestureDetector(
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onHorizontalDragCancel: _handleDragCancel,
      behavior: HitTestBehavior.translucent,
      child: content,
    );
  }
}

class _SwipeBackgroundClipper extends CustomClipper<Rect> {
  const _SwipeBackgroundClipper({required this.offset});

  final double offset;

  @override
  Rect getClip(Size size) {
    if (offset > 0) {
      return Rect.fromLTWH(0, 0, offset, size.height);
    } else if (offset < 0) {
      return Rect.fromLTWH(size.width + offset, 0, -offset, size.height);
    }
    return Rect.zero;
  }

  @override
  bool shouldReclip(_SwipeBackgroundClipper oldClipper) =>
      oldClipper.offset != offset;
}
