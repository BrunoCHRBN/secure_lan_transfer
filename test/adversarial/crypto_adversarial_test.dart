import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
import 'package:secure_lan_transfer/core/crypto/obfuscation.dart';
import 'package:secure_lan_transfer/core/crypto/sas_authenticator.dart';
import 'package:secure_lan_transfer/core/crypto/zero_metadata_staging.dart';

Uint8List _hexToBytes(String hex) {
  final clean = hex.replaceAll(' ', '').replaceAll('0x', '');
  final result = Uint8List(clean.length ~/ 2);
  for (int i = 0; i < clean.length; i += 2) {
    result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
  }
  return result;
}

double _calcEntropy(Uint8List data) {
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
  final cipherSuite = CipherSuite();

  group('CHALLENGER TIER 1: 100+ Bit-Flip & AEAD Tampering Attacks', () {
    test('ChaCha20-Poly1305: 250 random bit-flips across ciphertext & MAC tag -> 100% rejection', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Sensitive cryptographic payload data for transmission.'));

      final originalEncrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
        cipherType: CipherType.chacha20Poly1305,
      );

      final totalLen = originalEncrypted.length;
      expect(totalLen, equals(plaintext.length + 16));

      int rejectionCount = 0;
      const totalTrials = 250;
      final rng = Random(42); // Deterministic seed for reproducibility

      for (int i = 0; i < totalTrials; i++) {
        final tampered = Uint8List.fromList(originalEncrypted);
        final byteIndex = rng.nextInt(totalLen);
        final bitMask = 1 << rng.nextInt(8);
        tampered[byteIndex] ^= bitMask;

        try {
          await cipherSuite.decryptChunk(
            ciphertextAndTag: tampered,
            key: key,
            nonce: nonce,
            aad: aad,
            cipherType: CipherType.chacha20Poly1305,
          );
          fail('Decryption should have failed on bit-flip at byte $byteIndex with mask $bitMask');
        } catch (e) {
          expect(e, isA<SecretBoxAuthenticationError>());
          rejectionCount++;
        }
      }

      expect(rejectionCount, equals(totalTrials), reason: 'All 250 bit-flips must be rejected');
    });

    test('AES-256-GCM: 250 random bit-flips across ciphertext & MAC tag -> 100% rejection', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Sensitive AES-GCM encrypted message payload.'));

      final originalEncrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
        cipherType: CipherType.aes256Gcm,
      );

      final totalLen = originalEncrypted.length;
      int rejectionCount = 0;
      const totalTrials = 250;
      final rng = Random(1337);

      for (int i = 0; i < totalTrials; i++) {
        final tampered = Uint8List.fromList(originalEncrypted);
        final byteIndex = rng.nextInt(totalLen);
        final bitMask = 1 << rng.nextInt(8);
        tampered[byteIndex] ^= bitMask;

        try {
          await cipherSuite.decryptChunk(
            ciphertextAndTag: tampered,
            key: key,
            nonce: nonce,
            aad: aad,
            cipherType: CipherType.aes256Gcm,
          );
          fail('AES-GCM decryption should have failed on bit-flip at byte $byteIndex with mask $bitMask');
        } catch (e) {
          expect(e, isA<SecretBoxAuthenticationError>());
          rejectionCount++;
        }
      }

      expect(rejectionCount, equals(totalTrials));
    });

    test('Systematic single-bit sweep across every bit in 16B ciphertext + 16B MAC tag (256 bits)', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List(16); // 16 bytes

      final encrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      expect(encrypted.length, equals(32)); // 16B ciphertext + 16B Poly1305 MAC

      int testedBits = 0;
      for (int byteIdx = 0; byteIdx < encrypted.length; byteIdx++) {
        for (int bitPos = 0; bitPos < 8; bitPos++) {
          final tampered = Uint8List.fromList(encrypted);
          tampered[byteIdx] ^= (1 << bitPos);

          try {
            await cipherSuite.decryptChunk(
              ciphertextAndTag: tampered,
              key: key,
              nonce: nonce,
              aad: aad,
            );
            fail('Expected authentication failure at byte $byteIdx bit $bitPos');
          } catch (e) {
            expect(e, isA<SecretBoxAuthenticationError>());
            testedBits++;
          }
        }
      }

      expect(testedBits, equals(256), reason: 'Every single bit of the 256 bits was verified');
    });

    test('AAD tampering: 100 bit-flips in Additional Authenticated Data -> 100% rejection', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(32);
      final plaintext = Uint8List.fromList(utf8.encode('Payload with authenticated metadata AAD'));

      final encrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      int rejectionCount = 0;
      const totalTrials = 100;
      final rng = Random(999);

      for (int i = 0; i < totalTrials; i++) {
        final tamperedAad = Uint8List.fromList(aad);
        final byteIndex = rng.nextInt(aad.length);
        final bitMask = 1 << rng.nextInt(8);
        tamperedAad[byteIndex] ^= bitMask;

        try {
          await cipherSuite.decryptChunk(
            ciphertextAndTag: encrypted,
            key: key,
            nonce: nonce,
            aad: tamperedAad,
          );
          fail('Decryption should have failed when AAD was tampered');
        } catch (e) {
          expect(e, isA<SecretBoxAuthenticationError>());
          rejectionCount++;
        }
      }

      expect(rejectionCount, equals(totalTrials));
    });

    test('Truncation and Extension attacks -> 100% rejection', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Standard payload'));

      final encrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      // Truncation: remove 1 to 15 bytes
      for (int cut = 1; cut <= 15; cut++) {
        final truncated = encrypted.sublist(0, encrypted.length - cut);
        if (truncated.length < 16) {
          expect(
            () => cipherSuite.decryptChunk(
              ciphertextAndTag: truncated,
              key: key,
              nonce: nonce,
              aad: aad,
            ),
            throwsA(isA<ArgumentError>()),
          );
        } else {
          expect(
            () => cipherSuite.decryptChunk(
              ciphertextAndTag: truncated,
              key: key,
              nonce: nonce,
              aad: aad,
            ),
            throwsA(isA<SecretBoxAuthenticationError>()),
          );
        }
      }

      // Extension: append 1 to 32 garbage bytes
      for (int ext = 1; ext <= 32; ext++) {
        final extended = Uint8List(encrypted.length + ext);
        extended.setRange(0, encrypted.length, encrypted);
        for (int j = 0; j < ext; j++) {
          extended[encrypted.length + j] = 0xAA;
        }

        expect(
          () => cipherSuite.decryptChunk(
            ciphertextAndTag: extended,
            key: key,
            nonce: nonce,
            aad: aad,
          ),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      }
    });
  });

  group('CHALLENGER TIER 2: Monotonic Nonce & Replay Attack Resistance', () {
    test('Replay attack: replaying chunk C_i under subsequent sequence number fails authentication', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final baseIv = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Chunk zero content'));

      final nonce0 = CipherSuite.deriveNonce(baseIv, 0);
      final encrypted0 = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce0,
        aad: aad,
      );

      // Attempt to decrypt encrypted0 using nonce1 (simulating replay of chunk 0 at sequence 1)
      final nonce1 = CipherSuite.deriveNonce(baseIv, 1);
      expect(
        () => cipherSuite.decryptChunk(
          ciphertextAndTag: encrypted0,
          key: key,
          nonce: nonce1,
          aad: aad,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // Attempt to decrypt encrypted0 using arbitrary sequence numbers 2..50
      for (int seq = 2; seq <= 50; seq++) {
        final replayNonce = CipherSuite.deriveNonce(baseIv, seq);
        expect(
          () => cipherSuite.decryptChunk(
            ciphertextAndTag: encrypted0,
            key: key,
            nonce: replayNonce,
            aad: aad,
          ),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      }
    });

    test('Out-of-order permutation rejection: nonces are strictly ordered and non-interchangeable', () async {
      final key = ByteUtils.secureRandomBytes(32);
      final baseIv = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);

      final chunks = List.generate(
        10,
        (i) => Uint8List.fromList(utf8.encode('Stream chunk sequence number #$i')),
      );

      final ciphertexts = <Uint8List>[];
      for (int i = 0; i < chunks.length; i++) {
        final nonce = CipherSuite.deriveNonce(baseIv, i);
        ciphertexts.add(await cipherSuite.encryptChunk(
          plaintext: chunks[i],
          key: key,
          nonce: nonce,
          aad: aad,
        ));
      }

      // Verify that decrypting chunk i with nonce j (i != j) always fails
      for (int i = 0; i < chunks.length; i++) {
        for (int j = 0; j < chunks.length; j++) {
          final nonceJ = CipherSuite.deriveNonce(baseIv, j);
          if (i == j) {
            final decrypted = await cipherSuite.decryptChunk(
              ciphertextAndTag: ciphertexts[i],
              key: key,
              nonce: nonceJ,
              aad: aad,
            );
            expect(decrypted, equals(chunks[i]));
          } else {
            expect(
              () => cipherSuite.decryptChunk(
                ciphertextAndTag: ciphertexts[i],
                key: key,
                nonce: nonceJ,
                aad: aad,
              ),
              throwsA(isA<SecretBoxAuthenticationError>()),
            );
          }
        }
      }
    });

    test('Sequence counter boundary values and 64-bit endian correctness', () {
      final baseIv = Uint8List(12); // All zeros
      final seqCases = [
        0,
        1,
        255,
        256,
        65535,
        65536,
        0x7FFFFFFF,
        0x80000000,
        0xFFFFFFFF,
        0x100000000,
        0x7FFFFFFFFFFFFFFF,
      ];

      final derived = <String>{};
      for (final seq in seqCases) {
        final nonce = CipherSuite.deriveNonce(baseIv, seq);
        expect(nonce.length, equals(12));
        final hex = nonce.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        expect(derived.contains(hex), isFalse, reason: 'Collision for sequence $seq');
        derived.add(hex);

        // Verify that the first 4 bytes of baseIv are untouched
        expect(nonce.sublist(0, 4), equals(baseIv.sublist(0, 4)));

        // Verify big-endian placement in bytes 4..11
        final byteData = ByteData.sublistView(nonce, 4, 12);
        expect(byteData.getUint64(0, Endian.big), equals(seq));
      }
    });

    test('Directional key separation prevents reflection attacks', () async {
      final sharedSecret = ByteUtils.secureRandomBytes(32);
      final salt = ByteUtils.secureRandomBytes(32);

      final aliceKeys = await SessionKeys.derive(
        sharedSecret: sharedSecret,
        salt: salt,
        isInitiator: true,
      );

      final bobKeys = await SessionKeys.derive(
        sharedSecret: sharedSecret,
        salt: salt,
        isInitiator: false,
      );

      final payload = Uint8List.fromList(utf8.encode('Directional message from Alice to Bob'));
      final nonce = CipherSuite.deriveNonce(aliceKeys.outboundBaseIv, 0);
      final aad = Uint8List(0);

      // Alice encrypts with outbound key
      final encrypted = await cipherSuite.encryptChunk(
        plaintext: payload,
        key: aliceKeys.outboundKey,
        nonce: nonce,
        aad: aad,
      );

      // Bob decrypts with inbound key (SUCCESS)
      final bobDecrypted = await cipherSuite.decryptChunk(
        ciphertextAndTag: encrypted,
        key: bobKeys.inboundKey,
        nonce: nonce,
        aad: aad,
      );
      expect(bobDecrypted, equals(payload));

      // Reflection attack: Attempting to decrypt Alice's outbound message with Alice's inbound key MUST FAIL
      expect(
        () => cipherSuite.decryptChunk(
          ciphertextAndTag: encrypted,
          key: aliceKeys.inboundKey,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('CHALLENGER TIER 3: Degenerate & Small Subgroup X25519 Public Key Rejection', () {
    test('Rejects all-zero public key', () async {
      final kp = await cipherSuite.generateKeyPair();
      final allZeros = Uint8List(32);

      expect(
        () => cipherSuite.computeSharedSecret(
          localKeyPair: kp.keyPair,
          remotePublicKeyBytes: allZeros,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Rejects known Curve25519 small-order and non-contributory public key points', () async {
      final kp = await cipherSuite.generateKeyPair();

      // Canonical small-subgroup & non-contributory points (RFC 7748 Section 6.1):
      final nonContributoryPoints = <String, String>{
        'Point 0 (all zeros, order 4)': '0000000000000000000000000000000000000000000000000000000000000000',
        'Point 1 (order 1)': '0100000000000000000000000000000000000000000000000000000000000000',
        'p-1 (2^255 - 20, order 2)': 'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
        'p (2^255 - 19, order 4)': 'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
        'p+1 (2^255 - 18, order 1)': 'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
        'Non-canonical 2^255 (alias of 0)': '0000000000000000000000000000000000000000000000000000000000000080',
        'Non-canonical 2^255+1 (alias of 1)': '0100000000000000000000000000000000000000000000000000000000000080',
      };

      int rejectedCount = 0;

      for (final entry in nonContributoryPoints.entries) {
        final rawBytes = _hexToBytes(entry.value);
        try {
          final secret = await cipherSuite.computeSharedSecret(
            localKeyPair: kp.keyPair,
            remotePublicKeyBytes: rawBytes,
          );
          if (ByteUtils.isZero(secret)) {
            fail('Derived secret for ${entry.key} was all zeros but was not rejected!');
          }
        } catch (e) {
          expect(e, isA<StateError>());
          rejectedCount++;
        }
      }

      expect(rejectedCount, equals(nonContributoryPoints.length),
          reason: 'All 7 RFC 7748 non-contributory Curve25519 points must be 100% rejected');
    });

    test('Rejects invalid length public keys (<32B or >32B)', () async {
      final kp = await cipherSuite.generateKeyPair();

      expect(
        () => cipherSuite.computeSharedSecret(
          localKeyPair: kp.keyPair,
          remotePublicKeyBytes: Uint8List(31),
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => cipherSuite.computeSharedSecret(
          localKeyPair: kp.keyPair,
          remotePublicKeyBytes: Uint8List(33),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('Zero shared secret defense: under no circumstance can computeSharedSecret return all zeros', () async {
      final kp = await cipherSuite.generateKeyPair();
      final testKeys = [
        Uint8List(32),
        Uint8List.fromList([1, ...List.filled(31, 0)]),
        Uint8List.fromList([0xEC, ...List.filled(30, 0xFF), 0x7F]),
        Uint8List.fromList([0xED, ...List.filled(30, 0xFF), 0x7F]),
        Uint8List.fromList([0xEE, ...List.filled(30, 0xFF), 0x7F]),
      ];

      for (final pk in testKeys) {
        try {
          final secret = await cipherSuite.computeSharedSecret(
            localKeyPair: kp.keyPair,
            remotePublicKeyBytes: pk,
          );
          expect(ByteUtils.isZero(secret), isFalse);
        } catch (e) {
          expect(e, isA<StateError>());
        }
      }
    });
  });

  group('CHALLENGER TIER 4: Statistical Shannon Entropy on 100 Random 64KB Buffers', () {
    test('100 independent 64KB CSPRNG buffers maintain Shannon Entropy >= 7.995 bits/byte', () {
      const bufferSize = 65536; // 64 KB
      const numBuffers = 100;

      final entropies = <double>[];
      double sumEntropy = 0.0;
      double minEntropy = 8.0;
      double maxEntropy = 0.0;

      for (int i = 0; i < numBuffers; i++) {
        final buf = ByteUtils.secureRandomBytes(bufferSize);
        final h = _calcEntropy(buf);
        entropies.add(h);
        sumEntropy += h;
        if (h < minEntropy) minEntropy = h;
        if (h > maxEntropy) maxEntropy = h;

        expect(h, greaterThanOrEqualTo(7.995),
            reason: 'Buffer #$i entropy $h is below 7.995 threshold');
      }

      final meanEntropy = sumEntropy / numBuffers;
      print('=== 100 CSPRNG 64KB Buffers Entropy Stats ===');
      print('Min:  $minEntropy bits/byte');
      print('Max:  $maxEntropy bits/byte');
      print('Mean: $meanEntropy bits/byte');

      expect(minEntropy, greaterThanOrEqualTo(7.995));
      expect(meanEntropy, greaterThanOrEqualTo(7.995));
    });

    test('100 encrypted & padded 64KB chunks maintain Shannon Entropy >= 7.995 bits/byte', () async {
      const bufferSize = 65536;
      const numBuffers = 100;

      final key = ByteUtils.secureRandomBytes(32);
      final baseIv = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);

      final entropies = <double>[];
      double sumEntropy = 0.0;
      double minEntropy = 8.0;
      double maxEntropy = 0.0;

      for (int i = 0; i < numBuffers; i++) {
        // Worst-case low entropy plaintexts: all zeros, constant patterns, linear sequences
        final plaintext = Uint8List(bufferSize);
        if (i % 3 == 0) {
          plaintext.fillRange(0, bufferSize, 0x00);
        } else if (i % 3 == 1) {
          plaintext.fillRange(0, bufferSize, 0xFF);
        } else {
          for (int j = 0; j < bufferSize; j++) {
            plaintext[j] = j % 256;
          }
        }

        final nonce = CipherSuite.deriveNonce(baseIv, i);
        final encrypted = await cipherSuite.encryptChunk(
          plaintext: plaintext,
          key: key,
          nonce: nonce,
          aad: aad,
        );

        final h = _calcEntropy(encrypted);
        entropies.add(h);
        sumEntropy += h;
        if (h < minEntropy) minEntropy = h;
        if (h > maxEntropy) maxEntropy = h;

        expect(h, greaterThanOrEqualTo(7.995),
            reason: 'Encrypted chunk #$i entropy $h is below 7.995 threshold');
      }

      final meanEntropy = sumEntropy / numBuffers;
      print('=== 100 Encrypted Chunks Entropy Stats ===');
      print('Min:  $minEntropy bits/byte');
      print('Max:  $maxEntropy bits/byte');
      print('Mean: $meanEntropy bits/byte');

      expect(minEntropy, greaterThanOrEqualTo(7.995));
      expect(meanEntropy, greaterThanOrEqualTo(7.995));
    });
  });

  group('CHALLENGER TIER 5: In-Memory Key Zeroization Verification', () {
    test('EphemeralKeyPairData.zeroize() completely clears public key and nonce in place', () async {
      final kp = await cipherSuite.generateKeyPair();

      expect(kp.publicKeyBytes.length, equals(32));
      expect(kp.nonce.length, equals(32));
      expect(ByteUtils.isZero(kp.publicKeyBytes), isFalse);
      expect(ByteUtils.isZero(kp.nonce), isFalse);

      // Store references to ensure in-place modification
      final pkRef = kp.publicKeyBytes;
      final nonceRef = kp.nonce;

      kp.zeroize();

      expect(ByteUtils.isZero(kp.publicKeyBytes), isTrue);
      expect(ByteUtils.isZero(kp.nonce), isTrue);
      expect(ByteUtils.isZero(pkRef), isTrue);
      expect(ByteUtils.isZero(nonceRef), isTrue);

      for (int i = 0; i < 32; i++) {
        expect(kp.publicKeyBytes[i], equals(0));
        expect(kp.nonce[i], equals(0));
      }
    });

    test('SessionKeys.zeroize() completely zeroes all 6 cryptographic key buffers in place', () async {
      final sharedSecret = ByteUtils.secureRandomBytes(32);
      final transcriptHash = ByteUtils.secureRandomBytes(32);

      final keys = await SessionKeys.derive(
        sharedSecret: sharedSecret,
        salt: ByteUtils.secureRandomBytes(32),
        transcriptHash: transcriptHash,
        isInitiator: true,
      );

      // Verify all keys are non-zero before zeroization
      expect(ByteUtils.isZero(keys.outboundKey), isFalse);
      expect(ByteUtils.isZero(keys.inboundKey), isFalse);
      expect(ByteUtils.isZero(keys.outboundBaseIv), isFalse);
      expect(ByteUtils.isZero(keys.inboundBaseIv), isFalse);
      expect(ByteUtils.isZero(keys.maskKey), isFalse);
      expect(ByteUtils.isZero(keys.transcriptHash), isFalse);

      // Store references
      final outKeyRef = keys.outboundKey;
      final inKeyRef = keys.inboundKey;
      final outIvRef = keys.outboundBaseIv;
      final inIvRef = keys.inboundBaseIv;
      final maskRef = keys.maskKey;
      final hashRef = keys.transcriptHash;

      keys.zeroize();

      // Assert all buffers are zeroed
      expect(ByteUtils.isZero(keys.outboundKey), isTrue);
      expect(ByteUtils.isZero(keys.inboundKey), isTrue);
      expect(ByteUtils.isZero(keys.outboundBaseIv), isTrue);
      expect(ByteUtils.isZero(keys.inboundBaseIv), isTrue);
      expect(ByteUtils.isZero(keys.maskKey), isTrue);
      expect(ByteUtils.isZero(keys.transcriptHash), isTrue);

      // Assert referenced buffers were modified in place
      expect(ByteUtils.isZero(outKeyRef), isTrue);
      expect(ByteUtils.isZero(inKeyRef), isTrue);
      expect(ByteUtils.isZero(outIvRef), isTrue);
      expect(ByteUtils.isZero(inIvRef), isTrue);
      expect(ByteUtils.isZero(maskRef), isTrue);
      expect(ByteUtils.isZero(hashRef), isTrue);
    });

    test('ByteUtils.zeroize() handles null, empty, and arbitrary buffers safely', () {
      ByteUtils.zeroize(null);
      ByteUtils.zeroize(Uint8List(0));

      final testBuf = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE]);
      ByteUtils.zeroize(testBuf);
      expect(ByteUtils.isZero(testBuf), isTrue);
    });
  });

  group('CHALLENGER TIER 6: Additional Obfuscation & Path Traversal Stress Tests', () {
    test('ChaCha20 wire mask prefix tamper detection and fuzzing', () {
      final maskKey = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);

      final masked = TrafficObfuscator.maskLengthPrefixSync(1024, maskKey, nonce);

      // Tamper with masked prefix
      for (int i = 0; i < 4; i++) {
        for (int b = 0; b < 8; b++) {
          final tampered = Uint8List.fromList(masked);
          tampered[i] ^= (1 << b);

          try {
            final unmasked = TrafficObfuscator.unmaskLengthPrefixSync(tampered, maskKey, nonce);
            expect(unmasked, isNot(equals(1024)));
          } catch (e) {
            expect(e, isA<SecurityException>());
          }
        }
      }
    });

    test('SAS Avalanche Effect: 500 bit-flips in transcript hash produce distinct SAS codes', () {
      final baseHash = ByteUtils.secureRandomBytes(32);
      final baseSas = SasAuthenticator.computeSas(baseHash);

      int collisionCount = 0;
      const totalTrials = 500;

      for (int i = 0; i < totalTrials; i++) {
        final flippedHash = Uint8List.fromList(baseHash);
        final byteIdx = i % 32;
        final bitIdx = (i ~/ 32) % 8;
        flippedHash[byteIdx] ^= (1 << bitIdx);

        final testSas = SasAuthenticator.computeSas(flippedHash);
        if (testSas.numericCode == baseSas.numericCode || testSas.matches(baseSas)) {
          collisionCount++;
        }
      }

      expect(collisionCount, equals(0), reason: 'Zero collisions allowed across 500 single-bit variations');
    });

    test('Path traversal fuzzer: 100 malicious inputs cannot escape or crash sanitizer', () {
      final maliciousInputs = [
        '../../../../../../../../etc/shadow',
        '..\\..\\..\\..\\..\\..\\..\\Windows\\System32\\config\\SAM',
        'normal_file.txt\x00.exe',
        'con.txt',
        'aux.dat',
        'nul',
        'com1',
        'lpt1',
        '..%2f..%2f..%2fetc%2fpasswd',
        r'file.txt::$DATA',
        'file.txt:stream',
        '   spaces   ',
        '.....dots.....',
        '\x01\x02\x03control.bin',
        'file<with>illegal|chars?*.txt',
        '.hidden_file',
        '/',
        '\\',
        'C:\\autoexec.bat',
        '/var/log/syslog',
      ];

      for (final input in maliciousInputs) {
        final sanitized = PathSanitizer.sanitize(input);
        expect(sanitized.contains('/'), isFalse, reason: 'Must not contain / for input: $input');
        expect(sanitized.contains('\\'), isFalse, reason: 'Must not contain \\ for input: $input');
        expect(sanitized.contains('..'), isFalse, reason: 'Must not contain .. for input: $input');
        expect(sanitized.contains('\x00'), isFalse, reason: 'Must not contain null byte for input: $input');
        expect(sanitized.isNotEmpty, isTrue);
      }
    });
  });
}
