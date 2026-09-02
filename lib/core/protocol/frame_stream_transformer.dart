import 'dart:async';
import 'dart:typed_data';
import '../crypto/cipher_suite.dart';
import 'frame_codec.dart';
import 'packet_types.dart';

/// StreamTransformer converting an arbitrary chunked TCP byte stream
/// (`Stream<Uint8List>`) into an authenticated, decrypted stream of [Frame] objects.
class FrameStreamTransformer extends StreamTransformerBase<Uint8List, Frame> {
  final FrameCodec codec;
  SessionKeys? sessionKeys;
  final int maxBufferSize;

  FrameStreamTransformer({
    FrameCodec? codec,
    this.sessionKeys,
    this.maxBufferSize = 32 * 1024 * 1024, // 32MB safety guard
  }) : codec = codec ?? FrameCodec();

  /// Dynamically updates session keys post-handshake.
  void updateSessionKeys(SessionKeys keys) {
    sessionKeys = keys;
  }

  @override
  Stream<Frame> bind(Stream<Uint8List> stream) {
    final controller = StreamController<Frame>();
    final accumulator = _BytesAccumulator(maxCapacity: maxBufferSize);
    StreamSubscription<Uint8List>? subscription;
    bool isProcessing = false;
    bool isDone = false;

    // Sequential async processing queue
    Future<void> processAccumulator() async {
      if (isProcessing) return;
      isProcessing = true;

      try {
        while (true) {
          if (accumulator.availableBytes < FrameCodec.headerSize) {
            break; // Need at least 34 bytes for header
          }

          // Peek header bytes without removing from accumulator yet
          final headerBytes = accumulator.peek(FrameCodec.headerSize);
          final headerData = ByteData.sublistView(headerBytes, 0, FrameCodec.headerSize);

          // Verify Magic
          final magic = headerData.getUint32(0, Endian.big);
          if (magic != FrameCodec.magicValue) {
            throw FrameCodecException(
              'Malformed stream: invalid magic bytes 0x${magic.toRadixString(16)}',
            );
          }

          // Verify Version
          final version = headerData.getUint8(4);
          if (version != FrameCodec.protocolVersion) {
            throw FrameCodecException(
              'Malformed stream: unsupported version $version',
            );
          }

          final sequence = headerData.getUint32(8, Endian.big);

          // Unmask payload length
          final int payloadLen;
          final keys = sessionKeys;
          if (keys != null) {
            final nonce = CipherSuite.deriveNonce(keys.inboundBaseIv, sequence);
            final maskedBytes = Uint8List.sublistView(headerBytes, 12, 16);
            payloadLen = FrameCodec.unmaskLength(
              maskedBytes,
              keys.maskKey,
              nonce,
            );
          } else {
            payloadLen = headerData.getUint32(12, Endian.big);
          }

          if (payloadLen < 0 || payloadLen > FrameCodec.maxPayloadSize) {
            throw FrameCodecException('Unmasked payload length ($payloadLen) exceeds limit');
          }

          final paddingLen = headerData.getUint16(16, Endian.big);
          final totalFrameSize = FrameCodec.headerSize + payloadLen + paddingLen;

          if (accumulator.availableBytes < totalFrameSize) {
            break; // Awaiting remaining payload and padding bytes
          }

          // Extract full frame bytes from accumulator
          final completeFrameBytes = accumulator.readBytes(totalFrameSize);

          // Decode and authenticate frame
          final frame = await codec.decodeFrame(completeFrameBytes, keys: keys);
          if (!controller.isClosed) {
            controller.add(frame);
          }
        }

        if (isDone && !controller.isClosed) {
          if (accumulator.availableBytes > 0 && controller.hasListener) {
            controller.addError(
              FrameCodecException(
                'Stream closed prematurely with ${accumulator.availableBytes} unparsed bytes in buffer',
              ),
            );
          }
          await controller.close();
        }
      } catch (e, st) {
        if (!controller.isClosed && controller.hasListener && !isDone) {
          controller.addError(e, st);
          await controller.close();
        }
        await subscription?.cancel();
      } finally {
        isProcessing = false;
      }
    }

    controller.onListen = () {
      subscription = stream.listen(
        (chunk) {
          if (chunk.isNotEmpty && !isDone) {
            try {
              accumulator.addChunk(chunk);
            } catch (e, st) {
              if (!controller.isClosed && controller.hasListener && !isDone) {
                controller.addError(e, st);
                controller.close();
              }
              subscription?.cancel();
              return;
            }
            unawaited(processAccumulator());
          }
        },
        onError: (Object e, StackTrace st) {
          if (!controller.isClosed && controller.hasListener && !isDone) {
            controller.addError(e, st);
            controller.close();
          }
        },
        onDone: () {
          isDone = true;
          unawaited(processAccumulator());
        },
        cancelOnError: true,
      );
    };

    controller.onPause = () => subscription?.pause();
    controller.onResume = () => subscription?.resume();
    controller.onCancel = () {
      isDone = true;
      return subscription?.cancel();
    };

    return controller.stream;
  }
}

/// Dynamic zero-copy chunk accumulator with fast indexing and sliding compacting.
class _BytesAccumulator {
  final int maxCapacity;
  final List<Uint8List> _chunks = [];
  int _totalBytes = 0;

  _BytesAccumulator({required this.maxCapacity});

  int get availableBytes => _totalBytes;

  void addChunk(Uint8List chunk) {
    if (_totalBytes + chunk.length > maxCapacity) {
      throw FrameCodecException(
        'Accumulator buffer overflow: ${_totalBytes + chunk.length} exceeds max capacity $maxCapacity',
      );
    }
    _chunks.add(chunk);
    _totalBytes += chunk.length;
  }

  Uint8List peek(int count) {
    if (count > _totalBytes) {
      throw RangeError('Cannot peek $count bytes; only $_totalBytes available');
    }
    if (_chunks.isNotEmpty && _chunks.first.length >= count) {
      return Uint8List.sublistView(_chunks.first, 0, count);
    }
    final out = Uint8List(count);
    int copied = 0;
    for (final chunk in _chunks) {
      final toCopy = (count - copied < chunk.length) ? count - copied : chunk.length;
      out.setRange(copied, copied + toCopy, chunk);
      copied += toCopy;
      if (copied == count) break;
    }
    return out;
  }

  Uint8List readBytes(int count) {
    if (count > _totalBytes) {
      throw RangeError('Cannot read $count bytes; only $_totalBytes available');
    }

    final out = Uint8List(count);
    int copied = 0;

    while (copied < count && _chunks.isNotEmpty) {
      final first = _chunks.first;
      final needed = count - copied;

      if (first.length <= needed) {
        out.setRange(copied, copied + first.length, first);
        copied += first.length;
        _chunks.removeAt(0);
      } else {
        out.setRange(copied, copied + needed, Uint8List.sublistView(first, 0, needed));
        _chunks[0] = Uint8List.sublistView(first, needed);
        copied += needed;
      }
    }

    _totalBytes -= count;
    return out;
  }
}
