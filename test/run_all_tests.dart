import 'dart:async';
import 'dart:io';

/// Unified Single-Command Master Test Runner for Secure LAN File Transfer (SLFT).
/// Executes all 5 testing tiers and provides structured reporting.
void main(List<String> args) async {
  final stopwatch = Stopwatch()..start();

  print('===============================================================');
  print('    SECURE LAN FILE TRANSFER (SLFT) — UNIFIED TEST RUNNER     ');
  print('===============================================================');

  final filterTier = _parseTierArg(args);
  final isVerbose = args.contains('--verbose') || args.contains('-v');

  final tiers = <int, List<String>>{
    1: [
      'test/unit/crypto_test.dart',
      'test/unit/obfuscation_test.dart',
      'test/unit/zero_metadata_staging_test.dart',
      'test/unit/frame_codec_test.dart',
      'test/unit/session_state_test.dart',
      'test/unit/device_registry_test.dart',
      'test/unit/discovery_test.dart',
      'test/unit/transfer_queue_test.dart',
    ],
    2: [
      'test/integration/session_handshake_test.dart',
      'test/integration/streaming_transfer_test.dart',
      'test/integration/memory_bound_test.dart',
      'test/integration/e2e_large_transfer_stress_test.dart',
      'test/integration/multi_peer_concurrency_test.dart',
      'test/integration/discovery_pairing_e2e_test.dart',
      'test/integration/flow_control_bandwidth_throttling_test.dart',
      'test/integration/adversarial_network_simulation_test.dart',
    ],
    3: [
      'test/cli/cli_test.dart',
      'test/cli/cli_subprocess_e2e_test.dart',
    ],
    4: [
      'test/ui/providers_test.dart',
      'test/ui/screens_test.dart',
      'test/ui/widgets_test.dart',
      'test/ui/state_stress_test.dart',
      'test/widget_test.dart',
    ],
    5: [
      'test/adversarial/crypto_adversarial_test.dart',
      'test/adversarial/challenger_m1_2_staging_test.dart',
      'test/adversarial/challenger_m2_framing_test.dart',
      'test/adversarial/challenger_m2_streaming_test.dart',
      'test/adversarial/challenger_m3_discovery_test.dart',
      'test/adversarial/challenger_m3_session_test.dart',
      'test/adversarial/challenger_m4_cli_adversarial_test.dart',
    ],
  };

  final tierNames = <int, String>{
    1: 'Tier 1: Core Unit Tests (Crypto, Codecs, State Machines, Discovery)',
    2: 'Tier 2: Integration & Streaming Stress Tests (Memory Bounds, Backpressure, Concurrency)',
    3: 'Tier 3: CLI Subprocess & Execution Tests',
    4: 'Tier 4: UI Widgets, Providers & State Stress Tests',
    5: 'Tier 5: Adversarial Challenger Suites (Tampering, Replays, Floods, Truncations)',
  };

  int totalPassed = 0;
  int totalFailed = 0;
  final failedSuites = <String>[];

  final tiersToRun = filterTier != null ? [filterTier] : [1, 2, 3, 4, 5];

  for (final tier in tiersToRun) {
    final suites = tiers[tier] ?? [];
    final name = tierNames[tier] ?? 'Tier $tier';

    print('\n---------------------------------------------------------------');
    print('  [TIER $tier] $name');
    print('---------------------------------------------------------------');

    for (final suite in suites) {
      final file = File(suite);
      if (!file.existsSync()) {
        print('  [SKIP] $suite (file not found)');
        continue;
      }

      stdout.write('  Running $suite ... ');
      final suiteStopwatch = Stopwatch()..start();

      // Use flutter test for UI and dart test for others
      final isFlutterTest = tier == 4 || suite.startsWith('test/ui/') || suite == 'test/widget_test.dart';
      final cmd = isFlutterTest
          ? (Platform.isWindows ? 'flutter.bat' : 'flutter')
          : (Platform.isWindows ? 'dart.bat' : 'dart');

      final cmdArgs = ['test', suite];

      final result = await Process.run(
        cmd,
        cmdArgs,
        runInShell: Platform.isWindows,
      );

      suiteStopwatch.stop();

      if (result.exitCode == 0) {
        print('PASSED (${suiteStopwatch.elapsedMilliseconds}ms)');
        totalPassed++;
      } else {
        print('FAILED (${suiteStopwatch.elapsedMilliseconds}ms)');
        totalFailed++;
        failedSuites.add(suite);
        if (isVerbose) {
          print('\n--- Output from $suite ---');
          print(result.stdout);
          print(result.stderr);
          print('--------------------------\n');
        }
      }
    }
  }

  stopwatch.stop();

  print('\n===============================================================');
  print('                    TEST EXECUTION SUMMARY                     ');
  print('===============================================================');
  print('  Total Suites Run   : ${totalPassed + totalFailed}');
  print('  Passed Suites      : $totalPassed');
  print('  Failed Suites      : $totalFailed');
  print('  Total Duration     : ${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');

  if (failedSuites.isNotEmpty) {
    print('\n  Failed Test Suites:');
    for (final f in failedSuites) {
      print('    - $f');
    }
    print('\nResult: FAILED');
    exit(1);
  } else {
    print('\nResult: ALL TESTS PASSED (100% SUCCESS)');
    exit(0);
  }
}

int? _parseTierArg(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--tier=')) {
      return int.tryParse(arg.substring('--tier='.length));
    }
  }
  return null;
}
