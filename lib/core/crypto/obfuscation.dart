import 'dart:math';
import 'dart:typed_data';
import 'zero_metadata_staging.dart' show SecurityException;
export 'zero_metadata_staging.dart' show SecurityException;

/// Exception thrown during wire frame de-obfuscation or padding violations.
class ObfuscationException implements Exception {
  final String message;
  const ObfuscationException(this.message);

  @override
  String toString() => 'ObfuscationException: $message';
}

/// Disguised handshake packet envelope containing public key, nonce, and CSPRNG jitter.
class HandshakeEnvelope {
  final Uint8List publicKey;
  final Uint8List nonce;
  final Uint8List jitterPadding;
  final Uint8List rawEnvelopeBytes;

  const HandshakeEnvelope._({
    required this.publicKey,
    required this.nonce,
    required this.jitterPadding,
    required this.rawEnvelopeBytes,
  });

  /// Generates a randomized handshake envelope of 96..160 total bytes (64B payload + 32..96B jitter).
  factory HandshakeEnvelope.create({
    required Uint8List publicKey,
    required Uint8List nonce,
    int? customJitterLength,
  }) {
    if (publicKey.length != 32) {
      throw ArgumentError('publicKey must be 32 bytes');
    }
    if (nonce.length != 32) {
      throw ArgumentError('nonce must be 32 bytes');
    }

    final random = Random.secure();
    final jitterLen = customJitterLength ?? (32 + random.nextInt(65)); // 32..96 bytes
    if (jitterLen < 32 || jitterLen > 96) {
      throw ArgumentError('jitter length must be between 32 and 96 bytes');
    }

    final jitter = Uint8List(jitterLen);
    for (int i = 0; i < jitterLen; i++) {
      jitter[i] = random.nextInt(256);
    }

    final envelope = Uint8List(64 + jitterLen);
    envelope.setRange(0, 32, publicKey);
    envelope.setRange(32, 64, nonce);
    envelope.setRange(64, 64 + jitterLen, jitter);

    return HandshakeEnvelope._(
      publicKey: Uint8List.fromList(publicKey),
      nonce: Uint8List.fromList(nonce),
      jitterPadding: jitter,
      rawEnvelopeBytes: envelope,
    );
  }

  /// Parses an incoming raw byte stream into a [HandshakeEnvelope].
  factory HandshakeEnvelope.parse(Uint8List rawBytes) {
    if (rawBytes.length < 64 || rawBytes.length > 160) {
      throw ObfuscationException(
        'Invalid handshake envelope length (${rawBytes.length} bytes). Expected 64..160 bytes.',
      );
    }

    final pk = Uint8List.fromList(rawBytes.sublist(0, 32));
    final nonce = Uint8List.fromList(rawBytes.sublist(32, 64));
    final jitter = Uint8List.fromList(rawBytes.sublist(64));

    return HandshakeEnvelope._(
      publicKey: pk,
      nonce: nonce,
      jitterPadding: jitter,
      rawEnvelopeBytes: Uint8List.fromList(rawBytes),
    );
  }
}

/// Internal synchronous RFC 8439 ChaCha20 block 0 keystream generator.
class ChaCha20KeystreamGenerator {
  static void _quarterRound(Uint32List s, int a, int b, int c, int d) {
    s[a] = (s[a] + s[b]) & 0xFFFFFFFF;
    s[d] = (s[d] ^ s[a]) & 0xFFFFFFFF;
    s[d] = ((s[d] << 16) | (s[d] >>> 16)) & 0xFFFFFFFF;

    s[c] = (s[c] + s[d]) & 0xFFFFFFFF;
    s[b] = (s[b] ^ s[c]) & 0xFFFFFFFF;
    s[b] = ((s[b] << 12) | (s[b] >>> 20)) & 0xFFFFFFFF;

    s[a] = (s[a] + s[b]) & 0xFFFFFFFF;
    s[d] = (s[d] ^ s[a]) & 0xFFFFFFFF;
    s[d] = ((s[d] << 8) | (s[d] >>> 24)) & 0xFFFFFFFF;

    s[c] = (s[c] + s[d]) & 0xFFFFFFFF;
    s[b] = (s[b] ^ s[c]) & 0xFFFFFFFF;
    s[b] = ((s[b] << 7) | (s[b] >>> 25)) & 0xFFFFFFFF;
  }

  /// Generates the first 4 bytes of ChaCha20 keystream for block counter 0.
  static Uint8List generateBlock0Mask4Bytes(Uint8List key, Uint8List nonce) {
    if (key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');

    final state = Uint32List(16);
    // Constants: "expand 32-byte k"
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;

    // Key words (8 x 32-bit little-endian)
    final keyData = ByteData.sublistView(key);
    for (int i = 0; i < 8; i++) {
      state[4 + i] = keyData.getUint32(i * 4, Endian.little);
    }

    // Counter = 0
    state[12] = 0;

    // Nonce words (3 x 32-bit little-endian)
    final nonceData = ByteData.sublistView(nonce);
    state[13] = nonceData.getUint32(0, Endian.little);
    state[14] = nonceData.getUint32(4, Endian.little);
    state[15] = nonceData.getUint32(8, Endian.little);

    final working = Uint32List.fromList(state);

    // 20 rounds (10 column rounds + 10 diagonal rounds)
    for (int i = 0; i < 10; i++) {
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);

      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }

    final firstWord = (working[0] + state[0]) & 0xFFFFFFFF;
    final out = Uint8List(4);
    ByteData.sublistView(out).setUint32(0, firstWord, Endian.little);
    return out;
  }
}

/// Traffic obfuscation, wire prefix masking, padding, and entropy engine.
class TrafficObfuscator {
  static const int minFrameSize = 0;
  static const int maxFrameSize = 65572; // 16B header + 65536B chunk + 16B tag + 4B prefix
  static const int controlFrameTargetSize = 1024;
  static const int dataChunkTargetSize = 65536;

  /// Masks a 4-byte frame length using ChaCha20 block 0 keystream.
  static Uint8List maskLengthPrefixSync(int frameLength, Uint8List maskKey, Uint8List nonce) {
    if (frameLength < minFrameSize || frameLength > maxFrameSize) {
      throw SecurityException(
        'Frame length $frameLength outside bounds [$minFrameSize, $maxFrameSize]',
      );
    }
    final mask = ChaCha20KeystreamGenerator.generateBlock0Mask4Bytes(maskKey, nonce);
    final lengthBytes = Uint8List(4);
    ByteData.sublistView(lengthBytes).setUint32(0, frameLength, Endian.big);

    final masked = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      masked[i] = lengthBytes[i] ^ mask[i];
    }
    return masked;
  }

  /// Unmasks a 4-byte wire prefix to obtain the actual frame length.
  static int unmaskLengthPrefixSync(Uint8List maskedPrefix, Uint8List maskKey, Uint8List nonce) {
    if (maskedPrefix.length != 4) {
      throw ArgumentError('maskedPrefix must be 4 bytes');
    }
    final mask = ChaCha20KeystreamGenerator.generateBlock0Mask4Bytes(maskKey, nonce);
    final unmaskedBytes = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      unmaskedBytes[i] = maskedPrefix[i] ^ mask[i];
    }
    final length = ByteData.sublistView(unmaskedBytes).getUint32(0, Endian.big);

    if (length < minFrameSize || length > maxFrameSize) {
      throw SecurityException(
        'Unmasked frame length $length exceeds valid range [$minFrameSize, $maxFrameSize]. Potential corruption or tampering.',
      );
    }
    return length;
  }

  /// Instance & async-compatible maskLengthPrefix supporting named and positional arguments.
  Future<Uint8List> maskLengthPrefix({
    int? length,
    int? frameLength,
    required Uint8List maskKey,
    required Uint8List nonce,
  }) async {
    final len = length ?? frameLength;
    if (len == null) throw ArgumentError('length or frameLength must be provided');
    return maskLengthPrefixSync(len, maskKey, nonce);
  }

  /// Positional overload for maskLengthPrefix.
  Uint8List maskLengthPrefixPositional(int length, Uint8List maskKey, Uint8List nonce) =>
      maskLengthPrefixSync(length, maskKey, nonce);

  /// Instance & async-compatible unmaskLengthPrefix supporting named and positional arguments.
  Future<int> unmaskLengthPrefix({
    Uint8List? maskedPrefix,
    Uint8List? masked,
    required Uint8List maskKey,
    required Uint8List nonce,
  }) async {
    final prefix = maskedPrefix ?? masked;
    if (prefix == null) throw ArgumentError('maskedPrefix or masked must be provided');
    return unmaskLengthPrefixSync(prefix, maskKey, nonce);
  }

  /// Positional overload for unmaskLengthPrefix.
  int unmaskLengthPrefixPositional(Uint8List masked, Uint8List maskKey, Uint8List nonce) =>
      unmaskLengthPrefixSync(masked, maskKey, nonce);

  /// Generates a buffer of [length] cryptographically secure random bytes.
  static Uint8List generateRandomNoise(int length) {
    if (length <= 0) return Uint8List(0);
    final random = Random.secure();
    final buffer = Uint8List(length);
    for (int i = 0; i < length; i++) {
      buffer[i] = random.nextInt(256);
    }
    return buffer;
  }

  /// Pads [payload] with CSPRNG noise bytes up to [targetTotalSize].
  static Uint8List padToTarget(Uint8List payload, int targetTotalSize) {
    if (payload.length == targetTotalSize) {
      return Uint8List.fromList(payload);
    }
    if (payload.length > targetTotalSize) {
      throw ObfuscationException(
        'Payload size (${payload.length} bytes) exceeds target padding size ($targetTotalSize bytes).',
      );
    }

    final paddingLen = targetTotalSize - payload.length;
    final padding = generateRandomNoise(paddingLen);

    final padded = Uint8List(targetTotalSize);
    padded.setRange(0, payload.length, payload);
    padded.setRange(payload.length, targetTotalSize, padding);
    return padded;
  }

  /// Instance padPayload supporting targetSize.
  Uint8List padPayload(Uint8List data, int targetSize) => padToTarget(data, targetSize);

  /// Extracts the original unpadded payload from a padded buffer.
  static Uint8List extractPayload(Uint8List paddedData, int originalLength) {
    if (originalLength > paddedData.length) {
      throw ObfuscationException(
        'originalLength ($originalLength) is greater than padded buffer length (${paddedData.length}).',
      );
    }
    return Uint8List.fromList(paddedData.sublist(0, originalLength));
  }

  /// Instance unpadPayload.
  Uint8List unpadPayload(Uint8List paddedData, int originalLength) =>
      extractPayload(paddedData, originalLength);

  /// Creates a disguised handshake envelope: pk (32B) || nonce (32B) || CSPRNG jitter (32..96B).
  Uint8List createHandshakeEnvelope(Uint8List publicKey, Uint8List nonce, {int minJitter = 32, int maxJitter = 96}) {
    if (publicKey.length != 32 || nonce.length != 32) {
      throw ArgumentError('Public key and nonce must be 32 bytes each');
    }
    final random = Random.secure();
    final jitterLen = minJitter + random.nextInt(maxJitter - minJitter + 1);
    final env = HandshakeEnvelope.create(
      publicKey: publicKey,
      nonce: nonce,
      customJitterLength: jitterLen,
    );
    return env.rawEnvelopeBytes;
  }

  /// Alias for createHandshakeEnvelope.
  Uint8List buildHandshakeEnvelope(Uint8List publicKey, Uint8List nonce, {int minJitter = 32, int maxJitter = 96}) =>
      createHandshakeEnvelope(publicKey, nonce, minJitter: minJitter, maxJitter: maxJitter);

  /// Parses handshake envelope extracting public key and nonce (discards jitter).
  ({Uint8List publicKey, Uint8List nonce}) parseHandshakeEnvelope(Uint8List envelope) {
    final parsed = HandshakeEnvelope.parse(envelope);
    return (publicKey: parsed.publicKey, nonce: parsed.nonce);
  }

  /// Calculates Shannon Entropy H(X) = -sum(p(x) * log2(p(x))) in bits/byte.
  static double calculateShannonEntropy(Uint8List data) {
    if (data.isEmpty) return 0.0;
    final freqs = List<int>.filled(256, 0);
    for (final b in data) {
      freqs[b]++;
    }
    double entropy = 0.0;
    final n = data.length.toDouble();
    for (final f in freqs) {
      if (f > 0) {
        final p = f / n;
        entropy -= p * (log(p) / ln2);
      }
    }
    return entropy;
  }

  /// Instance method for calculating entropy.
  double calculateEntropy(Uint8List data) => calculateShannonEntropy(data);
}
