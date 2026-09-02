import 'dart:async';
import 'dart:io';
import '../crypto/sas_authenticator.dart';
import '../crypto/zero_metadata_staging.dart';
import '../transfer/transfer_queue.dart';
import '../models/transfer_progress.dart';
import '../protocol/session_state.dart';
import '../transfer/flow_controller.dart';
import '../transfer/transfer_receiver.dart';
import '../transfer/transfer_sender.dart';
import 'handshake_protocol.dart';

/// Callback signature for SAS verification confirmation.
typedef SasVerificationHandler = Future<bool> Function(
  SasCode sasCode,
  String remoteDeviceName,
);

/// Configuration options for [SessionManager].
class SessionManagerOptions {
  final int defaultPort;
  final Duration connectionTimeout;
  final Duration handshakeTimeout;
  final bool autoAcceptInbound;
  final bool autoVerifySas;
  final Directory? downloadDirectory;
  final int? chunkSize;
  final int? creditWindowSize;
  final int? rateLimitBytesPerSec;
  final int? maxAllowableFileSize;
  final bool secureWipeOnAbort;

  const SessionManagerOptions({
    this.defaultPort = 42385,
    this.connectionTimeout = const Duration(seconds: 15),
    this.handshakeTimeout = const Duration(seconds: 60),
    this.autoAcceptInbound = true,
    this.autoVerifySas = false,
    this.downloadDirectory,
    this.chunkSize,
    this.creditWindowSize,
    this.rateLimitBytesPerSec,
    this.maxAllowableFileSize,
    this.secureWipeOnAbort = false,
  });
}

/// Request bundle presented to the UI/User to confirm an inbound connection proposal.
class InboundSessionProposal {
  final Socket socket;
  final String remoteAddress;
  final int remotePort;
  final Completer<bool> _decisionCompleter = Completer<bool>();

  InboundSessionProposal({
    required this.socket,
    required this.remoteAddress,
    required this.remotePort,
  });

  void accept() {
    if (!_decisionCompleter.isCompleted) _decisionCompleter.complete(true);
  }

  void reject([String reason = 'User declined connection']) {
    if (!_decisionCompleter.isCompleted) _decisionCompleter.complete(false);
  }

  Future<bool> get userDecision => _decisionCompleter.future;
}

/// Request bundle presented to the UI/User to confirm SAS code visual/numeric match.
class SasVerificationRequest {
  final SasCode sasCode;
  final String remoteAddress;
  final int remotePort;
  final Completer<bool> _completer = Completer<bool>();

  SasVerificationRequest({
    required this.sasCode,
    required this.remoteAddress,
    required this.remotePort,
  });

  void approve() {
    if (!_completer.isCompleted) _completer.complete(true);
  }

  void confirm() => approve();

  void reject() {
    if (!_completer.isCompleted) _completer.complete(false);
  }

  Future<bool> get decision => _completer.future;
}

/// High-Level Session Manager orchestrating TCP listener server, client connections,
/// pairing negotiations, SAS visual verification, and streaming transfer handoffs.
class SessionManager {
  final SessionStateMachine stateMachine;
  final HandshakeProtocol handshakeProtocol;
  final TransferSender sender;
  final TransferReceiver receiver;
  final SessionManagerOptions options;

  ServerSocket? _serverSocket;
  Socket? _currentActiveSocket;
  CancellationToken? _currentCancelToken;
  StreamSubscription<Socket>? _serverSubscription;

  final _sasRequestsController =
      StreamController<SasVerificationRequest>.broadcast();
  final _inboundProposalsController =
      StreamController<InboundSessionProposal>.broadcast();

  SessionManager({
    SessionStateMachine? stateMachine,
    HandshakeProtocol? handshakeProtocol,
    TransferSender? sender,
    TransferReceiver? receiver,
    SessionManagerOptions? options,
  })  : stateMachine = stateMachine ?? SessionStateMachine(),
        handshakeProtocol = handshakeProtocol ?? HandshakeProtocol(),
        sender = sender ??
            TransferSender(
              options: TransferSenderOptions(
                chunkSize: options?.chunkSize ?? 262144,
                defaultInitialCredits: options?.creditWindowSize ?? 16,
                rateLimitBytesPerSec: options?.rateLimitBytesPerSec,
              ),
            ),
        receiver = receiver ??
            TransferReceiver(
              options: TransferReceiverOptions(
                creditWindowSize: options?.creditWindowSize ?? 16,
                maxAllowableFileSize: options?.maxAllowableFileSize ??
                    100 * 1024 * 1024 * 1024,
                secureWipeOnAbort: options?.secureWipeOnAbort ?? false,
              ),
            ),
        options = options ?? const SessionManagerOptions();

  Stream<SessionState> get sessionStateStream => stateMachine.stream;
  SessionState get currentState => stateMachine.currentState;
  Stream<SasVerificationRequest> get sasRequestsStream =>
      _sasRequestsController.stream;
  Stream<InboundSessionProposal> get inboundProposalsStream =>
      _inboundProposalsController.stream;
  int? get serverPort => _serverSocket?.port;
  bool get isServerRunning => _serverSocket != null;

  /// Binds the inbound TCP listener server.
  Future<void> startServer({int? port, String? host}) async {
    if (_serverSocket != null) return;

    final targetPort = port ?? options.defaultPort;
    final targetHost =
        host != null ? InternetAddress(host) : InternetAddress.anyIPv4;

    try {
      _serverSocket =
          await ServerSocket.bind(targetHost, targetPort, shared: false);
    } catch (_) {
      try {
        _serverSocket =
            await ServerSocket.bind(targetHost, targetPort, shared: true);
      } catch (_) {
        // Ephemeral port fallback if default is bound
        _serverSocket = await ServerSocket.bind(targetHost, 0);
      }
    }

    _serverSubscription = _serverSocket!.listen(_handleIncomingConnection);
  }

  /// Stops the inbound TCP listener server.
  Future<void> stopServer() async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _serverSocket?.close();
    _serverSocket = null;
  }

  /// Internal handler for inbound connections.
  void _handleIncomingConnection(Socket socket) async {
    socket.setOption(SocketOption.tcpNoDelay, true);

    if (stateMachine.currentState.isActive || _currentActiveSocket != null) {
      // Busy: close incoming connection
      socket.destroy();
      return;
    }

    if (stateMachine.currentState.isTerminal) {
      stateMachine.reset(role: TransferRole.receiver);
    }

    _currentActiveSocket = socket;
    _currentCancelToken = CancellationToken();

    try {
      if (!options.autoAcceptInbound) {
        final proposal = InboundSessionProposal(
          socket: socket,
          remoteAddress: socket.remoteAddress.address,
          remotePort: socket.remotePort,
        );
        _inboundProposalsController.add(proposal);
        final accepted = await proposal.userDecision;
        if (!accepted) {
          socket.destroy();
          return;
        }
      }

      stateMachine.transitionTo(
        TransferState.handshaking,
        remoteDeviceId: socket.remoteAddress.address,
      );

      final handshakeResult = await handshakeProtocol.performServerHandshake(
        socket,
        onVerifySas: (sas) async {
          if (options.autoVerifySas) return true;
          final req = SasVerificationRequest(
            sasCode: sas,
            remoteAddress: socket.remoteAddress.address,
            remotePort: socket.remotePort,
          );
          _sasRequestsController.add(req);
          return await req.decision;
        },
      );

      stateMachine.transitionTo(TransferState.transferring);

      final destDir = options.downloadDirectory ?? Directory.current;

      final result = await receiver.receiveFile(
        destDir,
        socket,
        handshakeResult.sessionKeys,
        incomingFrameStream: handshakeResult.incomingFrameStream,
        cancelToken: _currentCancelToken,
        onProgress: (progress) => stateMachine.updateProgress(progress),
      );

      stateMachine.transitionTo(
        TransferState.completed,
        fileName: result.fileName,
        totalBytes: result.totalBytes,
        committedFilePath: result.file.path,
      );
    } catch (e, st) {
      if (stateMachine.currentState.state != TransferState.cancelled) {
        // If the socket closed before handshake (e.g. discovery sweep port probe),
        // reset to idle so the server remains ready to accept real incoming transfers.
        if (e is HandshakeException && e.message.contains('Socket closed prematurely')) {
          stateMachine.reset(role: TransferRole.receiver);
          return;
        }

        final SessionErrorCode errorCode;
        if (e is TimeoutException) {
          errorCode = SessionErrorCode.connectionTimeout;
        } else if (e is SocketException) {
          errorCode = SessionErrorCode.socketClosed;
        } else if (e is HandshakeException) {
          errorCode = SessionErrorCode.handshakeFailed;
        } else if (e is IntegrityMismatchException) {
          errorCode = SessionErrorCode.integrityMismatch;
        } else {
          errorCode = SessionErrorCode.protocolViolation;
        }
        stateMachine.fail(
          errorCode,
          e.toString(),
          e,
          st,
        );
      }
    } finally {
      socket.destroy();
      if (_currentActiveSocket == socket) {
        _currentActiveSocket = null;
        _currentCancelToken = null;
      }
    }
  }

  /// Connects to a remote peer and transfers a file.
  Future<TransferSenderResult> sendFile({
    required String host,
    required int port,
    required File file,
    String? targetDeviceName,
    Future<bool> Function(SasCode)? onVerifySas,
    void Function(TransferProgress)? onProgress,
    CancellationToken? cancelToken,
  }) async {
    if (stateMachine.currentState.isTerminal) {
      stateMachine.reset(role: TransferRole.initiator);
    }

    stateMachine.transitionTo(
      TransferState.connecting,
      remoteDeviceName: targetDeviceName ?? host,
      fileName: file.path,
    );

    Socket? socket;
    final effectiveCancelToken = cancelToken ?? CancellationToken();

    try {
      socket =
          await Socket.connect(host, port, timeout: options.connectionTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _currentActiveSocket = socket;
      _currentCancelToken = effectiveCancelToken;

      stateMachine.transitionTo(TransferState.handshaking);

      final handshakeResult = await handshakeProtocol.performClientHandshake(
        socket,
        onVerifySas: (sas) async {
          if (options.autoVerifySas) return true;
          if (onVerifySas != null) return await onVerifySas(sas);
          final req = SasVerificationRequest(
            sasCode: sas,
            remoteAddress: host,
            remotePort: port,
          );
          _sasRequestsController.add(req);
          return await req.decision;
        },
      );

      stateMachine.transitionTo(TransferState.transferring);

      final result = await sender.sendFile(
        file,
        socket,
        handshakeResult.sessionKeys,
        incomingFrameStream: handshakeResult.incomingFrameStream,
        cancelToken: effectiveCancelToken,
        onProgress: (progress) {
          stateMachine.updateProgress(progress);
          onProgress?.call(progress);
        },
      );

      stateMachine.transitionTo(
        TransferState.completed,
        fileName: result.fileName,
        totalBytes: result.totalBytes,
      );

      return result;
    } catch (e, st) {
      if (stateMachine.currentState.state != TransferState.cancelled) {
        final SessionErrorCode errorCode;
        if (e is TimeoutException) {
          errorCode = SessionErrorCode.connectionTimeout;
        } else if (e is SocketException) {
          errorCode = SessionErrorCode.socketClosed;
        } else if (e is HandshakeException) {
          errorCode = SessionErrorCode.handshakeFailed;
        } else if (e is IntegrityMismatchException) {
          errorCode = SessionErrorCode.integrityMismatch;
        } else {
          errorCode = SessionErrorCode.protocolViolation;
        }
        stateMachine.fail(
          errorCode,
          e.toString(),
          e,
          st,
        );
      }
      rethrow;
    } finally {
      socket?.destroy();
      if (_currentActiveSocket == socket) {
        _currentActiveSocket = null;
        _currentCancelToken = null;
      }
    }
  }

  /// Connects to a remote peer and transfers multiple files sequentially
  /// over a single authenticated connection (single handshake).
  Future<List<TransferSenderResult>> sendFiles({
    required String host,
    required int port,
    required List<File> files,
    required TransferQueue queue,
    String? targetDeviceName,
    Future<bool> Function(SasCode)? onVerifySas,
    void Function(TransferProgress)? onProgress,
    CancellationToken? cancelToken,
  }) async {
    if (files.isEmpty) return [];
    if (files.length == 1) {
      final result = await sendFile(
        host: host,
        port: port,
        file: files.first,
        targetDeviceName: targetDeviceName,
        onVerifySas: onVerifySas,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      return [result];
    }

    if (stateMachine.currentState.isTerminal) {
      stateMachine.reset(role: TransferRole.initiator);
    }

    stateMachine.transitionTo(
      TransferState.connecting,
      remoteDeviceName: targetDeviceName ?? host,
      fileName: '${files.length} files',
    );

    Socket? socket;
    final effectiveCancelToken = cancelToken ?? CancellationToken();
    final results = <TransferSenderResult>[];

    try {
      socket =
          await Socket.connect(host, port, timeout: options.connectionTimeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      _currentActiveSocket = socket;
      _currentCancelToken = effectiveCancelToken;

      stateMachine.transitionTo(TransferState.handshaking);

      final handshakeResult = await handshakeProtocol.performClientHandshake(
        socket,
        onVerifySas: (sas) async {
          if (options.autoVerifySas) return true;
          if (onVerifySas != null) return await onVerifySas(sas);
          final req = SasVerificationRequest(
            sasCode: sas,
            remoteAddress: host,
            remotePort: port,
          );
          _sasRequestsController.add(req);
          return await req.decision;
        },
      );

      stateMachine.transitionTo(TransferState.transferring);
      queue.startTimer();

      // Transfer each file sequentially over the same authenticated connection
      for (int i = 0; i < files.length; i++) {
        if (effectiveCancelToken.isCancelled || queue.isCancelled) break;

        final job = queue.jobs[i];
        queue.markJobTransferring(job);

        stateMachine.transitionTo(
          TransferState.transferring,
          fileName: job.fileName,
        );

        try {
          final result = await sender.sendFile(
            files[i],
            socket,
            handshakeResult.sessionKeys,
            incomingFrameStream: handshakeResult.incomingFrameStream,
            cancelToken: effectiveCancelToken,
            streamId: i + 1,
            onProgress: (progress) {
              job.progress = progress;
              stateMachine.updateProgress(progress);
              onProgress?.call(progress);
              queue.emitProgress(currentFileProgress: progress);
            },
          );

          queue.markJobCompleted(job, result);
          results.add(result);
        } catch (e) {
          queue.markJobFailed(job, e.toString());
          // Continue with next file unless cancelled
          if (effectiveCancelToken.isCancelled) rethrow;
        }
      }

      queue.stopTimer();
      queue.emitProgress();

      if (results.isNotEmpty) {
        stateMachine.transitionTo(
          TransferState.completed,
          fileName: '${results.length}/${files.length} files',
          totalBytes: results.fold<int>(0, (sum, r) => sum + r.totalBytes),
        );
      }

      return results;
    } catch (e, st) {
      if (stateMachine.currentState.state != TransferState.cancelled) {
        final SessionErrorCode errorCode;
        if (e is TimeoutException) {
          errorCode = SessionErrorCode.connectionTimeout;
        } else if (e is SocketException) {
          errorCode = SessionErrorCode.socketClosed;
        } else if (e is HandshakeException) {
          errorCode = SessionErrorCode.handshakeFailed;
        } else {
          errorCode = SessionErrorCode.protocolViolation;
        }
        stateMachine.fail(errorCode, e.toString(), e, st);
      }
      rethrow;
    } finally {
      socket?.destroy();
      if (_currentActiveSocket == socket) {
        _currentActiveSocket = null;
        _currentCancelToken = null;
      }
    }
  }

  /// Cancels the ongoing transfer session.
  void cancelCurrentSession({String reason = 'Cancelled by user'}) {
    final activeSocket = _currentActiveSocket;
    _currentActiveSocket = null;
    _currentCancelToken?.cancel(reason);
    stateMachine.cancel(reason);
    if (activeSocket != null) {
      Future.delayed(const Duration(milliseconds: 60), () {
        try {
          activeSocket.destroy();
        } catch (_) {}
      });
    }
  }

  /// Pauses the active sender transmission.
  void pause() {
    sender.pause();
    if (stateMachine.canTransitionTo(TransferState.paused)) {
      stateMachine.transitionTo(TransferState.paused);
    }
  }

  /// Resumes the active sender transmission.
  void resume() {
    sender.resume();
    if (stateMachine.canTransitionTo(TransferState.transferring)) {
      stateMachine.transitionTo(TransferState.transferring);
    }
  }

  /// Cleans up all resources.
  void dispose() {
    stopServer();
    _currentActiveSocket?.destroy();
    _sasRequestsController.close();
    _inboundProposalsController.close();
    stateMachine.dispose();
  }
}
