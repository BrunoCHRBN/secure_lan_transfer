# Project: Secure LAN File Transfer (SLFT)

## Architecture
A production-quality, cross-platform secure LAN file transfer application built with Flutter for the UI and a pure Dart core engine for headless CLI and automated testing.

```
secure_lan_transfer/
├── bin/
│   └── secure_transfer_cli.dart          # Headless CLI for sender/receiver and benchmarks
├── lib/
│   ├── main.dart                         # Flutter UI Entry Point
│   ├── core/                             # Pure Dart Core Engine (no UI dependencies)
│   │   ├── crypto/                       # X25519, HKDF-SHA256, ChaCha20-Poly1305, SAS
│   │   ├── protocol/                     # Framing codec, packet types, session FSM
│   │   ├── transfer/                     # Memory-bounded stream sender/receiver, speed & SHA-256
│   │   ├── discovery/                    # mDNS advertiser/browser, UDP broadcast beacon, manual IP
│   │   └── models/                       # PeerDevice, FilePayload, TransferProgress
│   └── ui/                               # Flutter Material 3 UI
│       ├── theme/                        # Modern responsive dark/light styling
│       ├── providers/                    # UI state controllers & notifiers
│       ├── screens/                      # Home, Transfer, Settings screens
│       └── widgets/                      # Device cards, SAS verification badge, Progress visualizer
└── test/                                 # Unified test suite
    ├── unit/                             # Crypto, protocol, discovery unit tests
    ├── integration/                      # E2E transfer, memory bounding, flow control tests
    ├── widget/                           # Flutter UI component tests
    ├── adversarial/                      # Adversarial challenge suites
    └── run_all_tests.dart                # Single-command unified test runner
```

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Ephemeral Key Exchange (X25519) | Zero pre-shared secrets, ephemeral ECDH over Curve25519 with PFS | M1 (DONE) | Survey (Spec Miner 2) |
| 2 | Key Derivation (HKDF-SHA256) | Derives directional session keys ($K_{A\to B}, K_{B\to A}$), base IVs, and mask keys | M1 (DONE) | Survey (Spec Miner 2) |
| 3 | Authenticated Encryption (ChaCha20-Poly1305) | 256-bit AEAD with 16-byte Poly1305 MAC tag per chunk & AES-GCM fallback | M1 (DONE) | Survey (Spec Miner 2) |
| 4 | Monotonic Nonce Construction | Deterministic 96-bit nonce from base IV $\oplus$ counter injected into AAD | M1 (DONE) | Survey (Spec Miner 2) |
| 5 | Short Authentication String (SAS) | 6-digit decimal code and 4-visual emoji tuple derived from transcript hash | M1 (DONE) | Survey (Spec Miner 2) |
| 6 | Traffic Obfuscation & Noise Padding | ChaCha20 length prefix masking, CSPRNG jitter handshake (96-160B), uniform 64KB/1024B frames (Entropy $\ge 7.995$ bits/byte) | M1 (DONE) | Survey (Spec Miner 2) |
| 7 | Zero-Metadata Disk Policy & Hygiene | In-memory ephemeral keys, zero persistent disk logs, atomic `.part` staging & immediate unlink on abort | M1 (DONE) | Survey (Spec Miner 2) |
| 8 | Path Traversal Sanitization | Strips relative path tokens (`..`, `/`, `\`), Unicode Bidi/RLO, and illegal characters | M1 (DONE) | Survey (Spec Miner 2) |
| 9 | TCP Binary Framing Protocol | 34-byte binary wire frame header with magic, version, frame type, sequence, stream ID, payload len, padding len, auth tag | M2 | Survey (Spec Miner 3) |
| 10 | Memory-Bounded Streaming Pipeline | Chunk-by-chunk read-encrypt-send and receive-decrypt-write pipeline guaranteeing $<200\text{ MB}$ RSS overhead for 1GB+ files | M2 | Survey (Spec Miner 3) |
| 11 | Reactive Backpressure & Flow Control | Credit-based windowing (max 4-8 in-flight chunks) and `StreamSubscription.pause()` / `Socket.flush()` synchronization | M2 | Survey (Spec Miner 3) |
| 12 | Incremental SHA-256 Verification | Dual-layer verification: per-chunk hash and cumulative full-file root digest | M2 | Survey (Spec Miner 3) |
| 13 | Speed Smoothing & Real-Time ETA | EWMA speed smoothing ($\alpha = 0.20$) + 3s sliding window and robust ETA formatting | M2 | Survey (Spec Miner 3) |
| 14 | Transfer State Machine | 7-state deterministic FSM (IDLE, CONNECTING, HANDSHAKING, TRANSFERRING, PAUSED, VERIFYING, COMPLETED, ERROR, CANCELLED) | M2 | Survey (Spec Miner 3) |
| 15 | Primary mDNS / DNS-SD Discovery | Multicast DNS discovery on `_securetransfer._tcp.local` (<2s latency) | M3 | Survey (Spec Miner 3) |
| 16 | Secondary UDP Broadcast Fallback | LAN UDP broadcast beacon on `255.255.255.255:42386` every 2.5s for restricted routers | M3 | Survey (Spec Miner 3) |
| 17 | Tertiary Manual IP:Port Fallback | Direct TCP connection to user-entered IP and port | M3 | Survey (Spec Miner 3) |
| 18 | Dynamic Device Registry & Stale Pruning | Reactive device catalog tracking online state, stale marking (12s), and pruning (25s) | M3 | Survey (Spec Miner 3) |
| 19 | Session Manager & Handshake Orchestration | End-to-end connection orchestration, pairing negotiation, and SAS verification flow | M3 | Survey (Spec Miner 3) |
| 20 | Flutter Native UI (Material 3) | Clean, responsive UI with Radar Discovery, Device List, File Picker, Transfer Visualizer, Settings | M4 | Survey (Explorer 1) |
| 21 | SAS Visual Verification UI | Modal dialog displaying 6-digit code and 4-emoji badge for out-of-band visual confirmation | M4 | Survey (Explorer 1) |
| 22 | Headless CLI Tool | Standalone CLI (`bin/secure_transfer_cli.dart`) for automated headless send/receive | M4 | Survey (Explorer 1) |
| 23 | Single-Command Automated Test Suite | Unified test runner verifying crypto, framing, discovery, 1GB+ memory bounds, and integrity | M5 | Survey (Explorer 1 & Spec Miner 3) |
| 24 | E2E Transfer Verification & Adversarial Hardening | Phase 1: 100% pass of Tiers 1-4 tests; Phase 2: Tier 5 adversarial coverage hardening | Final Milestone | Survey (Top-Level) |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Project Setup & Core Cryptography Engine | Flutter project creation (`pubspec.yaml`), X25519, HKDF-SHA256, ChaCha20-Poly1305, SAS generation, obfuscation padding, zero-meta staging | none | DONE (83/83 tests pass) |
| M2 | Memory-Bounded Network Streaming Engine | TCP binary wire framing codec, chunked streaming sender/receiver with backpressure, SHA-256 integrity, EWMA speed & ETA, FSM | M1 | DONE (146/146 tests pass) |
| M3 | Device Discovery Subsystem & Session Manager | mDNS discovery, UDP broadcast fallback, manual IP:port, reactive device registry, session manager | M1, M2 | PLANNED |
| M4 | Flutter Material 3 UI & Headless CLI | Responsive Flutter UI, SAS visual confirmation dialog, radar discovery, transfer progress visualizer, settings screen, headless CLI | M1, M2, M3 | PLANNED |
| M5 | E2E Testing Track & Test Infrastructure | Test harness (Tiers 1-4), mock discovery, synthetic 100MB/1GB stream generator, memory monitor assertions, unified test runner | M1, M2, M3, M4 | PLANNED |
| Final | Final Milestone (E2E Pass & Adversarial Hardening) | Phase 1: Pass 100% of E2E tests (Tiers 1-4); Phase 2: Tier 5 adversarial coverage hardening with Challenger loop | M1, M2, M3, M4, M5 | PLANNED |

## Interface Contracts
### `lib/core/crypto/` ↔ `lib/core/protocol/` & `lib/core/transfer/`
- `CipherSuite`: `Future<EphemeralKeyPairData> generateKeyPair()`, `Future<Uint8List> computeSharedSecret(PrivateKey local, PublicKey remote)`, `SessionKeys deriveSessionKeys(Uint8List sharedSecret, Uint8List salt)`, `Uint8List encryptChunk(...)`, `Uint8List decryptChunk(...)`.
- `SasAuthenticator`: `SasCode computeSas(Uint8List transcriptHash)` returning `String numericCode` (e.g. "482-913") and `List<String> emojis` (e.g. `["🦊", "⚡", "🪐", "💎"]`).
- `TrafficObfuscator`: `Uint8List maskLengthPrefixSync(int length, Uint8List maskKey, Uint8List nonce)`, `int unmaskLengthPrefixSync(Uint8List masked, Uint8List maskKey, Uint8List nonce)`, `Uint8List padPayload(Uint8List data, int targetSize)`.
- `StagingFileHandle`: `Future<StagingFileHandle> create(Directory destDir, String filename, int totalBytes, String expectedSha256, {bool secureWipeOnAbort = false})`, `Future<void> writeChunk(Uint8List chunk)`, `Future<File> commitAndVerify()`, `Future<void> abort()`.

### `lib/core/protocol/` ↔ `lib/core/transfer/`
- `FrameCodec`: `Uint8List encodeFrame(Frame frame, SessionKeys? keys)`, `Stream<Frame> decodeFrameStream(Stream<Uint8List> byteStream, SessionKeys? keys)`.
- `Frame`: `FrameType type`, `int streamId`, `int sequenceOrChunkIndex`, `Uint8List payload`, `int paddingLen`.

### `lib/core/transfer/` ↔ `lib/ui/`
- `TransferSender`: `Future<void> sendFile(File file, Socket socket, SessionKeys keys, {Function(TransferProgress) onProgress})`.
- `TransferReceiver`: `Future<File> receiveFile(Directory destDir, Socket socket, SessionKeys keys, {Function(TransferProgress) onProgress})`.
- `TransferProgress`: `int transferredBytes`, `int totalBytes`, `double fraction`, `double speedBytesPerSec`, `String speedFormatted`, `Duration? eta`, `String etaFormatted`, `TransferState state`.

### `lib/core/discovery/` ↔ `lib/ui/`
- `DiscoveryManager`: `Future<void> startDiscovery()`, `Future<void> stopDiscovery()`, `Stream<List<DiscoveredDevice>> get devicesStream`, `Future<void> broadcastPresence()`.

## Code Layout
- `bin/secure_transfer_cli.dart` — Standalone CLI entrypoint.
- `lib/main.dart` — Flutter entrypoint.
- `lib/core/crypto/` — Cryptography & Obfuscation (DONE).
- `lib/core/protocol/` — Wire frame encoding/decoding & FSM.
- `lib/core/transfer/` — Memory-bounded streaming sender & receiver.
- `lib/core/discovery/` — mDNS & UDP discovery.
- `lib/core/models/` — Data models.
- `lib/ui/screens/` — UI screens.
- `lib/ui/widgets/` — UI reusable widgets.
- `test/` — Unit, integration, widget tests & `run_all_tests.dart`.
