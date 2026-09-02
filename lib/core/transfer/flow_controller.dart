import 'dart:async';

/// Token to cooperatively cancel an in-flight transfer or credit wait.
class CancellationToken {
  bool _isCancelled = false;
  String? _cancelReason;
  final List<void Function(String reason)> _listeners = [];

  bool get isCancelled => _isCancelled;
  String? get cancelReason => _cancelReason;

  void cancel([String reason = 'Transfer cancelled by user']) {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelReason = reason;
    for (final listener in List.of(_listeners)) {
      listener(reason);
    }
  }

  void onCancel(void Function(String reason) listener) {
    if (_isCancelled) {
      listener(_cancelReason ?? 'Cancelled');
    } else {
      _listeners.add(listener);
    }
  }
}

/// Credit-based flow control semaphore governing in-flight chunks and backpressure.
class FlowController {
  final int initialCredits;
  final int maxCredits;

  int _availableCredits;
  bool _isPaused = false;
  bool _isClosed = false;
  Object? _closeError;
  StackTrace? _closeStackTrace;

  final List<Completer<void>> _waiters = [];

  FlowController({
    this.initialCredits = 16,
    this.maxCredits = 32,
  }) : _availableCredits = initialCredits;

  int get availableCredits => _availableCredits;
  bool get isPaused => _isPaused;
  bool get isClosed => _isClosed;
  Object? get closeError => _closeError;

  void _throwIfClosed() {
    if (_isClosed) {
      if (_closeError != null) {
        Error.throwWithStackTrace(
          _closeError!,
          _closeStackTrace ?? StackTrace.current,
        );
      }
      throw StateError('FlowController is closed');
    }
  }

  /// Acquires 1 credit to transmit a data chunk.
  /// If credits == 0 or paused, asynchronously waits until replenished or resumed.
  Future<void> acquireCredit({CancellationToken? cancelToken}) async {
    _throwIfClosed();
    if (cancelToken?.isCancelled == true) {
      throw StateError('Cancelled: ${cancelToken?.cancelReason}');
    }

    while (_availableCredits <= 0 || _isPaused) {
      _throwIfClosed();
      if (cancelToken?.isCancelled == true) {
        throw StateError('Cancelled: ${cancelToken?.cancelReason}');
      }

      final completer = Completer<void>();
      _waiters.add(completer);

      void cancelListener(String reason) {
        if (!completer.isCompleted) {
          _waiters.remove(completer);
          completer.completeError(StateError('Cancelled: $reason'));
        }
      }

      cancelToken?.onCancel(cancelListener);

      try {
        await completer.future;
      } finally {
        _waiters.remove(completer);
      }
    }

    _availableCredits--;
  }

  /// Replenishes credits upon receiving ACK from receiver.
  void replenishCredits(int count) {
    if (_isClosed || count <= 0) return;
    _availableCredits = (_availableCredits + count).clamp(0, maxCredits);
    _wakeWaiters();
  }

  /// Alias for replenishing 1 credit.
  void releaseCredit([int count = 1]) => replenishCredits(count);

  /// Pauses credit acquisition.
  void pause() {
    _isPaused = true;
  }

  /// Resumes credit acquisition.
  void resume() {
    if (_isPaused) {
      _isPaused = false;
      _wakeWaiters();
    }
  }

  /// Wakes up queued waiters if credits are available and not paused.
  void _wakeWaiters() {
    if (_isPaused || _availableCredits <= 0) return;

    while (_waiters.isNotEmpty && _availableCredits > 0 && !_isPaused) {
      final next = _waiters.removeAt(0);
      if (!next.isCompleted) {
        next.complete();
      }
    }
  }

  /// Resets controller state back to initial credits.
  void reset() {
    _availableCredits = initialCredits;
    _isPaused = false;
    _isClosed = false;
    _closeError = null;
    _closeStackTrace = null;
    _wakeWaiters();
  }

  /// Closes the controller and wakes all waiters with an error.
  void close([Object? error, StackTrace? stackTrace]) {
    _isClosed = true;
    _closeError = error;
    _closeStackTrace = stackTrace;
    for (final waiter in List.of(_waiters)) {
      if (!waiter.isCompleted) {
        if (error != null) {
          waiter.completeError(error, stackTrace);
        } else {
          waiter.completeError(StateError('FlowController closed'));
        }
      }
    }
    _waiters.clear();
  }
}
