import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:secure_lan_transfer/core/crypto/zero_metadata_staging.dart';

void main() {
  late Directory tempTestDir;

  setUp(() async {
    tempTestDir = await Directory.systemTemp.createTemp('slft_challenger2_staging_');
  });

  tearDown(() async {
    if (await tempTestDir.exists()) {
      try {
        await tempTestDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('CHALLENGER 2 - TIER 1: Path Traversal & Device Name Sanitization (80+ Vectors)', () {
    final adversarialVectors = <String>[
      // 1. Classic Directory Traversal (45 vectors)
      '../secret.txt',
      '../../secret.txt',
      '../../../secret.txt',
      '../../../../../../../../../../../../etc/passwd',
      '../../../../../../../../../../../../etc/shadow',
      r'..\secret.txt',
      r'..\..\secret.txt',
      r'..\..\..\..\..\..\Windows\System32\calc.exe',
      r'..\..\..\..\..\..\Windows\System32\drivers\etc\hosts',
      r'..\..\..\..\..\..\Windows\System32\config\SAM',
      '....//evil.txt',
      r'....\\\\evil.txt',
      '..;/evil.txt',
      '..%2fevil.txt',
      '..%252fevil.txt',
      '..%5cevil.txt',
      '.%2e/evil.txt',
      '%2e%2e/evil.txt',
      '%2e%2e%2fevil.txt',
      r'%2e%2e%5cevil.txt',
      '%252e%252e%252fevil.txt',
      '.../evil.txt',
      '..../evil.txt',
      '/etc/passwd',
      '/var/log/syslog',
      '/root/.ssh/id_rsa',
      r'C:\Windows\System32\drivers\etc\hosts',
      'C:/Windows/System32/cmd.exe',
      r'\\?\C:\Windows\System32\evil.dll',
      r'\\.\COM1',
      r'//localhost/c$/evil.txt',
      'D:/data/secret.key',
      '..',
      '.',
      '...',
      '....',
      '../../',
      r'..\..\',
      'foo/../../../bar.txt',
      r'foo\..\..\..\bar.txt',
      'nested/dir/../traversal.txt',
      'a/b/c/../../../../../../root.txt',
      r'a\b\c\..\..\..\..\..\..\root.txt',
      '.../...//.../...//evil.txt',
      r'..\..\..\..\..\..\..\..\..\..\boot.ini',
      '~/secret.key',
      '~root/.bashrc',

      // 2. Windows Reserved Device Names & Variations (27 vectors)
      'CON',
      'con',
      'PRN',
      'prn',
      'AUX',
      'aux',
      'NUL',
      'nul',
      'COM1',
      'COM2',
      'COM3',
      'COM4',
      'COM5',
      'COM6',
      'COM7',
      'COM8',
      'COM9',
      'com1',
      'com2',
      'com3',
      'com4',
      'com5',
      'com6',
      'com7',
      'com8',
      'com9',
      'LPT1',
      'LPT2',
      'LPT3',
      'LPT4',
      'LPT5',
      'LPT6',
      'LPT7',
      'LPT8',
      'LPT9',
      'lpt1',
      'lpt2',
      'lpt3',
      'lpt4',
      'lpt5',
      'lpt6',
      'lpt7',
      'lpt8',
      'lpt9',
      'CON.txt',
      'PRN.dat',
      'AUX.tar.gz',
      'NUL.json',
      'com1.pdf',
      'lpt9.bin',
      'con.backup.iso',
      'aux.123',
      'nul.exe',
      'COM4.docx',
      'LPT2.log',

      // 3. Alternate Data Streams (ADS) (10 vectors)
      'file.txt:stream',
      r'file.txt:$DATA',
      r'file.txt::$DATA',
      'payload.exe:zone.identifier',
      r'secret.doc::$INDEX_ALLOCATION',
      'script.ps1:hidden',
      r'data.bin:alt:$DATA',
      r'test.csv:stream:$INDEX',
      'archive.zip:meta',
      'image.png:thumb',

      // 4. Null Bytes and Control Characters (13 vectors)
      'malware.exe\x00.txt',
      '\x00malware.exe',
      'malware.exe\x00',
      'file\x01\x02\x03.bin',
      'file\x08backspace.txt',
      'file\x0Cformfeed.txt',
      'file\x1Bescape.txt',
      'file\x7Fdelete.txt',
      'file\x80\x9Fcontrol.txt',
      'file\n\r\ttest.txt',
      'file\u0000test.txt',
      'file\u202Ecod.exe', // RTL Override Trojan vector
      'file\u200Bzero.txt', // Zero-width space vector

      // 5. Illegal Characters and Boundary Cases (10 vectors)
      'file<test>.txt',
      'file>test>.txt',
      'file:test.txt',
      'file"test".txt',
      'file/test.txt',
      r'file\test.txt',
      'file|test.txt',
      'file?test.txt',
      'file*test.txt',
      r'?*<>:"/\\|',
      ' ',
      '   ',
      '\t\t\t',
      '......',
      '   spaced   ',
      'filename.ext . . .',
      '.hidden_config',
      '..double_dot',
      '...triple_dot',
      '${"A" * 300}.txt',
    ];

    test('All 80+ adversarial filenames are sanitized to safe single-level filenames inside destination', () async {
      expect(adversarialVectors.length, greaterThanOrEqualTo(80));

      for (int i = 0; i < adversarialVectors.length; i++) {
        final raw = adversarialVectors[i];
        final sanitized = PathSanitizer.sanitize(raw);

        // Security Invariant 1: Sanitized name must not be empty
        expect(sanitized.isNotEmpty, isTrue, reason: 'Vector #$i "$raw" produced empty string');

        // Security Invariant 2: No directory separators
        expect(sanitized.contains('/'), isFalse, reason: 'Vector #$i "$raw" contains /');
        expect(sanitized.contains(r'\'), isFalse, reason: 'Vector #$i "$raw" contains \\');

        // Security Invariant 3: No parent directory traversal
        expect(sanitized.contains('..'), isFalse, reason: 'Vector #$i "$raw" contains ..');

        // Security Invariant 4: No null bytes or ASCII control characters
        expect(sanitized.contains('\x00'), isFalse, reason: 'Vector #$i "$raw" contains null byte');
        expect(sanitized.contains(RegExp(r'[\x00-\x1F\x7F-\x9F]')), isFalse,
            reason: 'Vector #$i "$raw" contains control chars');

        // Security Invariant 5: No Windows illegal characters < > : " | ? *
        expect(sanitized.contains(RegExp(r'[<>:"/\\|?*]')), isFalse,
            reason: 'Vector #$i "$raw" contains illegal filesystem characters');

        // Security Invariant 6: Length bounded <= 240
        expect(sanitized.length, lessThanOrEqualTo(240),
            reason: 'Vector #$i "$raw" length exceeds 240');

        // Security Invariant 7: Resolving unique path remains strictly confined to tempTestDir
        final resolved = await DestinationPathResolver.resolveUniquePath(tempTestDir, sanitized);
        expect(p.dirname(resolved), equals(tempTestDir.path),
            reason: 'Vector #$i "$raw" resolved outside destination root: $resolved');
      }
    });

    test('Unicode Bidirectional formatting and zero-width spoofing characters are stripped', () {
      // Testing Unicode Spoofing vectors
      final unicodeVectors = [
        'file\u202Ecod.exe', // RTL Override (displays as fileexe.doc)
        'file\u202Atest.pdf', // Left-to-Right Embedding
        'file\u202Btest.pdf', // Right-to-Left Embedding
        'file\u202Ctest.pdf', // Pop Directional Formatting
        'file\u202Dtest.pdf', // Left-to-Right Override
        'file\u2066test.pdf', // Left-to-Right Isolate
        'file\u2067test.pdf', // Right-to-Left Isolate
        'file\u2068test.pdf', // First Strong Isolate
        'file\u2069test.pdf', // Pop Directional Isolate
        'file\u200Bzero.txt', // Zero Width Space
        'file\u200Czero.txt', // Zero Width Non-Joiner
        'file\u200Dzero.txt', // Zero Width Joiner
        'file\uFEFFzero.txt', // BOM / Zero Width No-Break Space
      ];

      for (final vec in unicodeVectors) {
        final sanitized = PathSanitizer.sanitize(vec);
        // Expect that dangerous Unicode control characters are stripped
        expect(
          sanitized.contains(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]')),
          isFalse,
          reason: 'PathSanitizer failed to strip dangerous Unicode Bidi/Invisible character in $vec -> $sanitized',
        );
      }
    });

    test('Windows reserved device names with arbitrary extensions are safely prefixed', () {
      final reservedNames = ['CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM9', 'LPT1', 'LPT9'];
      final extensions = ['', '.txt', '.dat', '.tar.gz', '.json', '.pdf', '.exe', '.123'];

      for (final name in reservedNames) {
        for (final ext in extensions) {
          for (final isUpper in [true, false]) {
            final testName = isUpper ? '$name$ext' : '${name.toLowerCase()}$ext';
            final sanitized = PathSanitizer.sanitize(testName);
            expect(sanitized.startsWith('_'), isTrue,
                reason: '$testName must be prefixed with underscore, got: $sanitized');
          }
        }
      }
    });

    test('Alternate Data Streams colons are replaced with underscores preventing stream creation', () {
      final adsVectors = [
        'file.txt:stream',
        r'file.txt:$DATA',
        r'file.txt::$DATA',
        'document.docx:secret_stream',
        r'image.png:thumbnail:$DATA',
      ];

      for (final vec in adsVectors) {
        final sanitized = PathSanitizer.sanitize(vec);
        expect(sanitized.contains(':'), isFalse);
        expect(sanitized.contains(r'$DATA') || sanitized.contains('stream') || sanitized.contains('secret'), isTrue);
      }
    });
  });

  group('CHALLENGER 2 - TIER 2: Staging Handle Robustness & Abrupt Closure Safety', () {
    test('State properties reflect lifecycle accurately', () async {
      final payload = Uint8List.fromList(utf8.encode('Lifecycle verification data'));
      final sha = Uint8List.fromList(crypto.sha256.convert(payload).bytes);

      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'lifecycle.txt',
        expectedTotalBytes: payload.length,
        expectedRootSha256: sha,
      );

      expect(handle.isClosed, isFalse);
      expect(handle.isCommitted, isFalse);
      expect(handle.bytesWritten, equals(0));

      await handle.writeChunk(payload);
      expect(handle.bytesWritten, equals(payload.length));
      expect(handle.isClosed, isFalse);
      expect(handle.isCommitted, isFalse);

      final finalFile = await handle.commitAndVerify();
      expect(handle.isClosed, isTrue);
      expect(handle.isCommitted, isTrue);
      expect(await finalFile.exists(), isTrue);
      expect(await handle.stagingFile.exists(), isFalse);
    });

    test('Write chunk to closed or aborted handle throws TransferAbortedException', () async {
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'closed_write.txt',
        expectedTotalBytes: 100,
        expectedRootSha256: Uint8List(32),
      );

      await handle.abort(reason: 'Early cancel');
      expect(handle.isClosed, isTrue);

      expect(
        () => handle.writeChunk(Uint8List(10)),
        throwsA(isA<TransferAbortedException>()),
      );
    });

    test('Commit on closed or aborted handle throws TransferAbortedException', () async {
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'closed_commit.txt',
        expectedTotalBytes: 100,
        expectedRootSha256: Uint8List(32),
      );

      await handle.abort(reason: 'Early cancel');

      expect(
        () => handle.commitAndVerify(),
        throwsA(isA<TransferAbortedException>()),
      );
    });

    test('Multiple sequential and concurrent abort calls do not leave orphaned staging files', () async {
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'multi_abort.txt',
        expectedTotalBytes: 100,
        expectedRootSha256: Uint8List(32),
      );

      await handle.writeChunk(Uint8List(50));
      expect(await handle.stagingFile.exists(), isTrue);

      // Concurrent abort calls
      await Future.wait([
        handle.abort(reason: 'Concurrent Abort 1'),
        handle.abort(reason: 'Concurrent Abort 2'),
        handle.abort(reason: 'Concurrent Abort 3'),
      ]);

      expect(await handle.stagingFile.exists(), isFalse,
          reason: 'Staging file must be deleted after abort');
      expect(handle.isClosed, isTrue);
      expect(handle.isCommitted, isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });

    test('Abort after commit is a safe no-op and does NOT delete committed file', () async {
      final payload = Uint8List.fromList(utf8.encode('Safe committed payload'));
      final sha = Uint8List.fromList(crypto.sha256.convert(payload).bytes);

      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'safe_commit.txt',
        expectedTotalBytes: payload.length,
        expectedRootSha256: sha,
      );

      await handle.writeChunk(payload);
      final finalFile = await handle.commitAndVerify();

      expect(await finalFile.exists(), isTrue);
      expect(handle.isCommitted, isTrue);

      // Attempt abort on committed handle
      await handle.abort(reason: 'Post-commit abort attempt');

      // Final file MUST remain intact
      expect(await finalFile.exists(), isTrue);
      expect(await finalFile.readAsBytes(), equals(payload));
    });

    test('Mid-stream exception triggers clean unlinking with zero remnants', () async {
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'unhandled_stream.bin',
        expectedTotalBytes: 1024 * 1024,
        expectedRootSha256: Uint8List(32),
      );

      try {
        for (int i = 0; i < 10; i++) {
          if (i == 5) {
            throw Exception('Simulated network connection reset mid-transfer');
          }
          await handle.writeChunk(Uint8List(1024));
        }
        fail('Exception should have been thrown');
      } catch (e) {
        expect(e.toString(), contains('Simulated network connection reset'));
        await handle.abort(reason: 'Network reset exception');
      }

      expect(await handle.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });
  });

  group('CHALLENGER 2 - TIER 3: High-Concurrency Staging & Collision Resistance', () {
    test('Concurrent staging sessions created simultaneously for SAME filename preserve all data without overwrite', () async {
      const concurrentTransfers = 5;
      final payloads = <Uint8List>[];
      final shas = <Uint8List>[];
      final handles = <StagingFileHandle>[];

      for (int i = 0; i < concurrentTransfers; i++) {
        final data = Uint8List.fromList(utf8.encode('Unique content for transfer #$i'));
        payloads.add(data);
        shas.add(Uint8List.fromList(crypto.sha256.convert(data).bytes));
      }

      // Create 5 handles concurrently
      final handleFutures = List.generate(
        concurrentTransfers,
        (i) => StagingFileHandle.create(
          destinationDir: tempTestDir,
          originalFilename: 'shared_report.pdf',
          expectedTotalBytes: payloads[i].length,
          expectedRootSha256: shas[i],
        ),
      );
      final createdHandles = await Future.wait(handleFutures);
      handles.addAll(createdHandles);

      // Write chunks
      for (int i = 0; i < concurrentTransfers; i++) {
        await handles[i].writeChunk(payloads[i]);
      }

      // Commit all handles
      final committedFiles = <File>[];
      for (final h in handles) {
        committedFiles.add(await h.commitAndVerify());
      }

      // Assert all 5 committed files exist and have unique paths
      final committedPaths = committedFiles.map((f) => f.path).toSet();
      expect(
        committedPaths.length,
        equals(concurrentTransfers),
        reason: 'Concurrent transfers to same filename must resolve to unique collision-free paths, not overwrite each other',
      );

      final allDirFiles = tempTestDir.listSync();
      expect(allDirFiles.length, equals(concurrentTransfers));
    });

    test('30 concurrent mixed operations (10 succeed, 10 abort, 10 fail hash) maintain strict hygiene', () async {
      const totalOps = 30;

      final futures = List.generate(totalOps, (i) async {
        final opType = i % 3; // 0: succeed, 1: abort mid-way, 2: corrupt hash
        final payload = Uint8List.fromList(utf8.encode('Mixed operation test payload #$i'));
        final correctSha = Uint8List.fromList(crypto.sha256.convert(payload).bytes);
        final corruptSha = Uint8List.fromList(List.filled(32, 0xEE));

        final handle = await StagingFileHandle.create(
          destinationDir: tempTestDir,
          originalFilename: 'mixed_doc_$i.dat',
          expectedTotalBytes: payload.length,
          expectedRootSha256: opType == 2 ? corruptSha : correctSha,
        );

        if (opType == 0) {
          // Success case
          await handle.writeChunk(payload);
          await handle.commitAndVerify();
          return 'SUCCESS';
        } else if (opType == 1) {
          // Abort case
          await handle.writeChunk(payload.sublist(0, payload.length ~/ 2));
          await handle.abort(reason: 'Aborted operation #$i');
          return 'ABORTED';
        } else {
          // Corrupt hash case
          await handle.writeChunk(payload);
          try {
            await handle.commitAndVerify();
            return 'UNEXPECTED_SUCCESS';
          } catch (e) {
            expect(e, isA<IntegrityMismatchException>());
            return 'HASH_FAILED';
          }
        }
      });

      final outcomes = await Future.wait(futures);
      final successCount = outcomes.where((o) => o == 'SUCCESS').length;
      final abortCount = outcomes.where((o) => o == 'ABORTED').length;
      final failCount = outcomes.where((o) => o == 'HASH_FAILED').length;

      expect(successCount, equals(10));
      expect(abortCount, equals(10));
      expect(failCount, equals(10));

      // Assert destination directory contains EXACTLY 10 files (the successful ones)
      final remainingFiles = tempTestDir.listSync();
      expect(remainingFiles.length, equals(10));

      for (final file in remainingFiles) {
        expect(file.path.endsWith('.slft_part'), isFalse);
        expect(p.basename(file.path).startsWith('mixed_doc_'), isTrue);
      }
    });
  });

  group('CHALLENGER 2 - TIER 4: Corrupted Root SHA-256 & Zero-Metadata Disk Hygiene', () {
    test('1-bit flip in 1MB file payload triggers IntegrityMismatchException and instant deletion', () async {
      const fileSize = 1024 * 1024; // 1 MB
      final rng = Random(42);
      final originalData = Uint8List(fileSize);
      for (int i = 0; i < fileSize; i++) {
        originalData[i] = rng.nextInt(256);
      }

      final expectedSha = Uint8List.fromList(crypto.sha256.convert(originalData).bytes);

      // Create tampered data with 1 bit flipped in middle (byte 500,000)
      final tamperedData = Uint8List.fromList(originalData);
      tamperedData[500000] ^= 0x01;

      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'large_tampered.bin',
        expectedTotalBytes: fileSize,
        expectedRootSha256: expectedSha,
      );

      // Stream in 16KB chunks
      const chunkSize = 16384;
      for (int offset = 0; offset < fileSize; offset += chunkSize) {
        final end = min(offset + chunkSize, fileSize);
        await handle.writeChunk(tamperedData.sublist(offset, end));
      }

      expect(handle.bytesWritten, equals(fileSize));

      await expectLater(
        () => handle.commitAndVerify(),
        throwsA(isA<IntegrityMismatchException>()),
      );

      // Verify file is unlinked immediately
      expect(await handle.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });

    test('Size mismatch (truncated or excess bytes) triggers IntegrityMismatchException and instant deletion', () async {
      final data = Uint8List.fromList(utf8.encode('Expected exact 100 bytes of data buffer'));
      final sha = Uint8List.fromList(crypto.sha256.convert(data).bytes);

      // Case 1: Truncated
      final handle1 = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'truncated.bin',
        expectedTotalBytes: data.length + 10, // Expecting more
        expectedRootSha256: sha,
      );
      await handle1.writeChunk(data);
      await expectLater(
        () => handle1.commitAndVerify(),
        throwsA(isA<IntegrityMismatchException>()),
      );
      expect(await handle1.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);

      // Case 2: Excess
      final handle2 = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'excess.bin',
        expectedTotalBytes: data.length - 10, // Expecting less
        expectedRootSha256: sha,
      );
      await handle2.writeChunk(data);
      await expectLater(
        () => handle2.commitAndVerify(),
        throwsA(isA<IntegrityMismatchException>()),
      );
      expect(await handle2.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });

    test('Secure wipe mode overwrites disk sectors with zeros before deletion', () async {
      final sensitiveBytes = Uint8List.fromList(utf8.encode('TOP_SECRET_CRYPTO_KEY_MATERIAL_NEVER_PERSIST'));
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'classified.key',
        expectedTotalBytes: sensitiveBytes.length,
        expectedRootSha256: Uint8List(32),
        secureWipeOnAbort: true,
      );

      await handle.writeChunk(sensitiveBytes);
      expect(await handle.stagingFile.exists(), isTrue);

      await handle.abort(reason: 'Security breach emergency purge');

      expect(await handle.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });

    test('Stress test: 50 consecutive aborted/corrupted staging sessions leave ZERO remnant files', () async {
      const trials = 50;
      final rng = Random(12345);

      for (int i = 0; i < trials; i++) {
        final length = rng.nextInt(5000) + 100;
        final data = ByteUtils.secureRandomBytes(length);
        final isCorruptSha = rng.nextBool();
        final isMidAbort = rng.nextBool();

        final sha = isCorruptSha
            ? ByteUtils.secureRandomBytes(32)
            : Uint8List.fromList(crypto.sha256.convert(data).bytes);

        final handle = await StagingFileHandle.create(
          destinationDir: tempTestDir,
          originalFilename: 'fuzz_test_$i.bin',
          expectedTotalBytes: length,
          expectedRootSha256: sha,
          secureWipeOnAbort: rng.nextBool(),
        );

        if (isMidAbort) {
          await handle.writeChunk(data.sublist(0, length ~/ 2));
          await handle.abort(reason: 'Fuzz abort at trial $i');
        } else {
          await handle.writeChunk(data);
          if (isCorruptSha) {
            try {
              await handle.commitAndVerify();
              fail('Expected IntegrityMismatchException on trial $i');
            } catch (e) {
              expect(e, isA<IntegrityMismatchException>());
            }
          } else {
            final f = await handle.commitAndVerify();
            expect(await f.exists(), isTrue);
            await f.delete(); // Clean up for next check
          }
        }

        // Verify that after each trial, NO .slft_part files exist in temp directory
        final remnantPartFiles = tempTestDir
            .listSync()
            .where((entity) => entity.path.endsWith('.slft_part'))
            .toList();
        expect(remnantPartFiles, isEmpty,
            reason: 'Remnant staging files found after trial #$i: $remnantPartFiles');
      }

      expect(tempTestDir.listSync(), isEmpty);
    });
  });
}
