import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Cryptographic and memory hygiene exceptions.
class IntegrityMismatchException implements Exception {
  final String message;
  const IntegrityMismatchException(this.message);
  @override
  String toString() => 'IntegrityMismatchException: $message';
}

class TransferAbortedException implements Exception {
  final String message;
  const TransferAbortedException(this.message);
  @override
  String toString() => 'TransferAbortedException: $message';
}

class SecurityException implements Exception {
  final String message;
  const SecurityException(this.message);
  @override
  String toString() => 'SecurityException: $message';
}

/// Utility for in-memory hygiene, zeroization, and constant-time operations.
class ByteUtils {
  /// Zeroizes the given byte buffer in place to prevent memory scraping.
  static void zeroize(Uint8List? buffer) {
    if (buffer == null || buffer.isEmpty) return;
    buffer.fillRange(0, buffer.length, 0);
  }

  /// Checks whether all bytes in the buffer are zero.
  static bool isZero(Uint8List buffer) {
    for (int i = 0; i < buffer.length; i++) {
      if (buffer[i] != 0) return false;
    }
    return true;
  }

  /// Constant-time byte buffer comparison to mitigate timing side-channel attacks.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Generates cryptographically secure random bytes from OS entropy pool.
  static Uint8List secureRandomBytes(int length) {
    final rng = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }
}

/// Strict Path Sanitizer preventing Directory Traversal, Null Byte Injection,
/// Windows Device Name collisions, and illegal filesystem characters.
class PathSanitizer {
  static final RegExp _controlChars = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\uFFF0-\uFFFF]',
  );
  static final RegExp _illegalChars = RegExp(r'[<>:"/\\|?*]');
  static final RegExp _windowsReserved = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
    caseSensitive: false,
  );

  /// Sanitizes a raw untrusted filename received over the network.
  static String sanitize(
    String rawName, {
    String defaultFallback = 'unnamed_file',
    int maxLength = 240,
    bool allowDotFiles = false,
  }) {
    if (rawName.isEmpty) return defaultFallback;

    // 1. Strip null bytes and control characters
    var clean = rawName.replaceAll(_controlChars, '');

    // 2. Normalize path separators to forward slashes and extract basename
    clean = clean.replaceAll('\\', '/');
    clean = p.basename(clean);

    // 3. Remove relative traversal sequences
    clean = clean.replaceAll(RegExp(r'\.{2,}'), '_');

    // 4. Replace illegal filesystem characters with underscores
    clean = clean.replaceAll(_illegalChars, '_');

    // 5. Trim leading/trailing whitespace and trailing dots
    clean = clean.trim();
    while (clean.endsWith('.')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }

    // 6. Handle Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9)
    if (_windowsReserved.hasMatch(clean)) {
      clean = '_$clean';
    }

    // 7. Handle hidden dot-files
    if (clean.startsWith('.') && !allowDotFiles) {
      clean = '_$clean';
    }

    // 8. Handle empty or degenerate filenames
    if (clean.isEmpty || clean == '_' || clean == '.') {
      return defaultFallback;
    }

    // 9. Length bounding while preserving file extension
    if (clean.length > maxLength) {
      final ext = p.extension(clean);
      if (ext.isNotEmpty && ext.length < 24 && maxLength > ext.length) {
        final base = p.basenameWithoutExtension(clean);
        clean = '${base.substring(0, maxLength - ext.length)}$ext';
      } else {
        clean = clean.substring(0, maxLength);
      }
    }

    return clean;
  }
}

/// Resolves collision-free unique destination file paths and tracks in-flight reservations.
class DestinationPathResolver {
  static final Set<String> _activeReservations = <String>{};

  static String _canonicalKey(String path) {
    final canonical = p.canonicalize(path);
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  /// Reserves a unique path in memory and on disk during staging handle creation.
  static Future<String> reserveUniquePath(
    Directory destinationDir,
    String sanitizedFilename,
  ) async {
    final ext = p.extension(sanitizedFilename);
    final nameWithoutExt = p.basenameWithoutExtension(sanitizedFilename);

    int counter = 0;
    while (true) {
      final candidateName = counter == 0
          ? sanitizedFilename
          : '$nameWithoutExt ($counter)$ext';
      final candidatePath = p.join(destinationDir.path, candidateName);
      final key = _canonicalKey(candidatePath);

      if (!_activeReservations.contains(key) && !File(candidatePath).existsSync()) {
        _activeReservations.add(key);
        return candidatePath;
      }
      counter++;
    }
  }

  /// Releases an in-memory reservation upon transfer abort or commit.
  static void releaseReservation(String path) {
    _activeReservations.remove(_canonicalKey(path));
  }

  /// Clears in-memory reservations (for testing purposes).
  static void clearReservations() {
    _activeReservations.clear();
  }

  /// Resolves an available unique path against disk state.
  static Future<String> resolveUniquePath(
    Directory destinationDir,
    String sanitizedFilename,
  ) async {
    final basePath = p.join(destinationDir.path, sanitizedFilename);
    if (!await File(basePath).exists()) {
      return basePath;
    }

    final ext = p.extension(sanitizedFilename);
    final nameWithoutExt = p.basenameWithoutExtension(sanitizedFilename);

    int counter = 1;
    while (true) {
      final candidateName = '$nameWithoutExt ($counter)$ext';
      final candidatePath = p.join(destinationDir.path, candidateName);
      if (!await File(candidatePath).exists()) {
        return candidatePath;
      }
      counter++;
    }
  }
}

/// FIFO asynchronous mutex for serialized operations.
class _AsyncMutex {
  Future<void>? _lastOp;

  Future<T> synchronized<T>(Future<T> Function() criticalSection) {
    final previous = _lastOp;
    final completer = Completer<void>();
    _lastOp = completer.future;

    return Future.sync(() async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      try {
        return await criticalSection();
      } finally {
        completer.complete();
      }
    });
  }
}

/// Directory-level commit lock preventing TOCTOU races between concurrent transfer finalizations.
class DirectoryCommitLock {
  static final Map<String, _AsyncMutex> _locks = {};

  static String _canonicalKey(String path) {
    final canonical = p.canonicalize(path);
    return Platform.isWindows ? canonical.toLowerCase() : canonical;
  }

  /// Executes [action] under exclusive lock for [dirPath].
  static Future<T> synchronized<T>(
    String dirPath,
    Future<T> Function() action,
  ) {
    final key = _canonicalKey(dirPath);
    final mutex = _locks.putIfAbsent(key, () => _AsyncMutex());
    return mutex.synchronized(action);
  }
}

/// Atomic File Staging Handle with automatic unlinking, SHA-256 validation,
/// and re-entrancy / concurrency synchronization.
class StagingFileHandle {
  final File stagingFile;
  final Directory destinationDir;
  final String sanitizedFilename;
  final String tentativePath;
  final int expectedTotalBytes;
  final Uint8List expectedRootSha256;
  final bool secureWipeOnAbort;

  String? _committedPath;
  RandomAccessFile? _raf;
  late final AccumulatorSink<crypto.Digest> _accumulator;
  late final ByteConversionSink _hashSink;
  int _bytesWritten = 0;
  bool _isClosed = false;
  bool _isCommitted = false;
  Completer<void>? _abortCompleter;

  StagingFileHandle._({
    required this.stagingFile,
    required this.destinationDir,
    required this.sanitizedFilename,
    required this.tentativePath,
    required this.expectedTotalBytes,
    required this.expectedRootSha256,
    required this.secureWipeOnAbort,
    required RandomAccessFile raf,
  }) : _raf = raf {
    _accumulator = AccumulatorSink<crypto.Digest>();
    _hashSink = crypto.sha256.startChunkedConversion(_accumulator);
  }

  String get resolvedFinalPath => _committedPath ?? tentativePath;
  String? get committedPath => _committedPath;
  int get bytesWritten => _bytesWritten;
  bool get isClosed => _isClosed;
  bool get isCommitted => _isCommitted;

  /// Creates a new staging file session in `<destinationDir>/.<uuid>.slft_part`.
  static Future<StagingFileHandle> create({
    required Directory destinationDir,
    required String originalFilename,
    required int expectedTotalBytes,
    required Uint8List expectedRootSha256,
    bool secureWipeOnAbort = false,
  }) async {
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    final sanitizedName = PathSanitizer.sanitize(originalFilename);
    final tentativePath = await DestinationPathResolver.reserveUniquePath(
      destinationDir,
      sanitizedName,
    );

    final stagingUuid = const Uuid().v4();
    final stagingPath = p.join(destinationDir.path, '.$stagingUuid.slft_part');
    final stagingFile = File(stagingPath);

    final raf = await stagingFile.open(mode: FileMode.write);

    return StagingFileHandle._(
      stagingFile: stagingFile,
      destinationDir: destinationDir,
      sanitizedFilename: sanitizedName,
      tentativePath: tentativePath,
      expectedTotalBytes: expectedTotalBytes,
      expectedRootSha256: expectedRootSha256,
      secureWipeOnAbort: secureWipeOnAbort,
      raf: raf,
    );
  }

  /// Appends a decrypted chunk to the staging file and updates progressive SHA-256.
  Future<void> writeChunk(Uint8List decryptedChunk) async {
    if (_isClosed || _abortCompleter != null) {
      throw const TransferAbortedException('Attempted write to closed staging file.');
    }
    if (_raf == null) {
      throw const TransferAbortedException('RandomAccessFile handle is null.');
    }

    await _raf!.writeFrom(decryptedChunk);
    _hashSink.add(decryptedChunk);
    _bytesWritten += decryptedChunk.length;
  }

  /// Verifies byte count and cumulative SHA-256 root digest, then atomically renames.
  Future<File> commitAndVerify() async {
    if (_isClosed || _raf == null || _abortCompleter != null) {
      throw const TransferAbortedException('Staging file handle is not open for commit.');
    }

    final raf = _raf!;
    _raf = null;
    _isClosed = true;

    await raf.flush();
    await raf.close();

    _hashSink.close();
    final computedDigest = _accumulator.events.single.bytes;

    // 1. Verify byte length
    if (_bytesWritten != expectedTotalBytes) {
      await abort(reason: 'Byte count mismatch: expected $expectedTotalBytes, got $_bytesWritten');
      throw IntegrityMismatchException(
        'Size mismatch: expected $expectedTotalBytes, received $_bytesWritten',
      );
    }

    // 2. Verify SHA-256 root digest using constant-time comparison
    if (!ByteUtils.constantTimeEquals(computedDigest, expectedRootSha256)) {
      await abort(reason: 'SHA-256 checksum mismatch');
      throw const IntegrityMismatchException('Cryptographic SHA-256 root digest mismatch.');
    }

    // 3. Atomically resolve destination path and rename inside directory commit lock
    return await DirectoryCommitLock.synchronized(destinationDir.path, () async {
      try {
        DestinationPathResolver.releaseReservation(tentativePath);

        final finalPath = await DestinationPathResolver.resolveUniquePath(
          destinationDir,
          sanitizedFilename,
        );

        final finalFile = await stagingFile.rename(finalPath);
        _committedPath = finalPath;
        _isCommitted = true;
        return finalFile;
      } catch (e) {
        await abort(reason: 'Atomic rename failed: $e');
        rethrow;
      }
    });
  }

  /// Immediately unlinks and deletes the staging file upon abort, error, or mismatch.
  /// Synchronized via [_abortCompleter] to guarantee exactly-once teardown across
  /// concurrent invocations and eliminate file lock races.
  Future<void> abort({String? reason}) async {
    if (_isCommitted) return;

    if (_abortCompleter != null) {
      return _abortCompleter!.future;
    }

    final completer = Completer<void>();
    _abortCompleter = completer;
    _isClosed = true;

    // Release in-flight path reservation
    DestinationPathResolver.releaseReservation(tentativePath);

    // Immediate synchronous detachment of RAF before async suspension
    final raf = _raf;
    _raf = null;

    try {
      if (raf != null) {
        try {
          await raf.flush();
        } catch (_) {}
        try {
          await raf.close();
        } catch (_) {}
      }

      try {
        _hashSink.close();
      } catch (_) {}

      if (await stagingFile.exists()) {
        if (secureWipeOnAbort && _bytesWritten > 0) {
          await _secureWipeFile(stagingFile, _bytesWritten);
        }
        for (int i = 0; i < 30; i++) {
          try {
            if (await stagingFile.exists()) {
              await stagingFile.delete();
            }
            break;
          } catch (_) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
      }
    } catch (_) {
      // Teardown errors suppressed to guarantee clean completion
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    return completer.future;
  }

  /// Overwrites file sectors with zero bytes before unlinking.
  static Future<void> _secureWipeFile(File file, int length) async {
    try {
      if (!await file.exists()) return;
      final wipeRaf = await file.open(mode: FileMode.write);
      try {
        const chunkSize = 65536;
        final zeroBuffer = Uint8List(min(chunkSize, length));
        int remaining = length;
        while (remaining > 0) {
          final toWrite = min(zeroBuffer.length, remaining);
          await wipeRaf.writeFrom(zeroBuffer, 0, toWrite);
          remaining -= toWrite;
        }
        await wipeRaf.flush();
      } finally {
        await wipeRaf.close();
      }
    } catch (_) {}
  }
}
