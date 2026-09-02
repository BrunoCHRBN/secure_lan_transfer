import '../protocol/session_state.dart';

/// Comprehensive transfer progress data model.
class TransferProgress {
  final int transferredBytes;
  final int totalBytes;
  final double fraction;
  final double speedBytesPerSec;
  final Duration? eta;
  final Duration elapsedTime;
  final bool isStalled;
  final TransferState state;

  const TransferProgress({
    required this.transferredBytes,
    required this.totalBytes,
    required this.fraction,
    required this.speedBytesPerSec,
    required this.eta,
    required this.elapsedTime,
    required this.isStalled,
    required this.state,
  });

  factory TransferProgress.initial({int totalBytes = 0}) => TransferProgress(
        transferredBytes: 0,
        totalBytes: totalBytes,
        fraction: 0.0,
        speedBytesPerSec: 0.0,
        eta: null,
        elapsedTime: Duration.zero,
        isStalled: false,
        state: TransferState.idle,
      );

  factory TransferProgress.completed({
    required int totalBytes,
    required Duration elapsedTime,
  }) =>
      TransferProgress(
        transferredBytes: totalBytes,
        totalBytes: totalBytes,
        fraction: 1.0,
        speedBytesPerSec: 0.0,
        eta: Duration.zero,
        elapsedTime: elapsedTime,
        isStalled: false,
        state: TransferState.completed,
      );

  // Formatting Helpers
  String get speedFormatted => formatSpeed(speedBytesPerSec);
  String get etaFormatted => formatDuration(eta, isStalled: isStalled);
  String get transferredFormatted => formatBytes(transferredBytes);
  String get totalFormatted => formatBytes(totalBytes);
  String get percentageFormatted => '${(fraction * 100).toStringAsFixed(1)}%';

  static String formatBytes(int bytes) {
    if (bytes < 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    if (bytesPerSec < 1024) {
      return '${bytesPerSec.toStringAsFixed(0)} B/s';
    }
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    if (bytesPerSec < 1024 * 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
  }

  static String formatDuration(Duration? duration, {bool isStalled = false}) {
    if (isStalled) return 'Stalled';
    if (duration == null) return 'Calculating...';
    if (duration == Duration.zero) return '00:00';

    final totalSec = duration.inSeconds;
    final hours = totalSec ~/ 3600;
    final minutes = (totalSec % 3600) ~/ 60;
    final seconds = totalSec % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'TransferProgress($percentageFormatted, $transferredFormatted / $totalFormatted, $speedFormatted, ETA: $etaFormatted)';
}
