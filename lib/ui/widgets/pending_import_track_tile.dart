import 'package:flutter/material.dart';
import '../../state/app_providers.dart';

class PendingImportTrackTile extends StatelessWidget {
  const PendingImportTrackTile({super.key, required this.item});

  final PendingImportTrack item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Opacity(
      opacity: item.isCompleted ? 0.95 : 0.60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Album art container with circular progress indicator
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.isCompleted
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Center(
                child: item.isCompleted
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: cs.onPrimaryContainer,
                        size: 26,
                      )
                    : SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: item.progress > 0 ? item.progress : null,
                          strokeWidth: 2.8,
                          color: cs.primary,
                          backgroundColor:
                              cs.outlineVariant.withValues(alpha: 0.30),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: item.isCompleted
                          ? cs.onSurface
                          : cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.isCompleted ? '${item.artist} • Ready' : item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: item.isCompleted ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: item.isCompleted
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.isCompleted)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: cs.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Ready',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              )
            else if (item.progress > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${(item.progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
