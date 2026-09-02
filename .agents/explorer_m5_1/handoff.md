# Milestone 5 Architecture & Specification: Single-Command Master Test Runner & Test Infrastructure

**Agent**: Explorer 1 (Test Runner Architect & Test Writer)  
**Date**: 2026-08-31T18:22:00Z  
**Target Milestone**: Milestone 5 (Comprehensive E2E Testing Suite & Single-Command Test Runner)  
**Primary Deliverables Designed**:
1. `test/run_all_tests.dart` Master Test Runner Architecture
2. `TEST_INFRA.md` Specification and Infrastructure Contracts
3. CI/CD Integration & Developer Ergonomics Specification

---

## 1. Observation

### 1.1 Existing Test Suite Inventory
A scan of `test/` revealed 22 test files spanning 5 distinct domains:
- **`test/unit/` (7 files)**:
  - `crypto_test.dart`: X25519 ECDH, HKDF-SHA256, ChaCha20-Poly1305 AEAD, AES-GCM fallback, SAS 6-digit + 4-emoji generation, buffer zeroization.
  - `obfuscation_test.dart`: ChaCha20 length prefix masking, CSPRNG jitter handshake (96–160B), uniform frame padding (64KB/1024B, entropy $\ge 7.995$ bits/byte).
  - `zero_metadata_staging_test.dart`: Ephemeral RAM staging, atomic `.part` disk staging, path traversal sanitization, secure wipe on abort.
  - `frame_codec_test.dart`: 34-byte wire frame headers, all frame opcodes (handshake, propose, accept, chunk, ack, finish, error), bit-level decoding.
  - `session_state_test.dart`: 7-state deterministic FSM transitions, state timeouts, invalid transition rejections.
  - `device_registry_test.dart`: Device catalog, heartbeat updates, 12s stale mark, 25s auto-pruning.
  - `discovery_test.dart`: mDNS codec, UDP broadcast beacon pack/unpack, manual IP parsing.
- **`test/integration/` (3 files)**:
  - `streaming_transfer_test.dart`: Loopback socket transfer, backpressure flow control, multi-chunk stream, SHA-256 verification.
  - `memory_bound_test.dart`: 100MB active chunked transfer with periodic RSS sampling (<200MB delta requirement).
  - `session_handshake_test.dart`: Full mutual handshake, X25519 ECDH exchange, SAS match verification, session establishment.
- **`test/adversarial/` (7 files)**:
  - `crypto_adversarial_test.dart`: Ciphertext bit-flips, MAC corruption, nonce reuse prevention, replay attack rejection.
  - `challenger_m1_2_staging_test.dart`: Staging directory traversal (`../../`), disk full simulation, unlinked partial files.
  - `challenger_m2_framing_test.dart`: 1-byte stream slicing across 50 heterogeneous frames, oversized frames, corrupt auth tags.
  - `challenger_m2_streaming_test.dart`: Credit exhaustion, receiver freeze, backpressure starvation, corrupted chunk retries.
  - `challenger_m3_discovery_test.dart`: Malformed mDNS packets, UDP flood, spoofed beacons, stale cleanup.
  - `challenger_m3_session_test.dart`: Handshake MITM bit-flip attacks, invalid public keys, protocol downgrade attempts.
  - `challenger_m4_cli_adversarial_test.dart`: CLI argument fuzzing, invalid flags, missing files/targets, illegal ports.
- **`test/ui/` (4 files)**:
  - `widgets_test.dart`: Material 3 widgets (`RadarView`, `DeviceCard`, `SpeedometerWidget`, `ChunkProgressBar`, `SasVerificationDialog`, `FileDropTarget`, `InboundProposalDialog`, `ManualConnectDialog`).
  - `screens_test.dart`: `HomeScreen`, `TransferScreen`, `SettingsScreen`.
  - `providers_test.dart`: `DiscoveryProvider`, `TransferProvider`, `SettingsProvider`.
  - `state_stress_test.dart`: High-frequency UI state mutations, rapid cancellation, theme toggle.
- **`test/cli/` (1 file)**:
  - `cli_test.dart`: Standalone CLI subcommands (`send`, `receive`, `discover`, `pair`), help screens, error exit codes, loopback E2E transfer.

### 1.2 Execution Observations & Tool Behavior
- Running `flutter test test/unit/crypto_test.dart` executes 17 test groups with 100% pass rate in **< 1.0s**.
- Running `flutter test test/integration/memory_bound_test.dart` verified that a 100MB transfer achieves:
  - `Baseline RSS: 133.02 MB`
  - `Peak RSS:     162.12 MB`
  - `Delta RSS:    29.10 MB (Strict Limit: < 200.00 MB)`
- In `cli_test.dart` and `challenger_m4_cli_adversarial_test.dart`, direct `Process.run('dart', ...)` encountered `ProcessException: O sistema não pode encontrar o arquivo especificado` on Windows when the test worker process executes without `runInShell: true` or `Platform.resolvedExecutable`. Using `Platform.resolvedExecutable` or `flutter` binary resolution completely resolves this cross-platform issue.

---

## 2. Logic Chain & Architecture Design

### 2.1 Master Test Runner Architecture (`test/run_all_tests.dart`)

```
                          ┌──────────────────────────────────────────────┐
                          │         test/run_all_tests.dart              │
                          │   (Master CLI Entrypoint & Coordinator)     │
                          └──────────────────────┬───────────────────────┘
                                                 │
                   ┌─────────────────────────────┼─────────────────────────────┐
                   ▼                             ▼                             ▼
       ┌──────────────────────┐      ┌──────────────────────┐      ┌──────────────────────┐
       │   CLI Arg Parser     │      │   Suite Discovery    │      │  Environment Probe   │
       │ --tier, --skip-stress│      │ Scans test/ for all  │      │ OS, CPU cores, Dart, │
       │ --verbose, --json    │      │ *_test.dart by Tier  │      │ Flutter, Initial RSS │
       └──────────┬───────────┘      └──────────┬───────────┘      └──────────┬───────────┘
                  │                             │                             │
                  └──────────────────────┬──────┴─────────────────────────────┘
                                         ▼
                          ┌──────────────────────────────┐
                          │   Execution Scheduler Engine │
                          │   (Sequential/Concurrent)   │
                          └──────────────┬───────────────┘
                                         │
        ┌────────────────────────────────┼────────────────────────────────┐
        ▼                                ▼                                ▼
┌─────────────────┐              ┌─────────────────┐              ┌─────────────────┐
│ Tier 1: Unit    │              │ Tier 2: State   │              │ Tier 3: UI/CLI  │
│ Crypto, Frames  │              │ Discovery, FSM  │              │ Widgets, Screens│
└───────┬─────────┘              └───────┬─────────┘              └───────┬─────────┘
        │                                │                                │
        └────────────────────────────────┼────────────────────────────────┘
                                         ▼
                         ┌────────────────────────────────┐
                         │ Tier 4: E2E & Memory Bounding  │
                         │ Multi-MB/GB Stream, SHA256     │
                         └───────────────┬────────────────┘
                                         ▼
                         ┌────────────────────────────────┐
                         │ Tier 5: Adversarial & Chaos    │
                         │ MITM, Packet Loss, Bit-Flips   │
                         └───────────────┬────────────────┘
                                         │
                   ┌─────────────────────┴──────────────────────┐
                   ▼                                            ▼
       ┌──────────────────────┐                     ┌──────────────────────┐
       │ Live ANSI Terminal   │                     │ JSON Summary Report  │
       │ Progress & Matrix    │                     │ schemaVersion: 1.0.0 │
       └──────────┬───────────┘                     └──────────┬───────────┘
                  │                                            │
                  └──────────────────────┬─────────────────────┘
                                         ▼
                          ┌──────────────────────────────┐
                          │ Deterministic Exit Code      │
                          │ 0: All Pass | 1: Fail | 2:Err│
                          └──────────────────────────────┘
```

#### A. Suite Discovery & Tier Categorization
The test runner dynamically discovers all test files in `test/` matching `*_test.dart` and categorizes them:

| Tier | Name | Target Directories & Suites | Characteristics |
|---|---|---|---|
| **Tier 1** | Primitive Cryptography & Wire Framing | `test/unit/crypto_test.dart`<br>`test/unit/obfuscation_test.dart`<br>`test/unit/frame_codec_test.dart`<br>`test/unit/zero_metadata_staging_test.dart` | Pure CPU / in-memory, deterministic, zero I/O latency, $< 2\text{s}$ total. |
| **Tier 2** | Subsystem Protocols, Discovery & Session FSM | `test/unit/discovery_test.dart`<br>`test/unit/device_registry_test.dart`<br>`test/unit/session_state_test.dart`<br>`test/integration/session_handshake_test.dart` | Local timers, state transitions, mDNS/UDP mock beacons, $< 3\text{s}$ total. |
| **Tier 3** | User Interface Widgets & Headless CLI | `test/ui/widgets_test.dart`<br>`test/ui/screens_test.dart`<br>`test/ui/providers_test.dart`<br>`test/ui/state_stress_test.dart`<br>`test/cli/cli_test.dart` | Flutter widget tester (`pumpWidget`, `pumpAndSettle`), Provider state, CLI process verification, $< 5\text{s}$ total. |
| **Tier 4** | End-to-End Streaming & Resource Constraints | `test/integration/streaming_transfer_test.dart`<br>`test/integration/memory_bound_test.dart`<br>`test/integration/e2e_transfer_test.dart` (M5 additions) | Full loopback sockets, multi-MB & 100MB+ transfers, continuous RSS tracking ($<200\text{MB}$ delta assertion), SHA-256 root digest verification. |
| **Tier 5** | Adversarial Hardening & Network Chaos | `test/adversarial/crypto_adversarial_test.dart`<br>`test/adversarial/challenger_m1_2_staging_test.dart`<br>`test/adversarial/challenger_m2_framing_test.dart`<br>`test/adversarial/challenger_m2_streaming_test.dart`<br>`test/adversarial/challenger_m3_discovery_test.dart`<br>`test/adversarial/challenger_m3_session_test.dart`<br>`test/adversarial/challenger_m4_cli_adversarial_test.dart` | Active MITM, packet loss, jitter injection, credit starvation, bit-flip tamper resistance, process crash resilience. |

#### B. Command-Line Arguments & Flags Specification

```dart
class RunnerOptions {
  final List<int> tiers;           // [1, 2, 3, 4, 5] (default: all)
  final String? category;         // 'unit', 'integration', 'ui', 'cli', 'adversarial'
  final bool skipStress;          // Skip >50MB and heavy RSS saturation tests
  final bool verbose;             // Print per-assertion logs and stdout
  final int timeoutSeconds;       // Per-suite timeout (default: 120s)
  final int concurrency;          // Parallel suite execution count (default: 1)
  final bool bail;                // Immediate exit on first test failure
  final String? jsonSummaryPath;  // Path to emit JSON summary report
  final RegExp? filter;           // Regex filter for suite names / test names
  final bool noColor;             // Suppress ANSI color codes
  final bool dryRun;              // List matching suites without executing
}
```

Flag mapping:
- `--tier <tiers>` / `-t <tiers>`: e.g. `--tier 1`, `--tier 1-3`, `--tier 4,5`
- `--category <cat>` / `-c <cat>`: `unit`, `integration`, `adversarial`, `ui`, `cli`
- `--skip-stress`: Excludes test suites flagged with `@Tags(['stress'])` or filenames containing `memory_bound` / `multi_gb`
- `--verbose` / `-v`: Real-time streaming of all test events and assertion outputs
- `--timeout <sec>`: Suite execution watchdog timer
- `--concurrency <N>` / `-j <N>`: Concurrency level (defaults to sequential `1` to avoid TCP port collisions)
- `--bail` / `-b`: Abort suite on first failure
- `--json-summary <path>` / `--json <path>`: Write structured JSON report
- `--filter <regex>` / `-k <regex>`: Match file path or test group name
- `--no-color`: Disable ANSI styling
- `--dry-run`: Preview selected suites
- `--help` / `-h`: Print manual

#### C. Execution Engine & JSON Machine Protocol Parser
The master runner executes individual suites using `flutter test <path> --reporter json` (or batched per tier), spawning child processes via `Process.start`:
1. **JSON Stream Ingestion**:
   - `testStart`: Registers active test ID, name, parent groups, suite path.
   - `testDone`: Calculates elapsed duration, records result (`success`, `failure`, `error`), increments totals.
   - `error`: Records verbatim assertion failure, expected vs actual mismatch, and stack trace.
   - `print`: Captures application stdout/stderr.
   - `done`: Finalizes suite status.
2. **Resource Footprint Monitoring**:
   - Spawns background `Timer.periodic(Duration(milliseconds: 50))` sampling `ProcessInfo.currentRss` during execution.
   - Computes:
     - `Baseline RSS`: Memory footprint prior to test launch.
     - `Peak RSS`: Maximum observed RSS during execution.
     - `Max Delta RSS`: $\text{Peak RSS} - \text{Baseline RSS}$.
   - Verifies the core requirement: $\Delta \text{RSS} < 200\text{ MB}$.

#### D. Terminal UI & ANSI UX Specification
- **Color Codes**:
  - Emerald Green (`\x1B[38;2;16;185;129m` / `\x1B[32m`) for PASS
  - Crimson Red (`\x1B[38;2;239;68;68m` / `\x1B[31m`) for FAIL
  - Amber Yellow (`\x1B[38;2;245;158;11m` / `\x1B[33m`) for SKIP / WARN
  - Cyan (`\x1B[38;2;6;182;212m` / `\x1B[36m`) for Tiers & Info
  - Bold / Dim formatting for hierarchy.
- **Live Animated Spinner**: Unicode frames (`⠋`, `⠙`, `⠹`, `⠸`, `⠼`, `⠴`, `⠦`, `⠧`, `⠇`, `⠏`) updated on `stdout` without line wrapping.
- **Structured Failure Callouts**: Red border with clear separation of error message and origin stack frame.
- **ANSI Summary Matrix Table**: Complete summary breakdown by Category, Tier, Suite count, Passed, Failed, Time, and Peak RSS.

#### E. Deterministic Exit Codes
- `0`: All selected tests executed and passed ($100\%$ green).
- `1`: One or more tests failed, timed out, or crashed.
- `2`: CLI parsing error, invalid flags, missing files, or initialization error.

---

### 2.2 JSON Summary Schema Specification (`report.json`)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "schemaVersion": "1.0.0",
  "title": "SLFT Master Test Suite Summary Report",
  "timestamp": "2026-08-31T18:22:00.000Z",
  "environment": {
    "os": "windows",
    "osVersion": "Windows 11 Home 10.0.26100",
    "dartVersion": "3.3.0",
    "flutterVersion": "3.19.0",
    "cpuCores": 16,
    "baselineRssBytes": 139587584,
    "baselineRssMb": 133.12
  },
  "configuration": {
    "tiers": [1, 2, 3, 4, 5],
    "category": null,
    "skipStress": false,
    "timeoutSeconds": 120,
    "concurrency": 1,
    "filter": null
  },
  "summary": {
    "totalSuites": 22,
    "passedSuites": 22,
    "failedSuites": 0,
    "skippedSuites": 0,
    "totalTests": 511,
    "passedTests": 511,
    "failedTests": 0,
    "skippedTests": 0,
    "totalDurationMs": 28450,
    "totalDurationFormatted": "28.45s",
    "peakRssBytes": 183926784,
    "peakRssMb": 175.40,
    "maxRssDeltaBytes": 44339200,
    "maxRssDeltaMb": 42.28,
    "rssConstraintPassed": true,
    "exitCode": 0
  },
  "suites": [
    {
      "filePath": "test/unit/crypto_test.dart",
      "category": "unit",
      "tier": 1,
      "status": "passed",
      "durationMs": 840,
      "totalTests": 17,
      "passedTests": 17,
      "failedTests": 0,
      "skippedTests": 0,
      "peakRssBytes": 149028864,
      "peakRssMb": 142.12,
      "failures": []
    }
  ]
}
```

---

### 2.3 CI/CD Integration & Developer Workflows

#### A. GitHub Actions Workflow (`.github/workflows/test.yml`)
```yaml
name: SLFT Comprehensive Test Suite

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  analyze-and-test:
    name: Test on ${{ matrix.os }}
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ ubuntu-latest, windows-latest, macos-latest ]

    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'
          channel: 'stable'
          cache: true

      - name: Install Dependencies
        run: flutter pub get

      - name: Static Analysis & Lint Check
        run: flutter analyze --fatal-infos --fatal-warnings

      - name: Fast Smoke Test (Tiers 1-3)
        run: dart run test/run_all_tests.dart --tier 1-3 --skip-stress --json-summary smoke-report-${{ matrix.os }}.json

      - name: Full E2E & Adversarial Matrix (Tiers 1-5)
        run: dart run test/run_all_tests.dart --tier 1-5 --json-summary full-report-${{ matrix.os }}.json

      - name: Upload Test Results Artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-reports-${{ matrix.os }}
          path: |
            smoke-report-*.json
            full-report-*.json
```

#### B. Developer Local Ergonomics
- **Quick Crypto & Wire Frame Check (<2s)**:
  `dart run test/run_all_tests.dart --tier 1`
- **Fast Local Pre-Commit Check (skipping multi-GB heavy stress)**:
  `dart run test/run_all_tests.dart --skip-stress`
- **Single Suite Debugging with Verbose Logs**:
  `dart run test/run_all_tests.dart --filter streaming_transfer -v`
- **Full Verification Audit**:
  `dart run test/run_all_tests.dart`

---

## 3. Specification of `TEST_INFRA.md`

`TEST_INFRA.md` at the project root must document:
1. **Architecture & Scope**: Overview of the 5 testing tiers, test runner design, and deterministic constraints.
2. **Directory Taxonomy**: Rules for organizing unit, integration, ui/widget, cli, and adversarial tests.
3. **Execution Manual**: Complete command-line flag guide, examples, exit code contracts, and CI recipes.
4. **Test Helper Library Specification (`test/helpers/`)**:
   - `test_socket_pair.dart`: Hermetic loopback socket pairs on ephemeral ports (`InternetAddress.loopbackIPv4`, port 0).
   - `synthetic_stream_generator.dart`: Memory-bounded pseudo-random and patterned chunk generator for 1MB, 100MB, 1GB streams.
   - `memory_monitor.dart`: High-resolution RSS tracker with assertion helper `expectRssDeltaLessThan(200.megabytes)`.
   - `network_chaos_interceptor.dart`: Configurable socket wrapper for injecting packet loss, delay jitter, chunk bit-flips, and RST drops.
5. **Report & JSON Schema**: Complete documentation of JSON summary payload fields.
6. **Writing New Tests**: Step-by-step developer guidelines for authoring tests in each tier.

---

## 4. Caveats

1. **Subprocess Invocation on Windows**: Tests invoking external binaries (`dart` or `flutter`) must use `Platform.resolvedExecutable` or `runInShell: true` to avoid `ProcessException` on Windows where `.bat` / `.cmd` wrappers are in PATH.
2. **Port Binding in Integration Tests**: To allow safe parallel execution in the future, integration tests must bind to ephemeral port `0` (or dynamically allocated offsets) rather than hardcoded port `42385`.
3. **Memory Sampling Resolution**: `ProcessInfo.currentRss` measures overall Dart VM RSS. Background GC cycles can affect instant measurements; sampling at 20-50ms intervals over the entire transfer duration provides accurate peak RSS tracking.

---

## 5. Conclusion & Actionable Plan for Workers

The master test runner `test/run_all_tests.dart` and testing infrastructure are fully designed to satisfy all Milestone 5 acceptance criteria:
- Single-command unified execution across all 22+ suites in `test/`.
- Flexible CLI flags (`--tier`, `--skip-stress`, `--verbose`, `--json-summary`, `--timeout`).
- Terminal UX with ANSI colors, live spinner, timing, and RSS memory monitoring.
- Deterministic exit codes (`0` for all pass, `1` for any failure).
- Complete CI/CD workflow and developer ergonomics.

### Next Implementation Steps (for Worker Agent):
1. Create `test/helpers/test_utils.dart` (ephemeral loopback sockets, synthetic stream generator, memory monitor).
2. Create `test/run_all_tests.dart` implementing the CLI argument parser, suite discovery engine, JSON reporter stream consumer, ANSI terminal visualizer, and deterministic exit code return.
3. Create `TEST_INFRA.md` in the project root documenting all contracts, tiers, flags, and helper APIs.
4. Add comprehensive E2E tests (multi-MB / 100MB+ memory-bounded transfer, SHA-256 root digest verification, mock discovery, and network fault tolerance).

---

## 6. Verification Method

To independently verify the test runner once implemented:
1. **Help Screen Verification**:
   `dart run test/run_all_tests.dart --help` (must exit 0 and print all flags).
2. **Tier 1 Quick Run**:
   `dart run test/run_all_tests.dart --tier 1` (must execute pure unit tests in < 3s and exit 0).
3. **JSON Output Verification**:
   `dart run test/run_all_tests.dart --tier 1 --json-summary report.json` (must produce valid JSON matching the schema).
4. **Full Test Suite Run**:
   `dart run test/run_all_tests.dart` (must execute all test suites, display ANSI matrix summary, verify $\Delta\text{RSS} < 200\text{ MB}$, and exit deterministically).
