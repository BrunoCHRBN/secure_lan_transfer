import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';
import '../helpers/test_utils.dart';

void main() {
  const cliScript = 'bin/secure_transfer_cli.dart';

  group('CLI Syntax & Subcommand Tests', () {
    test('secure_transfer_cli --help exits with code 0 and displays usage',
        () async {
      final result = await runDartProcess(['run', cliScript, '--help']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('Secure LAN File Transfer CLI'));
      expect(result.stdout, contains('COMMANDS:'));
      expect(result.stdout, contains('send'));
      expect(result.stdout, contains('receive'));
      expect(result.stdout, contains('discover'));
      expect(result.stdout, contains('pair'));
    });

    test('secure_transfer_cli --version exits with code 0', () async {
      final result = await runDartProcess(['run', cliScript, '--version']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('v1.'));
      expect(result.stdout, contains('SLFT/1.0'));
    });

    test('secure_transfer_cli send --help exits with code 0', () async {
      final result =
          await runDartProcess(['run', cliScript, 'send', '--help']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('--target'));
      expect(result.stdout, contains('--file'));
    });

    test('secure_transfer_cli receive --help exits with code 0', () async {
      final result =
          await runDartProcess(['run', cliScript, 'receive', '--help']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('--port'));
      expect(result.stdout, contains('--output-dir'));
    });

    test('secure_transfer_cli discover --help exits with code 0', () async {
      final result =
          await runDartProcess(['run', cliScript, 'discover', '--help']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('--timeout'));
    });

    test('secure_transfer_cli pair --help exits with code 0', () async {
      final result =
          await runDartProcess(['run', cliScript, 'pair', '--help']);
      expect(result.exitCode, equals(0));
      expect(result.stdout, contains('--target'));
    });
  });

  group('CLI Error Handling & Exit Codes', () {
    test('Missing arguments to send command exits with code 6', () async {
      final result = await runDartProcess(['run', cliScript, 'send']);
      expect(result.exitCode, equals(6));
    });

    test('Missing source file to send command exits with code 5', () async {
      final result = await runDartProcess([
        'run',
        cliScript,
        'send',
        '--target',
        '127.0.0.1:42385',
        '--file',
        'nonexistent_payload_12345.dat',
      ]);
      expect(result.exitCode, equals(5));
    });

    test('Invalid target address syntax exits with code 6', () async {
      final result = await runDartProcess([
        'run',
        cliScript,
        'pair',
        '--target',
        '[invalid_ipv6_bracket',
      ]);
      expect(result.exitCode, equals(6));
    });

    test('Connection refused to unopened port exits with code 2', () async {
      final result = await runDartProcess([
        'run',
        cliScript,
        'send',
        '--target',
        '127.0.0.1:59996',
        '--file',
        'pubspec.yaml',
        '--auto-verify',
      ]);
      expect(result.exitCode, equals(2));
    });
  });

  group('CLI Loopback E2E Transfer Tests', () {
    late Directory tempDir;
    late Directory outDir;
    late File sampleFile;
    const testPort = 42397;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('slft_cli_test_');
      outDir = Directory('${tempDir.path}/out');
      await outDir.create();

      sampleFile = File('${tempDir.path}/test_file.txt');
      await sampleFile.writeAsString('Hello, Secure LAN File Transfer E2EE CLI!');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('Send and receive one-shot loopback transfer succeeds with code 0 and verified digest',
        () async {
      // 1. Spawn receiver in background
      final receiverProc = await startDartProcess([
        'run',
        cliScript,
        'receive',
        '--port',
        testPort.toString(),
        '--output-dir',
        outDir.path,
        '--auto-accept',
        '--auto-verify',
        '--json',
      ]);

      final receiverReady = Completer<void>();
      final receiverOutput = <String>[];

      final sub = receiverProc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        receiverOutput.add(line);
        if (line.contains('"event":"listening"')) {
          if (!receiverReady.isCompleted) receiverReady.complete();
        }
      });

      // Wait for receiver to bind socket
      await receiverReady.future.timeout(const Duration(seconds: 10));

      // 2. Spawn sender to transmit file
      final senderResult = await runDartProcess([
        'run',
        cliScript,
        'send',
        '--target',
        '127.0.0.1:$testPort',
        '--file',
        sampleFile.path,
        '--auto-verify',
        '--json',
      ]);

      expect(senderResult.exitCode, equals(0));

      final receivedFile = File('${outDir.path}/test_file.txt');
      expect(await receivedFile.exists(), isTrue);

      final expectedSha = await calculateFileSha256(sampleFile);
      final receivedSha = await calculateFileSha256(receivedFile);
      expect(receivedSha, equals(expectedSha));

      await sub.cancel();
      final receiverExit = await receiverProc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        receiverProc.killTree();
        return -1;
      });
      expect(receiverExit, equals(0));
    });

    test('Positional shorthand send transfer succeeds with code 0', () async {
      const posPort = 42398;
      final receiverProc = await startDartProcess([
        'run',
        cliScript,
        'recv',
        '--port',
        posPort.toString(),
        '--output-dir',
        outDir.path,
        '--auto-accept',
        '--auto-verify',
        '--json',
      ]);

      final receiverReady = Completer<void>();
      final sub = receiverProc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.contains('"event":"listening"')) {
          if (!receiverReady.isCompleted) receiverReady.complete();
        }
      });

      await receiverReady.future.timeout(const Duration(seconds: 10));

      final senderResult = await runDartProcess([
        'run',
        cliScript,
        sampleFile.path,
        '127.0.0.1:$posPort',
        '--auto-verify',
        '--json',
      ]);

      expect(senderResult.exitCode, equals(0));
      await sub.cancel();
      final receiverExit = await receiverProc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
        receiverProc.killTree();
        return -1;
      });
      expect(receiverExit, equals(0));
    });

    test('CLI aliases recv, scan, s and p are recognized', () async {
      final recvRes = await runDartProcess(['run', cliScript, 'recv', '--help']);
      expect(recvRes.exitCode, equals(0));
      expect(recvRes.stdout, contains('--port'));

      final scanRes = await runDartProcess(['run', cliScript, 'scan', '--help']);
      expect(scanRes.exitCode, equals(0));
      expect(scanRes.stdout, contains('--timeout'));

      final sRes = await runDartProcess(['run', cliScript, 's', '--help']);
      expect(sRes.exitCode, equals(0));
      expect(sRes.stdout, contains('--target'));
    });
  });
}
