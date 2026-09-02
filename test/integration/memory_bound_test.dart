import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
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

  final transcriptHash = Uint8List(32)..fillRange(0, 32, 0x88);

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

void main() {
  late Directory tempDir;
  late Directory destDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slft_mem_test_');
    destDir = await Directory.systemTemp.createTemp('slft_mem_dst_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    if (await destDir.exists()) await destDir.delete(recursive: true);
  });

  group('Memory Bounded Streaming & RSS Constraints (<200MB)', () {
    test('100 MB active chunked transfer maintains Peak RSS Delta < 200 MB', () async {
      // 1. Create a 100 MB synthetic file on disk chunk-by-chunk
      const totalFileSize = 100 * 1024 * 1024; // 100 MB
      const chunkSize = 65536; // 64 KB

      final srcFile = File(p.join(tempDir.path, '100mb_source.dat'));
      final raf = await srcFile.open(mode: FileMode.write);

      final hashAccumulator = AccumulatorSink<crypto.Digest>();
      final hashSink = crypto.sha256.startChunkedConversion(hashAccumulator);

      // Write in 64KB increments to keep disk creation memory-bounded
      final singleChunkBuffer = Uint8List(chunkSize);
      for (int i = 0; i < chunkSize; i++) {
        singleChunkBuffer[i] = i % 256;
      }

      int written = 0;
      while (written < totalFileSize) {
        final toWrite = min(chunkSize, totalFileSize - written);
        final slice = Uint8List.sublistView(singleChunkBuffer, 0, toWrite);
        await raf.writeFrom(slice);
        hashSink.add(slice);
        written += toWrite;
      }
      await raf.close();
      hashSink.close();

      final expectedShaHex = hex.encode(hashAccumulator.events.single.bytes);

      // 2. Measure Baseline RSS
      final baselineRss = ProcessInfo.currentRss;
      int peakRss = baselineRss;

      // Start memory monitor timer (every 10ms)
      final memTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final current = ProcessInfo.currentRss;
        if (current > peakRss) {
          peakRss = current;
        }
      });

      final sockets = await createLoopbackSockets();
      final keys = await createPairedKeys();

      final sender = TransferSender(
        options: const TransferSenderOptions(
          chunkSize: chunkSize,
          defaultInitialCredits: 4,
        ),
      );
      final receiver = TransferReceiver(
        options: const TransferReceiverOptions(
          creditWindowSize: 4,
        ),
      );

      final receiverFuture = receiver.receiveFile(
        destDir,
        sockets.receiverSocket,
        keys.receiverKeys,
      );

      final senderFuture = sender.sendFile(
        srcFile,
        sockets.senderSocket,
        keys.senderKeys,
      );

      final results = await Future.wait([senderFuture, receiverFuture]);
      memTimer.cancel();

      final receiverResult = results[1] as TransferReceiverResult;
      expect(receiverResult.sha256Digest, equals(expectedShaHex));
      expect(await receiverResult.file.length(), equals(totalFileSize));

      final deltaRss = peakRss - baselineRss;
      final deltaRssMb = deltaRss / (1024 * 1024);

      print('=== 100 MB Transfer Memory Bounding Stats ===');
      print('Baseline RSS: ${(baselineRss / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('Peak RSS:     ${(peakRss / (1024 * 1024)).toStringAsFixed(2)} MB');
      print('Delta RSS:    ${deltaRssMb.toStringAsFixed(2)} MB (Limit: 200.00 MB)');

      // Verify that RSS growth is strictly < 200 MB
      expect(deltaRss, lessThan(200 * 1024 * 1024));

      await sockets.senderSocket.close();
      await sockets.receiverSocket.close();
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
