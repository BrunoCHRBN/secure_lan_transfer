import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:secure_lan_transfer/core/crypto/zero_metadata_staging.dart';

void main() {
  late Directory tempTestDir;

  setUp(() async {
    tempTestDir = await Directory.systemTemp.createTemp('slft_staging_test_');
  });

  tearDown(() async {
    if (await tempTestDir.exists()) {
      try {
        await tempTestDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('1. Path Traversal & Filename Sanitization Tests', () {
    test('Strips directory traversal tokens (../ and ..\\)', () {
      expect(PathSanitizer.sanitize('../../etc/passwd'), equals('passwd'));
      expect(PathSanitizer.sanitize(r'..\..\Windows\System32\cmd.exe'), equals('cmd.exe'));
      expect(PathSanitizer.sanitize('../../../secret.dat'), equals('secret.dat'));
    });

    test('Strips null bytes and ASCII control characters', () {
      expect(PathSanitizer.sanitize('malware.exe\x00.pdf'), equals('malware.exe.pdf'));
      expect(PathSanitizer.sanitize('evil\n\r\tscript.sh'), equals('evilscript.sh'));
    });

    test('Replaces illegal filesystem characters with underscores', () {
      expect(PathSanitizer.sanitize('report<2026>:draft"|?*.pdf'), equals('report_2026__draft____.pdf'));
    });

    test('Protects Windows reserved device names', () {
      expect(PathSanitizer.sanitize('CON.txt'), equals('_CON.txt'));
      expect(PathSanitizer.sanitize('aux'), equals('_aux'));
      expect(PathSanitizer.sanitize('NUL.json'), equals('_NUL.json'));
      expect(PathSanitizer.sanitize('COM1.dat'), equals('_COM1.dat'));
      expect(PathSanitizer.sanitize('LPT9.png'), equals('_LPT9.png'));
    });

    test('Trims trailing dots and spaces', () {
      expect(PathSanitizer.sanitize('document.pdf . . .'), equals('document.pdf'));
      expect(PathSanitizer.sanitize('  space_padded.jpg  '), equals('space_padded.jpg'));
    });

    test('Prefixes hidden dot-files', () {
      expect(PathSanitizer.sanitize('.bashrc'), equals('_.bashrc'));
      expect(PathSanitizer.sanitize('.env'), equals('_.env'));
    });

    test('Truncates overly long filenames while preserving extension', () {
      final longName = '${'A' * 300}.tar.gz';
      final sanitized = PathSanitizer.sanitize(longName, maxLength: 100);
      expect(sanitized.length, lessThanOrEqualTo(100));
      expect(sanitized.endsWith('.gz'), isTrue);
    });

    test('Fallback for degenerate inputs', () {
      expect(PathSanitizer.sanitize(''), equals('unnamed_file'));
      expect(PathSanitizer.sanitize('   '), equals('unnamed_file'));
      expect(PathSanitizer.sanitize('...'), equals('unnamed_file'));
    });

    test('Strips Unicode Trojan Bidi overrides and zero-width invisible characters', () {
      expect(PathSanitizer.sanitize('file\u202Ecod.exe'), equals('filecod.exe'));
      expect(PathSanitizer.sanitize('doc\u202Atest.pdf'), equals('doctest.pdf'));
      expect(PathSanitizer.sanitize('report\u2067secret.docx'), equals('reportsecret.docx'));
      expect(PathSanitizer.sanitize('hidden\u200Bspace.txt'), equals('hiddenspace.txt'));
      expect(PathSanitizer.sanitize('bom\uFEFFfile.dat'), equals('bomfile.dat'));
      expect(PathSanitizer.sanitize('\u202E\u200B\uFEFF'), equals('unnamed_file'));
    });
  });

  group('2. Atomic Staging & Commit Lifecycle Tests', () {
    test('Successful write and commit creates destination file and unlinks .part', () async {
      final fileData = Uint8List.fromList(utf8.encode('Hello Secure LAN Transfer World!'));
      final expectedSha = Uint8List.fromList(crypto.sha256.convert(fileData).bytes);

      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'hello.txt',
        expectedTotalBytes: fileData.length,
        expectedRootSha256: expectedSha,
      );

      expect(await handle.stagingFile.exists(), isTrue);
      expect(handle.stagingFile.path.endsWith('.slft_part'), isTrue);

      await handle.writeChunk(fileData);
      final finalFile = await handle.commitAndVerify();

      expect(await finalFile.exists(), isTrue);
      expect(p.basename(finalFile.path), equals('hello.txt'));
      expect(await handle.stagingFile.exists(), isFalse); // Staging file renamed
      expect(await finalFile.readAsBytes(), equals(fileData));
    });

    test('Destination file collision appends numeric suffix', () async {
      // Pre-create existing file
      final existingFile = File(p.join(tempTestDir.path, 'data.csv'));
      await existingFile.writeAsString('initial,data');

      final newPayload = Uint8List.fromList(utf8.encode('new,data,row'));
      final expectedSha = Uint8List.fromList(crypto.sha256.convert(newPayload).bytes);

      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'data.csv',
        expectedTotalBytes: newPayload.length,
        expectedRootSha256: expectedSha,
      );

      await handle.writeChunk(newPayload);
      final finalFile = await handle.commitAndVerify();

      expect(p.basename(finalFile.path), equals('data (1).csv'));
      expect(await existingFile.readAsString(), equals('initial,data')); // Original intact
    });

    test('Concurrent staging creations reserve non-colliding tentative paths', () async {
      final h1 = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'concurrent.txt',
        expectedTotalBytes: 10,
        expectedRootSha256: Uint8List(32),
      );
      final h2 = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'concurrent.txt',
        expectedTotalBytes: 10,
        expectedRootSha256: Uint8List(32),
      );

      expect(p.basename(h1.resolvedFinalPath), equals('concurrent.txt'));
      expect(p.basename(h2.resolvedFinalPath), equals('concurrent (1).txt'));

      await h1.abort();
      await h2.abort();
    });
  });

  group('3. Abort & SHA-256 Mismatch Immediate Unlinking Tests', () {
    test('SHA-256 digest mismatch triggers immediate deletion of staging file', () async {
      final actualData = Uint8List.fromList(utf8.encode('Actual received bytes'));
      final fakeSha = Uint8List.fromList(List.filled(32, 0xFF)); // Corrupted hash

      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'corrupt.bin',
        expectedTotalBytes: actualData.length,
        expectedRootSha256: fakeSha,
      );

      await handle.writeChunk(actualData);

      await expectLater(
        () => handle.commitAndVerify(),
        throwsA(isA<IntegrityMismatchException>()),
      );

      // Verify zero remnant files remain in directory
      expect(await handle.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });

    test('Mid-transfer abort call immediately removes staging file', () async {
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'aborted.iso',
        expectedTotalBytes: 10000,
        expectedRootSha256: Uint8List(32),
      );

      await handle.writeChunk(Uint8List(5000));
      expect(await handle.stagingFile.exists(), isTrue);

      await handle.abort(reason: 'User cancelled transfer');

      expect(await handle.stagingFile.exists(), isFalse);
      expect(await tempTestDir.list().isEmpty, isTrue);
    });

    test('Multiple concurrent abort calls safely synchronize without errors', () async {
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'concurrent_abort.txt',
        expectedTotalBytes: 100,
        expectedRootSha256: Uint8List(32),
      );

      await handle.writeChunk(Uint8List(50));
      expect(await handle.stagingFile.exists(), isTrue);

      await Future.wait([
        handle.abort(reason: 'Abort 1'),
        handle.abort(reason: 'Abort 2'),
        handle.abort(reason: 'Abort 3'),
      ]);

      expect(await handle.stagingFile.exists(), isFalse);
      expect(handle.isClosed, isTrue);
    });

    test('Secure wipe mode overwrites file with zeros before deletion', () async {
      final sensitiveData = Uint8List.fromList(utf8.encode('Very sensitive in-flight data'));
      final handle = await StagingFileHandle.create(
        destinationDir: tempTestDir,
        originalFilename: 'sensitive.txt',
        expectedTotalBytes: sensitiveData.length,
        expectedRootSha256: Uint8List(32),
        secureWipeOnAbort: true,
      );

      await handle.writeChunk(sensitiveData);
      await handle.abort(reason: 'Emergency wipe');

      expect(await handle.stagingFile.exists(), isFalse);
    });
  });
}
