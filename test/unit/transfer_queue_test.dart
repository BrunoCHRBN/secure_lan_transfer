import 'dart:io';
import 'package:secure_lan_transfer/core/models/transfer_progress.dart';
import 'package:secure_lan_transfer/core/protocol/session_state.dart';
import 'package:secure_lan_transfer/core/transfer/transfer_queue.dart';
import 'package:secure_lan_transfer/core/transfer/transfer_sender.dart';
import 'package:test/test.dart';

void main() {
  group('TransferQueue Unit Tests', () {
    late Directory tempDir;
    late File fileA;
    late File fileB;
    late File fileC;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('queue_test_');
      fileA = File('${tempDir.path}/a.txt');
      fileB = File('${tempDir.path}/b.png');
      fileC = File('${tempDir.path}/c.zip');

      await fileA.writeAsBytes(List.filled(1024, 0x41)); // 1 KB
      await fileB.writeAsBytes(List.filled(2048, 0x42)); // 2 KB
      await fileC.writeAsBytes(List.filled(4096, 0x43)); // 4 KB
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('Initializes empty with zero metrics', () {
      final queue = TransferQueue();
      expect(queue.totalFiles, equals(0));
      expect(queue.totalBytes, equals(0));
      expect(queue.isComplete, isFalse);
      expect(queue.isCancelled, isFalse);
      expect(queue.jobs, isEmpty);
      queue.dispose();
    });

    test('addFiles adds valid existing files to queue', () {
      final queue = TransferQueue();
      queue.addFiles([fileA, fileB, fileC]);

      expect(queue.totalFiles, equals(3));
      expect(queue.totalBytes, equals(1024 + 2048 + 4096));
      expect(queue.jobs[0].fileName, equals('a.txt'));
      expect(queue.jobs[1].fileName, equals('b.png'));
      expect(queue.jobs[2].fileName, equals('c.zip'));
      expect(queue.jobs.every((j) => j.isPending), isTrue);

      queue.dispose();
    });

    test('removeJob removes pending file by ID', () {
      final queue = TransferQueue();
      queue.addFiles([fileA, fileB]);

      final firstId = queue.jobs.first.id;
      final removed = queue.removeJob(firstId);

      expect(removed, isTrue);
      expect(queue.totalFiles, equals(1));
      expect(queue.jobs.first.fileName, equals('b.png'));

      queue.dispose();
    });

    test('cancel marks pending jobs as cancelled and sets isCancelled', () {
      final queue = TransferQueue();
      queue.addFiles([fileA, fileB]);

      queue.cancel();
      expect(queue.isCancelled, isTrue);
      expect(queue.jobs.every((j) => j.isCancelled), isTrue);

      queue.dispose();
    });

    test('reset clears jobs and restores pristine state', () {
      final queue = TransferQueue();
      queue.addFiles([fileA]);
      queue.cancel();

      queue.reset();
      expect(queue.totalFiles, equals(0));
      expect(queue.totalBytes, equals(0));
      expect(queue.isCancelled, isFalse);
      expect(queue.jobs, isEmpty);

      queue.dispose();
    });

    test('QueueProgress calculates overall fraction correctly', () {
      const qp = QueueProgress(
        totalFiles: 3,
        completedFiles: 1,
        failedFiles: 0,
        currentFileIndex: 1,
        currentFileName: 'b.png',
        totalBytes: 7168,
        transferredBytes: 3584,
        speedBytesPerSec: 1024 * 1024,
        elapsed: Duration(seconds: 2),
      );

      expect(qp.overallFraction, closeTo(0.5, 0.001));
      expect(qp.isComplete, isFalse);
    });
  });
}
