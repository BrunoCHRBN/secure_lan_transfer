import 'dart:async';
import '../models/transfer_progress.dart';

/// Transfer session role.
enum TransferRole {
  initiator,
  receiver,
}

/// 7-state lifecycle progression + 2 terminal states.
enum TransferState {
  idle,
  connecting,
  handshaking,
  transferring,
  paused,
  verifying,
  completed,
  error,
  cancelled,
}

/// Structured error codes for transfer failures.
enum SessionErrorCode {
  connectionRefused,
  connectionTimeout,
  handshakeFailed,
  sasMismatch,
  tagMismatch,
  integrityMismatch,
  diskFull,
  fileNotFound,
  permissionDenied,
  socketClosed,
  protocolViolation,
  userCancelled,
  unknown,
}

/// Structured error payload capturing failures with stack traces and timestamps.
class SessionError {
  final SessionErrorCode code;
  final String message;
  final dynamic underlyingError;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  SessionError({
    required this.code,
    required this.message,
    this.underlyingError,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => 'SessionError($code): $message';
}

/// Immutable snapshot of the transfer session state.
class SessionState {
  final TransferState state;
  final TransferRole role;
  final String? remoteDeviceId;
  final String? remoteDeviceName;
  final String? fileName;
  final int? totalBytes;
  final TransferProgress? progress;
  final SessionError? error;
  final String? committedFilePath;
  final DateTime timestamp;

  const SessionState({
    required this.state,
    required this.role,
    this.remoteDeviceId,
    this.remoteDeviceName,
    this.fileName,
    this.totalBytes,
    this.progress,
    this.error,
    this.committedFilePath,
    required this.timestamp,
  });

  factory SessionState.idle({TransferRole role = TransferRole.initiator}) =>
      SessionState(
        state: TransferState.idle,
        role: role,
        timestamp: DateTime.now(),
      );

  bool get isTerminal =>
      state == TransferState.completed ||
      state == TransferState.error ||
      state == TransferState.cancelled;

  bool get isActive =>
      state == TransferState.connecting ||
      state == TransferState.handshaking ||
      state == TransferState.transferring ||
      state == TransferState.paused ||
      state == TransferState.verifying;

  bool get isBusy => isActive;
  bool get isAvailable => state == TransferState.idle || isTerminal;

  bool get isPaused => state == TransferState.paused;
  bool get isCompleted => state == TransferState.completed;
  bool get hasError => state == TransferState.error;

  SessionState copyWith({
    TransferState? state,
    TransferRole? role,
    String? remoteDeviceId,
    String? remoteDeviceName,
    String? fileName,
    int? totalBytes,
    TransferProgress? progress,
    SessionError? error,
    String? committedFilePath,
  }) {
    return SessionState(
      state: state ?? this.state,
      role: role ?? this.role,
      remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
      remoteDeviceName: remoteDeviceName ?? this.remoteDeviceName,
      fileName: fileName ?? this.fileName,
      totalBytes: totalBytes ?? this.totalBytes,
      progress: progress ?? this.progress,
      error: error ?? this.error,
      committedFilePath: committedFilePath ?? this.committedFilePath,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'SessionState(state: $state, role: $role, file: $fileName, total: $totalBytes, error: $error)';
}

/// Deterministic finite state machine managing transfer session transitions.
class SessionStateMachine {
  static const Map<TransferState, Set<TransferState>> _validTransitions = {
    TransferState.idle: {
      TransferState.connecting,
      TransferState.handshaking,
      TransferState.error,
    },
    TransferState.connecting: {
      TransferState.handshaking,
      TransferState.error,
      TransferState.cancelled,
    },
    TransferState.handshaking: {
      TransferState.transferring,
      TransferState.error,
      TransferState.cancelled,
    },
    TransferState.transferring: {
      TransferState.paused,
      TransferState.verifying,
      TransferState.completed,
      TransferState.error,
      TransferState.cancelled,
    },
    TransferState.paused: {
      TransferState.transferring,
      TransferState.error,
      TransferState.cancelled,
    },
    TransferState.verifying: {
      TransferState.completed,
      TransferState.error,
      TransferState.cancelled,
    },
    TransferState.completed: {
      TransferState.idle,
    },
    TransferState.error: {
      TransferState.idle,
    },
    TransferState.cancelled: {
      TransferState.idle,
    },
  };

  final _stateController = StreamController<SessionState>.broadcast();
  SessionState _currentState;

  SessionStateMachine({TransferRole role = TransferRole.initiator})
      : _currentState = SessionState.idle(role: role);

  Stream<SessionState> get stream => _stateController.stream;
  SessionState get currentState => _currentState;

  bool canTransitionTo(TransferState nextState) {
    final allowed = _validTransitions[_currentState.state];
    return allowed != null && allowed.contains(nextState);
  }

  void transitionTo(
    TransferState nextState, {
    String? remoteDeviceId,
    String? remoteDeviceName,
    String? fileName,
    int? totalBytes,
    TransferProgress? progress,
    String? committedFilePath,
  }) {
    if (!canTransitionTo(nextState)) {
      throw StateError(
        'Invalid state transition: cannot transition from ${_currentState.state} to $nextState',
      );
    }

    _currentState = _currentState.copyWith(
      state: nextState,
      remoteDeviceId: remoteDeviceId,
      remoteDeviceName: remoteDeviceName,
      fileName: fileName,
      totalBytes: totalBytes,
      progress: progress,
      committedFilePath: committedFilePath,
      error: null,
    );
    _stateController.add(_currentState);
  }

  void updateProgress(TransferProgress progress) {
    if (_currentState.state != TransferState.transferring &&
        _currentState.state != TransferState.paused &&
        _currentState.state != TransferState.verifying) {
      return;
    }
    _currentState = _currentState.copyWith(progress: progress);
    _stateController.add(_currentState);
  }

  void fail(
    SessionErrorCode code,
    String message, [
    dynamic underlyingError,
    StackTrace? stackTrace,
  ]) {
    final error = SessionError(
      code: code,
      message: message,
      underlyingError: underlyingError,
      stackTrace: stackTrace,
    );

    if (canTransitionTo(TransferState.error)) {
      _currentState = _currentState.copyWith(
        state: TransferState.error,
        error: error,
      );
      _stateController.add(_currentState);
    }
  }

  void cancel([String reason = 'Transfer cancelled by user']) {
    if (canTransitionTo(TransferState.cancelled)) {
      final error = SessionError(
        code: SessionErrorCode.userCancelled,
        message: reason,
      );
      _currentState = _currentState.copyWith(
        state: TransferState.cancelled,
        error: error,
      );
      _stateController.add(_currentState);
    }
  }

  void reset({TransferRole? role}) {
    _currentState = SessionState.idle(role: role ?? _currentState.role);
    _stateController.add(_currentState);
  }

  void dispose() {
    _stateController.close();
  }
}
