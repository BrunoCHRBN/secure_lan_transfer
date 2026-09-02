import 'dart:async';
import 'dart:math';
import 'flow_controller.dart';

/// Token bucket algorithm for bandwidth rate limiting in streaming transfers.
class TokenBucketRateLimiter {
  final int bytesPerSecond;
  final int maxBurstBytes;

  double _tokens;
  DateTime _lastRefill;

  TokenBucketRateLimiter({
    required this.bytesPerSecond,
    int? maxBurstBytes,
  })  : maxBurstBytes = maxBurstBytes ?? (bytesPerSecond * 2),
        _tokens = (maxBurstBytes ?? (bytesPerSecond * 2)).toDouble(),
        _lastRefill = DateTime.now();

  /// Asynchronously consumes [byteCount] tokens, delaying until tokens refill.
  Future<void> consume(int byteCount, {CancellationToken? cancelToken}) async {
    if (bytesPerSecond <= 0 || byteCount <= 0) return;

    while (true) {
      if (cancelToken?.isCancelled == true) {
        throw StateError('Cancelled: ${cancelToken?.cancelReason}');
      }

      final now = DateTime.now();
      final elapsedSec = now.difference(_lastRefill).inMicroseconds / 1000000.0;
      _tokens = min(maxBurstBytes.toDouble(), _tokens + (elapsedSec * bytesPerSecond));
      _lastRefill = now;

      if (_tokens >= byteCount || (_tokens >= 0 && byteCount >= maxBurstBytes)) {
        _tokens -= byteCount;
        return;
      }

      final needed = byteCount - _tokens;
      final waitMs = ((needed / bytesPerSecond) * 1000).ceil();
      await Future<void>.delayed(Duration(milliseconds: max(1, min(waitMs, 100))));
    }
  }
}