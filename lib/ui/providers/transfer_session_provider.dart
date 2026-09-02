import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/peer_device.dart';
import '../../core/models/transfer_progress.dart';
import '../../core/platform/notification_service.dart';
import '../../core/protocol/session_state.dart';
import '../../core/session/session_manager.dart';
import '../../core/transfer/transfer_queue.dart';
import '../../core/transfer/transfer_sender.dart';
import 'settings_provider.dart';

/// Ephemeral transfer history record maintained exclusively in volatile RAM.
class TransferHistoryItem {
  final String id;
  final String fileName;
  final int totalBytes;
  final String peerName;
  final String peerAddress;
  final TransferRole role;
  final TransferState finalState;
  final String? sha256Digest;
  final Duration duration;
  final double averageSpeed;
  final DateTime timestamp;
  final String? committedFilePath;

  TransferHistoryItem({
    required this.id,
    required this.fileName,
    required this.totalBytes,
    required this.peerName,
    required this.peerAddress,
    required this.role,
    required this.finalState,
    this.sha256Digest,
    required this.duration,
    required this.averageSpeed,
    required this.timestamp,
    this.committedFilePath,
  });

  bool get isCompleted => finalState == TransferState.completed;
  bool get isFailed => finalState == TransferState.error;
  bool get isCancelled => finalState == TransferState.cancelled;
}

/// Provider managing active inbound/outbound transfer sessions, user SAS confirmation,
/// inbound proposals, progress notifications, and zero-metadata transfer history.
class TransferSessionProvider extends ChangeNotifier {
  final SessionManager _sessionManager;
  final SettingsProvider _settings;
  final NotificationService _notifications = NotificationService();

  StreamSubscription<SessionState>? _stateSubscription;
  StreamSubscription<SasVerificationRequest>? _sasSubscription;
  StreamSubscription<InboundSessionProposal>? _proposalSubscription;

  SessionState _currentState = SessionState.idle();
  SasVerificationRequest? _pendingSasRequest;
  InboundSessionProposal? _pendingProposal;

  // Multi-file transfer queue
  TransferQueue? _activeQueue;
  QueueProgress _queueProgress = QueueProgress.empty();
  StreamSubscription<QueueProgress>? _queueProgressSub;
  StreamSubscription<TransferJob>? _queueJobSub;

  // Ephemeral In-Memory Transfer History (Zero-Metadata Disk Policy)
  final List<TransferHistoryItem> _history = [];

  TransferSessionProvider({
    required SettingsProvider settings,
    SessionManager? sessionManager,
  })  : _settings = settings,
        _sessionManager = sessionManager ??
            SessionManager(
              options: SessionManagerOptions(
                defaultPort: settings.transferPort,
                autoAcceptInbound: settings.autoAcceptPairedDevices,
                autoVerifySas: settings.autoVerifySas,
                downloadDirectory: Directory(settings.downloadDirectoryPath),
                chunkSize: settings.chunkSize,
                creditWindowSize: settings.creditWindowSize,
              ),
            ) {
    _initListeners();
    _notifications.initialize();
  }

  // Getters
  SessionManager get sessionManager => _sessionManager;
  SessionState get currentState => _currentState;
  TransferState get transferState => _currentState.state;
  TransferProgress? get progress => _currentState.progress;
  SasVerificationRequest? get pendingSasRequest => _pendingSasRequest;
  InboundSessionProposal? get pendingProposal => _pendingProposal;
  bool get hasActiveTransfer => _currentState.isActive;
  bool get isServerRunning => _sessionManager.isServerRunning;
  int? get serverPort => _sessionManager.serverPort;
  List<TransferHistoryItem> get history => List.unmodifiable(_history);

  // Multi-file queue getters
  TransferQueue? get activeQueue => _activeQueue;
  QueueProgress get queueProgress => _queueProgress;
  bool get isMultiFileTransfer =>
      _activeQueue != null && _activeQueue!.totalFiles > 1;
  List<TransferJob> get queueJobs => _activeQueue?.jobs ?? [];

  void _initListeners() {
    _stateSubscription = _sessionManager.sessionStateStream.listen((state) {
      _currentState = state;
      if (state.isTerminal) {
        _recordHistory(state);
        if (state.state == TransferState.completed) {
          _notifications.showTransferComplete(
            fileName: state.fileName ?? 'File',
            totalBytes: state.totalBytes ?? 0,
          );
        } else if (state.state == TransferState.error) {
          _notifications.showTransferFailed(
            fileName: state.fileName ?? 'File',
            error: state.error?.message ?? 'Transfer failed',
          );
        }
      }
      notifyListeners();
    });

    _sasSubscription = _sessionManager.sasRequestsStream.listen((req) {
      _pendingSasRequest = req;
      notifyListeners();
    });

    _proposalSubscription =
        _sessionManager.inboundProposalsStream.listen((prop) {
      _pendingProposal = prop;
      notifyListeners();
    });
  }

  /// Binds the inbound TCP listener server.
  Future<void> startServer() async {
    await _sessionManager.startServer(
      port: _settings.transferPort,
    );
    notifyListeners();
  }

  /// Stops the inbound TCP listener server.
  Future<void> stopServer() async {
    await _sessionManager.stopServer();
    notifyListeners();
  }

  /// Sends a single file to a remote peer device.
  Future<TransferSenderResult> sendFile(
    PeerDevice target,
    File file, {
    void Function(TransferProgress)? onProgress,
  }) async {
    final results = await sendFiles(target, [file], onProgress: onProgress);
    return results.first;
  }

  /// Sends multiple files to a remote peer device sequentially over a single session.
  Future<List<TransferSenderResult>> sendFiles(
    PeerDevice target,
    List<File> files, {
    void Function(TransferProgress)? onProgress,
  }) async {
    final targetIp = target.primaryAddress;
    if (targetIp == null) {
      throw ArgumentError(
          'Target device "${target.name}" has no reachable IP address');
    }

    if (files.isEmpty) return [];

    for (final file in files) {
      if (!file.existsSync()) {
        throw FileSystemException('Source file not found', file.path);
      }
    }

    // Set up queue
    _activeQueue?.dispose();
    final queue = TransferQueue();
    queue.addFiles(files);
    _activeQueue = queue;

    _queueProgressSub?.cancel();
    _queueProgressSub = queue.progressStream.listen((qp) {
      _queueProgress = qp;
      final speedText = qp.speedBytesPerSec > 0
          ? '${(qp.speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s'
          : '0.0 MB/s';
      _notifications.showTransferProgress(
        fileName: qp.currentFileName ?? '${files.length} files',
        progress: qp.overallFraction,
        speedText: speedText,
      );
      notifyListeners();
    });

    _queueJobSub?.cancel();
    _queueJobSub = queue.jobUpdateStream.listen((_) {
      notifyListeners();
    });

    notifyListeners();

    try {
      final results = await _sessionManager.sendFiles(
        host: targetIp,
        port: target.port,
        files: files,
        queue: queue,
        targetDeviceName: target.name,
        onVerifySas: (sas) async {
          if (_settings.autoVerifySas) return true;
          final req = SasVerificationRequest(
            sasCode: sas,
            remoteAddress: targetIp,
            remotePort: target.port,
          );
          _pendingSasRequest = req;
          notifyListeners();
          return await req.decision;
        },
        onProgress: onProgress,
      );
      return results;
    } finally {
      // Keep queue around for completed display until resetSession
    }
  }

  /// User confirms SAS code match in UI modal.
  void confirmSas() {
    _pendingSasRequest?.confirm();
    _pendingSasRequest = null;
    notifyListeners();
  }

  /// User rejects SAS code match in UI modal.
  void rejectSas() {
    _pendingSasRequest?.reject();
    _pendingSasRequest = null;
    notifyListeners();
  }

  /// User accepts inbound connection proposal.
  void acceptProposal() {
    _pendingProposal?.accept();
    _pendingProposal = null;
    notifyListeners();
  }

  /// User rejects inbound connection proposal.
  void rejectProposal() {
    _pendingProposal?.reject();
    _pendingProposal = null;
    notifyListeners();
  }

  /// Pauses active sender transfer.
  void pauseTransfer() {
    _sessionManager.pause();
    notifyListeners();
  }

  /// Resumes active sender transfer.
  void resumeTransfer() {
    _sessionManager.resume();
    notifyListeners();
  }

  /// Cancels active transfer session.
  void cancelTransfer([String reason = 'Cancelled by user']) {
    _activeQueue?.cancel();
    _sessionManager.cancelCurrentSession(reason: reason);
    _notifications.cancelAll();
    notifyListeners();
  }

  /// Resets state machine to idle for next transfer.
  void resetSession() {
    _sessionManager.stateMachine.reset();
    _pendingSasRequest = null;
    _pendingProposal = null;
    _activeQueue?.dispose();
    _activeQueue = null;
    _queueProgress = QueueProgress.empty();
    _queueProgressSub?.cancel();
    _queueJobSub?.cancel();
    _notifications.cancelAll();
    notifyListeners();
  }

  /// Clears in-memory transfer history.
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }

  void _recordHistory(SessionState state) {
    final fileName = state.fileName ??
        (state.committedFilePath != null
            ? File(state.committedFilePath!).uri.pathSegments.last
            : 'Unknown file');

    _history.insert(
      0,
      TransferHistoryItem(
        id: const Uuid().v4(),
        fileName: fileName,
        totalBytes: state.totalBytes ?? state.progress?.totalBytes ?? 0,
        peerName: state.remoteDeviceName ?? 'LAN Peer',
        peerAddress: state.remoteDeviceId ?? 'LAN',
        role: state.role,
        finalState: state.state,
        duration: state.progress?.elapsedTime ?? Duration.zero,
        averageSpeed: state.progress?.speedBytesPerSec ?? 0.0,
        timestamp: DateTime.now(),
        committedFilePath: state.committedFilePath,
      ),
    );
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _sasSubscription?.cancel();
    _proposalSubscription?.cancel();
    _queueProgressSub?.cancel();
    _queueJobSub?.cancel();
    _activeQueue?.dispose();
    _sessionManager.dispose();
    _notifications.cancelAll();
    super.dispose();
  }
}
