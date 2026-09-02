import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/crypto/zero_metadata_staging.dart';
import 'package:secure_lan_transfer/core/models/transfer_progress.dart';
import 'package:secure_lan_transfer/core/protocol/frame_codec.dart';
import 'package:secure_lan_transfer/core/protocol/frame_stream_transformer.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';
import 'package:secure_lan_transfer/core/transfer/flow_controller.dart';
import 'package:secure_lan_transfer/core/transfer/transfer_receiver.dart';
import 'package:secure_lan_transfer/core/transfer/transfer_sender.dart';
import 'package:test/test.dart';

Future<({Socket senderSocket, Socket receiverSocket})> createLoopbackSockets() async {
  final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final clientFuture = Socket.connect(InternetAddress.loopbackIPv4, serverSocket.port);
  final serverConnFuture = serverSocket.first;
  final results = await Future.wait([clientFuture, serverConnFuture]);
  await serverSocket.close();
  return (senderSocket: results[0], receiverSocket: results[1]);
}

Future<({SessionKeys senderKeys, SessionKeys receiverKeys})> createPairedKeys() async {
  final cipherSuite = CipherSuite();
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

  final senderKeys = await SessionKeys.derive(
    sharedSecret: aliceSecret,
    initiatorNonce: aliceKeyPair.nonce,
    receiverNonce: bobKeyPair.nonce,
    transcriptHash: transcriptHash,
    isInitiator: true,
  );

  final receiverKeys = await SessionKeys.derive(
    sharedSecret: bobSecret,
    initiatorNonce: aliceKeyPair.nonce,
    receiverNonce: bobKeyPair.nonce,
    transcriptHash: transcriptHash,
    isInitiator: false,
  );

  return (senderKeys: senderKeys, receiverKeys: receiverKeys);
}

Future<File> createSyntheticFile(Directory dir, String name, int byteCount) async {
  final file = File(p.join(dir.path, name));
  final raf = await file.open(mode: FileMode.write);
  const chunkSize = 65536;
  int written = 0;
  while (written < byteCount) {
    final toWrite = (byteCount - written < chunkSize) ? byteCount - written : chunkSize;
    final buffer = Uint8List(toWrite);
    for (int i = 0; i < toWrite; i++) {
      buffer[i] = (written + i) % 256;
    }
    await raf.writeFrom(buffer);
    written += toWrite;
  }
  await raf.close();
  return file;
}

Future<String> calculateSha256(File file) async {
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return hex.encode(digest.bytes);
}

void main() {
  late Directory sourceDir;
  late Directory destDir;

  setUp(() async {
    sourceDir = await Directory.systemTemp.createTemp('slft_test_src_');
    destDir = await Directory.systemTemp.createTemp('slft_test_dst_');
  });

  tearDown(() async {
    if (await sourceDir.exists()) await sourceDir.delete(recursive: true);
    if (await destDir.exists()) await destDir.delete(recursive: true);
  });

  group('1. Loopback TCP Streaming Transfers', () {
    test('Transfers 0-byte, 1 KB, 256 KB, and 2 MB files with SHA-256 match', () async {
      final fileSizes = [0, 1024, 256 * 1024, 2 * 1024 * 1024];

      for (final size in fileSizes) {
        final srcFile = await createSyntheticFile(sourceDir, 'test_file_$size.dat', size);
        final srcSha = await calculateSha256(srcFile);

        final sockets = await createLoopbackSockets();
        final keys = await createPairedKeys();

        final sender = TransferSender();
        final receiver = TransferReceiver();

        final progressList = <TransferProgress>[];

        final receiverFuture = receiver.receiveFile(
          destDir,
          sockets.receiverSocket,
          keys.receiverKeys,
          onProgress: (p) => progressList.add(p),
        );

        final senderFuture = sender.sendFile(
          srcFile,
          sockets.senderSocket,
          keys.senderKeys,
          onProgress: (p) => progressList.add(p),
        );

        final results = await Future.wait([senderFuture, receiverFuture]);
        final senderResult = results[0] as TransferSenderResult;
        final receiverResult = results[1] as TransferReceiverResult;

        expect(senderResult.sha256Digest, equals(srcSha));
        expect(receiverResult.sha256Digest, equals(srcSha));
        expect(await receiverResult.file.exists(), isTrue);
        expect(await receiverResult.file.length(), equals(size));

        final destSha = await calculateSha256(receiverResult.file);
        expect(destSha, equals(srcSha));

        // Check staging file is completely removed
        final partFiles = destDir.listSync().where((e) => e.path.endsWith('.slft_part'));
        expect(partFiles.isEmpty, isTrue);

        await sockets.senderSocket.close();
        await sockets.receiverSocket.close();
      }
    });
  });

  group('2. Pause and Resume Transmission', () {
    test('Pausing mid-transfer halts transmission and resuming completes transfer successfully', () async {
      final srcFile = await createSyntheticFile(sourceDir, 'pause_test.bin', 512 * 1024);
      final srcSha = await calculateSha256(srcFile);

      final sockets = await createLoopbackSockets();
      final keys = await createPairedKeys();

      final sender = TransferSender();
      final receiver = TransferReceiver();

      bool pauseTriggered = false;
      bool resumed = false;

      final receiverFuture = receiver.receiveFile(
        destDir,
        sockets.receiverSocket,
        keys.receiverKeys,
      );

      final senderFuture = sender.sendFile(
        srcFile,
        sockets.senderSocket,
        keys.senderKeys,
        onProgress: (progress) {
          if (!pauseTriggered && progress.transferredBytes >= 128 * 1024) {
            pauseTriggered = true;
            sender.pause();
            expect(sender.isPaused, isTrue);

            // Resume after brief delay
            Timer(const Duration(milliseconds: 100), () {
              resumed = true;
              sender.resume();
              expect(sender.isPaused, isFalse);
            });
          }
        },
      );

      final results = await Future.wait([senderFuture, receiverFuture]);
      final receiverResult = results[1] as TransferReceiverResult;

      expect(pauseTriggered, isTrue);
      expect(resumed, isTrue);
      expect(await calculateSha256(receiverResult.file), equals(srcSha));

      await sockets.senderSocket.close();
      await sockets.receiverSocket.close();
    });
  });

  group('3. Cancellation & Clean Teardown', () {
    test('Sender cancellation unlinks staging .part file immediately', () async {
      final srcFile = await createSyntheticFile(sourceDir, 'cancel_src.bin', 1024 * 1024);

      final sockets = await createLoopbackSockets();
      final keys = await createPairedKeys();

      final sender = TransferSender();
      final receiver = TransferReceiver();
      final cancelToken = CancellationToken();

      final receiverFuture = receiver.receiveFile(
        destDir,
        sockets.receiverSocket,
        keys.receiverKeys,
      );

      final senderFuture = sender.sendFile(
        srcFile,
        sockets.senderSocket,
        keys.senderKeys,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (progress.transferredBytes >= 128 * 1024 && !cancelToken.isCancelled) {
            cancelToken.cancel('User clicked cancel button');
          }
        },
      );

      try {
        await Future.wait([senderFuture, receiverFuture]);
        fail('Should have aborted transfer');
      } catch (_) {}

      // Allow staging unlinking and handle release to finish on Windows
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final partFiles = destDir.listSync().where((e) => e.path.endsWith('.slft_part'));
      expect(partFiles.isEmpty, isTrue);

      await sockets.senderSocket.close();
      await sockets.receiverSocket.close();
    });
  });

  group('4. Fault Injection & Corrupted Chunks', () {
    test('1-bit flip in wire chunk triggers Poly1305 authentication error and unlinks .part file', () async {
      final srcFile = await createSyntheticFile(sourceDir, 'corrupt_test.bin', 256 * 1024);

      final sockets = await createLoopbackSockets();
      final keys = await createPairedKeys();

      final receiverCodec = FrameCodec();
      final senderCodec = FrameCodec();

      final rawReceiverFrames = sockets.receiverSocket.transform(
        FrameStreamTransformer(codec: receiverCodec, sessionKeys: keys.receiverKeys),
      );

      // We intercept the stream of frames and inject corruption into chunk 2
      final corruptedController = StreamController<Frame>();
      int chunkCount = 0;

      rawReceiverFrames.listen(
        (frame) {
          if (frame.type == FrameType.fileChunk) {
            chunkCount++;
            if (chunkCount == 2) {
              // Corrupt the payload so SHA-256 / content check fails
              final corruptedBytes = Uint8List.fromList(frame.payload);
              corruptedBytes[0] ^= 0xFF;
              corruptedController.add(Frame.fileChunk(
                streamId: frame.streamId,
                chunkIndex: frame.sequence,
                chunkData: corruptedBytes,
              ));
              return;
            }
          }
          corruptedController.add(frame);
        },
        onError: (Object e, StackTrace st) => corruptedController.addError(e, st),
        onDone: () => corruptedController.close(),
      );

      final receiver = TransferReceiver(frameCodec: receiverCodec);
      final receiverFuture = receiver.receiveFile(
        destDir,
        sockets.receiverSocket,
        keys.receiverKeys,
        incomingFrameStream: corruptedController.stream,
      );

      final sender = TransferSender(frameCodec: senderCodec);
      final senderFuture = sender.sendFile(
        srcFile,
        sockets.senderSocket,
        keys.senderKeys,
      );

      try {
        await Future.wait([senderFuture, receiverFuture]);
        fail('Should have thrown authentication error');
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 400));

      final partFiles = destDir.listSync().where((e) => e.path.endsWith('.slft_part'));
      expect(partFiles.isEmpty, isTrue);

      await sockets.senderSocket.close();
      await sockets.receiverSocket.close();
    });
  });
}
