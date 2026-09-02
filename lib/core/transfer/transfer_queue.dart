import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../models/transfer_progress.dart';
import '../transfer/transfer_sender.dart';

/// Status of a single file in the transfer queue.
enum TransferJobStatus {
  pending,
  transferring,
  completed,
  failed,
  cancelled,
}

/// Represents a single file queued for transfer.
class TransferJob {
  final String id;
  final File file;
  final String fileName;
  final int fileSize;
  TransferJobStatus status;
  TransferSenderResult? result;
  String? errorMessage;
  TransferProgress? progress;

  TransferJob({
    required this.file,
    required this.fileName,
    required this.fileSize,
    this.status = TransferJobStatus.pending,
  }) : id = const Uuid().v4();

  bool get isPending => status == TransferJobStatus.pending;
  bool get isTransferring => status == TransferJobStatus.transferring;
  bool get isCompleted => status == TransferJobStatus.completed;
  bool get isFailed => status == TransferJobStatus.failed;
  bool get isCancelled => status == TransferJobStatus.cancelled;
  bool get isTerminal =>
      isCompleted || isFailed || isCancelled;
}

/// Aggregate progress for the entire transfer queue.
class QueueProgress {
  final int totalFiles;
  final int completedFiles;
  final int failedFiles;
  final int currentFileIndex;
  final String? currentFileName;
  final int totalBytes;
  final int transferredBytes;
  final double speedBytesPerSec;
  final Duration elapsed;
  final TransferProgress? currentFileProgress;

  const QueueProgress({
    required this.totalFiles,
    required this.completedFiles,
    required this.failedFiles,
    required this.currentFileIndex,
    this.currentFileName,
    required this.totalBytes,
    required this.transferredBytes,
    required this.speedBytesPerSec,
    required this.elapsed,
    this.currentFileProgress,
  });

  double get overallFraction =>
      totalBytes > 0 ? transferredBytes / totalBytes : 0.0;

  bool get isComplete =>
      completedFiles + failedFiles >= totalFiles;

  factory QueueProgress.empty() => const QueueProgress(
        totalFiles: 0,
        completedFiles: 0,
        failedFiles: 0,
        currentFileIndex: 0,
        totalBytes: 0,
        transferredBytes: 0,
        speedBytesPerSec: 0,
        elapsed: Duration.zero,
      );
}

/// Manages an ordered queue of files to transfer sequentially over a single
/// authenticated connection. Emits aggregate and per-file progress.
class TransferQueue {
  final List<TransferJob> _jobs = [];
  final _progressController = StreamController<QueueProgress>.broadcast();
  final _jobUpdateController = StreamController<TransferJob>.broadcast();

  int _completedFiles = 0;
  int _failedFiles = 0;
  int _bytesTransferredBefore = 0; // bytes from completed files
  bool _isCancelled = false;
  final Stopwatch _stopwatch = Stopwatch();

  /// Unmodifiable view of the current job list.
  List<TransferJob> get jobs => List.unmodifiable(_jobs);

  /// Stream of aggregate queue progress updates.
  Stream<QueueProgress> get progressStream => _progressController.stream;

  /// Stream of individual job status updates.
  Stream<TransferJob> get jobUpdateStream => _jobUpdateController.stream;

  /// Total size of all files in the queue.
  int get totalBytes => _jobs.fold(0, (sum, j) => sum + j.fileSize);

  /// Number of files in the queue.
  int get totalFiles => _jobs.length;

  /// Whether the queue has been cancelled.
  bool get isCancelled => _isCancelled;

  /// Whether all files have been processed.
  bool get isComplete =>
      _completedFiles + _failedFiles >= _jobs.length && _jobs.isNotEmpty;

  /// Current file index being transferred (0-based).
  int get currentIndex => _completedFiles + _failedFiles;

  /// Adds files to the queue. Must be called before [start].
  void addFiles(List<File> files) {
    for (final file in files) {
      if (file.existsSync()) {
        final job = TransferJob(
          file: file,
          fileName: file.uri.pathSegments.last,
          fileSize: file.lengthSync(),
        );
        _jobs.add(job);
      }
    }
  }

  /// Removes a pending job from the queue by ID. Returns true if removed.
  bool removeJob(String jobId) {
    final index = _jobs.indexWhere((j) => j.id == jobId && j.isPending);
    if (index >= 0) {
      _jobs.removeAt(index);
      return true;
    }
    return false;
  }

  /// Cancels the entire queue. Running transfer will be cancelled via the
  /// [CancellationToken] passed to [start].
  void cancel() {
    _isCancelled = true;
    for (final job in _jobs) {
      if (job.isPending) {
        job.status = TransferJobStatus.cancelled;
        _jobUpdateController.add(job);
      }
    }
  }

  /// Resets the queue for reuse.
  void reset() {
    _jobs.clear();
    _completedFiles = 0;
    _failedFiles = 0;
    _bytesTransferredBefore = 0;
    _isCancelled = false;
    _stopwatch.reset();
  }

  /// Starts the elapsed time stopwatch.
  void startTimer() {
    if (!_stopwatch.isRunning) {
      _stopwatch.start();
    }
  }

  /// Stops the elapsed time stopwatch.
  void stopTimer() {
    _stopwatch.stop();
  }

  /// Builds aggregate progress from current state.
  QueueProgress _buildProgress({
    TransferProgress? currentFileProgress,
  }) {
    final currentTransferred = currentFileProgress?.transferredBytes ?? 0;
    final totalTransferred = _bytesTransferredBefore + currentTransferred;
    final currentJob = currentIndex < _jobs.length ? _jobs[currentIndex] : null;

    return QueueProgress(
      totalFiles: _jobs.length,
      completedFiles: _completedFiles,
      failedFiles: _failedFiles,
      currentFileIndex: currentIndex,
      currentFileName: currentJob?.fileName,
      totalBytes: totalBytes,
      transferredBytes: totalTransferred,
      speedBytesPerSec: currentFileProgress?.speedBytesPerSec ?? 0.0,
      elapsed: _stopwatch.elapsed,
      currentFileProgress: currentFileProgress,
    );
  }

  /// Emits current aggregate progress.
  void emitProgress({TransferProgress? currentFileProgress}) {
    if (!_progressController.isClosed) {
      _progressController.add(_buildProgress(
        currentFileProgress: currentFileProgress,
      ));
    }
  }

  /// Marks current job as transferring and notifies.
  void markJobTransferring(TransferJob job) {
    job.status = TransferJobStatus.transferring;
    if (!_jobUpdateController.isClosed) {
      _jobUpdateController.add(job);
    }
  }

  /// Marks current job as completed and notifies.
  void markJobCompleted(TransferJob job, TransferSenderResult result) {
    job.status = TransferJobStatus.completed;
    job.result = result;
    _completedFiles++;
    _bytesTransferredBefore += job.fileSize;
    if (!_jobUpdateController.isClosed) {
      _jobUpdateController.add(job);
    }
  }

  /// Marks current job as failed and notifies.
  void markJobFailed(TransferJob job, String error) {
    job.status = TransferJobStatus.failed;
    job.errorMessage = error;
    _failedFiles++;
    _bytesTransferredBefore += job.fileSize; // count towards progress
    if (!_jobUpdateController.isClosed) {
      _jobUpdateController.add(job);
    }
  }

  /// Disposes stream controllers.
  void dispose() {
    _progressController.close();
    _jobUpdateController.close();
  }
}
