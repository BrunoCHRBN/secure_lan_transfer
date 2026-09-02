import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Handles streaming and disk-bounded compression/decompression of folders.
class DirectoryArchive {
  /// Compresses a directory into a temporary ZIP file using streaming disk writes.
  /// Does not load the entire archive into RAM, respecting memory bounds.
  static Future<File> packDirectory(
    Directory directory, {
    String? customZipPath,
    void Function(String currentFile, int count)? onProgress,
  }) async {
    if (!directory.existsSync()) {
      throw FileSystemException('Directory does not exist', directory.path);
    }

    final dirName = p.basename(directory.path.replaceAll(RegExp(r'[\\/]+$'), ''));
    final safeName = dirName.isEmpty ? 'folder' : dirName;
    final zipPath = customZipPath ??
        p.join(
          Directory.systemTemp.path,
          'slft_${safeName}_${DateTime.now().millisecondsSinceEpoch}.zip',
        );

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    int count = 0;
    final entities = directory.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (entity is File) {
        // Zip spec mandates standard forward slashes for internal paths
        final relPath = p.relative(entity.path, from: directory.path).replaceAll('\\', '/');
        await encoder.addFile(entity, relPath);
        count++;
        onProgress?.call(relPath, count);
      }
    }

    await encoder.close();
    return File(zipPath);
  }

  /// Safely extracts a ZIP archive into a target directory.
  /// Includes Zip-Slip vulnerability protection against path traversal.
  static Future<Directory> unpackDirectory(
    File zipFile,
    Directory destinationDir, {
    void Function(String extractedFile)? onProgress,
  }) async {
    if (!zipFile.existsSync()) {
      throw FileSystemException('Archive file does not exist', zipFile.path);
    }

    if (!destinationDir.existsSync()) {
      destinationDir.createSync(recursive: true);
    }

    final baseDir = destinationDir.absolute.path;
    final inputStream = InputFileStream(zipFile.path);
    final archive = ZipDecoder().decodeStream(inputStream);

    for (final file in archive.files) {
      final safeName = file.name.replaceAll('\\', '/');
      final outPath = p.normalize(p.join(baseDir, safeName));

      // Zip Slip Protection: Ensure target path remains inside baseDir
      if (!p.isWithin(baseDir, outPath) && outPath != baseDir) {
        throw SecurityException(
          'Zip Slip security violation: archive attempted path traversal ($safeName)',
        );
      }

      if (file.isFile) {
        final parentDir = Directory(p.dirname(outPath));
        if (!parentDir.existsSync()) {
          parentDir.createSync(recursive: true);
        }
        final outputStream = OutputFileStream(outPath);
        file.writeContent(outputStream);
        await outputStream.close();
        onProgress?.call(safeName);
      } else {
        Directory(outPath).createSync(recursive: true);
      }
    }

    await inputStream.close();
    return destinationDir;
  }
}

class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
