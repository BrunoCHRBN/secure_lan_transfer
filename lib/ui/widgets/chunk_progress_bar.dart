import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/transfer_progress.dart';

/// Chunk Sliding Window Pipeline & Progress Visualizer.
class ChunkProgressBar extends StatelessWidget {
  final int transferredBytes;
  final int totalBytes;
  final int chunkSize;
  final int creditWindowSize;
  final bool isPaused;

  const ChunkProgressBar({
    super.key,
    required this.transferredBytes,
    required this.totalBytes,
    this.chunkSize = 65536, // 64 KB
    this.creditWindowSize = 4,
    this.isPaused = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final double fraction = totalBytes > 0
        ? (transferredBytes / totalBytes).clamp(0.0, 1.0)
        : 0.0;
    final int totalChunks =
        totalBytes > 0 ? (totalBytes / chunkSize).ceil() : 0;
    final int verifiedChunks =
        chunkSize > 0 ? (transferredBytes / chunkSize).floor() : 0;
    final int inFlightChunks = (fraction >= 1.0 || isPaused || totalChunks == 0)
        ? 0
        : math.min(creditWindowSize, totalChunks - verifiedChunks);

    final double inFlightFraction = totalChunks > 0
        ? (inFlightChunks / totalChunks).clamp(0.0, 1.0 - fraction)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Upper Chunk Pipeline Sliding Window
        Container(
          height: 16,
          decoration: BoxDecoration(
            color:
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              children: [
                // In-Flight chunks segment (pulsing / accent)
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (fraction + inFlightFraction).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isPaused
                          ? Colors.amber.withValues(alpha: 0.5)
                          : colorScheme.tertiary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                // Verified committed chunks segment (primary)
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary.withValues(alpha: 0.85),
                          colorScheme.primary,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Readout Stats
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(fraction * 100).toStringAsFixed(1)}% (${TransferProgress.formatBytes(transferredBytes)} / ${TransferProgress.formatBytes(totalBytes)})',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Row(
              children: [
                // Pipeline badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPaused
                        ? Colors.amber.withValues(alpha: 0.2)
                        : colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isPaused
                        ? 'PAUSED'
                        : '$inFlightChunks in flight ($creditWindowSize slot window)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isPaused
                          ? Colors.amber
                          : colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Chunks: $verifiedChunks / $totalChunks committed • Backpressure: ${isPaused ? "Paused" : "Optimal"}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
