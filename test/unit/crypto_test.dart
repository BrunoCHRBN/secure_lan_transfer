import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';
import 'package:secure_lan_transfer/core/crypto/cipher_suite.dart';
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

String _bytesToHex(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  group('1. X25519 Ephemeral Key Exchange Tests', () {
    test('X25519 key exchange computes commutative shared secrets', () async {
      final cipherSuite = CipherSuite();
      final kpAlice = await cipherSuite.generateKeyPair();
      final kpBob = await cipherSuite.generateKeyPair();

      expect(kpAlice.publicKey.length, equals(32));
      expect(kpBob.publicKey.length, equals(32));
      expect(kpAlice.publicKey, isNot(equals(kpBob.publicKey)));

      // Alice computes shared secret with Bob's public key
      final secretA = await cipherSuite.computeSharedSecret(
        localKeyPair: kpAlice.keyPair,
        remotePublicKeyBytes: kpBob.publicKeyBytes,
      );

      // Bob computes shared secret with Alice's public key
      final secretB = await cipherSuite.computeSharedSecret(
        localKeyPair: kpBob.keyPair,
        remotePublicKeyBytes: kpAlice.publicKeyBytes,
      );

      expect(secretA.length, equals(32));
      expect(secretB.length, equals(32));
      expect(secretA, equals(secretB));
      expect(ByteUtils.isZero(secretA), isFalse);
    });

    test('CipherSuite ephemeral key generation produces valid 32-byte nonces and keys', () async {
      final cipherSuite = CipherSuite();
      final kp1 = await cipherSuite.generateKeyPair();
      final kp2 = await cipherSuite.generateKeyPair();

      expect(kp1.publicKey.length, equals(32));
      expect(kp2.publicKey.length, equals(32));
      expect(kp1.nonce.length, equals(32));
      expect(kp2.nonce.length, equals(32));
      expect(kp1.publicKey, isNot(equals(kp2.publicKey)));
      expect(kp1.nonce, isNot(equals(kp2.nonce)));
    });

    test('Weak public keys (e.g. all zeros) are rejected', () async {
      final cipherSuite = CipherSuite();
      final kp = await cipherSuite.generateKeyPair();
      final allZeroPub = Uint8List(32);

      await expectLater(
        () => cipherSuite.computeSharedSecret(
          localKeyPair: kp.keyPair,
          remotePublicKeyBytes: allZeroPub,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('2. HKDF-SHA256 Key Derivation Tests', () {
    test('RFC 5869 Test Case 1 Official Vector', () async {
      final ikm = _hexToBytes('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b');
      final salt = _hexToBytes('000102030405060708090a0b0c');
      final info = _hexToBytes('f0f1f2f3f4f5f6f7f8f9');
      const l = 42;
      final expectedOkm = _hexToBytes('3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');

      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: l);
      final secretKey = SecretKey(ikm);
      final derivedKey = await hkdf.deriveKey(
        secretKey: secretKey,
        nonce: salt,
        info: info,
      );
      final okmBytes = await derivedKey.extractBytes();
      expect(Uint8List.fromList(okmBytes), equals(expectedOkm));
    });

    test('SLFT Directional Session Key Derivation and Symmetry', () async {
      final cipherSuite = CipherSuite();
      final sharedSecret = _hexToBytes('4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742');
      final nonceA = ByteUtils.secureRandomBytes(32);
      final nonceB = ByteUtils.secureRandomBytes(32);

      final salt = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        salt[i] = nonceA[i] ^ nonceB[i];
      }

      final aliceKeys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        salt: salt,
        isInitiator: true,
      );

      final bobKeys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        salt: salt,
        isInitiator: false,
      );

      // Verify outbound Alice == inbound Bob
      expect(aliceKeys.outboundEncryptionKey, equals(bobKeys.inboundEncryptionKey));
      expect(aliceKeys.inboundEncryptionKey, equals(bobKeys.outboundEncryptionKey));
      expect(aliceKeys.outboundBaseIv, equals(bobKeys.inboundBaseIv));
      expect(aliceKeys.inboundBaseIv, equals(bobKeys.outboundBaseIv));
      expect(aliceKeys.maskKey, equals(bobKeys.maskKey));
      expect(aliceKeys.outboundKey.length, equals(32));
      expect(aliceKeys.outboundBaseIv.length, equals(12));
    });
  });

  group('3. ChaCha20-Poly1305 AEAD Tests', () {
    test('RFC 8439 Section 2.8.2 Test Vector (Sunscreen)', () async {
      final key = _hexToBytes('808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f');
      final nonce = _hexToBytes('070000004041424344454647');
      final plaintext = utf8.encode("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.");
      final aad = _hexToBytes('50515253c0c1c2c3c4c5c6c7');

      final expectedCiphertext = _hexToBytes('d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116');
      final expectedTag = _hexToBytes('1ae10b594f09e26a7e902ecbd0600691');

      final algorithm = Chacha20.poly1305Aead();
      final secretBox = await algorithm.encrypt(
        plaintext,
        secretKey: SecretKey(key),
        nonce: nonce,
        aad: aad,
      );

      expect(Uint8List.fromList(secretBox.cipherText), equals(expectedCiphertext));
      expect(Uint8List.fromList(secretBox.mac.bytes), equals(expectedTag));

      // Decrypt and verify
      final decrypted = await algorithm.decrypt(
        secretBox,
        secretKey: SecretKey(key),
        aad: aad,
      );
      expect(utf8.decode(decrypted), equals(utf8.decode(plaintext)));
    });

    test('Bit-flip in ciphertext causes SecretBoxAuthenticationError', () async {
      final cipherSuite = CipherSuite();
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Top Secret Data Transfer Payload'));

      final encrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      // Flip 1 bit in the ciphertext payload
      final tampered = Uint8List.fromList(encrypted);
      tampered[5] ^= 0x01;

      await expectLater(
        () => cipherSuite.decryptChunk(
          ciphertextAndTag: tampered,
          key: key,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('Bit-flip in Poly1305 MAC tag causes SecretBoxAuthenticationError', () async {
      final cipherSuite = CipherSuite();
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Top Secret Data Transfer Payload'));

      final encrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
      );

      // Flip 1 bit in the 16-byte trailing tag
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0x80;

      await expectLater(
        () => cipherSuite.decryptChunk(
          ciphertextAndTag: tampered,
          key: key,
          nonce: nonce,
          aad: aad,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('AES-256-GCM fallback cipher suite encryption and decryption roundtrip', () async {
      final cipherSuite = CipherSuite();
      final key = ByteUtils.secureRandomBytes(32);
      final nonce = ByteUtils.secureRandomBytes(12);
      final aad = ByteUtils.secureRandomBytes(16);
      final plaintext = Uint8List.fromList(utf8.encode('Fallback GCM encrypted transfer message'));

      final encrypted = await cipherSuite.encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
        cipherType: CipherType.aes256Gcm,
      );

      expect(encrypted.length, equals(plaintext.length + 16));

      final decrypted = await cipherSuite.decryptChunk(
        ciphertextAndTag: encrypted,
        key: key,
        nonce: nonce,
        aad: aad,
        cipherType: CipherType.aes256Gcm,
      );

      expect(utf8.decode(decrypted), equals('Fallback GCM encrypted transfer message'));
    });
  });

  group('4. Monotonic Nonce Construction Tests', () {
    test('Nonce XOR derivation is strictly deterministic and distinct', () {
      final baseIv = _hexToBytes('0102030405060708090a0b0c');

      final nonce0 = CipherSuite.deriveNonce(baseIv, 0);
      expect(nonce0, equals(baseIv));

      final nonce1 = CipherSuite.deriveNonce(baseIv, 1);
      expect(nonce1[11], equals(baseIv[11] ^ 0x01));

      final nonces = <String>{};
      for (int i = 0; i < 1000; i++) {
        final n = CipherSuite.deriveNonce(baseIv, i);
        final hex = _bytesToHex(n);
        expect(nonces.contains(hex), isFalse);
        nonces.add(hex);
      }
    });
  });

  group('5. SAS Authenticator Tests', () {
    test('Transcript hash derives matching 6-digit string and 4 emojis', () {
      final transcriptHash = _hexToBytes('2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae');
      final sas1 = SasAuthenticator.computeSas(transcriptHash);
      final sas2 = SasAuthenticator.computeSas(transcriptHash);

      expect(sas1.numericCode, equals(sas2.numericCode));
      expect(sas1.numericCode, matches(r'^\d{3}-\d{3}$'));
      expect(sas1.emojis, equals(sas2.emojis));
      expect(sas1.emojis.length, equals(4));
      expect(sas1.matches(sas2), isTrue);
    });

    test('1-bit transcript alteration produces distinct SAS codes', () {
      final hashA = _hexToBytes('2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae');
      final hashB = Uint8List.fromList(hashA);
      hashB[0] ^= 0x01; // 1-bit flip

      final sasA = SasAuthenticator.computeSas(hashA);
      final sasB = SasAuthenticator.computeSas(hashB);

      expect(sasA.numericCode, isNot(equals(sasB.numericCode)));
      expect(sasA.emojis, isNot(equals(sasB.emojis)));
      expect(sasA.matches(sasB), isFalse);
    });

    test('Emoji dictionary has exactly 256 unique glyphs and 256 unique names', () {
      expect(SasAuthenticator.emojiDictionary.length, equals(256));

      final uniqueGlyphs = <String>{};
      final uniqueNames = <String>{};

      for (int i = 0; i < 256; i++) {
        final entry = SasAuthenticator.emojiDictionary[i];
        expect(entry.index, equals(i));
        expect(uniqueGlyphs.contains(entry.emoji), isFalse, reason: 'Duplicate emoji glyph: ${entry.emoji}');
        expect(uniqueNames.contains(entry.name), isFalse, reason: 'Duplicate emoji name: ${entry.name}');
        uniqueGlyphs.add(entry.emoji);
        uniqueNames.add(entry.name);
      }
    });

    test('SasAuthenticator constantTimeEquals works reliably', () {
      expect(SasAuthenticator.constantTimeEquals('123-456', '123-456'), isTrue);
      expect(SasAuthenticator.constantTimeEquals('123-456', '123-457'), isFalse);
      expect(SasAuthenticator.constantTimeEquals('short', 'longer_string'), isFalse);
    });
  });

  group('6. In-Memory Zeroization & Constant-Time Utilities', () {
    test('ByteUtils.zeroize clears buffer to zeros', () {
      final key = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      expect(ByteUtils.isZero(key), isFalse);
      ByteUtils.zeroize(key);
      expect(ByteUtils.isZero(key), isTrue);
      expect(key, equals(Uint8List(8)));
    });

    test('ByteUtils.constantTimeEquals behavior', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      final c = Uint8List.fromList([1, 2, 3, 5]);
      final d = Uint8List.fromList([1, 2, 3]);

      expect(ByteUtils.constantTimeEquals(a, b), isTrue);
      expect(ByteUtils.constantTimeEquals(a, c), isFalse);
      expect(ByteUtils.constantTimeEquals(a, d), isFalse);
    });

    test('SessionKeys.zeroize clears all sensitive buffers', () async {
      final cipherSuite = CipherSuite();
      final sharedSecret = ByteUtils.secureRandomBytes(32);
      final keys = await cipherSuite.deriveSessionKeys(
        sharedSecret: sharedSecret,
        initiatorNonce: ByteUtils.secureRandomBytes(32),
        receiverNonce: ByteUtils.secureRandomBytes(32),
        isInitiator: true,
      );

      expect(ByteUtils.isZero(keys.outboundKey), isFalse);
      expect(ByteUtils.isZero(keys.inboundKey), isFalse);
      expect(ByteUtils.isZero(keys.maskKey), isFalse);

      keys.zeroize();

      expect(ByteUtils.isZero(keys.outboundKey), isTrue);
      expect(ByteUtils.isZero(keys.inboundKey), isTrue);
      expect(ByteUtils.isZero(keys.maskKey), isTrue);
    });
  });
}
