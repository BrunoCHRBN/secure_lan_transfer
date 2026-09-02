import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/crypto/zero_metadata_staging.dart';
import 'package:secure_lan_transfer/core/protocol/frame_codec.dart';
import 'package:secure_lan_transfer/core/protocol/frame_stream_transformer.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';
import 'package:secure_lan_transfer/core/transfer/transfer_receiver.dart';
import 'package:secure_lan_transfer/core/transfer/transfer_sender.dart';
import 'package:test/test.dart';

void main() {
  late CipherSuite cipherSuite;
  late FrameCodec frameCodec;
  late SessionKeys senderKeys;
  late SessionKeys receiverKeys;
  late Directory tempDir;

  setUp(() async {
    cipherSuite = CipherSuite();
    frameCodec = FrameCodec(cipherSuite: cipherSuite);

    tempDir = await Directory.systemTemp.createTemp('slft_adversarial_m2_');

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

    final transcriptHash = Uint8List(32)..fillRange(0, 32, 0x42);

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

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CHALLENGER M2 - TIER 1: Wire Frame Boundary & Extreme Fragmentation Attacks', () {
    test('1-byte slice stream across 50 heterogeneous frames (all opcodes, payloads & padding)', () async {
      final testFrames = <Frame>[];
      for (int i = 0; i < 50; i++) {
        final opcode = FrameType.values[i % FrameType.values.length];
        final payloadSize = (i * 37) % 512;
        final payload = Uint8List.fromList(List.generate(payloadSize, (j) => (i + j) % 256));
        final paddingLen = (i % 3 == 0) ? (i * 5) % 64 : 0;

        testFrames.add(Frame(
          type: opcode,
          streamId: 100 + (i % 5),
          sequence: i,
          payload: payload,
          paddingLen: paddingLen,
        ));
      }

      final totalWireBytes = BytesBuilder();
      for (final f in testFrames) {
        final encoded = await frameCodec.encodeFrame(f, keys: senderKeys);
        totalWireBytes.add(encoded);
      }
      final allBytes = totalWireBytes.toBytes();

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final receivedFrames = <Frame>[];
      final completion = Completer<void>();

      byteController.stream.transform(transformer).listen(
        (f) {
          receivedFrames.add(f);
          if (receivedFrames.length == testFrames.length) {
            completion.complete();
          }
        },
        onError: (Object e, StackTrace st) {
          if (!completion.isCompleted) {
            completion.completeError(e, st);
          }
        },
      );

      // Feed exactly 1 byte per event
      for (int b = 0; b < allBytes.length; b++) {
        byteController.add(Uint8List.fromList([allBytes[b]]));
      }
      await byteController.close();

      await completion.future.timeout(const Duration(seconds: 15));

      expect(receivedFrames.length, equals(testFrames.length));
      for (int i = 0; i < testFrames.length; i++) {
        expect(receivedFrames[i].type, equals(testFrames[i].type));
        expect(receivedFrames[i].streamId, equals(testFrames[i].streamId));
        expect(receivedFrames[i].sequence, equals(testFrames[i].sequence));
        expect(receivedFrames[i].payload, equals(testFrames[i].payload));
        expect(receivedFrames[i].paddingLen, equals(testFrames[i].paddingLen));
      }
    });

    test('Random byte slice fragmentation (1..19 bytes) across 100 continuous frames', () async {
      final testFrames = <Frame>[];
      for (int i = 0; i < 100; i++) {
        testFrames.add(Frame.fileChunk(
          streamId: 1,
          chunkIndex: i,
          chunkData: Uint8List.fromList(List.generate(128, (j) => (i ^ j) & 0xFF)),
          paddingLen: (i % 2 == 0) ? 16 : 0,
        ));
      }

      final totalWireBytes = BytesBuilder();
      for (final f in testFrames) {
        final encoded = await frameCodec.encodeFrame(f, keys: senderKeys);
        totalWireBytes.add(encoded);
      }
      final allBytes = totalWireBytes.toBytes();

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final receivedFrames = <Frame>[];
      final completion = Completer<void>();

      byteController.stream.transform(transformer).listen(
        (f) {
          receivedFrames.add(f);
          if (receivedFrames.length == testFrames.length) {
            completion.complete();
          }
        },
        onError: (Object e) {
          if (!completion.isCompleted) completion.completeError(e);
        },
      );

      final rng = Random(0x1337);
      int offset = 0;
      while (offset < allBytes.length) {
        final chunkSize = rng.nextInt(19) + 1; // 1 to 19 bytes
        final end = min(offset + chunkSize, allBytes.length);
        byteController.add(Uint8List.sublistView(allBytes, offset, end));
        offset = end;
      }
      await byteController.close();

      await completion.future.timeout(const Duration(seconds: 15));
      expect(receivedFrames.length, equals(100));
      for (int i = 0; i < 100; i++) {
        expect(receivedFrames[i].sequence, equals(i));
        expect(receivedFrames[i].payload, equals(testFrames[i].payload));
      }
    });

    test('Massive burst coalescing (50 full frames packed in single 128KB buffer)', () async {
      final frames = List.generate(
        50,
        (i) => Frame.fileChunk(
          streamId: 2,
          chunkIndex: i,
          chunkData: Uint8List.fromList(List.generate(500, (k) => (i + k) % 256)),
        ),
      );

      final builder = BytesBuilder();
      for (final f in frames) {
        builder.add(await frameCodec.encodeFrame(f, keys: senderKeys));
      }
      final singleGiantBuffer = builder.toBytes();

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
          if (receivedFrames.length == 50) {
            doneCompleter.complete();
          }
        },
      );

      byteController.add(singleGiantBuffer);
      await byteController.close();

      await doneCompleter.future.timeout(const Duration(seconds: 10));
      expect(receivedFrames.length, equals(50));
    });

    test('Header boundary slice precision: slicing at every single byte offset (0..34) of the 34B header', () async {
      final frame = Frame.fileChunk(
        streamId: 7,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(utf8.encode('Header boundary verification')),
      );
      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);

      for (int splitPoint = 1; splitPoint < FrameCodec.headerSize; splitPoint++) {
        final chunkA = Uint8List.sublistView(wireBytes, 0, splitPoint);
        final chunkB = Uint8List.sublistView(wireBytes, splitPoint);

        final byteController = StreamController<Uint8List>();
        final transformer = FrameStreamTransformer(
          codec: frameCodec,
          sessionKeys: receiverKeys,
        );

        final received = <Frame>[];
        final comp = Completer<void>();

        byteController.stream.transform(transformer).listen(
          (f) {
            received.add(f);
            comp.complete();
          },
          onError: (Object e) => comp.completeError(e),
        );

        byteController.add(chunkA);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        byteController.add(chunkB);
        await byteController.close();

        await comp.future;
        expect(received.length, equals(1));
        expect(utf8.decode(received.first.payload), equals('Header boundary verification'));
      }
    });

    test('Premature stream truncation: stream closes with partial frame in accumulator throws FrameCodecException', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(List.generate(200, (i) => i)),
      );
      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);

      // Send 50 bytes (34B header + 16B partial ciphertext) then abruptly close
      final partialBytes = Uint8List.sublistView(wireBytes, 0, 50);

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final errorCompleter = Completer<dynamic>();

      byteController.stream.transform(transformer).listen(
        (_) => fail('Should not emit frame for truncated stream'),
        onError: (Object e) {
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(e);
          }
        },
      );

      byteController.add(partialBytes);
      await byteController.close();

      final err = await errorCompleter.future;
      expect(err, isA<FrameCodecException>());
      expect(err.toString(), contains('unparsed bytes in buffer'));
    });
  });

  group('CHALLENGER M2 - TIER 2: Payload Length Overflow & Resource Exhaustion Injection', () {
    test('Direct FrameCodec encode rejection on payload length > 16 MB', () async {
      final oversizedPayload = Uint8List(16 * 1024 * 1024 + 1); // 16MB + 1 byte
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: oversizedPayload,
      );

      expect(
        () async => await frameCodec.encodeFrame(frame, keys: senderKeys),
        throwsA(isA<FrameCodecException>()),
      );
    });

    test('Injected wire length prefix unmasking to > 16MB is rejected during peek before allocation', () async {
      const forgedSeq = 0;
      final nonce = CipherSuite.deriveNonce(senderKeys.outboundBaseIv, forgedSeq);

      // Craft an unmasked length of 32MB (exceeding 16MB cap)
      const forgedLength = 32 * 1024 * 1024; // 32 MB
      final maskedLength = FrameCodec.maskLength(forgedLength, senderKeys.maskKey, nonce);

      // Build 34-byte wire header with forged length
      final wireHeader = Uint8List(FrameCodec.headerSize);
      final data = ByteData.sublistView(wireHeader);
      data.setUint32(0, FrameCodec.magicValue, Endian.big);
      data.setUint8(4, FrameCodec.protocolVersion);
      data.setUint8(5, FrameType.fileChunk.opcode);
      data.setUint16(6, 1, Endian.big);
      data.setUint32(8, forgedSeq, Endian.big);
      wireHeader.setRange(12, 16, maskedLength);
      data.setUint16(16, 0, Endian.big); // 0 padding

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final errorCompleter = Completer<dynamic>();

      byteController.stream.transform(transformer).listen(
        (_) => fail('Should not emit frame for oversized payload header'),
        onError: (Object e) {
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(e);
          }
        },
      );

      byteController.add(wireHeader);
      await byteController.close();

      final err = await errorCompleter.future;
      expect(err, isA<FrameCodecException>());
      expect(err.toString(), contains('exceeds limit'));
    });

    test('Injected maximum 32-bit integer length (0xFFFFFFFF) is rejected safely', () async {
      const forgedSeq = 0;
      final nonce = CipherSuite.deriveNonce(senderKeys.outboundBaseIv, forgedSeq);
      const int forgedLength = 0xFFFFFFFF; // 4GB - 1
      final maskedLength = FrameCodec.maskLength(forgedLength, senderKeys.maskKey, nonce);

      final wireHeader = Uint8List(FrameCodec.headerSize);
      final data = ByteData.sublistView(wireHeader);
      data.setUint32(0, FrameCodec.magicValue, Endian.big);
      data.setUint8(4, FrameCodec.protocolVersion);
      data.setUint8(5, FrameType.fileChunk.opcode);
      data.setUint16(6, 1, Endian.big);
      data.setUint32(8, forgedSeq, Endian.big);
      wireHeader.setRange(12, 16, maskedLength);

      final byteController = StreamController<Uint8List>();
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
      );

      final errorCompleter = Completer<dynamic>();

      byteController.stream.transform(transformer).listen(
        (_) => fail('Should reject 0xFFFFFFFF length'),
        onError: (Object e) {
          if (!errorCompleter.isCompleted) errorCompleter.complete(e);
        },
      );

      byteController.add(wireHeader);
      await byteController.close();

      final err = await errorCompleter.future;
      expect(err, isA<FrameCodecException>());
    });

    test('Accumulator capacity overflow defense: injecting > 32MB stream without valid frames throws overflow exception', () {
      final transformer = FrameStreamTransformer(
        codec: frameCodec,
        sessionKeys: receiverKeys,
        maxBufferSize: 1024 * 1024, // Set small 1MB limit for fast test
      );

      final byteController = StreamController<Uint8List>();
      final errorCompleter = Completer<dynamic>();

      byteController.stream.transform(transformer).listen(
        (_) => fail('Should not emit frames'),
        onError: (Object e) {
          if (!errorCompleter.isCompleted) errorCompleter.complete(e);
        },
      );

      // Add 2MB of raw non-frame bytes
      final garbage = Uint8List(512 * 1024);
      byteController.add(garbage);
      byteController.add(garbage);
      byteController.add(garbage); // Exceeds 1MB

      expect(errorCompleter.future, completion(isA<FrameCodecException>()));
    });

    test('Padding length overflow (> 65535 or negative) throws FrameCodecException', () async {
      final frame = Frame(
        type: FrameType.fileChunk,
        streamId: 1,
        sequence: 0,
        payload: Uint8List(10),
        paddingLen: 70000, // Exceeds uint16
      );

      expect(
        () async => await frameCodec.encodeFrame(frame, keys: senderKeys),
        throwsA(isA<FrameCodecException>()),
      );
    });

    test('Invalid magic value and unsupported protocol versions throw FrameCodecException', () async {
      final validFrame = Frame.ping(streamId: 1, timestamp: 12345);
      final validWire = await frameCodec.encodeFrame(validFrame, keys: senderKeys);

      // Corrupt magic
      final badMagicWire = Uint8List.fromList(validWire);
      badMagicWire[0] = 0xFF;
      expect(
        () async => await frameCodec.decodeFrame(badMagicWire, keys: receiverKeys),
        throwsA(isA<FrameCodecException>()),
      );

      // Corrupt version
      final badVerWire = Uint8List.fromList(validWire);
      badVerWire[4] = 0x02; // Version 2
      expect(
        () async => await frameCodec.decodeFrame(badVerWire, keys: receiverKeys),
        throwsA(isA<FrameCodecException>()),
      );
    });
  });

  group('CHALLENGER M2 - TIER 3: Tampered MAC Tags, Bit Flips, and Sequence Desynchronization', () {
    test('Exhaustive 272-bit sweep: 1-bit flip across every bit in the 34-byte wire header causes 100% rejection', () async {
      final frame = Frame.fileChunk(
        streamId: 0xABCD,
        chunkIndex: 0x123456,
        chunkData: Uint8List.fromList(utf8.encode('Exhaustive Header Bit Sweep Target')),
      );

      final originalWire = await frameCodec.encodeFrame(frame, keys: senderKeys);
      expect(originalWire.length, greaterThanOrEqualTo(FrameCodec.headerSize));

      int rejectionCount = 0;
      int testedBits = 0;

      for (int byteIdx = 0; byteIdx < FrameCodec.headerSize; byteIdx++) {
        for (int bitIdx = 0; bitIdx < 8; bitIdx++) {
          final tampered = Uint8List.fromList(originalWire);
          tampered[byteIdx] ^= (1 << bitIdx);

          try {
            await frameCodec.decodeFrame(tampered, keys: receiverKeys);
            fail('Header bit-flip at byte $byteIdx bit $bitIdx was accepted!');
          } catch (e) {
            expect(
              e,
              anyOf(
                isA<SecretBoxAuthenticationError>(),
                isA<FrameCodecException>(),
                isA<ArgumentError>(),
                isA<FormatException>(),
              ),
            );
            rejectionCount++;
          }
          testedBits++;
        }
      }

      expect(testedBits, equals(34 * 8)); // 272 bits tested
      expect(rejectionCount, equals(272), reason: 'All 272 bit-flips in header must be rejected');
    });

    test('100 random bit flips in ciphertext payload are 100% rejected by Poly1305 AEAD', () async {
      final payload = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: payload,
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);
      final ciphertextStart = FrameCodec.headerSize;
      final ciphertextEnd = ciphertextStart + payload.length;

      final rng = Random(0xCAFE);
      int rejectionCount = 0;
      const totalTrials = 100;

      for (int t = 0; t < totalTrials; t++) {
        final tampered = Uint8List.fromList(wireBytes);
        final targetByte = ciphertextStart + rng.nextInt(ciphertextEnd - ciphertextStart);
        final bitMask = 1 << rng.nextInt(8);
        tampered[targetByte] ^= bitMask;

        try {
          await frameCodec.decodeFrame(tampered, keys: receiverKeys);
          fail('Payload bit flip at index $targetByte was accepted!');
        } catch (e) {
          expect(e, anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>()));
          rejectionCount++;
        }
      }

      expect(rejectionCount, equals(totalTrials));
    });

    test('Sequence number tampering desynchronizes nonce and causes Poly1305 MAC failure', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(utf8.encode('Sequence Tampering Test')),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);

      // Modify sequence number in header from 0 to 1
      final tamperedSeq = Uint8List.fromList(wireBytes);
      ByteData.sublistView(tamperedSeq, 8, 12).setUint32(0, 1, Endian.big);

      expect(
        () async => await frameCodec.decodeFrame(tamperedSeq, keys: receiverKeys),
        throwsA(anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>())),
      );
    });

    test('Directional key reflection attack: sender frame decoded with sender keys fails MAC authentication', () async {
      final frame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.fromList(utf8.encode('Directional payload')),
      );

      final wireBytes = await frameCodec.encodeFrame(frame, keys: senderKeys);

      // Attacker attempts to reflect Alice's outbound frame back to Alice (using senderKeys instead of receiverKeys)
      expect(
        () async => await frameCodec.decodeFrame(wireBytes, keys: senderKeys),
        throwsA(anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>())),
      );
    });
  });

  group('CHALLENGER M2 - TIER 4: Replay Attacks & Out-of-Order Chunk Injection', () {
    test('Out-of-order chunk injection against TransferReceiver: chunk 2 before chunk 1 is rejected and aborts staging', () async {
      final destDir = Directory(p.join(tempDir.path, 'out_of_order_test'))..createSync();
      final receiver = TransferReceiver();

      final fileData = Uint8List.fromList(List.generate(65536 * 3, (i) => i % 256));
      final rootDigest = Uint8List.fromList(crypto.sha256.convert(fileData).bytes);

      final meta = FileMetaPayload(
        fileName: 'out_of_order.bin',
        totalBytes: fileData.length,
        rootSha256: rootDigest,
        chunkSize: 65536,
        totalChunks: 3,
      );

      // Create chunks
      final chunk0 = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List.sublistView(fileData, 0, 65536),
      );
      final chunk2 = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 2, // Out of order!
        chunkData: Uint8List.sublistView(fileData, 65536 * 2, 65536 * 3),
      );

      final inController = StreamController<Frame>();

      // Mock socket stream for receiver
      final receiveFuture = receiver.receiveFile(
        destDir,
        _MockAdversarialSocket(),
        receiverKeys,
        incomingFrameStream: inController.stream,
      );

      // Send metadata
      inController.add(Frame.fileMeta(streamId: 1, metadata: meta));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Send chunk 0
      inController.add(chunk0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Inject out-of-order chunk 2
      inController.add(chunk2);
      await inController.close();

      try {
        await receiveFuture;
        fail('Expected SecurityException');
      } catch (e) {
        expect(e, isA<SecurityException>());
      }

      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Verify staging file was wiped and no .part or final file exists
      final remainingFiles = destDir.listSync();
      expect(remainingFiles.isEmpty, isTrue, reason: 'Zero .part files should remain on abort');
    });

    test('Replayed chunk attack: injecting chunk 0 twice is rejected by sequence verification', () async {
      final destDir = Directory(p.join(tempDir.path, 'replay_test'))..createSync();
      final receiver = TransferReceiver();

      final fileData = Uint8List(65536 * 2);
      final rootDigest = Uint8List.fromList(crypto.sha256.convert(fileData).bytes);

      final meta = FileMetaPayload(
        fileName: 'replay.bin',
        totalBytes: fileData.length,
        rootSha256: rootDigest,
        chunkSize: 65536,
        totalChunks: 2,
      );

      final chunk0 = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List(65536),
      );

      final inController = StreamController<Frame>();

      final receiveFuture = receiver.receiveFile(
        destDir,
        _MockAdversarialSocket(),
        receiverKeys,
        incomingFrameStream: inController.stream,
      );

      inController.add(Frame.fileMeta(streamId: 1, metadata: meta));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      inController.add(chunk0);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Replay chunk 0 again
      inController.add(chunk0);
      await inController.close();

      try {
        await receiveFuture;
        fail('Expected SecurityException');
      } catch (e) {
        expect(e, isA<SecurityException>());
      }

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(destDir.listSync().isEmpty, isTrue);
    });

    test('Premature TransferComplete attack before sending file data chunks throws error and wipes .part', () async {
      final destDir = Directory(p.join(tempDir.path, 'premature_complete_test'))..createSync();
      final receiver = TransferReceiver();

      final fileData = Uint8List(65536);
      final rootDigest = Uint8List.fromList(crypto.sha256.convert(fileData).bytes);

      final meta = FileMetaPayload(
        fileName: 'premature.bin',
        totalBytes: 65536,
        rootSha256: rootDigest,
        chunkSize: 65536,
        totalChunks: 1,
      );

      final inController = StreamController<Frame>();

      final receiveFuture = receiver.receiveFile(
        destDir,
        _MockAdversarialSocket(),
        receiverKeys,
        incomingFrameStream: inController.stream,
      );

      inController.add(Frame.fileMeta(streamId: 1, metadata: meta));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Prematurely send transferComplete without sending chunk 0
      inController.add(Frame.transferComplete(streamId: 1, sequence: 1, rootSha256: rootDigest));
      await inController.close();

      try {
        await receiveFuture;
        fail('Expected exception');
      } catch (e) {
        expect(e, anyOf(isA<StateError>(), isA<IntegrityMismatchException>(), isA<TransferAbortedException>()));
      }

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(destDir.listSync().isEmpty, isTrue);
    });


    test('Premature data chunk before FileMeta throws FormatException', () async {
      final destDir = Directory(p.join(tempDir.path, 'premature_chunk_test'))..createSync();
      final receiver = TransferReceiver();

      final inController = StreamController<Frame>();

      final receiveFuture = receiver.receiveFile(
        destDir,
        _MockAdversarialSocket(),
        receiverKeys,
        incomingFrameStream: inController.stream,
      );

      // Send chunk without meta
      inController.add(Frame.fileChunk(streamId: 1, chunkIndex: 0, chunkData: Uint8List(100)));
      await inController.close();

      expect(
        () async => await receiveFuture,
        throwsA(isA<FormatException>()),
      );
    });

    test('Oversized file manifest (> 100GB or > maxAllowableFileSize) triggers rejection and SecurityException', () async {
      final destDir = Directory(p.join(tempDir.path, 'oversized_manifest_test'))..createSync();
      final receiver = TransferReceiver(
        options: const TransferReceiverOptions(
          maxAllowableFileSize: 10 * 1024 * 1024 * 1024, // 10 GB limit
        ),
      );

      final meta = FileMetaPayload(
        fileName: 'huge.iso',
        totalBytes: 50 * 1024 * 1024 * 1024, // 50 GB
        rootSha256: Uint8List(32),
        chunkSize: 65536,
        totalChunks: 1000000,
      );

      final inController = StreamController<Frame>();

      final receiveFuture = receiver.receiveFile(
        destDir,
        _MockAdversarialSocket(),
        receiverKeys,
        incomingFrameStream: inController.stream,
      );

      inController.add(Frame.fileMeta(streamId: 1, metadata: meta));
      await inController.close();

      expect(
        () async => await receiveFuture,
        throwsA(isA<SecurityException>()),
      );
    });
  });

  group('CHALLENGER M2 - TIER 5: In-Memory Adversarial Jitter Proxy & Full Transfer Verification', () {
    test('256 KB transfer survives a hostile TCP proxy that randomly fragments into 1-13 byte slices and bursts', () async {
      final sourceFile = File(p.join(tempDir.path, 'source_adversarial.dat'));
      final rng = Random(0x5EED);
      final originalData = Uint8List.fromList(List.generate(256 * 1024, (_) => rng.nextInt(256)));
      await sourceFile.writeAsBytes(originalData);

      final expectedSha = hex.encode(crypto.sha256.convert(originalData).bytes);
      final destDir = Directory(p.join(tempDir.path, 'dest_adversarial_proxy'))..createSync();

      // Setup in-memory loopback streams with adversarial jitter/slicing
      final senderToReceiverRaw = StreamController<Uint8List>();
      final receiverToSenderRaw = StreamController<Uint8List>();

      // Hostile proxy from sender to receiver
      final hostileSenderToReceiver = StreamController<Uint8List>();
      senderToReceiverRaw.stream.listen((chunk) {
        // Randomly split chunk into 1 to 13 byte sub-slices
        int offset = 0;
        while (offset < chunk.length) {
          final sliceLen = rng.nextInt(13) + 1;
          final end = min(offset + sliceLen, chunk.length);
          hostileSenderToReceiver.add(Uint8List.sublistView(chunk, offset, end));
          offset = end;
        }
      }, onDone: () => hostileSenderToReceiver.close());

      final senderSocket = _StreamLoopbackSocket(
        inputStream: receiverToSenderRaw.stream,
        outputSink: senderToReceiverRaw,
      );

      final receiverSocket = _StreamLoopbackSocket(
        inputStream: hostileSenderToReceiver.stream,
        outputSink: receiverToSenderRaw,
      );

      final sender = TransferSender();
      final receiver = TransferReceiver();

      final senderFuture = sender.sendFile(sourceFile, senderSocket, senderKeys);
      final receiverFuture = receiver.receiveFile(destDir, receiverSocket, receiverKeys);

      final results = await Future.wait([senderFuture, receiverFuture]);
      final senderRes = results[0] as TransferSenderResult;
      final receiverRes = results[1] as TransferReceiverResult;

      expect(senderRes.sha256Digest, equals(expectedSha));
      expect(receiverRes.sha256Digest, equals(expectedSha));
      expect(receiverRes.totalBytes, equals(256 * 1024));
      expect(await receiverRes.file.exists(), isTrue);

      final receivedBytes = await receiverRes.file.readAsBytes();
      expect(receivedBytes, equals(originalData));
    });
  });
}

/// Mock Socket for adversarial incoming frame stream tests
class _MockAdversarialSocket implements Socket {
  final List<List<int>> writtenBuffers = [];

  @override
  void add(List<int> data) {
    writtenBuffers.add(data);
  }

  @override
  Future<void> flush() async {}

  @override
  void destroy() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stream-backed loopback socket for end-to-end proxy testing
class _StreamLoopbackSocket implements Socket {
  final Stream<Uint8List> inputStream;
  final StreamController<Uint8List> outputSink;

  _StreamLoopbackSocket({
    required this.inputStream,
    required this.outputSink,
  });

  @override
  void add(List<int> data) {
    outputSink.add(Uint8List.fromList(data));
  }

  @override
  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return inputStream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Stream<S> transform<S>(StreamTransformer<Uint8List, S> streamTransformer) {
    return inputStream.transform(streamTransformer);
  }

  @override
  Future<void> close() async {
    await outputSink.close();
  }

  @override
  void destroy() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
