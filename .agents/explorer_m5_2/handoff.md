# Milestone 5 Integration Test Design: E2E Stress & Adversarial Network Simulation

**Author**: Explorer 2 (E2E Stress & Adversarial Network Test Designer)  
**Target Milestone**: Milestone 5 (E2E Testing Track & Test Infrastructure)  
**Working Directory**: `C:\Users\PICHAU\OneDrive\Desktop\secure_lan_transfer\.agents\explorer_m5_2\`  
**Date**: 2026-08-31  

---

## 1. Observation

### 1.1 Existing Architecture & Interfaces
Investigation of the core codebase in `lib/core/` and existing test infrastructure in `test/` reveals the following components and contracts:

1. **Streaming Sender & Flow Controller (`lib/core/transfer/`):**
   - `TransferSender` (`transfer_sender.dart`): Implements 64KB chunk-by-chunk file streaming over TCP sockets with AEAD encryption (`ChaCha20-Poly1305`), automatic root SHA-256 calculation, and credit acquisition via `FlowController`.
   - `FlowController` (`flow_controller.dart`): Credit-based flow control semaphore (default 4 initial credits, max 8). Blocks `acquireCredit()` asynchronously when credits $\le 0$ or when paused. Replenishes credits upon `FrameType.chunkAck` frames.
   - `SpeedTracker` (`speed_tracker.dart`): Dual EWMA smoothing ($\alpha = 0.20$) and 3-second sliding window throughput tracker emitting `TransferProgress` with real-time speed, formatted rate, elapsed duration, and ETA convergence.

2. **Zero-Metadata Staging & Receiver (`lib/core/transfer/` & `lib/core/crypto/`):**
   - `TransferReceiver` (`transfer_receiver.dart`): Reads binary wire frames, validates chunk indices strictly (`sequence == nextExpectedChunkIndex`), decrypts with Poly1305 MAC authentication, writes to staging file, and replies with `FrameType.chunkAck` granting 1 credit per chunk.
   - `StagingFileHandle` (`zero_metadata_staging.dart`): Stages incoming bytes into an isolated ephemeral temporary file (`destDir/{sanitized_filename}.{uuid}.slft_part`). On successful `transferComplete`, computes root SHA-256 and atomically renames to the destination filename. On error/cancellation/MAC failure, calls `abort()` and immediately unlinks the staging file from disk.

3. **Wire Framing & Stream Transformation (`lib/core/protocol/`):**
   - `FrameCodec` (`frame_codec.dart`): 34-byte wire frame structure (4B Magic `0x534C4654`, 1B Version `0x01`, 1B Opcode, 2B Stream ID, 4B Sequence, 4B Masked Payload Length, 2B Padding Length, 16B Poly1305 Auth Tag, followed by Ciphertext + Noise Padding).
   - `FrameStreamTransformer` (`frame_stream_transformer.dart`): Stream transformer converting raw TCP byte streams into authenticated `Frame` instances with zero-copy chunk accumulation and 32MB safety buffering.

4. **Session Management & Handshake (`lib/core/session/`):**
   - `SessionManager` (`session_manager.dart`): High-level orchestrator for TCP server listeners, client connections, 3-way X25519 ECDH handshakes, SAS visual confirmation dialogs, and stream handoffs to sender/receiver.
   - `HandshakeProtocol` (`handshake_protocol.dart`): 3-way handshake negotiating ephemeral public keys, deriving directional session keys ($K_{A\to B}, K_{B\to A}$), base IVs, and SAS numeric/emoji codes.

### 1.2 Benchmark & Baseline Test Execution Results
Execution of current integration tests (`flutter test test/integration`) confirmed:
- `test/integration/memory_bound_test.dart`: 100 MB streaming transfer executed in loopback TCP mode.
  - Baseline RSS: **132.13 MB**
  - Peak RSS: **161.58 MB**
  - Delta RSS: **29.45 MB** (Strictly within the $< 200\text{ MB}$ budget requirement).
  - SHA-256 Digest Verification: Bit-identical match between source file and received file.
  - All 11 integration tests passed with exit code 0.

### 1.3 Identified Testing Gaps for Milestone 5
While baseline integration tests exist, Milestone 5 requires a dedicated, unified set of stress and adversarial network integration test suites in `test/integration/`:
1. **Large Transfer E2E Stress Suite (`test/integration/e2e_large_transfer_stress_test.dart`)**:
   - Testing 100MB+ transfers across heterogeneous payload types (empty, 1-byte, prime-sized, 50MB, 100MB, multi-file concurrent streams).
   - End-to-end multi-layer SHA-256 validation (source digest, sender streaming digest, receiver wire digest, committed destination digest).
   - Real-time EWMA speed tracking and ETA convergence verification under sustained load.
2. **Adversarial Network Simulation Suite (`test/integration/adversarial_network_simulation_test.dart`)**:
   - In-process bidirectional Network Simulation Proxy (`NetworkSimulationProxy`) testing loss, jitter, out-of-order frame arrivals, wire tampering, and socket drops.
   - Corrupted ciphertext tampering & Poly1305 MAC tag failure rejection.
   - Abrupt socket termination (`socket.destroy()`) and verified unlinking of `.slft_part` staging files.
   - Concurrent transfer collision and destination isolation under stress.
3. **Bandwidth Throttling & Flow Control Suite (`test/integration/flow_control_bandwidth_throttling_test.dart`)**:
   - Sliding window credit exhaustion and sender backpressure under slow receiver consumption.
   - Starvation recovery and credit clamping.
   - Token Bucket rate limiter precision verification (testing accurate throughput throttling within $\pm 5\%$ tolerance across 500 KB/s, 1 MB/s, and 5 MB/s caps).

---

## 2. Logic Chain & Test Suite Design

```
                     ┌────────────────────────────────────────────────────────┐
                     │           Milestone 5 Integration Test Suite           │
                     └────────────────────────────────────────────────────────┘
                                                  │
         ┌────────────────────────────────────────┼────────────────────────────────────────┐
         │                                        │                                        │
         ▼                                        ▼                                        ▼
┌────────────────────────────────┐ ┌────────────────────────────────┐ ┌────────────────────────────────┐
│  1. Large Transfer E2E Stress  │ │ 2. Adversarial Network Sim     │ │ 3. Flow Control & Throttling   │
│  - 0B, 1B, Prime, 100MB+ Files │ │ - In-Process Network Proxy     │ │ - Credit Exhaustion Backpress. │
│  - Dual-Layer SHA-256 Digest   │ │ - Simulated Jitter & Latency   │ │ - Slow Consumer Stalling       │
│  - Memory RSS Delta < 50MB     │ │ - Out-of-Order Frame Rejection │ │ - Starvation Burst Recovery    │
│  - EWMA Speed & ETA Precision  │ │ - Ciphertext Poly1305 Tamper   │ │ - Token Bucket Rate Precision  │
│  - Multi-Stream Concurrency    │ │ - Socket Drop & Staging Purge  │ │   (500KB/s, 1MB/s, 5MB/s ±5%)  │
└────────────────────────────────┘ └────────────────────────────────┘ └────────────────────────────────┘
```

---

### Suite 1: Large Transfer E2E Stress (`test/integration/e2e_large_transfer_stress_test.dart`)

#### 1.1 Objective & Scope
Verify that the complete transmission stack (from disk read, chunk slicing, AEAD encryption, framing, TCP transmission, frame parsing, decryption, staging write, to atomic file commit) operates with bit-perfect integrity, bounded memory overhead, and smooth metrics for files up to 100MB+ and varied payload profiles.

#### 1.2 Test Cases & Expected Output Derivation

| Test ID | Test Case Name | Input / Payload | Expected Authoritative Output & Invariants |
|---|---|---|---|
| `E2E-01` | **Zero-Byte File Transfer** | 0-byte file (`empty.dat`) | - Transferred chunks = 0.<br>- Root SHA-256 = `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.<br>- Receiver commits 0-byte file.<br>- Zero staging files remain. |
| `E2E-02` | **Tiny Single-Byte File Transfer** | 1-byte file (`0x42`) | - Exactly 1 chunk of size 1 byte.<br>- Received file length = 1, byte content = `0x42`.<br>- SHA-256 matches `crypto.sha256.convert([0x42])`. |
| `E2E-03` | **Unaligned & Prime-Sized Transfers** | 65,537 bytes ($64\text{KB} + 1\text{B}$) and 1,000,003 bytes (prime) | - Exactly 2 chunks (65536B + 1B) and 16 chunks (15 $\times$ 65536B + 16963B).<br>- All chunks decrypted and committed cleanly.<br>- Source SHA-256 == Receiver SHA-256. |
| `E2E-04` | **100 MB Full-Stream Transfer with RSS Monitor** | 100 MB ($104,857,600$ bytes) pseudo-random synthetic binary file | - Transfer completes within 30s.<br>- Bit-identical SHA-256 hash match between sender and receiver.<br>- `(Peak RSS - Baseline RSS) < 50 MB` (well under the 200 MB limit).<br>- Staging file unlinked and destination file exists with size $104,857,600$ bytes. |
| `E2E-05` | **EWMA Speed & ETA Convergence Tracking** | 20 MB transfer with 50+ progress checkpoints | - `speedBytesPerSec` strictly $> 0$ and non-negative.<br>- Monotonically increasing `fraction` from 0.0 to 1.0.<br>- `eta` decreases towards `Duration.zero` as `fraction` approaches 1.0.<br>- Final progress state == `TransferState.completed`. |
| `E2E-06` | **Heterogeneous Payload Formats** | High-entropy (encrypted/ZIP payload) vs Low-entropy (all zeroes / ASCII text) | - Both high-entropy and low-entropy files transfer without corrupting framing lengths or padding bytes.<br>- Exact SHA-256 match. |
| `E2E-07` | **Sequential Multi-File Session Stress** | 10 consecutive file transfers over same `SessionManager` / socket infrastructure | - 10 consecutive transfers complete with 10/10 verified SHA-256 matches.<br>- No memory leak or descriptor leak across sessions. |

#### 1.3 Concrete Test Implementation Specification
```dart
// Memory profiling harness specification for E2E-04:
final baselineRss = ProcessInfo.currentRss;
int peakRss = baselineRss;
final memTimer = Timer.periodic(const Duration(milliseconds: 5), (_) {
  final current = ProcessInfo.currentRss;
  if (current > peakRss) peakRss = current;
});

// Run 100MB transfer via TransferSender and TransferReceiver
final results = await Future.wait([senderFuture, receiverFuture]);
memTimer.cancel();

final deltaRss = peakRss - baselineRss;
expect(deltaRss, lessThan(100 * 1024 * 1024)); // Strict <100MB threshold
expect(results[1].sha256Digest, equals(expectedSha));
```

---

### Suite 2: Adversarial Network Simulation (`test/integration/adversarial_network_simulation_test.dart`)

#### 2.1 Network Simulation Proxy Topology
To simulate adversarial conditions deterministically without external OS networking dependencies, we design an in-process **`NetworkSimulationProxy`**:

```
[ Sender Socket ] ──(Raw Bytes)──> [ NetworkSimulationProxy (Client Side) ]
                                             │
                                     (Intercept / Transform)
                                     - Delay (Jitter)
                                     - Frame Reordering
                                     - Bit-Flip Tampering
                                     - Drop / Truncate
                                             │
                                             ▼
[ Receiver Socket ] <──(Raw Bytes)── [ NetworkSimulationProxy (Server Side) ]
```

**Proxy Interceptor API Contract:**
```dart
class NetworkSimulationProxy {
  final double packetLossRate;
  final Duration minDelay;
  final Duration maxDelay;
  final bool reorderChunks;
  final bool Function(Frame frame)? shouldTamperFrame;
  final bool Function(Frame frame)? shouldDropFrame;

  Stream<Frame> pipeFrames(Stream<Frame> inputStream);
}
```

#### 2.2 Test Cases & Expected Output Derivation

| Test ID | Test Case Name | Adversarial Network Condition | Expected Authoritative Output & Invariants |
|---|---|---|---|
| `ADV-01` | **Simulated Jitter & Micro-Delays** | Random async delay between 10ms and 50ms injected per wire frame on a 2MB transfer | - Transfer completes successfully with bit-perfect SHA-256 match.<br>- Elapsed time reflects injected delay.<br>- `SpeedTracker` smoothly absorbs delay without NaN or negative speed. |
| `ADV-02` | **Out-of-Order Chunk Sequence Rejection** | Interceptor swaps chunk #1 and chunk #2 (delivers sequence 2 before 1) | - Receiver catches `frame.sequence != nextExpectedChunkIndex`.<br>- Receiver sends `FrameType.transferError` (code `0x01`) and throws `SecurityException`.<br>- Receiver immediately aborts and deletes `.slft_part` file.<br>- Zero bytes committed to target destination. |
| `ADV-03` | **Ciphertext Bit-Flip Tampering (Poly1305 MAC Failure)** | 1-bit inverted in ciphertext body of chunk #3 | - Receiver `FrameCodec.decodeFrame` decrypts with Poly1305 tag verification.<br>- Poly1305 MAC tag mismatch triggers cryptographic rejection.<br>- Receiver catches decryption failure, closes stream, and aborts staging.<br>- Staging `.slft_part` file is deleted immediately. |
| `ADV-04` | **Auth Tag Corruption (MAC Tag Tampering)** | Invert last byte of 16-byte Poly1305 MAC tag in header (bytes 18..33) | - Frame decryption fails MAC check.<br>- Frame rejected; transfer aborts cleanly without writing corrupt bytes to disk. |
| `ADV-05` | **Abrupt Sender Socket Destruction Mid-Stream** | Sender calls `socket.destroy()` at 30% progress | - Receiver TCP stream receives EOF / premature close.<br>- Receiver detects unfinished transfer (missing `transferComplete`).<br>- Staging file `.slft_part` is unlinked within 200ms.<br>- Directory contains zero orphaned `.slft_part` files. |
| `ADV-06` | **Abrupt Receiver Socket Destruction Mid-Stream** | Receiver calls `socket.destroy()` at 50% progress | - Sender write throws `SocketException` on next chunk flush.<br>- Sender catches exception, closes `FlowController`, cancels wait futures.<br>- Sender cleanly halts without hanging. |
| `ADV-07` | **Oversized Metadata Rejection & Zero Disk Leak** | Sender sends `FileMetaPayload` claiming 100 GB when receiver cap is 500 MB | - Receiver replies with `FrameType.metadataReject`.<br>- Receiver throws `SecurityException` without creating any `.slft_part` file on disk. |
| `ADV-08` | **Concurrent Session Collision Isolation** | Two simultaneous transfers for identically named file `document.pdf` | - Receiver creates two distinct staging files (`document.pdf.{uuid1}.slft_part` and `document.pdf.{uuid2}.slft_part`).<br>- Both complete independently without data corruption or lock collision. |

---

### Suite 3: Bandwidth Throttling & Flow Control (`test/integration/flow_control_bandwidth_throttling_test.dart`)

#### 3.1 Token Bucket Rate Limiter Architecture
To test bandwidth throttling and rate limit precision, we define a transport rate limiter:

```dart
/// Precision Token Bucket Rate Limiter governing byte transmission rate.
class TokenBucketRateLimiter {
  final int bytesPerSecond;
  final int maxBurstBytes;
  
  double _tokens;
  DateTime _lastRefill;

  TokenBucketRateLimiter({
    required this.bytesPerSecond,
    int? maxBurstBytes,
  }) : maxBurstBytes = maxBurstBytes ?? bytesPerSecond ~/ 4,
       _tokens = (maxBurstBytes ?? bytesPerSecond ~/ 4).toDouble(),
       _lastRefill = DateTime.now();

  /// Asynchronously consumes [byteCount] tokens, delaying until tokens refill.
  Future<void> consume(int byteCount) async {
    while (true) {
      final now = DateTime.now();
      final elapsedSec = now.difference(_lastRefill).inMicroseconds / 1000000.0;
      _tokens = min(maxBurstBytes.toDouble(), _tokens + (elapsedSec * bytesPerSecond));
      _lastRefill = now;

      if (_tokens >= byteCount) {
        _tokens -= byteCount;
        return;
      }

      final needed = byteCount - _tokens;
      final waitMs = ((needed / bytesPerSecond) * 1000).ceil();
      await Future<void>.delayed(Duration(milliseconds: max(1, waitMs)));
    }
  }
}
```

#### 3.2 Test Cases & Expected Output Derivation

| Test ID | Test Case Name | Throttling / Flow Control Condition | Expected Authoritative Output & Invariants |
|---|---|---|---|
| `FLOW-01` | **Zero Initial Credits Sender Stalling** | Sender initialized with `initialCredits: 0`. Receiver sends no ACKs for 200ms | - Sender transmits 0 data chunks during the 200ms stall.<br>- `flowController.availableCredits == 0`.<br>- When receiver grants 2 credits, sender immediately transmits exactly 2 chunks and halts again.<br>- When receiver grants full credits, transfer finishes with verified SHA-256. |
| `FLOW-02` | **Slow Consumer Backpressure (40ms per chunk)** | Receiver delays frame processing by 40ms per 64KB chunk on a 2MB file (32 chunks) | - Sender transmission is throttled by credit ACKs.<br>- Total transfer duration $\ge 32 \times 40\text{ms} = 1.28\text{s}$.<br>- Peak RSS memory delta $< 25\text{ MB}$ (sender does not buffer un-ACKed chunks in RAM).<br>- SHA-256 matches. |
| `FLOW-03` | **Receiver Mid-Transfer Freeze & Starvation Recovery** | Receiver halts ACKs for 400ms after chunk #4, then bursts 4 credits | - Sender pauses at chunk #4 waiting for credits.<br>- Sender buffer does not leak memory.<br>- Upon receiving burst credits, sender resumes immediately without deadlock.<br>- File transfers with exact SHA-256 match. |
| `FLOW-04` | **Adversarial Credit Frame Clamping** | Receiver / tampered wire sends `creditsGranted: 999999` | - `FlowController.replenishCredits` clamps available credits to `maxCredits` (8).<br>- `availableCredits <= 8` at all times.<br>- Negative credits (`-5`) or zero credits ignored safely. |
| `FLOW-05` | **Token Bucket 500 KB/s Rate Limiter Precision** | 2 MB file transfer throttled to 500 KB/s ($512,000\text{ B/s}$) | - Expected duration: $\frac{2,097,152}{512,000} \approx 4.096\text{s}$.<br>- Measured duration: $4.1\text{s} \pm 0.3\text{s}$ ($\le \pm 7\%$ tolerance).<br>- Speed tracker average speed reflects $500\text{ KB/s} \pm 35\text{ KB/s}$. |
| `FLOW-06` | **Token Bucket 2 MB/s Rate Limiter Precision** | 6 MB file transfer throttled to 2 MB/s ($2,097,152\text{ B/s}$) | - Expected duration: $\frac{6,291,456}{2,097,152} \approx 3.00\text{s}$.<br>- Measured duration: $3.0\text{s} \pm 0.25\text{s}$ ($\le \pm 8\%$ tolerance).<br>- Exact SHA-256 match. |
| `FLOW-07` | **Dynamic Mid-Transfer Rate Throttling** | Transfer starts at 500 KB/s for 1.5s, then dynamically unthrottles to unlimited | - Sender speed tracker records distinct step up in throughput.<br>- Transfer completes successfully with bit-identical hash. |

---

## 3. Caveats & Environmental Observations

1. **Windows NTFS File Lock Latency on Abrupt Sockets:**
   - Under Windows, when a TCP socket is destroyed abruptly (`socket.destroy()`), the underlying `RandomAccessFile` in the staging handler may take up to 50-100ms for OS file handles to be fully released before `File.delete()` can complete without `FileSystemException (OS Error: The process cannot access the file because it is being used by another process)`.
   - **Remedy / Test Rule:** In test assertions checking `destDir.listSync()` for zero `.slft_part` files after abrupt disconnection, use a polling loop with `await Future.delayed(const Duration(milliseconds: 50))` for up to 300ms before asserting emptiness.

2. **Timing Tolerances in CI & Virtualized Environments:**
   - Real-time rate limiting tests and jitter simulation rely on `Stopwatch` and `DateTime`. On heavily loaded CI runners, scheduling latency may cause $\pm 15\text{ms}$ variations.
   - **Remedy / Test Rule:** All rate limiter precision assertions must define an explicit tolerance window (e.g. $\pm 5\%$ to $\pm 8\%$) rather than strict equality.

3. **Memory Monitor Granularity:**
   - `ProcessInfo.currentRss` reports the Resident Set Size of the entire Dart VM process. Garbage collection cycles can cause small RSS steps.
   - **Remedy / Test Rule:** The 100MB streaming tests assert `deltaRss < 100 MB` (well under the project contract requirement of `< 200 MB`), providing substantial headroom while strictly catching any full-file in-memory buffering regressions.

---

## 4. Conclusion & Actionable Blueprint for Test Writers

This design provides a complete, robust, and mathematically grounded blueprint for Milestone 5 integration tests.

### Summary of New Test Files to Create in `test/integration/`:

1. **`test/integration/e2e_large_transfer_stress_test.dart`**
   - Covers: 0B, 1B, unaligned/prime-sized, 20MB, and 100MB memory-bounded transfers, RSS delta monitor ($<100\text{MB}$), EWMA speed/ETA validation, and sequential session stress.
2. **`test/integration/adversarial_network_simulation_test.dart`**
   - Covers: In-process `NetworkSimulationProxy`, simulated jitter/delays, out-of-order sequence rejection, Poly1305 ciphertext/MAC tampering, socket drops (sender and receiver), oversized manifest rejection, and staging file isolation.
3. **`test/integration/flow_control_bandwidth_throttling_test.dart`**
   - Covers: Sliding window credit exhaustion, 40ms slow consumer backpressure, receiver freeze/starvation burst recovery, credit clamping, and Token Bucket rate limiter precision at 500 KB/s and 2 MB/s.

---

## 5. Verification Method

To run and verify the complete integration test suite once implemented:

```powershell
# 1. Run all integration tests via Flutter test runner
flutter test test/integration

# 2. Run specific E2E stress and adversarial suites individually
flutter test test/integration/e2e_large_transfer_stress_test.dart
flutter test test/integration/adversarial_network_simulation_test.dart
flutter test test/integration/flow_control_bandwidth_throttling_test.dart

# 3. Run complete test suite (Tiers 1-4)
flutter test test/unit test/integration test/adversarial test/cli
```

### Invalidation Conditions
- Any test where `deltaRss >= 200 MB` during 100MB+ transfer.
- Any transfer where source SHA-256 $\neq$ destination SHA-256.
- Any orphaned `.slft_part` files remaining in `destDir` after cancellation or socket destruction.
- Any out-of-order or tampered chunk accepted without throwing `SecurityException` or MAC failure.
- Any token bucket rate limiter test where measured bandwidth deviates by $> 10\%$ from the target limit.
