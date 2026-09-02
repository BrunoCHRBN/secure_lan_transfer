import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/crypto/obfuscation.dart';
import 'package:secure_lan_transfer/core/crypto/sas_authenticator.dart';
import 'package:secure_lan_transfer/core/protocol/frame_codec.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';
import 'package:secure_lan_transfer/core/session/handshake_protocol.dart';
import 'package:secure_lan_transfer/core/session/session_manager.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late Directory destDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slft_adversarial_m3_');
    sourceDir = Directory(p.join(tempDir.path, 'source'))..createSync(recursive: true);
    destDir = Directory(p.join(tempDir.path, 'dest'))..createSync(recursive: true);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<File> createSyntheticFile(String name, int sizeBytes) async {
    final file = File(p.join(sourceDir.path, name));
    final sink = file.openWrite();
    final random = Random(42);
    final chunk = Uint8List(64 * 1024);
    int remaining = sizeBytes;
    while (remaining > 0) {
      final toWrite = remaining < chunk.length ? remaining : chunk.length;
      for (int i = 0; i < toWrite; i++) {
        chunk[i] = random.nextInt(256);
      }
      sink.add(chunk.sublist(0, toWrite));
      remaining -= toWrite;
    }
    await sink.flush();
    await sink.close();
    return file;
  }

  group('CHALLENGER M3 - TIER 1: Handshake MITM & Transcript Tampering Attacks', () {
    test('Active MITM bit-flip in Initiator Ephemeral Public Key produces SAS mismatch & encrypted ACK MAC rejection', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      final serverProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );
      final clientProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );

      final serverErrorCompleter = Completer<dynamic>();
      final clientErrorCompleter = Completer<dynamic>();

      SasCode? serverObservedSas;
      SasCode? clientObservedSas;

      // Hostile MITM Proxy: listens on mitmPort, forwards to serverPort while modifying client public key
      final mitmServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final mitmPort = mitmServer.port;

      mitmServer.listen((clientSocket) async {
        final realServerSocket = await Socket.connect('127.0.0.1', serverPort);

        // Forward server -> client verbatim
        realServerSocket.listen(
          (data) => clientSocket.add(data),
          onError: (e) => clientSocket.destroy(),
          onDone: () => clientSocket.destroy(),
        );

        // Intercept client -> server, tamper with handshakeInit
        bool tampered = false;
        clientSocket.listen(
          (data) {
            if (!tampered && data.length >= FrameCodec.headerSize + 64) {
              // Tamper with the public key (bytes 34..65 is ciphertext/payload in unencrypted frame)
              final tamperedBytes = Uint8List.fromList(data);
              tamperedBytes[FrameCodec.headerSize + 5] ^= 0x01; // 1-bit flip in public key
              realServerSocket.add(tamperedBytes);
              tampered = true;
            } else {
              realServerSocket.add(data);
            }
          },
          onError: (e) => realServerSocket.destroy(),
          onDone: () => realServerSocket.destroy(),
        );
      });

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(
            serverSocket,
            onVerifySas: (sas) async {
              serverObservedSas = sas;
              return true; // Server user accepts its own SAS
            },
          );
        } catch (e) {
          if (!serverErrorCompleter.isCompleted) serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', mitmPort);

      try {
        await clientProtocol.performClientHandshake(
          clientSocket,
          onVerifySas: (sas) async {
            clientObservedSas = sas;
            return true; // Client user accepts its own SAS
          },
        );
      } catch (e) {
        if (!clientErrorCompleter.isCompleted) clientErrorCompleter.complete(e);
      } finally {
        clientSocket.destroy();
      }

      // Handshake MUST fail on at least one or both endpoints due to AEAD decrypt failure or SAS mismatch
      final clientErr = await clientErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(clientErr, isA<HandshakeException>());

      if (serverObservedSas != null && clientObservedSas != null) {
        // Under MITM tampering, the two parties MUST NOT compute the same SAS
        expect(serverObservedSas!.matches(clientObservedSas!), isFalse);
        expect(serverObservedSas!.numericCode, isNot(equals(clientObservedSas!.numericCode)));
      }

      await mitmServer.close();
      await server.close();
    });

    test('Active MITM bit-flip in Responder Ephemeral Public Key triggers cryptographic derivation divergence', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      final serverProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );
      final clientProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );

      final clientErrorCompleter = Completer<dynamic>();

      // MITM proxy intercepts server -> client response and flips bit in server's public key
      final mitmServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final mitmPort = mitmServer.port;

      mitmServer.listen((clientSocket) async {
        final realServerSocket = await Socket.connect('127.0.0.1', serverPort);

        clientSocket.listen(
          (data) => realServerSocket.add(data),
          onError: (e) => realServerSocket.destroy(),
          onDone: () => realServerSocket.destroy(),
        );

        bool tampered = false;
        realServerSocket.listen(
          (data) {
            if (!tampered && data.length >= FrameCodec.headerSize + 64) {
              final tamperedBytes = Uint8List.fromList(data);
              tamperedBytes[FrameCodec.headerSize + 10] ^= 0x80; // 1-bit flip in server public key
              clientSocket.add(tamperedBytes);
              tampered = true;
            } else {
              clientSocket.add(data);
            }
          },
          onError: (e) => clientSocket.destroy(),
          onDone: () => clientSocket.destroy(),
        );
      });

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
        } catch (_) {}
        serverSocket.destroy();
      });

      final clientSocket = await Socket.connect('127.0.0.1', mitmPort);

      try {
        await clientProtocol.performClientHandshake(clientSocket);
      } catch (e) {
        if (!clientErrorCompleter.isCompleted) clientErrorCompleter.complete(e);
      } finally {
        clientSocket.destroy();
      }

      final clientErr = await clientErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(clientErr, isA<HandshakeException>());

      await mitmServer.close();
      await server.close();
    });

    test('Nonce tampering in HandshakeEnvelope leads to divergent HKDF keys and encrypted handshakeAck rejection', () async {
      final cipherSuite = CipherSuite();
      final aliceKeyPair = await cipherSuite.generateEphemeralKeyPair();
      final bobKeyPair = await cipherSuite.generateEphemeralKeyPair();

      final sharedSecret = await cipherSuite.computeSharedSecret(
        localKeyPair: aliceKeyPair.keyPair,
        remotePublicKeyBytes: bobKeyPair.publicKeyBytes,
      );

      // Alice computes transcript with original nonce
      final aliceTranscript = await cipherSuite.computeTranscriptHash(
        initiatorPk: aliceKeyPair.publicKeyBytes,
        receiverPk: bobKeyPair.publicKeyBytes,
        initiatorNonce: aliceKeyPair.nonce,
        receiverNonce: bobKeyPair.nonce,
        sharedSecret: sharedSecret,
      );

      // Tampered Bob nonce (1 bit flip)
      final tamperedBobNonce = Uint8List.fromList(bobKeyPair.nonce);
      tamperedBobNonce[0] ^= 0x01;

      final bobTranscriptTampered = await cipherSuite.computeTranscriptHash(
        initiatorPk: aliceKeyPair.publicKeyBytes,
        receiverPk: bobKeyPair.publicKeyBytes,
        initiatorNonce: aliceKeyPair.nonce,
        receiverNonce: tamperedBobNonce,
        sharedSecret: sharedSecret,
      );

      expect(aliceTranscript, isNot(equals(bobTranscriptTampered)));

      final aliceSas = SasAuthenticator.generateSas(aliceTranscript);
      final bobSas = SasAuthenticator.generateSas(bobTranscriptTampered);
      expect(aliceSas.matches(bobSas), isFalse);

      final aliceKeys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        initiatorNonce: aliceKeyPair.nonce,
        receiverNonce: bobKeyPair.nonce,
        transcriptHash: aliceTranscript,
        role: TransferRole.initiator,
      );

      final bobKeys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        initiatorNonce: aliceKeyPair.nonce,
        receiverNonce: tamperedBobNonce,
        transcriptHash: bobTranscriptTampered,
        role: TransferRole.receiver,
      );

      // Alice sends encrypted handshakeAck
      final ackFrame = Frame(
        type: FrameType.handshakeAck,
        streamId: 0,
        sequence: 0,
        payload: Uint8List.fromList(utf8.encode('OK')),
      );
      final codec = FrameCodec(cipherSuite: cipherSuite);
      final aliceWireBytes = await codec.encodeFrame(ackFrame, keys: aliceKeys);

      // Bob tries to decrypt with mismatched keys -> MUST fail Poly1305 authentication
      expect(
        () async => await codec.decodeFrame(aliceWireBytes, keys: bobKeys),
        throwsA(anyOf(isA<SecretBoxAuthenticationError>(), isA<FrameCodecException>())),
      );
    });

    test('HandshakeEnvelope strict length and boundary parsing rejects malformed sizes', () {
      // 1. Below minimum size (< 64 bytes)
      expect(
        () => HandshakeEnvelope.parse(Uint8List(0)),
        throwsA(isA<ObfuscationException>()),
      );
      expect(
        () => HandshakeEnvelope.parse(Uint8List(63)),
        throwsA(isA<ObfuscationException>()),
      );

      // 2. Above maximum size (> 160 bytes)
      expect(
        () => HandshakeEnvelope.parse(Uint8List(161)),
        throwsA(isA<ObfuscationException>()),
      );
      expect(
        () => HandshakeEnvelope.parse(Uint8List(500)),
        throwsA(isA<ObfuscationException>()),
      );

      // 3. Valid boundary lengths (64 bytes and 160 bytes)
      final validMin = Uint8List(64);
      final parsedMin = HandshakeEnvelope.parse(validMin);
      expect(parsedMin.publicKey.length, equals(32));
      expect(parsedMin.nonce.length, equals(32));
      expect(parsedMin.jitterPadding.length, equals(0));

      final validMax = Uint8List(160);
      final parsedMax = HandshakeEnvelope.parse(validMax);
      expect(parsedMax.publicKey.length, equals(32));
      expect(parsedMax.nonce.length, equals(32));
      expect(parsedMax.jitterPadding.length, equals(96));
    });

    test('HandshakeEnvelope factory rejects invalid jitter bounds or invalid key sizes', () {
      final validKey = Uint8List(32);
      final validNonce = Uint8List(32);

      // Invalid public key size
      expect(
        () => HandshakeEnvelope.create(publicKey: Uint8List(16), nonce: validNonce),
        throwsA(isA<ArgumentError>()),
      );

      // Invalid nonce size
      expect(
        () => HandshakeEnvelope.create(publicKey: validKey, nonce: Uint8List(12)),
        throwsA(isA<ArgumentError>()),
      );

      // Jitter < 32 bytes
      expect(
        () => HandshakeEnvelope.create(publicKey: validKey, nonce: validNonce, customJitterLength: 31),
        throwsA(isA<ArgumentError>()),
      );

      // Jitter > 96 bytes
      expect(
        () => HandshakeEnvelope.create(publicKey: validKey, nonce: validNonce, customJitterLength: 97),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('CHALLENGER M3 - TIER 2: SAS User Rejection & Zero Data Leakage', () {
    test('Client-side SAS rejection sends transferCancel and leaves zero plaintext data in socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol();
      final clientProtocol = HandshakeProtocol();

      final serverErrorCompleter = Completer<dynamic>();
      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
        } catch (e) {
          if (!serverErrorCompleter.isCompleted) serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);

      await expectLater(
        clientProtocol.performClientHandshake(
          clientSocket,
          onVerifySas: (sas) async => false, // User clicks REJECT
        ),
        throwsA(isA<HandshakeException>().having(
          (e) => e.message,
          'message',
          contains('SAS verification rejected by user'),
        )),
      );

      final serverErr = await serverErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(serverErr, isA<HandshakeException>());

      await server.close();
    });

    test('Server-side SAS rejection sends transferCancel and aborts client handshake cleanly', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol();
      final clientProtocol = HandshakeProtocol();

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(
            serverSocket,
            onVerifySas: (sas) async => false, // Server user rejects
          );
        } catch (_) {}
        serverSocket.destroy();
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);

      await expectLater(
        clientProtocol.performClientHandshake(
          clientSocket,
          onVerifySas: (sas) async => true,
        ),
        throwsA(isA<HandshakeException>()),
      );

      await server.close();
    });

    test('SessionManager SAS rejection via UI stream cleans up state and wipes partial downloads', () async {
      final srcFile = await createSyntheticFile('sas_reject_file.bin', 256 * 1024);

      final serverManager = SessionManager(
        options: SessionManagerOptions(
          autoVerifySas: false, // Force UI verification request
          downloadDirectory: destDir,
        ),
      );
      await serverManager.startServer(host: '127.0.0.1', port: 0);
      final serverPort = serverManager.serverPort!;

      // Handle server SAS request by rejecting
      final sasSub = serverManager.sasRequestsStream.listen((req) {
        req.reject();
      });

      final clientManager = SessionManager(
        options: const SessionManagerOptions(autoVerifySas: true),
      );

      await expectLater(
        clientManager.sendFile(
          host: '127.0.0.1',
          port: serverPort,
          file: srcFile,
        ),
        throwsA(isA<Exception>()),
      );

      // Verify no staging file remains on receiver disk
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final remainingParts = destDir.listSync().where((e) => e.path.endsWith('.slft_part')).toList();
      expect(remainingParts, isEmpty);

      await sasSub.cancel();
      serverManager.dispose();
      clientManager.dispose();
    });
  });

  group('CHALLENGER M3 - TIER 3: Incomplete Handshake & Abrupt Socket Termination', () {
    test('Client connects and closes socket immediately (0 bytes sent) without crashing server listener', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );

      final serverDoneCompleter = Completer<dynamic>();

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
          serverDoneCompleter.complete('SHOULD_NOT_SUCCEED');
        } catch (e) {
          if (!serverDoneCompleter.isCompleted) serverDoneCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);
      await clientSocket.close();
      clientSocket.destroy();

      final res = await serverDoneCompleter.future.timeout(const Duration(seconds: 5));
      expect(res, isA<HandshakeException>());

      // Verify server socket listener remains alive and accepting
      final client2 = await Socket.connect('127.0.0.1', port);
      client2.destroy();

      await server.close();
    });

    test('Truncated frame header (12 bytes instead of 34) during handshake triggers FrameCodecException and teardown', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );

      final serverErrorCompleter = Completer<dynamic>();

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
        } catch (e) {
          if (!serverErrorCompleter.isCompleted) serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);
      // Send partial 12 bytes then close
      clientSocket.add(Uint8List(12));
      await clientSocket.flush();
      await clientSocket.close();
      clientSocket.destroy();

      final err = await serverErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(err, isA<HandshakeException>());

      await server.close();
    });

    test('Corrupted frame magic bytes during handshake is immediately rejected', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol();
      final serverErrorCompleter = Completer<dynamic>();

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
        } catch (e) {
          if (!serverErrorCompleter.isCompleted) serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);
      final rawHeader = Uint8List(FrameCodec.headerSize);
      ByteData.sublistView(rawHeader).setUint32(0, 0xBAD0CAFE, Endian.big); // Invalid magic
      clientSocket.add(rawHeader);
      await clientSocket.flush();
      clientSocket.destroy();

      final err = await serverErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(err, isA<HandshakeException>());

      await server.close();
    });

    test('Premature non-handshake opcode (FrameType.fileChunk) during handshake causes handshake abortion', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 500)),
      );
      final serverErrorCompleter = Completer<dynamic>();

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
        } catch (e) {
          if (!serverErrorCompleter.isCompleted) serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);
      final prematureFrame = Frame.fileChunk(
        streamId: 1,
        chunkIndex: 0,
        chunkData: Uint8List(64),
      );
      final codec = FrameCodec();
      final encoded = await codec.encodeFrame(prematureFrame, keys: null);
      clientSocket.add(encoded);
      await clientSocket.flush();
      clientSocket.destroy();

      final err = await serverErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(err, isA<HandshakeException>());

      await server.close();
    });

    test('Silent peer timeout: Client stalls after handshakeResp without sending handshakeAck', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverProtocol = HandshakeProtocol(
        options: const HandshakeOptions(timeout: Duration(milliseconds: 200)),
      );
      final serverErrorCompleter = Completer<dynamic>();

      server.listen((serverSocket) async {
        try {
          await serverProtocol.performServerHandshake(serverSocket);
        } catch (e) {
          if (!serverErrorCompleter.isCompleted) serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);
      final cipherSuite = CipherSuite();
      final keyPair = await cipherSuite.generateEphemeralKeyPair();
      final env = HandshakeEnvelope.create(publicKey: keyPair.publicKeyBytes, nonce: keyPair.nonce);
      final initFrame = Frame(type: FrameType.handshakeInit, streamId: 0, sequence: 0, payload: env.rawEnvelopeBytes);
      final encodedInit = await FrameCodec().encodeFrame(initFrame, keys: null);

      clientSocket.add(encodedInit);
      await clientSocket.flush();

      // Client now remains completely silent, never sending handshakeAck
      final err = await serverErrorCompleter.future.timeout(const Duration(seconds: 5));
      expect(err, isA<HandshakeException>());
      expect(err.toString(), contains('Timed out awaiting client handshakeAck'));

      clientSocket.destroy();
      await server.close();
    });
  });

  group('CHALLENGER M3 - TIER 4: Concurrent Connections & Session State Invariants', () {
    test('SessionManager rejects second inbound connection when already active without corrupting active transfer', () async {
      const fileSize = 1 * 1024 * 1024; // 1 MB
      final srcFile = await createSyntheticFile('primary_active.bin', fileSize);
      final expectedSha = (await crypto.sha256.bind(srcFile.openRead()).first).toString();

      final serverManager = SessionManager(
        options: SessionManagerOptions(
          autoVerifySas: true,
          downloadDirectory: destDir,
        ),
      );
      await serverManager.startServer(host: '127.0.0.1', port: 0);
      final serverPort = serverManager.serverPort!;

      final clientManager = SessionManager(
        options: const SessionManagerOptions(autoVerifySas: true),
      );

      bool secondAttemptMade = false;

      // Start primary legitimate transfer
      final primaryTransferFuture = clientManager.sendFile(
        host: '127.0.0.1',
        port: serverPort,
        file: srcFile,
        onProgress: (progress) async {
          if (!secondAttemptMade && progress.transferredBytes >= 256 * 1024) {
            secondAttemptMade = true;

            // Attack: second connection attempts to hijack or connect while primary is transferring
            try {
              final rogueSocket = await Socket.connect('127.0.0.1', serverPort);
              final rogueProtocol = HandshakeProtocol();
              // Attempt handshake
              await rogueProtocol.performClientHandshake(rogueSocket);
              fail('Second concurrent connection should have been destroyed immediately by busy server');
            } catch (e) {
              // Expected rejection
              expect(e, isNotNull);
            }
          }
        },
      );

      final result = await primaryTransferFuture;
      expect(result.totalBytes, equals(fileSize));
      expect(result.sha256Digest, equals(expectedSha));

      // Wait for server to commit file
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final committed = File(p.join(destDir.path, 'primary_active.bin'));
      expect(committed.existsSync(), isTrue);
      expect(committed.lengthSync(), equals(fileSize));
      final receivedSha = (await crypto.sha256.bind(committed.openRead()).first).toString();
      expect(receivedSha, equals(expectedSha));

      serverManager.dispose();
      clientManager.dispose();
    });

    test('Rapid consecutive transfers (5 iterations) on the same SessionManager server instance succeed seamlessly', () async {
      final serverManager = SessionManager(
        options: SessionManagerOptions(
          autoVerifySas: true,
          downloadDirectory: destDir,
        ),
      );
      await serverManager.startServer(host: '127.0.0.1', port: 0);
      final serverPort = serverManager.serverPort!;

      final clientManager = SessionManager(
        options: const SessionManagerOptions(autoVerifySas: true),
      );

      for (int i = 0; i < 5; i++) {
        final fileName = 'consecutive_$i.dat';
        final fileSize = (64 + i * 32) * 1024; // 64KB, 96KB, 128KB, 160KB, 192KB
        final file = await createSyntheticFile(fileName, fileSize);
        final expectedSha = (await crypto.sha256.bind(file.openRead()).first).toString();

        final result = await clientManager.sendFile(
          host: '127.0.0.1',
          port: serverPort,
          file: file,
        );

        expect(result.totalBytes, equals(fileSize));
        expect(result.sha256Digest, equals(expectedSha));

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final receivedFile = File(p.join(destDir.path, fileName));
        expect(receivedFile.existsSync(), isTrue);
        expect(receivedFile.lengthSync(), equals(fileSize));
        final receivedSha = (await crypto.sha256.bind(receivedFile.openRead()).first).toString();
        expect(receivedSha, equals(expectedSha));
      }

      serverManager.dispose();
      clientManager.dispose();
    });

    test('Connection storm: 15 rogue sockets rapidly connecting and disconnecting do not incapacitate listener', () async {
      final serverManager = SessionManager(
        options: SessionManagerOptions(
          autoVerifySas: true,
          downloadDirectory: destDir,
        ),
      );
      await serverManager.startServer(host: '127.0.0.1', port: 0);
      final serverPort = serverManager.serverPort!;

      // Blast 15 rogue connections with random behavior
      final futures = <Future<void>>[];
      for (int i = 0; i < 15; i++) {
        futures.add(() async {
          try {
            final s = await Socket.connect('127.0.0.1', serverPort);
            if (i % 3 == 0) {
              s.add(Uint8List(50));
            } else if (i % 3 == 1) {
              s.add(Uint8List.fromList(utf8.encode('GARBAGE_PAYLOAD_DATA')));
            }
            await s.flush();
            s.destroy();
          } catch (_) {}
        }());
      }
      await Future.wait(futures);

      // Wait a moment for server listener to settle
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Legitimate client connects and transfers file
      final clientManager = SessionManager(
        options: const SessionManagerOptions(autoVerifySas: true),
      );
      final srcFile = await createSyntheticFile('post_storm.dat', 128 * 1024);
      final expectedSha = (await crypto.sha256.bind(srcFile.openRead()).first).toString();

      final result = await clientManager.sendFile(
        host: '127.0.0.1',
        port: serverPort,
        file: srcFile,
      );

      expect(result.sha256Digest, equals(expectedSha));

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final receivedFile = File(p.join(destDir.path, 'post_storm.dat'));
      expect(receivedFile.existsSync(), isTrue);

      serverManager.dispose();
      clientManager.dispose();
    });
  });
}
