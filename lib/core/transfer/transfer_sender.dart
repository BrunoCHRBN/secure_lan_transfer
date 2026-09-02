import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import '../crypto/cipher_suite.dart';
import '../crypto/zero_metadata_staging.dart';
import '../models/transfer_progress.dart';
import '../protocol/frame_codec.dart';
import '../protocol/frame_stream_transformer.dart';
import '../protocol/packet_types.dart';
import '../protocol/session_state.dart';
import 'flow_controller.dart';
import 'rate_limiter.dart';
import 'speed_tracker.dart';

/// Configuration options for TransferSender.
class TransferSenderOptions {
  final int chunkSize;
  final int defaultInitialCredits;
  final Duration socketTimeout;
  final bool enablePadding;
  final int? rateLimitBytesPerSec;

  const TransferSenderOptions({
    this.chunkSize = 262144, // 256 KB
    this.defaultInitialCredits = 16,
    this.socketTimeout = const Duration(seconds: 15),
    this.enablePadding = false,
    this.rateLimitBytesPerSec,
  });
}

/// Metadata result returned upon successful transfer completion.
class TransferSenderResult {
  final String fileName;
  final int totalBytes;
  final int totalChunks;
  final String sha256Digest;
  final Duration elapsed;
  final double averageSpeedBytesPerSec;

  const TransferSenderResult({
    required this.fileName,
    required this.totalBytes,
    required this.totalChunks,
    required this.sha256Digest,
    required this.elapsed,
    required this.averageSpeedBytesPerSec,
  });
}

/// High-performance memory-bounded streaming file sender with credit-based flow control,
/// socket backpressure, progressive SHA-256 calculation, and AEAD encryption.
class TransferSender {
  final FrameCodec frameCodec;
  final TransferSenderOptions options;
  final FlowController flowController;

  SpeedTracker? _speedTracker;
  bool _isPaused = false;

  TransferSender({
    FrameCodec? frameCodec,
    TransferSenderOptions? options,
    FlowController? flowController,
  })  : frameCodec = frameCodec ?? FrameCodec(),
        options = options ?? const TransferSenderOptions(),
        flowController = flowController ??
            FlowController(
              initialCredits: (options ?? const TransferSenderOptions()).defaultInitialCredits,
            );

  bool get isPaused => _isPaused;

  /// Pauses the transfer stream.
  void pause() {
    _isPaused = true;
    flowController.pause();
    _speedTracker?.pause();
  }

  /// Resumes the transfer stream.
  void resume() {
    if (_isPaused) {
      _isPaused = false;
      flowController.resume();
      _speedTracker?.resume();
    }
  }

  /// Transmits a file over [socket] using authenticated encryption [keys].
  Future<TransferSenderResult> sendFile(
    File file,
    Socket socket,
    SessionKeys keys, {
    int streamId = 1,
    void Function(TransferProgress)? onProgress,
    CancellationToken? cancelToken,
    String? customFileName,
    Stream<Frame>? incomingFrameStream,
  }) async {
    flowController.reset();
    _isPaused = false;

    if (!await file.exists()) {
      throw FileSystemException('Source file not found', file.path);
    }

    final totalBytes = await file.length();
    final totalChunks = (totalBytes == 0)
        ? 0
        : (totalBytes + options.chunkSize - 1) ~/ options.chunkSize;

    // Calculate full file root SHA-256 hash
    final digest = await crypto.sha256.bind(file.openRead()).first;
    final rootSha256Bytes = Uint8List.fromList(digest.bytes);
    final sha256Hex = hex.encode(rootSha256Bytes);

    final effectiveFileName = customFileName ?? p.basename(file.path);

    // Setup incoming control frame handling
    final Stream<Frame> frames = incomingFrameStream ??
        socket.transform(FrameStreamTransformer(
          codec: frameCodec,
          sessionKeys: keys,
        ));

    final metadataAcceptCompleter = Completer<void>();
    final transferVerifiedCompleter = Completer<void>();
    unawaited(metadataAcceptCompleter.future.catchError((_) {}));
    unawaited(transferVerifiedCompleter.future.catchError((_) {}));
    StreamSubscription<Frame>? frameSub;

    frameSub = frames.listen(
      (frame) {
        switch (frame.type) {
          case FrameType.metadataAccept:
            if (frame.payload.length >= 2) {
              final credits =
                  ByteData.sublistView(frame.payload).getUint16(0, Endian.big);
              flowController.replenishCredits(credits - flowController.availableCredits);
            }
            if (!metadataAcceptCompleter.isCompleted) {
              metadataAcceptCompleter.complete();
            }
            break;

          case FrameType.metadataReject:
            final reason = utf8.decode(frame.payload, allowMalformed: true);
            final error = TransferAbortedException('Metadata rejected: $reason');
            if (!metadataAcceptCompleter.isCompleted) {
              metadataAcceptCompleter.completeError(error);
            }
            break;

          case FrameType.chunkAck:
            try {
              final ack = ChunkAckPayload.fromBytes(frame.payload);
              flowController.replenishCredits(ack.creditsGranted);
            } catch (_) {}
            break;

          case FrameType.transferPause:
            _isPaused = true;
            flowController.pause();
            _speedTracker?.pause();
            break;

          case FrameType.transferResume:
            if (_isPaused) {
              _isPaused = false;
              flowController.resume();
              _speedTracker?.resume();
            }
            break;

          case FrameType.transferCancel:
            final reason = utf8.decode(frame.payload, allowMalformed: true);
            final cancelErr =
                TransferAbortedException('Receiver cancelled transfer: $reason');
            flowController.close(cancelErr);
            if (!transferVerifiedCompleter.isCompleted) {
              transferVerifiedCompleter.completeError(cancelErr);
            }
            break;

          case FrameType.transferError:
            try {
              final errPayload = TransferErrorPayload.fromBytes(frame.payload);
              final err = TransferAbortedException(
                'Receiver error (0x${errPayload.errorCode.toRadixString(16)}): ${errPayload.message}',
              );
              flowController.close(err);
              if (!transferVerifiedCompleter.isCompleted) {
                transferVerifiedCompleter.completeError(err);
              }
            } catch (_) {
              flowController.close();
            }
            break;

          case FrameType.transferVerified:
            if (!transferVerifiedCompleter.isCompleted) {
              transferVerifiedCompleter.complete();
            }
            break;

          default:
            break;
        }
      },
      onError: (Object e, StackTrace st) {
        flowController.close(e, st);
        if (!metadataAcceptCompleter.isCompleted) {
          metadataAcceptCompleter.completeError(e, st);
        }
        if (!transferVerifiedCompleter.isCompleted) {
          transferVerifiedCompleter.completeError(e, st);
        }
      },
      onDone: () {
        const doneErr = SocketException(
            'Remote socket closed prematurely before transfer completion');
        flowController.close(doneErr);
        if (!metadataAcceptCompleter.isCompleted) {
          metadataAcceptCompleter.completeError(doneErr);
        }
        if (!transferVerifiedCompleter.isCompleted) {
          transferVerifiedCompleter.completeError(doneErr);
        }
      },
      cancelOnError: true,
    );

    RandomAccessFile? raf;
    try {
      // 1. Send File Metadata Manifest
      final metadata = FileMetaPayload(
        fileName: effectiveFileName,
        totalBytes: totalBytes,
        rootSha256: rootSha256Bytes,
        chunkSize: options.chunkSize,
        totalChunks: totalChunks,
      );

      final metaFrame = Frame.fileMeta(streamId: streamId, metadata: metadata);
      final encodedMeta = await frameCodec.encodeFrame(metaFrame, keys: keys);
      socket.add(encodedMeta);
      await socket.flush();

      // 2. Await Metadata Acceptance from Receiver
      await metadataAcceptCompleter.future.timeout(
        options.socketTimeout,
        onTimeout: () => throw TimeoutException('Timed out waiting for metadata acceptance'),
      );

      // 3. Initialize Speed Tracker & Flow Controller
      final speedTracker = SpeedTracker(totalBytes: totalBytes);
      _speedTracker = speedTracker;
      speedTracker.start();

      final rateLimiter = (options.rateLimitBytesPerSec != null && options.rateLimitBytesPerSec! > 0)
          ? TokenBucketRateLimiter(bytesPerSecond: options.rateLimitBytesPerSec!)
          : null;

      raf = await file.open(mode: FileMode.read);
      int transferredBytes = 0;

      // 4. Chunk Streaming Loop
      for (int chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
        // Check cooperative cancellation
        if (cancelToken?.isCancelled == true) {
          final cancelFrame = Frame.transferCancel(
            streamId: streamId,
            reason: cancelToken!.cancelReason ?? 'Cancelled by user',
          );
          final encoded = await frameCodec.encodeFrame(cancelFrame, keys: keys);
          socket.add(encoded);
          await socket.flush();
          throw TransferAbortedException(
            cancelToken.cancelReason ?? 'Transfer cancelled by user',
          );
        }

        // Wait on flow control credits (gated by receiver ACKs and pause state)
        await flowController.acquireCredit(cancelToken: cancelToken);

        // Read chunk bounded in 64KB heap buffer
        final remaining = totalBytes - (chunkIndex * options.chunkSize);
        final currentChunkSize = min(options.chunkSize, remaining);

        // Apply rate limiting if configured
        if (rateLimiter != null) {
          await rateLimiter.consume(currentChunkSize, cancelToken: cancelToken);
        }

        final chunkBuffer = Uint8List(currentChunkSize);
        await raf.readInto(chunkBuffer, 0, currentChunkSize);

        // Assemble and AEAD-encrypt wire frame
        final chunkFrame = Frame.fileChunk(
          streamId: streamId,
          chunkIndex: chunkIndex,
          chunkData: chunkBuffer,
        );

        final encodedChunk = await frameCodec.encodeFrame(chunkFrame, keys: keys);

        // Dispatch frame and flush kernel socket buffer
        socket.add(encodedChunk);
        await socket.flush();

        transferredBytes += currentChunkSize;
        final progress = speedTracker.recordProgress(
          transferredBytes,
          state: _isPaused ? TransferState.paused : TransferState.transferring,
        );
        onProgress?.call(progress);
      }

      // 5. Send Transfer Complete Frame
      final completeFrame = Frame.transferComplete(
        streamId: streamId,
        sequence: totalChunks,
        rootSha256: rootSha256Bytes,
      );
      final encodedComplete = await frameCodec.encodeFrame(completeFrame, keys: keys);
      socket.add(encodedComplete);
      await socket.flush();

      // 6. Await Verification from Receiver
      await transferVerifiedCompleter.future.timeout(
        options.socketTimeout,
        onTimeout: () => throw TimeoutException('Timed out waiting for transfer verification'),
      );

      final finalProgress = speedTracker.recordProgress(
        totalBytes,
        state: TransferState.completed,
      );
      onProgress?.call(finalProgress);

      final elapsed = speedTracker.recordProgress(totalBytes).elapsedTime;
      final avgSpeed = elapsed.inMilliseconds > 0
          ? totalBytes / (elapsed.inMilliseconds / 1000.0)
          : 0.0;

      return TransferSenderResult(
        fileName: effectiveFileName,
        totalBytes: totalBytes,
        totalChunks: totalChunks,
        sha256Digest: sha256Hex,
        elapsed: elapsed,
        averageSpeedBytesPerSec: avgSpeed,
      );
    } finally {
      await raf?.close();
      await frameSub.cancel();
    }
  }
}
