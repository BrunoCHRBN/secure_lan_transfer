import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/crypto/sas_authenticator.dart';
import '../theme/app_theme.dart';

/// 8x8 Deterministic Identicon Matrix Custom Painter.
class IdenticonPainter extends CustomPainter {
  final Uint8List hash;
  final Color primaryColor;
  final Color backgroundColor;

  IdenticonPainter({
    required this.hash,
    required this.primaryColor,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = backgroundColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(8),
      ),
      bgPaint,
    );

    final cellWidth = size.width / 8;
    final cellHeight = size.height / 8;
    final cellPaint = Paint()..color = primaryColor;

    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 4; x++) {
        final byteIndex = (y * 4 + x) % (hash.isNotEmpty ? hash.length : 1);
        final val = hash.isNotEmpty ? hash[byteIndex] : 0;
        final isFilled = (val & (1 << (x % 8))) != 0;

        if (isFilled) {
          // Left half
          final leftRect = Rect.fromLTWH(
            x * cellWidth + 1,
            y * cellHeight + 1,
            cellWidth - 2,
            cellHeight - 2,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(leftRect, const Radius.circular(2)),
            cellPaint,
          );

          // Symmetrical right half (mirror)
          final rightRect = Rect.fromLTWH(
            (7 - x) * cellWidth + 1,
            y * cellHeight + 1,
            cellWidth - 2,
            cellHeight - 2,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rightRect, const Radius.circular(2)),
            cellPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant IdenticonPainter oldDelegate) =>
      oldDelegate.hash != hash || oldDelegate.primaryColor != primaryColor;
}

/// Short Authentication String (SAS) modal dialog for out-of-band visual/numeric verification.
class SasVerificationDialog extends StatelessWidget {
  final SasCode sasCode;
  final String remoteDeviceName;
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const SasVerificationDialog({
    super.key,
    required this.sasCode,
    required this.remoteDeviceName,
    required this.onConfirm,
    required this.onReject,
  });

  String _formatHexFingerprint(Uint8List hash) {
    if (hash.isEmpty) return '00:00:00:00:00:00:00:00';
    final take = hash.take(16).toList();
    return take
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        color: colorScheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Verify Security Code',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Peer: $remoteDeviceName',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Monospace 6-Digit Numeric Code
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            sasCode.numericCode,
                            style: AppTheme.monospace(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.primary,
                              letterSpacing: 3.0,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Copy numeric code',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: sasCode.numericCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('SAS code copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 4-Emoji Visual Badge Tuple
                Text(
                  'Emoji Verification Tuple',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: sasCode.emojis.map((emoji) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            emoji.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            emoji.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Identicon & Hex Fingerprint
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: colorScheme.outlineVariant
                            .withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CustomPaint(
                          painter: IdenticonPainter(
                            hash: sasCode.transcriptHash,
                            primaryColor: colorScheme.primary,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transcript Fingerprint',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatHexFingerprint(sasCode.transcriptHash),
                              style: AppTheme.monospace(
                                fontSize: 11,
                                color: colorScheme.onSurface,
                                letterSpacing: 0.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Instructions warning
                Text(
                  'Confirm that the exact same numbers and emojis appear on both screens before transferring files.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        label: const Text('Reject / Mismatch'),
                        onPressed: onReject,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.check_rounded, size: 20),
                        label: const Text('Confirm Match'),
                        onPressed: onConfirm,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
