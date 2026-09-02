# E2E Test Infra: Secure LAN File Transfer (SLFT)

## Test Philosophy
- Opaque-box, requirement-driven testing derived from `ORIGINAL_REQUEST.md`.
- Methodology: Category-Partition + Boundary Value Analysis (BVA) + Pairwise Interaction Testing + Real-World Workload Testing.
- Single-command test execution (`dart test` / `dart test test/run_all_tests.dart` / `flutter test`).

## Feature Inventory & Test Mapping
| # | Feature | Source (Requirement) | Tier 1 (Feature) | Tier 2 (Boundary) | Tier 3 (Pairwise) | Tier 4 (Real-World) |
|---|---------|----------------------|:----------------:|:-----------------:|:-----------------:|:-------------------:|
| 1 | X25519 Ephemeral Key Exchange | Req 2 (Zero pre-shared secrets, PFS) | 5 | 5 | ✓ | ✓ |
| 2 | HKDF-SHA256 Key Derivation | Req 2 (Session keys & directional separation) | 5 | 5 | ✓ | ✓ |
| 3 | ChaCha20-Poly1305 AEAD | Req 2 (E2EE, 128-bit MAC) | 5 | 5 | ✓ | ✓ |
| 4 | Traffic Obfuscation & Jitter Padding | Req 2 (High entropy $\ge 7.995$, no cleartext) | 5 | 5 | ✓ | ✓ |
| 5 | SAS 6-Digit & Visual Emoji Verification | Req 2 (MITM defense) | 5 | 5 | ✓ | ✓ |
| 6 | Zero-Metadata Disk Persistence | Req 2 (Zero disk logs, atomic rename, cleanup) | 5 | 5 | ✓ | ✓ |
| 7 | TCP Binary Framing Protocol | Req 1 (Framed chunks, error handling) | 5 | 5 | ✓ | ✓ |
| 8 | Memory-Bounded Streaming (<200MB RSS) | Req 1 (1GB+ stream <200MB overhead) | 5 | 5 | ✓ | ✓ |
| 9 | Incremental SHA-256 Digest | Req 1 (Bit-for-bit file integrity) | 5 | 5 | ✓ | ✓ |
| 10 | EWMA Speed & Real-time ETA | Req 1 (Real-time speed/progress metrics) | 5 | 5 | ✓ | ✓ |
| 11 | Multi-Tier Discovery (mDNS + UDP + IP:Port) | Req 3 (Discovery <10s + fallback) | 5 | 5 | ✓ | ✓ |
| 12 | Flutter Native UI & State Visualization | Req 4 (Material 3 UI, progress, settings) | 5 | 5 | ✓ | ✓ |

## Test Architecture
- **Test Runner**: Pure Dart VM and Flutter test runners.
  - Command: `dart test test/run_all_tests.dart` or `flutter test`
  - Pass/Fail Semantics: Zero exit code, all assertions passing, zero memory leaks.
- **Directory Layout**:
  - `test/unit/` — Unit tests for crypto, framing, SAS, speed calculations, discovery beacons.
  - `test/integration/` — E2E loopback transfer tests (100MB, 1GB), memory bounds assertions, backpressure tests, network fault recovery.
  - `test/widget/` — Flutter UI component tests (discovery radar, device cards, SAS dialog, progress bar).
  - `test/mocks/` — Mock discovery network sockets, throttled sinks.
  - `test/run_all_tests.dart` — Unified entry point orchestrating all suites.

## Real-World Application Scenarios (Tier 4)
| # | Scenario | Features Exercised | Complexity |
|---|----------|--------------------|------------|
| 1 | Multi-Gigabyte ISO Image Transfer (1GB+) | F1, F2, F3, F7, F8, F9, F10 | High |
| 2 | High-Concurrency Rapid Small Files (100 files < 1KB) | F1, F3, F4, F6, F7, F9 | Medium |
| 3 | Simulated Malicious MITM Interception (SAS mismatch abort) | F1, F2, F5, F6 | High |
| 4 | Network Dropout & Mid-Transfer Cancellation Cleanup | F6, F7, F8, F10, F14 | Medium |
| 5 | Multicast-Blocked LAN UDP Fallback Discovery & Transfer | F11, F15, F16, F18, F19 | Medium |

## Coverage Thresholds
- Tier 1: $\ge 5$ test cases per feature (Total: $12 \times 5 = 60$ cases)
- Tier 2: $\ge 5$ boundary/corner cases per feature (Total: $12 \times 5 = 60$ cases)
- Tier 3: Pairwise combinations of major features (Total: $\ge 12$ cases)
- Tier 4: $\ge 5$ realistic end-to-end workload scenarios
- **Total Minimum Test Count: $\ge 137$ test cases**
