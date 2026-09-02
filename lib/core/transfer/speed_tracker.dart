import '../models/transfer_progress.dart';
import '../protocol/session_state.dart';

class _SpeedSample {
  final DateTime timestamp;
  final int bytes;
  const _SpeedSample(this.timestamp, this.bytes);
}

/// Dynamic speed tracker utilizing EWMA smoothing and a sliding window
/// to provide stable, real-time throughput metrics and ETA estimations.
class SpeedTracker {
  final int totalBytes;
  final double alpha;
  final Duration windowDuration;

  final Stopwatch _stopwatch = Stopwatch();
  final List<_SpeedSample> _samples = [];

  int _transferredBytes = 0;
  double _ewmaSpeed = 0.0;
  DateTime? _lastSampleTime;
  int _lastSampleBytes = 0;
  bool _isPaused = false;
  bool _hasStarted = false;

  SpeedTracker({
    required this.totalBytes,
    this.alpha = 0.20,
    this.windowDuration = const Duration(seconds: 3),
  });

  void start() {
    _stopwatch.start();
    final now = DateTime.now();
    _lastSampleTime = now;
    _lastSampleBytes = 0;
    _transferredBytes = 0;
    _ewmaSpeed = 0.0;
    _samples.clear();
    _samples.add(_SpeedSample(now, 0));
    _hasStarted = true;
    _isPaused = false;
  }

  void pause() {
    _stopwatch.stop();
    _isPaused = true;
  }

  void resume() {
    if (_isPaused) {
      _stopwatch.start();
      _lastSampleTime = DateTime.now();
      _isPaused = false;
    }
  }

  TransferProgress recordProgress(
    int currentTransferredBytes, {
    TransferState state = TransferState.transferring,
  }) {
    if (!_hasStarted) start();
    final now = DateTime.now();
    _transferredBytes = currentTransferredBytes;

    if (!_isPaused && _lastSampleTime != null) {
      final deltaMs = now.difference(_lastSampleTime!).inMilliseconds;
      if (deltaMs >= 50) {
        final deltaBytes = _transferredBytes - _lastSampleBytes;
        final instSpeed = deltaBytes / (deltaMs / 1000.0);

        if (_ewmaSpeed == 0.0) {
          _ewmaSpeed = instSpeed;
        } else {
          _ewmaSpeed = (alpha * instSpeed) + ((1.0 - alpha) * _ewmaSpeed);
        }

        _lastSampleTime = now;
        _lastSampleBytes = _transferredBytes;
        _samples.add(_SpeedSample(now, _transferredBytes));

        // Prune sliding window samples older than windowDuration (3s)
        final cutoff = now.subtract(windowDuration);
        _samples.removeWhere((s) => s.timestamp.isBefore(cutoff));
      }
    }

    // Sliding window calculation
    double windowSpeed = _ewmaSpeed;
    if (_samples.length >= 2) {
      final oldest = _samples.first;
      final newest = _samples.last;
      final winDeltaMs = newest.timestamp.difference(oldest.timestamp).inMilliseconds;
      if (winDeltaMs >= 200) {
        final winDeltaBytes = newest.bytes - oldest.bytes;
        windowSpeed = winDeltaBytes / (winDeltaMs / 1000.0);
      }
    }

    // Composite speed
    double compositeSpeed = (0.70 * _ewmaSpeed) + (0.30 * windowSpeed);
    if (compositeSpeed < 0) compositeSpeed = 0.0;

    // Stall detection
    bool isStalled = false;
    if (_lastSampleTime != null) {
      final silenceDuration = now.difference(_lastSampleTime!);
      if (silenceDuration.inSeconds >= 3 && _transferredBytes < totalBytes) {
        isStalled = true;
        compositeSpeed = compositeSpeed * 0.5; // decay
      }
    }

    // ETA calculation
    Duration? eta;
    final remainingBytes = totalBytes > _transferredBytes ? totalBytes - _transferredBytes : 0;
    if (remainingBytes == 0) {
      eta = Duration.zero;
    } else if (_stopwatch.elapsedMilliseconds >= 500 && compositeSpeed >= 1024 && !isStalled) {
      final etaSec = remainingBytes / compositeSpeed;
      if (etaSec <= 359999) { // < 100 hours
        eta = Duration(milliseconds: (etaSec * 1000).round());
      }
    }

    final fraction = totalBytes > 0
        ? (_transferredBytes / totalBytes).clamp(0.0, 1.0)
        : 0.0;

    return TransferProgress(
      transferredBytes: _transferredBytes,
      totalBytes: totalBytes,
      fraction: fraction,
      speedBytesPerSec: compositeSpeed,
      eta: eta,
      elapsedTime: _stopwatch.elapsed,
      isStalled: isStalled,
      state: state,
    );
  }

  void reset() {
    _stopwatch.reset();
    _samples.clear();
    _transferredBytes = 0;
    _ewmaSpeed = 0.0;
    _lastSampleTime = null;
    _lastSampleBytes = 0;
    _hasStarted = false;
    _isPaused = false;
  }
}
