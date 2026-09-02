import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';

/// Helper to create an ephemeral loopback socket pair for deterministic testing.
Future<({Socket senderSocket, Socket receiverSocket})> createLoopbackSockets() async {
  final serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final clientFuture = Socket.connect(InternetAddress.loopbackIPv4, serverSocket.port);
  final serverConnFuture = serverSocket.first;
  final results = await Future.wait([clientFuture, serverConnFuture]);
  await serverSocket.close();
  return (senderSocket: results[0], receiverSocket: results[1]);
}

/// Helper to derive matched initiator and receiver SessionKeys via genuine ECDH.
Future<({SessionKeys senderKeys, SessionKeys receiverKeys})> createPairedKeys({
  Uint8List? customTranscriptHash,
}) async {
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

  final transcriptHash = customTranscriptHash ?? (Uint8List(32)..fillRange(0, 32, 0x42));

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

/// Creates a synthetic test file of exact [byteCount] bytes in [dir] using chunked I/O.
Future<File> createSyntheticFile(
  Directory dir,
  String name,
  int byteCount, {
  int Function(int byteIndex)? pattern,
}) async {
  final file = File(p.join(dir.path, name));
  final raf = await file.open(mode: FileMode.write);
  const chunkSize = 65536;
  int written = 0;

  final buffer = Uint8List(chunkSize);
  while (written < byteCount) {
    final toWrite = min(chunkSize, byteCount - written);
    for (int i = 0; i < toWrite; i++) {
      buffer[i] = pattern != null ? pattern(written + i) : (written + i) % 256;
    }
    await raf.writeFrom(buffer, 0, toWrite);
    written += toWrite;
  }
  await raf.close();
  return file;
}

/// Computes hex-encoded SHA-256 digest of a file using streaming chunked I/O.
Future<String> calculateFileSha256(File file) async {
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return hex.encode(digest.bytes);
}

/// Computes hex-encoded SHA-256 digest of an in-memory byte list.
String calculateBytesSha256(List<int> bytes) {
  final digest = crypto.sha256.convert(bytes);
  return hex.encode(digest.bytes);
}

/// High-resolution RSS memory monitor for verifying bounded memory footprint.
class MemoryMonitor {
  final Duration interval;
  Timer? _timer;
  int _baselineRss = 0;
  int _peakRss = 0;

  MemoryMonitor({this.interval = const Duration(milliseconds: 10)});

  int get baselineRss => _baselineRss;
  int get peakRss => _peakRss;
  int get deltaRss => max(0, _peakRss - _baselineRss);
  double get deltaMb => deltaRss / (1024 * 1024);
  double get baselineMb => _baselineRss / (1024 * 1024);
  double get peakMb => _peakRss / (1024 * 1024);

  void start() {
    _baselineRss = ProcessInfo.currentRss;
    _peakRss = _baselineRss;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      final current = ProcessInfo.currentRss;
      if (current > _peakRss) {
        _peakRss = current;
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    final finalCurrent = ProcessInfo.currentRss;
    if (finalCurrent > _peakRss) {
      _peakRss = finalCurrent;
    }
  }
}

/// Spawns a completed Dart CLI subprocess cross-platform.
Future<ProcessResult> runDartProcess(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.run(
    Platform.resolvedExecutable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

/// Spawns a streaming Dart CLI subprocess cross-platform.
Future<Process> startDartProcess(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.start(
    Platform.resolvedExecutable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}


/// Helper extension to forcefully kill process trees on Windows and POSIX.
extension ProcessKillExtension on Process {
  void killTree() {
    if (Platform.isWindows) {
      try {
        Process.runSync('taskkill', ['/F', '/T', '/PID', '$pid']);
      } catch (_) {}
    }
    try {
      kill(ProcessSignal.sigkill);
    } catch (_) {}
  }
}