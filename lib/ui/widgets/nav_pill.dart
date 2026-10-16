import 'package:flutter/material.dart';
import '../../services/haptics/pixel_haptics.dart';
import 'expressive_shapes.dart';

/// Navigation Destination definition for [MaterialYouNavPill].
class NavPillDestination {
  const NavPillDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating Material 3 Expressive Navigation Pill Bar.
/// Strictly implements the floating capsule / stadium pill bottom navigation
/// seen in Google Pixel and modern Material You music interfaces.
/// Features:
/// - Stadium border (BorderRadius.circular(100)).
/// - Smooth animated active pill indicator with Curves.easeOutCubic.
/// - Tactile spring press compression and Pixel haptic ticks.
/// - M3 tonal elevation and surface tint without harsh black shadows.
class MaterialYouNavPill extends StatelessWidget {
  const MaterialYouNavPill({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavPillDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 66,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (int i = 0; i < destinations.length; i++)
              _NavPillItem(
                destination: destinations[i],
                isSelected: selectedIndex == i,
                onTap: () {
                  PixelHaptics.tick(intensity: 0.70);
                  onDestinationSelected(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NavPillItem extends StatelessWidget {
  const _NavPillItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final NavPillDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: SpringPressScale(
        onTap: onTap,
        child: Container(
          color: Colors.transparent, // Expand touch target
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: isSelected ? 56 : 40,
                height: 30,
                decoration: BoxDecoration(
                  color: isSelected ? cs.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Center(
                  child: Icon(
                    isSelected ? destination.selectedIcon : destination.icon,
                    size: 21,
                    color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
                  letterSpacing: -0.2,
                ),
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Google Pixel Android Gesture Navigation Pill Indicator.
/// Renders the signature centered gesture handle / home bar pill at the bottom edge.
class AndroidGestureHandle extends StatelessWidget {
  const AndroidGestureHandle({
    super.key,
    this.width = 72,
    this.height = 4.5,
    this.margin = const EdgeInsets.only(top: 8, bottom: 8),
  });

  final double width;
  final double height;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: cs.onSurface.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(100),
        ),
      ),
    );
  }
}
