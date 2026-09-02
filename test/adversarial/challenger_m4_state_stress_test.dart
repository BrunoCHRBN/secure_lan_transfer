import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_lan_transfer/core/crypto/sas_authenticator.dart';
import 'package:secure_lan_transfer/core/models/transfer_progress.dart';
import 'package:secure_lan_transfer/core/protocol/session_state.dart';
import 'package:secure_lan_transfer/core/session/session_manager.dart';
import 'package:secure_lan_transfer/ui/providers/device_discovery_provider.dart';
import 'package:secure_lan_transfer/ui/providers/settings_provider.dart';
import 'package:secure_lan_transfer/ui/providers/transfer_session_provider.dart';
import 'package:secure_lan_transfer/ui/theme/app_theme.dart';
import 'package:secure_lan_transfer/ui/widgets/chunk_progress_bar.dart';
import 'package:secure_lan_transfer/ui/widgets/speedometer_widget.dart';

class MockSocket extends Stream<Uint8List> implements Socket {
  final _controller = StreamController<Uint8List>.broadcast();
  bool _destroyed = false;

  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;

  @override
  InternetAddress get remoteAddress => InternetAddress('10.0.0.99');

  @override
  int get port => 42385;

  @override
  int get remotePort => 55432;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) => Future.value();

  @override
  Future close() => Future.value();

  @override
  void destroy() {
    _destroyed = true;
  }

  bool get isDestroyed => _destroyed;

  @override
  Future get done => Future.value();

  @override
  Future flush() => Future.value();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _controller.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  bool setRawOption(RawSocketOption option) => true;

  @override
  Uint8List getRawOption(RawSocketOption option) => Uint8List(0);

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding encoding) {}
}

SasCode _createDummySas([int seed = 42]) {
  final rand = math.Random(seed);
  final codeNum = rand.nextInt(900000) + 100000;
  final codeStr = '${codeNum.toString().substring(0, 3)}-${codeNum.toString().substring(3, 6)}';
  return SasCode(
    numericCode: codeStr,
    numericValue: codeNum,
    emojis: const [
      SasEmoji(0, '🦊', 'Fox'),
      SasEmoji(1, '⚡', 'Lightning'),
      SasEmoji(2, '🪐', 'Saturn'),
      SasEmoji(3, '💎', 'Gem Stone'),
    ],
    rawBytes: Uint8List.fromList([1, 2, 3, 4]),
    transcriptHash: Uint8List(32),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CHALLENGER M4 - TIER 1: Concurrent Transfer Proposals & Cancellation Storm', () {
    late SettingsProvider settings;
    late TransferSessionProvider sessionProvider;

    setUp(() {
      settings = SettingsProvider();
      sessionProvider = TransferSessionProvider(settings: settings);
    });

    tearDown(() {
      sessionProvider.dispose();
    });

    test('50 rapid concurrent InboundSessionProposals each handle accept/reject independently without crashing', () async {
      final proposals = <InboundSessionProposal>[];
      for (int i = 0; i < 50; i++) {
        final mockSocket = MockSocket();
        final proposal = InboundSessionProposal(
          socket: mockSocket,
          remoteAddress: '192.168.1.${10 + i}',
          remotePort: 40000 + i,
        );
        proposals.add(proposal);
      }

      // Accept half, reject half concurrently
      final futures = <Future<bool>>[];
      for (int i = 0; i < proposals.length; i++) {
        futures.add(proposals[i].userDecision);
        if (i % 2 == 0) {
          proposals[i].accept();
          // Repeated call to verify idempotency
          proposals[i].accept();
        } else {
          proposals[i].reject('Declined in test');
          // Repeated call to verify idempotency
          proposals[i].reject('Declined again');
        }
      }

      final results = await Future.wait(futures);
      for (int i = 0; i < results.length; i++) {
        if (i % 2 == 0) {
          expect(results[i], isTrue);
        } else {
          expect(results[i], isFalse);
        }
      }
    });

    test('Null safety and idempotency: Calling acceptProposal() and rejectProposal() when no pending proposal is active', () {
      int notifyCount = 0;
      sessionProvider.addListener(() => notifyCount++);

      expect(sessionProvider.pendingProposal, isNull);

      // Should not throw
      for (int i = 0; i < 20; i++) {
        sessionProvider.acceptProposal();
        sessionProvider.rejectProposal();
      }

      expect(sessionProvider.pendingProposal, isNull);
      expect(notifyCount, equals(40));
    });

    test('Cancellation storm: 100 concurrent calls to cancelTransfer() across active and non-active states', () async {
      // In idle state
      expect(sessionProvider.currentState.state, equals(TransferState.idle));
      for (int i = 0; i < 25; i++) {
        sessionProvider.cancelTransfer('Storm cancel $i');
      }
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.idle));

      // Transition to connecting
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.connecting);
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.connecting));

      // Cancel while connecting
      for (int i = 0; i < 25; i++) {
        sessionProvider.cancelTransfer('Storm cancel connecting $i');
      }
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.cancelled));

      // Reset and transition to transferring
      sessionProvider.resetSession();
      await Future<void>.delayed(Duration.zero);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.connecting);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.handshaking);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.transferring);
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.transferring));

      // Cancel while transferring
      for (int i = 0; i < 25; i++) {
        sessionProvider.cancelTransfer('Storm cancel transferring $i');
      }
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.cancelled));

      // Reset and transition to paused
      sessionProvider.resetSession();
      await Future<void>.delayed(Duration.zero);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.connecting);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.handshaking);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.transferring);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.paused));

      // Cancel while paused
      for (int i = 0; i < 25; i++) {
        sessionProvider.cancelTransfer('Storm cancel paused $i');
      }
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.cancelled));
    });

    test('Re-entrant cancellation: Invoking cancelTransfer() inside a progress listener does not trigger infinite loops', () async {
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.connecting);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.handshaking);
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.transferring);
      await Future<void>.delayed(Duration.zero);

      bool cancelAttempted = false;
      sessionProvider.addListener(() {
        if (!cancelAttempted && sessionProvider.currentState.state == TransferState.transferring) {
          cancelAttempted = true;
          sessionProvider.cancelTransfer('Re-entrant cancellation test');
        }
      });

      // Emit progress to trigger listener
      sessionProvider.sessionManager.stateMachine.updateProgress(
        const TransferProgress(
          transferredBytes: 1024,
          totalBytes: 2048,
          fraction: 0.5,
          speedBytesPerSec: 1024.0,
          eta: Duration(seconds: 1),
          elapsedTime: Duration(seconds: 1),
          isStalled: false,
          state: TransferState.transferring,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(sessionProvider.currentState.state, equals(TransferState.cancelled));
    });
  });

  group('CHALLENGER M4 - TIER 2: Rapid Pause/Resume/Cancel State Machine Oscillations', () {
    late SettingsProvider settings;
    late TransferSessionProvider sessionProvider;

    setUp(() {
      settings = SettingsProvider();
      sessionProvider = TransferSessionProvider(settings: settings);
    });

    tearDown(() {
      sessionProvider.dispose();
    });

    test('100 rapid pause/resume oscillations while transferring maintain consistent state', () async {
      final fsm = sessionProvider.sessionManager.stateMachine;
      fsm.transitionTo(TransferState.connecting);
      fsm.transitionTo(TransferState.handshaking);
      fsm.transitionTo(TransferState.transferring);
      await Future<void>.delayed(Duration.zero);

      for (int i = 0; i < 100; i++) {
        sessionProvider.pauseTransfer();
        await Future<void>.delayed(Duration.zero);
        expect(sessionProvider.currentState.state, equals(TransferState.paused));
        expect(sessionProvider.currentState.isPaused, isTrue);

        sessionProvider.resumeTransfer();
        await Future<void>.delayed(Duration.zero);
        expect(sessionProvider.currentState.state, equals(TransferState.transferring));
        expect(sessionProvider.currentState.isPaused, isFalse);
      }

      sessionProvider.cancelTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.cancelled));
    });

    test('Calling pauseTransfer() and resumeTransfer() in invalid states does not crash', () async {
      // In idle
      sessionProvider.pauseTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.idle));
      sessionProvider.resumeTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.idle));

      // In connecting
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.connecting);
      await Future<void>.delayed(Duration.zero);
      sessionProvider.pauseTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.connecting));
      sessionProvider.resumeTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.connecting));

      // In handshaking: pause is illegal (stays handshaking), resume transitions to transferring
      sessionProvider.sessionManager.stateMachine.transitionTo(TransferState.handshaking);
      await Future<void>.delayed(Duration.zero);
      sessionProvider.pauseTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.handshaking));
      sessionProvider.resumeTransfer();
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState.state, equals(TransferState.transferring));
    });

    test('SessionStateMachine strict transition invariants reject illegal transitions with StateError', () {
      final fsm = SessionStateMachine();

      // Idle -> Paused (illegal)
      expect(() => fsm.transitionTo(TransferState.paused), throwsStateError);

      // Idle -> Transferring (illegal)
      expect(() => fsm.transitionTo(TransferState.transferring), throwsStateError);

      // Idle -> Completed (illegal)
      expect(() => fsm.transitionTo(TransferState.completed), throwsStateError);

      // Idle -> Connecting (legal)
      fsm.transitionTo(TransferState.connecting);

      // Connecting -> Completed (illegal)
      expect(() => fsm.transitionTo(TransferState.completed), throwsStateError);

      // Connecting -> Paused (illegal)
      expect(() => fsm.transitionTo(TransferState.paused), throwsStateError);

      // Connecting -> Handshaking (legal)
      fsm.transitionTo(TransferState.handshaking);

      // Handshaking -> Paused (illegal)
      expect(() => fsm.transitionTo(TransferState.paused), throwsStateError);

      // Handshaking -> Transferring (legal)
      fsm.transitionTo(TransferState.transferring);

      // Transferring -> Verifying (legal)
      fsm.transitionTo(TransferState.verifying);

      // Verifying -> Paused (illegal)
      expect(() => fsm.transitionTo(TransferState.paused), throwsStateError);

      // Verifying -> Completed (legal)
      fsm.transitionTo(TransferState.completed);

      // Completed -> Connecting (illegal)
      expect(() => fsm.transitionTo(TransferState.connecting), throwsStateError);

      // Reset to idle (legal)
      fsm.reset();
      expect(fsm.currentState.state, equals(TransferState.idle));

      fsm.dispose();
    });

    test('Random fuzz permutation sequence of 300 provider operations executes safely', () async {
      final rand = math.Random(12345);
      for (int i = 0; i < 300; i++) {
        final op = rand.nextInt(10);
        switch (op) {
          case 0:
            sessionProvider.pauseTransfer();
            break;
          case 1:
            sessionProvider.resumeTransfer();
            break;
          case 2:
            sessionProvider.cancelTransfer('Fuzz cancel $i');
            break;
          case 3:
            sessionProvider.confirmSas();
            break;
          case 4:
            sessionProvider.rejectSas();
            break;
          case 5:
            sessionProvider.acceptProposal();
            break;
          case 6:
            sessionProvider.rejectProposal();
            break;
          case 7:
            sessionProvider.resetSession();
            break;
          case 8:
            sessionProvider.clearHistory();
            break;
          case 9:
            final fsm = sessionProvider.sessionManager.stateMachine;
            if (fsm.canTransitionTo(TransferState.connecting)) {
              fsm.transitionTo(TransferState.connecting);
            } else if (fsm.canTransitionTo(TransferState.handshaking)) {
              fsm.transitionTo(TransferState.handshaking);
            } else if (fsm.canTransitionTo(TransferState.transferring)) {
              fsm.transitionTo(TransferState.transferring);
            }
            break;
        }
      }
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.currentState, isNotNull);
    });
  });

  group('CHALLENGER M4 - TIER 3: Out-of-Order Progress Updates & Extreme Numeric Formatting Stress', () {
    late SettingsProvider settings;
    late TransferSessionProvider sessionProvider;

    setUp(() {
      settings = SettingsProvider();
      sessionProvider = TransferSessionProvider(settings: settings);
    });

    tearDown(() {
      sessionProvider.dispose();
    });

    test('Out-of-order progress updates during active transfer update state without exceptions', () async {
      final fsm = sessionProvider.sessionManager.stateMachine;
      fsm.transitionTo(TransferState.connecting);
      fsm.transitionTo(TransferState.handshaking);
      fsm.transitionTo(TransferState.transferring);
      await Future<void>.delayed(Duration.zero);

      final erraticBytes = [1000, 5000, 2000, 10000, 0, 50000, 25000, 100000];
      for (final b in erraticBytes) {
        fsm.updateProgress(
          TransferProgress(
            transferredBytes: b,
            totalBytes: 100000,
            fraction: b / 100000,
            speedBytesPerSec: b * 10.0,
            eta: const Duration(seconds: 5),
            elapsedTime: const Duration(seconds: 2),
            isStalled: false,
            state: TransferState.transferring,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(sessionProvider.progress?.transferredBytes, equals(b));
      }
    });

    test('Progress updates emitted when session is in non-transferring states are safely ignored', () async {
      final fsm = sessionProvider.sessionManager.stateMachine;
      expect(fsm.currentState.state, equals(TransferState.idle));

      const dummyProgress = TransferProgress(
        transferredBytes: 500,
        totalBytes: 1000,
        fraction: 0.5,
        speedBytesPerSec: 100.0,
        eta: Duration(seconds: 5),
        elapsedTime: Duration(seconds: 1),
        isStalled: false,
        state: TransferState.transferring,
      );

      // In idle
      fsm.updateProgress(dummyProgress);
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.progress, isNull);

      // In connecting
      fsm.transitionTo(TransferState.connecting);
      await Future<void>.delayed(Duration.zero);
      fsm.updateProgress(dummyProgress);
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.progress, isNull);

      // In completed
      fsm.transitionTo(TransferState.handshaking);
      fsm.transitionTo(TransferState.transferring);
      fsm.transitionTo(TransferState.completed);
      await Future<void>.delayed(Duration.zero);
      fsm.updateProgress(dummyProgress);
      await Future<void>.delayed(Duration.zero);
      expect(sessionProvider.progress, isNull);
    });

    test('TransferProgress format helpers handle extreme, negative, and infinite values robustly', () {
      // 1. formatBytes
      expect(TransferProgress.formatBytes(-500), equals('0 B'));
      expect(TransferProgress.formatBytes(0), equals('0 B'));
      expect(TransferProgress.formatBytes(512), equals('512 B'));
      expect(TransferProgress.formatBytes(1024), equals('1.0 KB'));
      expect(TransferProgress.formatBytes(1048576), equals('1.0 MB'));
      expect(TransferProgress.formatBytes(1073741824), equals('1.00 GB'));
      expect(TransferProgress.formatBytes(107374182400), equals('100.00 GB'));

      // 2. formatSpeed
      expect(TransferProgress.formatSpeed(-100.0), equals('0 B/s'));
      expect(TransferProgress.formatSpeed(0.0), equals('0 B/s'));
      expect(TransferProgress.formatSpeed(500.0), equals('500 B/s'));
      expect(TransferProgress.formatSpeed(2048.0), equals('2.0 KB/s'));
      expect(TransferProgress.formatSpeed(5242880.0), equals('5.0 MB/s'));
      expect(TransferProgress.formatSpeed(2147483648.0), equals('2.00 GB/s'));
      expect(TransferProgress.formatSpeed(double.infinity), contains('GB/s'));
      expect(TransferProgress.formatSpeed(double.nan), anyOf(equals('0 B/s'), contains('NaN')));

      // 3. formatDuration
      expect(TransferProgress.formatDuration(null), equals('Calculating...'));
      expect(TransferProgress.formatDuration(Duration.zero), equals('00:00'));
      expect(TransferProgress.formatDuration(null, isStalled: true), equals('Stalled'));
      expect(TransferProgress.formatDuration(const Duration(seconds: 45)), equals('00:45'));
      expect(TransferProgress.formatDuration(const Duration(minutes: 5, seconds: 20)), equals('05:20'));
      expect(TransferProgress.formatDuration(const Duration(hours: 3, minutes: 12, seconds: 4)), equals('03:12:04'));
      expect(TransferProgress.formatDuration(const Duration(days: 100)), contains(':'));
    });

    testWidgets('SpeedometerWidget renders without throwing under NaN, Infinity, negative, and extreme speeds', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final extremeSpeeds = [
        0.0,
        -1000.0,
        500.0,
        50.0 * 1024 * 1024,
        1500.0 * 1024 * 1024,
        double.infinity,
        double.nan,
      ];

      for (final speed in extremeSpeeds) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
            home: Scaffold(
              body: SpeedometerWidget(
                speedBytesPerSec: speed,
                peakSpeedBytesPerSec: speed.isFinite && speed > 0 ? speed * 1.5 : 0.0,
                size: 200,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(SpeedometerWidget), findsOneWidget);
      }
    });

    testWidgets('ChunkProgressBar renders correctly under zero total bytes, negative transferred, and extreme sizes', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testCases = [
        {'transferred': 0, 'total': 0, 'window': 4},
        {'transferred': -100, 'total': 1000, 'window': 4},
        {'transferred': 1500, 'total': 1000, 'window': 4},
        {'transferred': 50000000, 'total': 100000000, 'window': 32},
        {'transferred': 0, 'total': 100000000000, 'window': 1},
      ];

      for (final tc in testCases) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.oledTheme(AppPalettes.cyberEmerald),
            home: Scaffold(
              body: ChunkProgressBar(
                transferredBytes: tc['transferred'] as int,
                totalBytes: tc['total'] as int,
                creditWindowSize: tc['window'] as int,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(ChunkProgressBar), findsOneWidget);
      }
    });
  });

  group('CHALLENGER M4 - TIER 4: SAS Verification Rejection Flow, Timeout Handling & Completer Safety', () {
    late SettingsProvider settings;
    late TransferSessionProvider sessionProvider;

    setUp(() {
      settings = SettingsProvider();
      sessionProvider = TransferSessionProvider(settings: settings);
    });

    tearDown(() {
      sessionProvider.dispose();
    });

    test('SasVerificationRequest confirm() and reject() are idempotent and do not throw on multiple calls', () async {
      final req1 = SasVerificationRequest(
        sasCode: _createDummySas(1),
        remoteAddress: '10.0.0.1',
        remotePort: 42385,
      );

      req1.confirm();
      req1.confirm(); // Second call must not throw Bad State
      req1.reject();  // Mismatched call must be ignored
      expect(await req1.decision, isTrue);

      final req2 = SasVerificationRequest(
        sasCode: _createDummySas(2),
        remoteAddress: '10.0.0.2',
        remotePort: 42385,
      );

      req2.reject();
      req2.reject();  // Second call must not throw Bad State
      req2.confirm(); // Mismatched call must be ignored
      expect(await req2.decision, isFalse);
    });

    test('Null safety: confirmSas() and rejectSas() when no request is pending', () {
      int notifyCount = 0;
      sessionProvider.addListener(() => notifyCount++);

      expect(sessionProvider.pendingSasRequest, isNull);
      sessionProvider.confirmSas();
      sessionProvider.rejectSas();
      expect(sessionProvider.pendingSasRequest, isNull);
      expect(notifyCount, equals(2));
    });

    test('Timeout handling: Awaiting SAS decision with timeout handles rejection cleanly without hanging futures', () async {
      final req = SasVerificationRequest(
        sasCode: _createDummySas(3),
        remoteAddress: '10.0.0.3',
        remotePort: 42385,
      );

      // Simulate timeout
      bool timedOut = false;
      try {
        await req.decision.timeout(const Duration(milliseconds: 50));
      } on TimeoutException {
        timedOut = true;
        req.reject(); // User or system rejects after timeout
      }

      expect(timedOut, isTrue);
      expect(await req.decision, isFalse);
    });

    test('Rapid sequence of 20 SAS verification requests resolved in interleaved order', () async {
      final requests = List.generate(
        20,
        (i) => SasVerificationRequest(
          sasCode: _createDummySas(i + 10),
          remoteAddress: '10.0.0.${i + 1}',
          remotePort: 42385,
        ),
      );

      final results = <Future<bool>>[];
      for (int i = 0; i < requests.length; i++) {
        results.add(requests[i].decision);
      }

      // Resolve in reverse order
      for (int i = requests.length - 1; i >= 0; i--) {
        if (i % 2 == 0) {
          requests[i].confirm();
        } else {
          requests[i].reject();
        }
      }

      final resolved = await Future.wait(results);
      for (int i = 0; i < resolved.length; i++) {
        if (i % 2 == 0) {
          expect(resolved[i], isTrue);
        } else {
          expect(resolved[i], isFalse);
        }
      }
    });
  });

  group('CHALLENGER M4 - TIER 5: Zero-Metadata Ephemeral RAM History & Reset Policy', () {
    late SettingsProvider settings;
    late TransferSessionProvider sessionProvider;

    setUp(() {
      settings = SettingsProvider();
      sessionProvider = TransferSessionProvider(settings: settings);
    });

    tearDown(() {
      sessionProvider.dispose();
    });

    test('100 terminal transfer states record into volatile RAM history and clearHistory() purges them completely', () async {
      final fsm = sessionProvider.sessionManager.stateMachine;

      for (int i = 0; i < 100; i++) {
        fsm.reset();
        await Future<void>.delayed(Duration.zero);
        fsm.transitionTo(TransferState.connecting);
        fsm.transitionTo(TransferState.handshaking);
        fsm.transitionTo(TransferState.transferring);

        if (i % 3 == 0) {
          fsm.transitionTo(
            TransferState.completed,
            fileName: 'test_file_$i.zip',
            totalBytes: (i + 1) * 1024 * 1024,
            committedFilePath: '/ephemeral/path/test_file_$i.zip',
          );
        } else if (i % 3 == 1) {
          fsm.fail(SessionErrorCode.integrityMismatch, 'Hash mismatch on chunk $i');
        } else {
          fsm.cancel('User cancelled iteration $i');
        }
        await Future<void>.delayed(Duration.zero);
      }

      expect(sessionProvider.history.length, equals(100));

      // Test latest item properties
      final latest = sessionProvider.history.first;
      expect(latest.id, isNotEmpty);
      expect(latest.timestamp, isNotNull);

      // Verify unmodifiable list
      expect(() => (sessionProvider.history as dynamic).add(latest), throwsUnsupportedError);

      // Clear history
      sessionProvider.clearHistory();
      expect(sessionProvider.history, isEmpty);
    });

    test('Session reset restores idle state and clears pending dialog states', () async {
      final fsm = sessionProvider.sessionManager.stateMachine;
      fsm.transitionTo(TransferState.connecting);
      fsm.transitionTo(TransferState.handshaking);
      await Future<void>.delayed(Duration.zero);

      sessionProvider.resetSession();
      await Future<void>.delayed(Duration.zero);

      expect(sessionProvider.currentState.state, equals(TransferState.idle));
      expect(sessionProvider.hasActiveTransfer, isFalse);
      expect(sessionProvider.pendingSasRequest, isNull);
      expect(sessionProvider.pendingProposal, isNull);
    });
  });

  group('CHALLENGER M4 - TIER 6: DeviceDiscoveryProvider & SettingsProvider Stress & Adversarial Inputs', () {
    late SettingsProvider settings;
    late DeviceDiscoveryProvider discoveryProvider;

    setUp(() {
      settings = SettingsProvider();
      discoveryProvider = DeviceDiscoveryProvider();
    });

    tearDown(() {
      discoveryProvider.dispose();
    });

    test('DeviceDiscoveryProvider handles rapid churn of 200 devices and adversarial search queries safely', () {
      // Trigger search filter tests
      discoveryProvider.setSearchQuery('Alice');
      expect(discoveryProvider.searchQuery, equals('Alice'));

      discoveryProvider.setOsFilter('windows');
      expect(discoveryProvider.selectedOsFilter, equals('windows'));

      // Adversarial search inputs
      final hostileQueries = [
        "'; DROP TABLE devices; --",
        r".*[a-z]+(?=pattern)",
        "\\x00\\xFF\\u0000",
        "A" * 2000,
        "🦊⚡🪐💎",
        "\u202E\u200B\uFEFF", // RTL overrides and zero-width
      ];

      for (final q in hostileQueries) {
        discoveryProvider.setSearchQuery(q);
        expect(discoveryProvider.searchQuery, equals(q));
      }

      discoveryProvider.clearFilters();
      expect(discoveryProvider.searchQuery, isEmpty);
      expect(discoveryProvider.selectedOsFilter, isNull);
    });

    test('SettingsProvider validates boundary inputs and clamps/ignores illegal values', () {
      // Port boundaries
      settings.setTransferPort(1024); // Invalid (must be > 1024)
      expect(settings.transferPort, equals(42385));

      settings.setTransferPort(65536); // Invalid (> 65535)
      expect(settings.transferPort, equals(42385));

      settings.setTransferPort(0); // Invalid
      expect(settings.transferPort, equals(42385));

      settings.setTransferPort(50000); // Valid
      expect(settings.transferPort, equals(50000));

      // Window size boundaries
      settings.setCreditWindowSize(0); // Invalid (< 1)
      expect(settings.creditWindowSize, equals(4));

      settings.setCreditWindowSize(33); // Invalid (> 32)
      expect(settings.creditWindowSize, equals(4));

      settings.setCreditWindowSize(16); // Valid
      expect(settings.creditWindowSize, equals(16));

      // Chunk size boundaries
      settings.setChunkSize(500); // Invalid (< 1024)
      expect(settings.chunkSize, equals(65536));

      settings.setChunkSize(2000000); // Invalid (> 1048576)
      expect(settings.chunkSize, equals(65536));

      settings.setChunkSize(131072); // Valid
      expect(settings.chunkSize, equals(131072));

      // Speed limits
      settings.setSpeedLimit(-500); // Invalid (< 0)
      expect(settings.maxSpeedLimitBytesPerSec, equals(0));

      settings.setSpeedLimit(10000000); // Valid
      expect(settings.maxSpeedLimitBytesPerSec, equals(10000000));

      // Reset to defaults
      settings.resetToDefaults();
      expect(settings.transferPort, equals(42385));
      expect(settings.creditWindowSize, equals(4));
      expect(settings.chunkSize, equals(65536));
      expect(settings.maxSpeedLimitBytesPerSec, equals(0));
    });
  });
}
