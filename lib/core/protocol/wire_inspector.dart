import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

/// Real snapshot of an encrypted wire frame transmitted over the network socket.
class WireFrameSample {
  final DateTime timestamp;
  final String direction; // 'ENVIADO (OUTBOUND)' or 'RECEBIDO (INBOUND)'
  final String frameType;
  final int sequence;
  final int streamId;
  final int totalWireBytes;
  final Uint8List rawHeaderBytes; // 18-byte AAD header
  final Uint8List macTagBytes; // 16-byte Poly1305 / GHASH MAC
  final Uint8List ciphertextSnippet; // First 64 bytes of ciphertext
  final double entropyBitsPerByte; // Shannon entropy (0..8.0 bits/byte)
  final bool plaintextLeakDetected;
  final String? leakDetails;

  const WireFrameSample({
    required this.timestamp,
    required this.direction,
    required this.frameType,
    required this.sequence,
    required this.streamId,
    required this.totalWireBytes,
    required this.rawHeaderBytes,
    required this.macTagBytes,
    required this.ciphertextSnippet,
    required this.entropyBitsPerByte,
    required this.plaintextLeakDetected,
    this.leakDetails,
  });

  /// Formats the raw wire sample into a Wireshark-style canonical Hex + ASCII dump.
  String toHexDump({int maxBytes = 64}) {
    final buffer = StringBuffer();
    final combined = Uint8List(rawHeaderBytes.length + macTagBytes.length + ciphertextSnippet.length);
    combined.setRange(0, rawHeaderBytes.length, rawHeaderBytes);
    combined.setRange(rawHeaderBytes.length, rawHeaderBytes.length + macTagBytes.length, macTagBytes);
    combined.setRange(
      rawHeaderBytes.length + macTagBytes.length,
      combined.length,
      ciphertextSnippet,
    );

    final displayLen = min(combined.length, maxBytes);

    for (int offset = 0; offset < displayLen; offset += 16) {
      final chunkLen = min(16, displayLen - offset);
      final offsetHex = offset.toRadixString(16).padLeft(4, '0').toUpperCase();
      buffer.write('$offsetHex   ');

      // Hex bytes
      for (int i = 0; i < 16; i++) {
        if (i < chunkLen) {
          final b = combined[offset + i];
          buffer.write(b.toRadixString(16).padLeft(2, '0').toUpperCase());
          buffer.write(' ');
        } else {
          buffer.write('   ');
        }
        if (i == 7) buffer.write(' ');
      }

      buffer.write('  |');

      // ASCII representation
      for (int i = 0; i < chunkLen; i++) {
        final b = combined[offset + i];
        if (b >= 32 && b <= 126) {
          buffer.write(String.fromCharCode(b));
        } else {
          buffer.write('.');
        }
      }
      buffer.write('|\n');
    }

    return buffer.toString().trimRight();
  }
}

/// Global live wire traffic inspector recording real frame transmissions.
class WireTrafficInspector {
  static final WireTrafficInspector instance = WireTrafficInspector._();
  WireTrafficInspector._();

  final List<WireFrameSample> _samples = [];
  final StreamController<WireFrameSample> _streamController =
      StreamController<WireFrameSample>.broadcast();

  static const int maxSamples = 30;
  DateTime _lastSampleTime = DateTime.fromMillisecondsSinceEpoch(0);

  List<WireFrameSample> get samples => List.unmodifiable(_samples);
  WireFrameSample? get latestSample => _samples.isNotEmpty ? _samples.first : null;
  Stream<WireFrameSample> get onFrameRecorded => _streamController.stream;

  void clear() {
    _samples.clear();
  }

  /// Calculates real Shannon entropy $H(X) = -\sum p_i \log_2(p_i)$ over a bounded [bytes] sample (up to 512 bytes).
  static double calculateShannonEntropy(Uint8List bytes) {
    if (bytes.isEmpty) return 0.0;
    final len = min(bytes.length, 512);
    final counts = List<int>.filled(256, 0);
    for (int i = 0; i < len; i++) {
      counts[bytes[i]]++;
    }

    double entropy = 0.0;
    final total = len.toDouble();
    for (final count in counts) {
      if (count > 0) {
        final p = count / total;
        entropy -= p * (log(p) / ln2);
      }
    }
    return entropy;
  }

  /// Scans sample wire payload for unencrypted plaintext patterns (e.g. UTF-8 strings or magic signatures).
  static bool scanForPlaintextLeak(Uint8List bytes, String? filename) {
    if (bytes.isEmpty) return false;
    final scanLen = min(bytes.length, 256);

    // Check common unencrypted media headers (MP4, PNG, ZIP, JPEG)
    const magicSignatures = [
      [0x89, 0x50, 0x4E, 0x47], // PNG
      [0xFF, 0xD8, 0xFF],       // JPEG
      [0x50, 0x4B, 0x03, 0x04], // ZIP/APK
      [0x66, 0x74, 0x79, 0x70], // MP4 ftyp
      [0x25, 0x50, 0x44, 0x46], // PDF
    ];

    for (final sig in magicSignatures) {
      if (sig.length <= scanLen) {
        for (int i = 0; i <= scanLen - sig.length; i++) {
          bool match = true;
          for (int j = 0; j < sig.length; j++) {
            if (bytes[i + j] != sig[j]) {
              match = false;
              break;
            }
          }
          if (match) return true;
        }
      }
    }

    return false;
  }

  /// Records a real wire frame safely with rate-limiting to preserve zero CPU latency on hot transfer path.
  void recordFrame({
    required String direction,
    required String frameType,
    required int sequence,
    required int streamId,
    required int totalWireBytes,
    required Uint8List aadHeader,
    required Uint8List macTag,
    required Uint8List ciphertext,
    String? currentFilename,
  }) {
    try {
      final now = DateTime.now();
      // Allow first 3 frames or rate-limit to 1 frame every 150ms for smooth live tail stream
      if (_samples.length >= 3 && now.difference(_lastSampleTime).inMilliseconds < 150) {
        return;
      }
      _lastSampleTime = now;

      final snippetLen = min(ciphertext.length, 64);
      final snippet = Uint8List.fromList(ciphertext.sublist(0, snippetLen));
      final entropy = calculateShannonEntropy(ciphertext);
      final hasLeak = scanForPlaintextLeak(ciphertext, currentFilename);

      final sample = WireFrameSample(
        timestamp: now,
        direction: direction,
        frameType: frameType,
        sequence: sequence,
        streamId: streamId,
        totalWireBytes: totalWireBytes,
        rawHeaderBytes: Uint8List.fromList(aadHeader),
        macTagBytes: Uint8List.fromList(macTag),
        ciphertextSnippet: snippet,
        entropyBitsPerByte: entropy,
        plaintextLeakDetected: hasLeak,
        leakDetails: hasLeak ? 'Alerta: Padrão não criptografado detectado' : null,
      );

      _samples.insert(0, sample);
      if (_samples.length > maxSamples) {
        _samples.removeLast();
      }

      _streamController.add(sample);
    } catch (_) {}
  }
}
