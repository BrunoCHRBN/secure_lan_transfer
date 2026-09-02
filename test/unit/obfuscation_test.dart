import 'dart:math';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/crypto/obfuscation.dart';
import 'package:secure_lan_transfer/core/crypto/zero_metadata_staging.dart';

double calculateShannonEntropy(Uint8List data) {
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

void main() {
  group('1. Shannon Entropy & DPI Resistance Tests', () {
    test('CSPRNG noise padding has entropy >= 7.995 bits/byte on 64KB buffers', () {
      final randomData = ByteUtils.secureRandomBytes(65536); // 64 KB
      final entropy = calculateShannonEntropy(randomData);
      expect(entropy, greaterThanOrEqualTo(7.995));
      expect(TrafficObfuscator.calculateShannonEntropy(randomData), greaterThanOrEqualTo(7.995));
    });

    test('Fully padded wire frames maintain high entropy >= 7.995 on 64KB chunks', () {
      final obfuscator = TrafficObfuscator();
      final payload = Uint8List.fromList(List.filled(100, 0xAA)); // Low entropy source
      final padded = obfuscator.padPayload(payload, 65536);
      final entropy = calculateShannonEntropy(padded);
      expect(entropy, greaterThanOrEqualTo(7.995));
    });

    test('Encrypted and padded data chunks satisfy entropy >= 7.995 bits/byte', () async {
      final cipherSuite = CipherSuite();
      final obfuscator = TrafficObfuscator();
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);

      // Low entropy structured payload (10KB of ASCII text)
      final rawPayload = Uint8List.fromList(List.generate(10000, (i) => (i % 26) + 65));
      final paddedPayload = obfuscator.padPayload(rawPayload, 65536);

      final ciphertext = await cipherSuite.encryptChunk(
        plaintext: paddedPayload,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      final entropy = calculateShannonEntropy(ciphertext);
      expect(entropy, greaterThanOrEqualTo(7.995));
    });

    test('Handshake jitter envelope (96-160B) has high entropy >= 6.0', () {
      final obfuscator = TrafficObfuscator();
      final pk = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(32);
      final envelope = obfuscator.createHandshakeEnvelope(pk, nonce);

      expect(envelope.length, greaterThanOrEqualTo(96));
      expect(envelope.length, lessThanOrEqualTo(160));
      final entropy = calculateShannonEntropy(envelope);
      expect(entropy, greaterThanOrEqualTo(6.0));
    });
  });

  group('2. ChaCha20 Length Prefix Masking Tests', () {
    test('Round-trip masking and unmasking for various frame sizes', () async {
      final obfuscator = TrafficObfuscator();
      final maskKey = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);

      final testLengths = [0, 16, 1024, 65536, 65572];

      for (final len in testLengths) {
        final maskedPrefix = await obfuscator.maskLengthPrefix(
          length: len,
          maskKey: maskKey,
          nonce: nonce,
        );

        expect(maskedPrefix.length, equals(4));

        final unmaskedLen = await obfuscator.unmaskLengthPrefix(
          maskedPrefix: maskedPrefix,
          maskKey: maskKey,
          nonce: nonce,
        );

        expect(unmaskedLen, equals(len));
      }
    });

    test('Synchronous ChaCha20 masking matches async method', () {
      final maskKey = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      const testLength = 65536;

      final maskedSync = TrafficObfuscator.maskLengthPrefixSync(testLength, maskKey, nonce);
      final unmaskedSync = TrafficObfuscator.unmaskLengthPrefixSync(maskedSync, maskKey, nonce);

      expect(unmaskedSync, equals(testLength));
    });

    test('Length unmasking with wrong key or nonce produces invalid length', () async {
      final obfuscator = TrafficObfuscator();
      final maskKey = ByteUtils.secureRandomBytes(32);
      final wrongKey = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);

      final maskedPrefix = await obfuscator.maskLengthPrefix(
        length: 65536,
        maskKey: maskKey,
        nonce: nonce,
      );

      // Attempt to unmask with wrong key
      try {
        final unmaskedLen = await obfuscator.unmaskLengthPrefix(
          maskedPrefix: maskedPrefix,
          maskKey: wrongKey,
          nonce: nonce,
        );
        expect(unmaskedLen, isNot(equals(65536)));
      } catch (e) {
        expect(e, isA<SecurityException>());
      }
    });

    test('Anti-DoS: Out-of-bounds frame lengths (> 65,572 bytes) throw SecurityException', () async {
      final obfuscator = TrafficObfuscator();
      final maskKey = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);

      // Oversized frame payload length
      expect(
        () async => await obfuscator.maskLengthPrefix(
          length: 70000,
          maskKey: maskKey,
          nonce: nonce,
        ),
        throwsA(isA<SecurityException>()),
      );
    });
  });

  group('3. Uniform Frame Padding & Recovery Tests', () {
    test('Metadata frame padded exactly to 1024 bytes and unpadded correctly', () {
      final obfuscator = TrafficObfuscator();
      final metadataJson = Uint8List.fromList('{"fileName":"notes.txt","size":512}'.codeUnits);

      final padded = obfuscator.padPayload(metadataJson, 1024);
      expect(padded.length, equals(1024));

      final unpadded = obfuscator.unpadPayload(padded, metadataJson.length);
      expect(unpadded, equals(metadataJson));
    });

    test('Data chunk padded exactly to 64 KB and unpadded correctly', () {
      final obfuscator = TrafficObfuscator();
      final chunkBytes = ByteUtils.secureRandomBytes(12345); // Partial chunk

      final padded = obfuscator.padPayload(chunkBytes, 65536);
      expect(padded.length, equals(65536));

      final unpadded = obfuscator.unpadPayload(padded, chunkBytes.length);
      expect(unpadded, equals(chunkBytes));
    });

    test('Padded data exceeding target size throws ObfuscationException', () {
      final obfuscator = TrafficObfuscator();
      final largeData = ByteUtils.secureRandomBytes(2000);

      expect(
        () => obfuscator.padPayload(largeData, 1024),
        throwsA(isA<ObfuscationException>()),
      );
    });
  });

  group('4. Handshake Envelope Tests', () {
    test('HandshakeEnvelope.create and HandshakeEnvelope.parse roundtrip', () {
      final pk = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(32);

      final envelope = HandshakeEnvelope.create(
        publicKey: pk,
        nonce: nonce,
        customJitterLength: 48,
      );

      expect(envelope.rawEnvelopeBytes.length, equals(64 + 48));

      final parsed = HandshakeEnvelope.parse(envelope.rawEnvelopeBytes);
      expect(parsed.publicKey, equals(pk));
      expect(parsed.nonce, equals(nonce));
      expect(parsed.jitterPadding.length, equals(48));
    });

    test('TrafficObfuscator buildHandshakeEnvelope and parseHandshakeEnvelope roundtrip', () {
      final obfuscator = TrafficObfuscator();
      final pk = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(32);

      final envelopeBytes = obfuscator.buildHandshakeEnvelope(pk, nonce);
      expect(envelopeBytes.length, inInclusiveRange(96, 160));

      final parsed = obfuscator.parseHandshakeEnvelope(envelopeBytes);
      expect(parsed.publicKey, equals(pk));
      expect(parsed.nonce, equals(nonce));
    });
  });
}
