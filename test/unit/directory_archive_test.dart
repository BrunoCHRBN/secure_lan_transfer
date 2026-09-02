import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:secure_lan_transfer/core/transfer/directory_archive.dart';
import 'package:test/test.dart';

void main() {
  group('DirectoryArchive Unit & Security Tests', () {
    late Directory tempDir;
    late Directory sourceFolder;
    late Directory extractFolder;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('slft_dir_test_');
      sourceFolder = Directory(p.join(tempDir.path, 'my_project'))..createSync();
      extractFolder = Directory(p.join(tempDir.path, 'extracted'))..createSync();

      // Create test directory structure with nested files
      File(p.join(sourceFolder.path, 'file1.txt')).writeAsStringSync('Hello World 1');
      File(p.join(sourceFolder.path, 'file2.json')).writeAsStringSync('{"key": "value"}');

      final subDir = Directory(p.join(sourceFolder.path, 'nested', 'sub'))..createSync(recursive: true);
      File(p.join(subDir.path, 'data.bin')).writeAsBytesSync(List.generate(1024, (i) => i % 256));
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('packDirectory creates a valid ZIP file containing all nested files', () async {
      final List<String> packedFiles = [];
      final zipFile = await DirectoryArchive.packDirectory(
        sourceFolder,
        onProgress: (name, count) {
          packedFiles.add(name);
        },
      );

      expect(zipFile.existsSync(), isTrue);
      expect(zipFile.lengthSync(), greaterThan(0));
      expect(packedFiles.length, equals(3));
      expect(packedFiles, contains('nested/sub/data.bin'));

      // Clean up zip
      try {
        zipFile.deleteSync();
      } catch (_) {}
    });

    test('unpackDirectory accurately restores original files and content hashes', () async {
      final zipFile = await DirectoryArchive.packDirectory(sourceFolder);

      final extractedDir = await DirectoryArchive.unpackDirectory(zipFile, extractFolder);
      expect(extractedDir.existsSync(), isTrue);

      final f1 = File(p.join(extractFolder.path, 'file1.txt'));
      final f2 = File(p.join(extractFolder.path, 'file2.json'));
      final f3 = File(p.join(extractFolder.path, 'nested', 'sub', 'data.bin'));

      expect(f1.existsSync(), isTrue);
      expect(f1.readAsStringSync(), equals('Hello World 1'));

      expect(f2.existsSync(), isTrue);
      expect(f2.readAsStringSync(), equals('{"key": "value"}'));

      expect(f3.existsSync(), isTrue);
      final originalF3 = File(p.join(sourceFolder.path, 'nested', 'sub', 'data.bin'));
      final originalHash = crypto.sha256.convert(originalF3.readAsBytesSync()).toString();
      final extractedHash = crypto.sha256.convert(f3.readAsBytesSync()).toString();
      expect(extractedHash, equals(originalHash));

      try {
        zipFile.deleteSync();
      } catch (_) {}
    });

    test('packDirectory fails gracefully for non-existent directories', () async {
      final nonExistent = Directory(p.join(tempDir.path, 'ghost_dir'));
      expect(
        () => DirectoryArchive.packDirectory(nonExistent),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('unpackDirectory rejects Zip Slip directory traversal attacks', () async {
      // Craft an adversarial archive containing path traversal "../evil.txt"
      final maliciousArchive = Archive();
      maliciousArchive.addFile(ArchiveFile('../evil.txt', 12, utf8.encode('malicious data')));
      final maliciousZipPath = p.join(tempDir.path, 'malicious.zip');
      final encoder = ZipEncoder();
      final zipBytes = encoder.encode(maliciousArchive);
      File(maliciousZipPath).writeAsBytesSync(zipBytes);

      expect(
        () => DirectoryArchive.unpackDirectory(File(maliciousZipPath), extractFolder),
        throwsA(isA<SecurityException>()),
      );
    });
  });
}
