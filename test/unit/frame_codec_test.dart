import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/protocol/frame_codec.dart';
import 'package:secure_lan_transfer/core/protocol/frame_stream_transformer.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';
import 'package:test/test.dart';

void main() {
  late CipherSuite cipherSuite;
  late FrameCodec frameCodec;
  late SessionKeys senderKeys;
  late SessionKeys receiverKeys;

  setUp(() async {
    cipherSuite = CipherSuite();
    frameCodec = FrameCodec(cipherSuite: cipherSuite);

    final aliceKeyPair = await cipherSuite.generateKeyPair();
    final bobKeyPair = await cipherSuite.generateKeyPair();

    final aliceSecret = await cipherSuite.computeSharedSecret(
      localKeyPair: aliceKeyPair.keyPair,
      remotePublicKeyBytes: bobKeyPair.publicKeyBytes,
    );
    final bobSecret = await cipherSuite.computeSharedSecret(
      localKeyPair: bobKeyPair.keyPair,
      remotePublicKeyBytes: aliceKeyPair.publicKeyBytes,
    );

    final transcriptHash = Uint8List(32)..fillRange(0, 32, 0xAA);

    senderKeys = await SessionKeys.derive(
      sharedSecret: aliceSecret,
      initiatorNonce: aliceKeyPair.nonce,
      receiverNonce: bobKeyPair.nonce,
      transcriptHash: transcriptHash,
      isInitiator: true,
    );

    receiverKeys = await SessionKeys.derive(
      sharedSecret: bobSecret,
      initiatorNonce: aliceKeyPair.nonce,
      receiverNonce: bobKeyPair.nonce,
      transcriptHash: transcriptHash,
      isInitiator: false,
    );
  });

  group('1. Wire Frame Header Serialization & Layout (34 Bytes Fixed)', () {
    test('Header fields serialize to exact byte offsets matching specification', () async {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      const streamId = 0x1234;
      const sequence = 0x56789ABC;

      final frame = Frame.fileChunk(
        streamId: streamId,
        chunkIndex: sequence,
        chunkData: payload,
        paddingLen: 10,
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);

      expect(wireBytes.length, equals(FrameCodec.headerSize + payload.length + 10));

      final headerData = ByteData.sublistView(wireBytes, 0, FrameCodec.headerSize);

      // 1. Magic (0..3) == 0x534C4654 ('SLFT')
      expect(headerData.getUint32(0, Endian.big), equals(FrameCodec.magicValue));
      expect(wireBytes[0], equals(0x53));
      expect(wireBytes[1], equals(0x4C));
      expect(wireBytes[2], equals(0x46));
      expect(wireBytes[3], equals(0x54));

      // 2. Version (4) == 0x01
      expect(headerData.getUint8(4), equals(FrameCodec.protocolVersion));

      // 3. Type (5) == fileChunk opcode (0x20)
      expect(headerData.getUint8(5), equals(FrameType.fileChunk.opcode));

      // 4. Stream ID (6..7) == 0x1234
      expect(headerData.getUint16(6, Endian.big), equals(streamId));

      // 5. Sequence (8..11) == 0x56789ABC
      expect(headerData.getUint32(8, Endian.big), equals(sequence));

      // 6. Padding Len (16..17) == 10
      expect(headerData.getUint16(16, Endian.big), equals(10));

      // 7. Poly1305 MAC Tag (18..33) is 16 non-zero bytes
      final macTag = Uint8List.sublistView(wireBytes, 18, 34);
      expect(macTag.length, equals(16));
      expect(macTag.any((b) => b != 0), isTrue);
    });

    test('All 16 FrameType enum opcodes encode and decode deterministically', () async {
      for (final type in FrameType.values) {
        final frame = Frame(
          type: type,
          streamId: 42,
          sequence: 7,
          payload: Uint8List.fromList(utf8.encode('test-${type.name}')),
        );

        final encoded = await frameCodec.encodeFrame(frame, keys: senderKeys);
        final decoded = await frameCodec.decodeFrame(encoded, keys: receiverKeys);

        expect(decoded.type, equals(type));
        expect(decoded.streamId, equals(42));
        expect(decoded.sequence, equals(7));
        expect(utf8.decode(decoded.payload), equals('test-${type.name}'));
      }
    });

    test('Unencrypted frame encoding (keys = null) uses raw payload and zero MAC tag', () async {
      final payload = Uint8List.fromList([10, 20, 30, 40]);
      final frame = Frame(
        type: FrameType.handshakeInit,
        streamId: 1,
        sequence: 0,
        payload: payload,
      );

      final encoded = await frameCodec.encodeFrame(frame, keys: null);
      final decoded = await frameCodec.decodeFrame(encoded, keys: null);

      expect(decoded.type, equals(FrameType.handshakeInit));
      expect(decoded.payload, equals(payload));

      final tag = Uint8List.sublistView(encoded, 18, 34);
      expect(tag.every((b) => b == 0), isTrue);
    });
  });

  group('2. Structured Payload Serialization', () {
    test('FileMetaPayload serializes to JSON and recovers all fields', () {
      final shaBytes = Uint8List(32)..fillRange(0, 32, 0xEE);
      final meta = FileMetaPayload(
        fileName: 'dataset.tar.gz',
        totalBytes: 1073741824,
        rootSha256: shaBytes,
        chunkSize: 65536,
        totalChunks: 16384,
        mimeType: 'application/gzip',
        customMetadata: {'author': 'engineer', 'priority': 1},
      );

      final bytes = meta.toBytes();
      final decoded = FileMetaPayload.fromBytes(bytes);

      expect(decoded.fileName, equals('dataset.tar.gz'));
      expect(decoded.totalBytes, equals(1073741824));
      expect(decoded.rootSha256, equals(shaBytes));
      expect(decoded.chunkSize, equals(65536));
      expect(decoded.totalChunks, equals(16384));
      expect(decoded.mimeType, equals('application/gzip'));
      expect(decoded.customMetadata?['author'], equals('engineer'));
    });

    test('ChunkAckPayload serializes to 6 big-endian bytes', () {
      const ack = ChunkAckPayload(chunkIndex: 123456, creditsGranted: 4);
      final bytes = ack.toBytes();

      expect(bytes.length, equals(6));
      final decoded = ChunkAckPayload.fromBytes(bytes);
      expect(decoded.chunkIndex, equals(123456));
      expect(decoded.creditsGranted, equals(4));
    });

    test('TransferErrorPayload serializes error code and message', () {
      const err = TransferErrorPayload(errorCode: 0x5001, message: 'Disk quota exceeded');
      final bytes = err.toBytes();
      final decoded = TransferErrorPayload.fromBytes(bytes);

      expect(decoded.errorCode, equals(0x5001));
      expect(decoded.message, equals('Disk quota exceeded'));
    });

    test('PingPongPayload serializes 64-bit millisecond timestamp', () {
      const ping = PingPongPayload(timestamp: 1725100000000);
      final bytes = ping.toBytes();
      expect(bytes.length, equals(8));
      final decoded = PingPongPayload.fromBytes(bytes);
      expect(decoded.timestamp, equals(1725100000000));
    });
  });

  group('3. ChaCha20 Length Prefix Masking & Unmasking', () {
    test('Masked length conceals actual length and decodes faithfully', () {
      final nonce = CipherSuite.deriveNonce(senderKeys.outboundBaseIv, 100);
      const originalLength = 65536;

      final masked = FrameCodec.maskLength(originalLength, senderKeys.maskKey, nonce);
      final rawLengthBytes = Uint8List(4)..buffer.asByteData().setUint32(0, originalLength, Endian.big);

      expect(masked, isNot(equals(rawLengthBytes)));

      final unmasked = FrameCodec.unmaskLength(masked, senderKeys.maskKey, nonce);
      expect(unmasked, equals(originalLength));
    });

    test('Unmasking with different nonce or key fails to recover original length', () {
      final nonce1 = CipherSuite.deriveNonce(senderKeys.outboundBaseIv, 1);
      final nonce2 = CipherSuite.deriveNonce(senderKeys.outboundBaseIv, 2);

      const originalLength = 12345;
      final masked = FrameCodec.maskLength(originalLength, senderKeys.maskKey, nonce1);
      final unmaskedWrongNonce = FrameCodec.unmaskLength(masked, senderKeys.maskKey, nonce2);

      expect(unmaskedWrongNonce, isNot(equals(originalLength)));
    });
  });

  group('4. Poly1305 MAC Authentication & Tamper Detection', () {
    test('Authenticated round-trip preserves payload bit-for-bit', () async {
      final payload = Uint8List.fromList(List.generate(1024, (i) => (i * 7) % 256));
      final frame = Frame.fileChunk(streamId: 99, chunkIndex: 5, chunkData: payload);

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);
      final decoded = await frameCodec.decodeFrame(wireBytes, keys: receiverKeys);

      expect(decoded.payload, equals(payload));
      expect(decoded.streamId, equals(99));
      expect(decoded.sequence, equals(5));
    });

    test('1-bit flip in 18-byte AAD header triggers MAC authentication failure', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList([1, 2, 3, 4]),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);
      final tampered = Uint8List.fromList(wireBytes);
      tampered[6] ^= 0x01; // Flip bit in streamId

      expect(
        () async => await frameCodec.decodeFrame(tampered, keys: receiverKeys),
        throwsA(anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>())),
      );
    });

    test('1-bit flip in ciphertext payload triggers MAC authentication failure', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList([10, 20, 30, 40, 50]),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);
      final tampered = Uint8List.fromList(wireBytes);
      tampered[FrameCodec.headerSize + 2] ^= 0x80; // Flip bit in ciphertext

      expect(
        () async => await frameCodec.decodeFrame(tampered, keys: receiverKeys),
        throwsA(anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>())),
      );
    });

    test('1-bit flip in 16-byte Poly1305 MAC tag triggers MAC authentication failure', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList([10, 20, 30, 40]),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);
      final tampered = Uint8List.fromList(wireBytes);
      tampered[18 + 5] ^= 0x01; // Flip bit in MAC tag

      expect(
        () async => await frameCodec.decodeFrame(tampered, keys: receiverKeys),
        throwsA(anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>())),
      );
    });

    test('Corrupted magic bytes in wire frame throws FrameCodecException', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList([1, 2]),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);
      final tampered = Uint8List.fromList(wireBytes);
      tampered[0] = 0x00; // Corrupt magic 'S'

      expect(
        () async => await frameCodec.decodeFrame(tampered, keys: receiverKeys),
        throwsA(isA<FrameCodecException>()),
      );
    });
  });

  group('5. TCP Stream Fragmentation & Reassembly (FrameStreamTransformer)', () {
    test('Reassembles frames delivered in 1-byte TCP stream chunks', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(utf8.encode('Hello 1-byte fragmentation world')),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final receivedFrames = <Frame>[];
      final frameCompleter = Completer<void>();

      byteController.stream.transform(transformer).listen(
        (f) {
          receivedFrames.add(f);
          frameCompleter.complete();
        },
        onError: (Object e) => frameCompleter.completeError(e),
      );

      // Feed 1 byte per chunk
      for (int i = 0; i < wireBytes.length; i++) {
        byteController.add(Uint8List.fromList([wireBytes[i]]));
      }
      await byteController.close();

      await frameCompleter.future;
      expect(receivedFrames.length, equals(1));
      expect(
        utf8.decode(receivedFrames.first.payload),
        equals('Hello 1-byte fragmentation world'),
      );
    });

    test('Handles multiple coalesced frames in a single incoming TCP packet', () async {
      final framesToSend = <Frame>[
        Frame.ping(streamId: 1, timestamp: 100),
        Frame.fileChunk(
          streamId: 1,
          chunkIndex: 0,
          chunkData: Uint8List.fromList([1, 2, 3]),
        ),
        Frame.chunkAck(streamId: 1, chunkIndex: 0, creditsGranted: 2),
        Frame.transferComplete(streamId: 1, sequence: 1),
        Frame.pong(streamId: 1, timestamp: 100),
      ];

      final totalWireBytes = BytesBuilder();
      for (final f in framesToSend) {
        final encoded = await frameCodec.encodeFrame(f, keys: senderKeys);
        totalWireBytes.add(encoded);
      }

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final receivedFrames = <Frame>[];
      final doneCompleter = Completer<void>();

      byteController.stream.transform(transformer).listen(
        (f) {
          receivedFrames.add(f);
          if (receivedFrames.length == framesToSend.length) {
            doneCompleter.complete();
          }
        },
        onError: (Object e) => doneCompleter.completeError(e),
      );

      // Send all 5 frames in ONE single add() call
      byteController.add(totalWireBytes.toBytes());
      await byteController.close();

      await doneCompleter.future;
      expect(receivedFrames.length, equals(5));
      expect(receivedFrames[0].type, equals(FrameType.ping));
      expect(receivedFrames[1].type, equals(FrameType.fileChunk));
      expect(receivedFrames[2].type, equals(FrameType.chunkAck));
      expect(receivedFrames[3].type, equals(FrameType.transferComplete));
      expect(receivedFrames[4].type, equals(FrameType.pong));
    });

    test('Handles arbitrary prime-sized TCP chunks spanning header/payload boundaries', () async {
      final frame1 = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(List.generate(200, (i) => i % 256)),
      );
      final frame2 = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 1,
        chunkData: Uint8List.fromList(List.generate(300, (i) => (i + 1) % 256)),
      );

      final builder = BytesBuilder();
      builder.add(await frameCodec.encodeFrame(frame1, keys: senderKeys));
      builder.add(await frameCodec.encodeFrame(frame2, keys: senderKeys));
      final allBytes = builder.toBytes();

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final receivedFrames = <Frame>[];
      final doneCompleter = Completer<void>();

      byteController.stream.transform(transformer).listen(
        (f) {
          receivedFrames.add(f);
          if (receivedFrames.length == 2) {
            doneCompleter.complete();
          }
        },
      );

      // Prime chunk slicing: 7, 13, 29, 47, etc.
      final primeSlices = [7, 13, 29, 47, 61, 83, 101];
      int offset = 0;
      int sliceIdx = 0;
      while (offset < allBytes.length) {
        final sliceSize = primeSlices[sliceIdx % primeSlices.length];
        final end = (offset + sliceSize < allBytes.length) ? offset + sliceSize : allBytes.length;
        byteController.add(Uint8List.sublistView(allBytes, offset, end));
        offset = end;
        sliceIdx++;
      }
      await byteController.close();

      await doneCompleter.future;
      expect(receivedFrames.length, equals(2));
      expect(receivedFrames[0].payload, equals(frame1.payload));
      expect(receivedFrames[1].payload, equals(frame2.payload));
    });

    test('Mid-stream session key upgrade seamlessly decrypts subsequent frames', () async {
      // 1. Unencrypted handshake frame
      final initFrame = Frame(
        type: FrameType.handshakeInit,
        streamId: 1,
        sequence: 0,
        payload: Uint8List.fromList(utf8.encode('unencrypted-handshake')),
      );
      final encodedInit = await frameCodec.encodeFrame(initFrame, keys: null);

      // 2. Encrypted data frame
      final chunkFrame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(utf8.encode('encrypted-data-chunk')),
      );
      final encodedChunk = await frameCodec.encodeFrame(chunkFrame, keys: senderKeys);

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: null, // Start unencrypted
      );

      final receivedFrames = <Frame>[];
      final secondFrameCompleter = Completer<void>();

      byteController.stream.transform(transformer).listen(
        (f) {
          receivedFrames.add(f);
          if (f.type == FrameType.handshakeInit) {
            // Upgrade keys post-handshake
            transformer.updateSessionKeys(receiverKeys);
          } else if (f.type == FrameType.fileChunk) {
            secondFrameCompleter.complete();
          }
        },
      );

      byteController.add(encodedInit);
      // Wait microtask for first frame to process and upgrade key
      await Future<void>.delayed(const Duration(milliseconds: 10));
      byteController.add(encodedChunk);
      await byteController.close();

      await secondFrameCompleter.future;
      expect(receivedFrames.length, equals(2));
      expect(utf8.decode(receivedFrames[0].payload), equals('unencrypted-handshake'));
      expect(utf8.decode(receivedFrames[1].payload), equals('encrypted-data-chunk'));
    });
  });
}
