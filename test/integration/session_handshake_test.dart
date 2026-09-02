import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/protocol/frame_codec.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';
import 'package:secure_lan_transfer/core/protocol/session_state.dart';
import 'package:secure_lan_transfer/core/session/handshake_protocol.dart';
import 'package:secure_lan_transfer/core/session/session_manager.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late Directory destDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slft_session_test_');
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
    final file = File('${sourceDir.path}/$name');
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

  group('HandshakeProtocol 3-Way Cryptographic Invariants', () {
    test('Successful 3-way X25519 ECDH + HKDF handshake and frame stream continuity', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverHandshakeProtocol = HandshakeProtocol();
      final clientHandshakeProtocol = HandshakeProtocol();

      final serverCompleter = Completer<HandshakeResult>();

      server.listen((serverSocket) async {
        try {
          final res = await serverHandshakeProtocol.performServerHandshake(serverSocket);
          serverCompleter.complete(res);
        } catch (e, st) {
          serverCompleter.completeError(e, st);
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);
      final clientResult = await clientHandshakeProtocol.performClientHandshake(clientSocket);
      final serverResult = await serverCompleter.future;

      // 1. Transcript Hash Invariant
      expect(clientResult.transcriptHash, equals(serverResult.transcriptHash));

      // 2. SAS Code Invariant (6-digit decimal & 4-emoji visual tuple)
      expect(clientResult.sasCode.numericCode, equals(serverResult.sasCode.numericCode));
      expect(clientResult.sasCode.emojiGlyphs, equals(serverResult.sasCode.emojiGlyphs));
      expect(clientResult.sasCode.emojiGlyphList, equals(serverResult.sasCode.emojiGlyphList));
      expect(clientResult.sasCode.matches(serverResult.sasCode), isTrue);

      // 3. Bidirectional Key Agreement Invariant
      expect(clientResult.sessionKeys.outboundKey, equals(serverResult.sessionKeys.inboundKey));
      expect(clientResult.sessionKeys.inboundKey, equals(serverResult.sessionKeys.outboundKey));
      expect(clientResult.sessionKeys.outboundBaseIv, equals(serverResult.sessionKeys.inboundBaseIv));
      expect(clientResult.sessionKeys.inboundBaseIv, equals(serverResult.sessionKeys.outboundBaseIv));
      expect(clientResult.sessionKeys.maskKey, equals(serverResult.sessionKeys.maskKey));

      // 4. Frame Stream Continuity Verification
      // Send encrypted post-handshake data frame from client to server
      final testFrame = Frame(
        type: FrameType.ping,
        streamId: 42,
        sequence: 1,
        payload: Uint8List.fromList(utf8.encode('CONTINUITY_CHECK')),
      );
      final codec = FrameCodec();
      final encodedFrame = await codec.encodeFrame(testFrame, keys: clientResult.sessionKeys);
      clientResult.socket.add(encodedFrame);
      await clientResult.socket.flush();

      final receivedFrame = await serverResult.incomingFrameStream.first;
      expect(receivedFrame.type, equals(FrameType.ping));
      expect(receivedFrame.streamId, equals(42));
      expect(receivedFrame.sequence, equals(1));
      expect(utf8.decode(receivedFrame.payload), equals('CONTINUITY_CHECK'));

      await clientResult.socket.close();
      await serverResult.socket.close();
      await server.close();
    });

    test('SAS user rejection on client aborts handshake with HandshakeException', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverHandshakeProtocol = HandshakeProtocol();
      final clientHandshakeProtocol = HandshakeProtocol();

      server.listen((serverSocket) async {
        try {
          await serverHandshakeProtocol.performServerHandshake(serverSocket);
        } catch (_) {
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);

      await expectLater(
        clientHandshakeProtocol.performClientHandshake(
          clientSocket,
          onVerifySas: (sas) async => false, // Reject SAS
        ),
        throwsA(isA<HandshakeException>()),
      );

      await server.close();
    });

    test('SAS user rejection on server aborts handshake with HandshakeException', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      final serverHandshakeProtocol = HandshakeProtocol();
      final clientHandshakeProtocol = HandshakeProtocol();

      final serverErrorCompleter = Completer<dynamic>();

      server.listen((serverSocket) async {
        try {
          await serverHandshakeProtocol.performServerHandshake(
            serverSocket,
            onVerifySas: (sas) async => false, // Reject SAS
          );
        } catch (e) {
          serverErrorCompleter.complete(e);
        } finally {
          serverSocket.destroy();
        }
      });

      final clientSocket = await Socket.connect('127.0.0.1', port);

      await expectLater(
        clientHandshakeProtocol.performClientHandshake(clientSocket),
        throwsA(isA<HandshakeException>()),
      );

      final serverErr = await serverErrorCompleter.future;
      expect(serverErr, isA<HandshakeException>());

      await server.close();
    });
  });

  group('SessionManager End-to-End Integration Tests', () {
    test('End-to-end file transfer with automatic SAS verification and state progression', () async {
      const fileSize = 512 * 1024; // 512 KB
      final srcFile = await createSyntheticFile('e2e_transfer.dat', fileSize);
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
        options: const SessionManagerOptions(
          autoVerifySas: true,
        ),
      );

      final clientStateHistory = <TransferState>[];
      final stateSub = clientManager.sessionStateStream.listen((s) {
        clientStateHistory.add(s.state);
      });

      final sendResult = await clientManager.sendFile(
        host: '127.0.0.1',
        port: serverPort,
        file: srcFile,
        targetDeviceName: 'Test Server Receiver',
      );

      expect(sendResult.totalBytes, equals(fileSize));
      expect(sendResult.fileName, equals('e2e_transfer.dat'));
      expect(sendResult.sha256Digest, equals(expectedSha));

      // Wait a moment for server to commit file
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final receivedFile = File('${destDir.path}/e2e_transfer.dat');
      expect(receivedFile.existsSync(), isTrue);
      expect(receivedFile.lengthSync(), equals(fileSize));

      final receivedSha = (await crypto.sha256.bind(receivedFile.openRead()).first).toString();
      expect(receivedSha, equals(expectedSha));

      expect(clientStateHistory, contains(TransferState.connecting));
      expect(clientStateHistory, contains(TransferState.handshaking));
      expect(clientStateHistory, contains(TransferState.transferring));
      expect(clientStateHistory, contains(TransferState.completed));

      await stateSub.cancel();
      serverManager.dispose();
      clientManager.dispose();
    });

    test('Inbound session proposal rejection cleanly declines incoming connection', () async {
      final serverManager = SessionManager(
        options: SessionManagerOptions(
          autoAcceptInbound: false, // Require explicit proposal approval
          downloadDirectory: destDir,
        ),
      );
      await serverManager.startServer(host: '127.0.0.1', port: 0);
      final serverPort = serverManager.serverPort!;

      // Automatically reject proposal
      final propSub = serverManager.inboundProposalsStream.listen((proposal) {
        proposal.reject('User declined connection');
      });

      final clientManager = SessionManager();
      final srcFile = await createSyntheticFile('declined.dat', 64 * 1024);

      await expectLater(
        clientManager.sendFile(
          host: '127.0.0.1',
          port: serverPort,
          file: srcFile,
        ),
        throwsA(isA<Exception>()),
      );

      await propSub.cancel();
      serverManager.dispose();
      clientManager.dispose();
    });

    test('Session cancellation mid-transfer cleans up socket and staging handles', () async {
      const fileSize = 2 * 1024 * 1024; // 2 MB
      final srcFile = await createSyntheticFile('cancel_test.dat', fileSize);

      final serverManager = SessionManager(
        options: SessionManagerOptions(
          autoVerifySas: true,
          downloadDirectory: destDir,
        ),
      );
      await serverManager.startServer(host: '127.0.0.1', port: 0);
      final serverPort = serverManager.serverPort!;

      final clientManager = SessionManager(
        options: const SessionManagerOptions(
          autoVerifySas: true,
        ),
      );

      bool cancelled = false;

      final transferFuture = clientManager.sendFile(
        host: '127.0.0.1',
        port: serverPort,
        file: srcFile,
        onProgress: (progress) {
          if (!cancelled && progress.transferredBytes >= 256 * 1024) {
            cancelled = true;
            clientManager.cancelCurrentSession(reason: 'User cancel test');
          }
        },
      );

      await expectLater(transferFuture, throwsA(isA<Exception>()));

      // Wait for server receiver to detect disconnect and finish abort unlinking
      for (int i = 0; i < 40; i++) {
        final state = serverManager.currentState.state;
        if (state == TransferState.error ||
            state == TransferState.cancelled ||
            state == TransferState.idle) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      List<FileSystemEntity> partFiles = [];
      for (int i = 0; i < 40; i++) {
        partFiles = destDir.listSync().where((e) => e.path.endsWith('.slft_part')).toList();
        if (partFiles.isEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(partFiles, isEmpty);

      serverManager.dispose();
      clientManager.dispose();
    });
  });
}
