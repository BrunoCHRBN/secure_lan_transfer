import 'package:secure_lan_transfer/core/models/transfer_progress.dart';
import 'package:secure_lan_transfer/core/protocol/session_state.dart';
import 'package:secure_lan_transfer/core/transfer/speed_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('SessionStateMachine Transition Tests', () {
    test('Follows normal lifecycle: idle -> connecting -> handshaking -> transferring -> verifying -> completed -> idle', () {
      final fsm = SessionStateMachine();
      expect(fsm.currentState.state, equals(TransferState.idle));

      fsm.transitionTo(TransferState.connecting);
      expect(fsm.currentState.state, equals(TransferState.connecting));

      fsm.transitionTo(TransferState.handshaking);
      expect(fsm.currentState.state, equals(TransferState.handshaking));

      fsm.transitionTo(TransferState.transferring, fileName: 'test.bin', totalBytes: 1000);
      expect(fsm.currentState.state, equals(TransferState.transferring));
      expect(fsm.currentState.fileName, equals('test.bin'));

      fsm.transitionTo(TransferState.paused);
      expect(fsm.currentState.state, equals(TransferState.paused));

      fsm.transitionTo(TransferState.transferring);
      expect(fsm.currentState.state, equals(TransferState.transferring));

      fsm.transitionTo(TransferState.verifying);
      expect(fsm.currentState.state, equals(TransferState.verifying));

      fsm.transitionTo(TransferState.completed, committedFilePath: '/path/test.bin');
      expect(fsm.currentState.state, equals(TransferState.completed));
      expect(fsm.currentState.committedFilePath, equals('/path/test.bin'));

      fsm.reset();
      expect(fsm.currentState.state, equals(TransferState.idle));
      fsm.dispose();
    });

    test('Disallowed transitions throw StateError', () {
      final fsm = SessionStateMachine();
      expect(fsm.currentState.state, equals(TransferState.idle));

      // Cannot jump from idle to completed or verifying
      expect(() => fsm.transitionTo(TransferState.completed), throwsStateError);
      expect(() => fsm.transitionTo(TransferState.verifying), throwsStateError);
      expect(() => fsm.transitionTo(TransferState.paused), throwsStateError);

      fsm.dispose();
    });

    test('fail() transitions to error state with typed SessionError', () {
      final fsm = SessionStateMachine();
      fsm.transitionTo(TransferState.connecting);

      fsm.fail(SessionErrorCode.connectionRefused, 'Connection refused by peer');
      expect(fsm.currentState.state, equals(TransferState.error));
      expect(fsm.currentState.hasError, isTrue);
      expect(fsm.currentState.error?.code, equals(SessionErrorCode.connectionRefused));
      expect(fsm.currentState.error?.message, equals('Connection refused by peer'));

      fsm.dispose();
    });

    test('cancel() transitions to cancelled state with reason', () {
      final fsm = SessionStateMachine();
      fsm.transitionTo(TransferState.connecting);
      fsm.transitionTo(TransferState.handshaking);

      fsm.cancel('User pressed stop button');
      expect(fsm.currentState.state, equals(TransferState.cancelled));
      expect(fsm.currentState.error?.code, equals(SessionErrorCode.userCancelled));
      expect(fsm.currentState.error?.message, equals('User pressed stop button'));

      fsm.dispose();
    });

    test('reset() cleanly resets from error, cancelled, and completed terminal states', () {
      // 1. From completed
      final fsm1 = SessionStateMachine(role: TransferRole.initiator);
      fsm1.transitionTo(TransferState.connecting);
      fsm1.transitionTo(TransferState.handshaking);
      fsm1.transitionTo(TransferState.transferring);
      fsm1.transitionTo(TransferState.completed);
      expect(fsm1.currentState.isTerminal, isTrue);
      expect(fsm1.currentState.isActive, isFalse);
      fsm1.reset(role: TransferRole.receiver);
      expect(fsm1.currentState.state, equals(TransferState.idle));
      expect(fsm1.currentState.role, equals(TransferRole.receiver));
      fsm1.dispose();

      // 2. From error
      final fsm2 = SessionStateMachine();
      fsm2.fail(SessionErrorCode.connectionTimeout, 'Timed out');
      expect(fsm2.currentState.isTerminal, isTrue);
      expect(fsm2.currentState.hasError, isTrue);
      fsm2.reset();
      expect(fsm2.currentState.state, equals(TransferState.idle));
      expect(fsm2.currentState.hasError, isFalse);
      fsm2.dispose();

      // 3. From cancelled
      final fsm3 = SessionStateMachine();
      fsm3.transitionTo(TransferState.connecting);
      fsm3.cancel('Cancelled');
      expect(fsm3.currentState.isTerminal, isTrue);
      fsm3.reset();
      expect(fsm3.currentState.state, equals(TransferState.idle));
      fsm3.dispose();
    });

    test('isActive, isBusy, isAvailable, isTerminal properties are consistent across all states', () {
      final fsm = SessionStateMachine();

      // idle
      expect(fsm.currentState.state, equals(TransferState.idle));
      expect(fsm.currentState.isActive, isFalse);
      expect(fsm.currentState.isBusy, isFalse);
      expect(fsm.currentState.isAvailable, isTrue);
      expect(fsm.currentState.isTerminal, isFalse);

      // connecting
      fsm.transitionTo(TransferState.connecting);
      expect(fsm.currentState.isActive, isTrue);
      expect(fsm.currentState.isBusy, isTrue);
      expect(fsm.currentState.isAvailable, isFalse);
      expect(fsm.currentState.isTerminal, isFalse);

      // handshaking
      fsm.transitionTo(TransferState.handshaking);
      expect(fsm.currentState.isActive, isTrue);
      expect(fsm.currentState.isBusy, isTrue);
      expect(fsm.currentState.isAvailable, isFalse);
      expect(fsm.currentState.isTerminal, isFalse);

      // transferring
      fsm.transitionTo(TransferState.transferring);
      expect(fsm.currentState.isActive, isTrue);
      expect(fsm.currentState.isBusy, isTrue);
      expect(fsm.currentState.isAvailable, isFalse);
      expect(fsm.currentState.isTerminal, isFalse);

      // paused
      fsm.transitionTo(TransferState.paused);
      expect(fsm.currentState.isActive, isTrue);
      expect(fsm.currentState.isBusy, isTrue);
      expect(fsm.currentState.isAvailable, isFalse);
      expect(fsm.currentState.isTerminal, isFalse);

      // verifying
      fsm.transitionTo(TransferState.transferring);
      fsm.transitionTo(TransferState.verifying);
      expect(fsm.currentState.isActive, isTrue);
      expect(fsm.currentState.isBusy, isTrue);
      expect(fsm.currentState.isAvailable, isFalse);
      expect(fsm.currentState.isTerminal, isFalse);

      // completed
      fsm.transitionTo(TransferState.completed);
      expect(fsm.currentState.isActive, isFalse);
      expect(fsm.currentState.isBusy, isFalse);
      expect(fsm.currentState.isAvailable, isTrue);
      expect(fsm.currentState.isTerminal, isTrue);

      fsm.dispose();
    });
  });

  group('SpeedTracker & TransferProgress Tests', () {
    test('Calculates fraction and formats bytes/speed/ETA cleanly', () {
      final tracker = SpeedTracker(totalBytes: 1000000);
      tracker.start();

      final p1 = tracker.recordProgress(500000);
      expect(p1.fraction, equals(0.5));
      expect(p1.percentageFormatted, equals('50.0%'));
      expect(p1.totalFormatted, isNotEmpty);
      expect(p1.transferredFormatted, isNotEmpty);
      expect(p1.speedFormatted, isNotEmpty);
      expect(p1.state, equals(TransferState.transferring));
    });

    test('Formatters handle zero, KB, MB, GB ranges accurately', () {
      expect(TransferProgress.formatBytes(0), equals('0 B'));
      expect(TransferProgress.formatBytes(500), equals('500 B'));
      expect(TransferProgress.formatBytes(2048), equals('2.0 KB'));
      expect(TransferProgress.formatBytes(5242880), equals('5.0 MB'));
      expect(TransferProgress.formatBytes(2147483648), equals('2.00 GB'));

      expect(TransferProgress.formatSpeed(0), equals('0 B/s'));
      expect(TransferProgress.formatSpeed(10485760), equals('10.0 MB/s'));

      expect(TransferProgress.formatDuration(null), equals('Calculating...'));
      expect(TransferProgress.formatDuration(Duration.zero), equals('00:00'));
      expect(TransferProgress.formatDuration(const Duration(seconds: 45)), equals('00:45'));
      expect(TransferProgress.formatDuration(const Duration(minutes: 5, seconds: 12)), equals('05:12'));
      expect(TransferProgress.formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), equals('01:02:03'));
      expect(TransferProgress.formatDuration(null, isStalled: true), equals('Stalled'));
    });
  });
}
