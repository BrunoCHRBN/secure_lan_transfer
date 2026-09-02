import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:convert/convert.dart';
import '../crypto/cipher_suite.dart';
import '../crypto/zero_metadata_staging.dart';
import '../models/transfer_progress.dart';
import '../protocol/frame_codec.dart';
import '../protocol/frame_stream_transformer.dart';
import '../protocol/packet_types.dart';
import '../protocol/session_state.dart';
import 'flow_controller.dart';
import 'speed_tracker.dart';

/// Configuration options for TransferReceiver.
class TransferReceiverOptions {
  final int creditWindowSize;
  final bool secureWipeOnAbort;
  final Duration chunkTimeout;
  final int maxAllowableFileSize;

  const TransferReceiverOptions({
    this.creditWindowSize = 16,
    this.secureWipeOnAbort = false,
    this.chunkTimeout = const Duration(seconds: 15),
    this.maxAllowableFileSize = 100 * 1024 * 1024 * 1024, // 100 GB
  });
}

/// Metadata result returned upon successful file reception and verification.
class TransferReceiverResult {
  final File file;
  final String fileName;
  final int totalBytes;
  final String sha256Digest;
  final Duration elapsed;
  final double averageSpeedBytesPerSec;

  const TransferReceiverResult({
    required this.file,
    required this.fileName,
    required this.totalBytes,
    required this.sha256Digest,
    required this.elapsed,
    required this.averageSpeedBytesPerSec,
  });
}

/// High-performance memory-bounded streaming file receiver with zero-metadata staging,
/// progressive SHA-256 verification, credit-based flow control ACKs, and AEAD decryption.
class TransferReceiver {
  final FrameCodec frameCodec;
  final TransferReceiverOptions options;

  TransferReceiver({
    FrameCodec? frameCodec,
    TransferReceiverOptions? options,
  })  : frameCodec = frameCodec ?? FrameCodec(),
        options = options ?? const TransferReceiverOptions();

  /// Receives, decrypts, and atomically commits a file from [socket] into [destDir].
  Future<TransferReceiverResult> receiveFile(
    Directory destDir,
    Socket socket,
    SessionKeys keys, {
    void Function(TransferProgress)? onProgress,
    CancellationToken? cancelToken,
    Stream<Frame>? incomingFrameStream,
  }) async {
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    final Stream<Frame> frameStream = incomingFrameStream ??
        socket.transform(FrameStreamTransformer(
          codec: frameCodec,
          sessionKeys: keys,
        ));

    StagingFileHandle? stagingHandle;
    SpeedTracker? speedTracker;
    int nextExpectedChunkIndex = 0;
    int transferredBytes = 0;
    FileMetaPayload? metadata;
    TransferReceiverResult? finalResult;

    void cancelListener(String reason) {
      final cancelFrame = Frame.transferCancel(
        streamId: 1,
        reason: reason,
      );
      frameCodec.encodeFrame(cancelFrame, keys: keys).then((encoded) {
        socket.add(encoded);
        socket.flush();
      });
      if (stagingHandle != null && !stagingHandle.isCommitted) {
        stagingHandle.abort(reason: reason);
      }
    }

    if (cancelToken?.isCancelled == true) {
      throw TransferAbortedException(cancelToken!.cancelReason ?? 'Cancelled');
    }
    cancelToken?.onCancel(cancelListener);

    try {
      await for (final frame in frameStream) {
        if (cancelToken?.isCancelled == true) {
          throw TransferAbortedException(cancelToken!.cancelReason ?? 'Cancelled');
        }

        switch (frame.type) {
          case FrameType.fileMeta:
            metadata = FileMetaPayload.fromBytes(frame.payload);
            if (metadata.totalBytes > options.maxAllowableFileSize) {
              final rejectFrame = Frame.metadataReject(
                streamId: frame.streamId,
                reason: 'File size exceeds maximum allowable limit',
              );
              socket.add(await frameCodec.encodeFrame(rejectFrame, keys: keys));
              await socket.flush();
              throw SecurityException('File size ${metadata.totalBytes} exceeds limit');
            }

            stagingHandle = await StagingFileHandle.create(
              destinationDir: destDir,
              originalFilename: metadata.fileName,
              expectedTotalBytes: metadata.totalBytes,
              expectedRootSha256: metadata.rootSha256,
              secureWipeOnAbort: options.secureWipeOnAbort,
            );

            speedTracker = SpeedTracker(totalBytes: metadata.totalBytes);
            speedTracker.start();

            final acceptFrame = Frame.metadataAccept(
              streamId: frame.streamId,
              initialCredits: options.creditWindowSize,
            );
            socket.add(await frameCodec.encodeFrame(acceptFrame, keys: keys));
            await socket.flush();
            break;

          case FrameType.fileChunk:
            if (stagingHandle == null || metadata == null) {
              throw const FormatException('Received data chunk before file metadata');
            }

            // Strict sequence validation
            if (frame.sequence != nextExpectedChunkIndex) {
              final errFrame = Frame.transferError(
                streamId: frame.streamId,
                errorCode: 0x01,
                message:
                    'Out-of-order chunk index: expected $nextExpectedChunkIndex, got ${frame.sequence}',
              );
              socket.add(await frameCodec.encodeFrame(errFrame, keys: keys));
              await socket.flush();
              throw SecurityException(
                'Out-of-order chunk: expected $nextExpectedChunkIndex, got ${frame.sequence}',
              );
            }

            await stagingHandle.writeChunk(frame.payload);
            nextExpectedChunkIndex++;
            transferredBytes += frame.payload.length;

            // Send Credit ACK back to sender (non-blocking streaming)
            final ackFrame = Frame.chunkAck(
              streamId: frame.streamId,
              chunkIndex: frame.sequence,
              creditsGranted: 1,
            );
            socket.add(await frameCodec.encodeFrame(ackFrame, keys: keys));

            if (speedTracker != null) {
              final progress = speedTracker.recordProgress(transferredBytes);
              onProgress?.call(progress);
            }
            break;

          case FrameType.transferPause:
            speedTracker?.pause();
            break;

          case FrameType.transferResume:
            speedTracker?.resume();
            break;

          case FrameType.transferCancel:
            final reason = utf8.decode(frame.payload, allowMalformed: true);
            await stagingHandle?.abort(reason: 'Sender cancelled transfer: $reason');
            throw TransferAbortedException('Sender cancelled transfer: $reason');

          case FrameType.transferError:
            final errPayload = TransferErrorPayload.fromBytes(frame.payload);
            await stagingHandle?.abort(reason: errPayload.message);
            throw TransferAbortedException(
              'Sender error (0x${errPayload.errorCode.toRadixString(16)}): ${errPayload.message}',
            );

          case FrameType.transferComplete:
            if (stagingHandle == null || metadata == null) {
              throw const FormatException('TransferComplete received before metadata');
            }

            // Finalize atomic commit and root SHA-256 verification
            final committedFile = await stagingHandle.commitAndVerify();

            // Send TransferVerified confirmation to sender
            final verifiedFrame = Frame.transferVerified(
              streamId: frame.streamId,
              sequence: frame.sequence,
            );
            socket.add(await frameCodec.encodeFrame(verifiedFrame, keys: keys));
            await socket.flush();

            if (speedTracker != null) {
              final completedProgress = speedTracker.recordProgress(
                metadata.totalBytes,
                state: TransferState.completed,
              );
              onProgress?.call(completedProgress);
            }

            final elapsed = speedTracker?.recordProgress(metadata.totalBytes).elapsedTime ??
                Duration.zero;
            final avgSpeed = elapsed.inMilliseconds > 0
                ? metadata.totalBytes / (elapsed.inMilliseconds / 1000.0)
                : 0.0;

            finalResult = TransferReceiverResult(
              file: committedFile,
              fileName: metadata.fileName,
              totalBytes: metadata.totalBytes,
              sha256Digest: hex.encode(metadata.rootSha256),
              elapsed: elapsed,
              averageSpeedBytesPerSec: avgSpeed,
            );
            return finalResult;

          default:
            break;
        }
      }

      if (finalResult != null) {
        return finalResult;
      }
      throw const SocketException('Stream finished before transferComplete frame');
    } catch (e) {
      if (stagingHandle != null && !stagingHandle.isCommitted) {
        await stagingHandle.abort(reason: e.toString());
      }
      rethrow;
    }
  }
}
