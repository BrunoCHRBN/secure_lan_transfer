import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Custom painter rendering a 240° circular arc gauge for transfer throughput.
class SpeedometerPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final Color primaryColor;
  final Color trackColor;
  final Color accentColor;

  SpeedometerPainter({
    required this.progress,
    required this.primaryColor,
    required this.trackColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;
    const startAngle = 150 * (math.pi / 180);
    const sweepAngle = 240 * (math.pi / 180);
    const strokeWidth = 14.0;

    // Background track arc
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Active speed gradient arc
    if (progress > 0.001) {
      final activePaint = Paint()
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle,
          colors: [
            accentColor,
            primaryColor,
            Colors.amber,
            Colors.deepOrangeAccent,
          ],
          stops: const [0.0, 0.4, 0.75, 1.0],
          transform: const GradientRotation(startAngle),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final clampedProgress = progress.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle * clampedProgress,
        false,
        activePaint,
      );

      // Indicator tip dot
      final tipAngle = startAngle + (sweepAngle * clampedProgress);
      final tipX = center.dx + radius * math.cos(tipAngle);
      final tipY = center.dy + radius * math.sin(tipAngle);
      final tipPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(tipX, tipY), 4.5, tipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant SpeedometerPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.trackColor != trackColor;
}

/// Circular Speedometer Arc Gauge with Auto-Ranging Scale and Digital Readout.
class SpeedometerWidget extends StatelessWidget {
  final double speedBytesPerSec;
  final double peakSpeedBytesPerSec;
  final double size;

  const SpeedometerWidget({
    super.key,
    required this.speedBytesPerSec,
    this.peakSpeedBytesPerSec = 0.0,
    this.size = 200,
  });

  /// Auto-ranging maximum scale in MB/s.
  double _getAutoRangeMaxMb(double currentMb) {
    if (currentMb <= 10.0) return 10.0;
    if (currentMb <= 50.0) return 50.0;
    if (currentMb <= 150.0) return 150.0;
    return 1000.0; // Multi-Gigabit
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final currentMb = speedBytesPerSec / (1024 * 1024);
    final peakMb = peakSpeedBytesPerSec / (1024 * 1024);
    final maxScaleMb = _getAutoRangeMaxMb(math.max(currentMb, peakMb));
    final fraction = (currentMb / maxScaleMb).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: fraction),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            builder: (context, animValue, child) {
              return CustomPaint(
                size: Size(size, size),
                painter: SpeedometerPainter(
                  progress: animValue,
                  primaryColor: colorScheme.primary,
                  trackColor: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  accentColor: colorScheme.tertiary,
                ),
              );
            },
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentMb < 0.1 && speedBytesPerSec > 0
                    ? '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s'
                    : currentMb.toStringAsFixed(1),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                currentMb >= 0.1 || speedBytesPerSec == 0 ? 'MB/s' : '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Range: 0-${maxScaleMb.toInt()} MB/s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (peakSpeedBytesPerSec > 0) ...[
                const SizedBox(height: 2),
                Text(
                  'Peak: ${peakMb.toStringAsFixed(1)} MB/s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
