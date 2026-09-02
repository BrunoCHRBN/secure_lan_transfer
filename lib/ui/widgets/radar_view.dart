import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/peer_device.dart';

/// Radar Visualizer Painter with concentric circles and rotating sweep.
class RadarPainter extends CustomPainter {
  final double animationValue; // 0.0 to 1.0
  final Color primaryColor;
  final Color outlineColor;
  final List<PeerDevice> devices;

  RadarPainter({
    required this.animationValue,
    required this.primaryColor,
    required this.outlineColor,
    required this.devices,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 8;

    // Background grid circles (3 concentric rings)
    final gridPaint = Paint()
      ..color = outlineColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 3; i++) {
      final r = maxRadius * (i / 3);
      canvas.drawCircle(center, r, gridPaint);
    }

    // Crosshairs
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      gridPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      gridPaint,
    );

    // Expanding pulsing ripples (2 waves)
    for (int i = 0; i < 2; i++) {
      final waveProgress = (animationValue + i * 0.5) % 1.0;
      final waveRadius = maxRadius * waveProgress;
      final opacity = (1.0 - waveProgress) * 0.35;
      final wavePaint = Paint()
        ..color = primaryColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, waveRadius, wavePaint);
    }

    // Rotating Sweep Sector
    final sweepAngle = animationValue * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi / 2,
        colors: [
          primaryColor.withValues(alpha: 0.3),
          primaryColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius),
      sweepAngle,
      math.pi / 3,
      true,
      sweepPaint,
    );

    // Center node (This device)
    final centerPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, centerPaint);

    // Peer device blips positioned deterministically around the circle
    final peerPaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;

    for (int i = 0; i < devices.length; i++) {
      final device = devices[i];
      // Deterministic angle based on device id hash
      final angle = (device.id.hashCode.abs() % 360) * (math.pi / 180);
      final distRatio = 0.35 + ((device.name.hashCode.abs() % 50) / 100);
      final dist = maxRadius * distRatio.clamp(0.3, 0.9);

      final dx = center.dx + dist * math.cos(angle);
      final dy = center.dy + dist * math.sin(angle);

      canvas.drawCircle(Offset(dx, dy), 4.5, peerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) => true;
}

/// Animated Radar Visualizer for peer scanning.
class RadarView extends StatefulWidget {
  final List<PeerDevice> devices;
  final bool isScanning;
  final double size;

  const RadarView({
    super.key,
    required this.devices,
    this.isScanning = true,
    this.size = 140,
  });

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isScanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant RadarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isScanning && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: RadarPainter(
            animationValue: _controller.value,
            primaryColor: colorScheme.primary,
            outlineColor: colorScheme.outline,
            devices: widget.devices,
          ),
        );
      },
    );
  }
}
