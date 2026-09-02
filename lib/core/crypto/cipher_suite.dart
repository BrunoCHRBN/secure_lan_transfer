import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Supported authenticated symmetric ciphers.
enum CipherType {
  chacha20Poly1305,
  aes256Gcm,
}

/// Transfer session role.
enum TransferRole {
  initiator, // Device A (Client)
  receiver,  // Device B (Server)
}

/// Ephemeral key exchange bundle containing X25519 key pair, public key bytes, and nonce.
class EphemeralKeyPairData {
  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;
  final Uint8List nonce;

  EphemeralKeyPairData({
    required this.keyPair,
    required this.publicKeyBytes,
    required this.nonce,
  });

  /// Alias for publicKeyBytes.
  Uint8List get publicKey => publicKeyBytes;

  /// Securely zeroes out public key and nonce buffers.
  void zeroize() {
    publicKeyBytes.fillRange(0, publicKeyBytes.length, 0);
    nonce.fillRange(0, nonce.length, 0);
  }
}

/// Derived directional session keys, base IVs, and mask keys.
class SessionKeys {
  final Uint8List outboundKey;      // 32 bytes
  final Uint8List inboundKey;       // 32 bytes
  final Uint8List outboundBaseIv;   // 12 bytes
  final Uint8List inboundBaseIv;    // 12 bytes
  final Uint8List maskKey;          // 32 bytes
  final Uint8List transcriptHash;   // 32 bytes
  final CipherType cipherType;

  SessionKeys({
    required this.outboundKey,
    required this.inboundKey,
    required this.outboundBaseIv,
    required this.inboundBaseIv,
    required this.maskKey,
    required this.transcriptHash,
    this.cipherType = CipherType.chacha20Poly1305,
  });

  /// Aliases for compatibility
  Uint8List get outboundEncryptionKey => outboundKey;
  Uint8List get inboundEncryptionKey => inboundKey;

  /// Derives full session keys via HKDF-SHA256 from shared secret and directional nonces.
  static Future<SessionKeys> derive({
    required Uint8List sharedSecret,
    Uint8List? initiatorNonce,
    Uint8List? receiverNonce,
    Uint8List? salt,
    Uint8List? transcriptHash,
    TransferRole? role,
    bool? isInitiator,
    CipherType cipherType = CipherType.chacha20Poly1305,
  }) async {
    final Uint8List derivationSalt;
    if (salt != null) {
      derivationSalt = salt;
    } else if (initiatorNonce != null && receiverNonce != null) {
      if (initiatorNonce.length != 32 || receiverNonce.length != 32) {
        throw ArgumentError('Initiator and receiver nonces must be 32 bytes each');
      }
      derivationSalt = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        derivationSalt[i] = initiatorNonce[i] ^ receiverNonce[i];
      }
    } else {
      derivationSalt = Uint8List(32);
    }

    final effectiveTranscriptHash = transcriptHash ?? Uint8List(32);
    final effectiveIsInitiator = isInitiator ?? (role == TransferRole.initiator);

    // Derive domain-separated keys using HKDF-SHA256
    final hkdf32 = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final hkdf12 = Hkdf(hmac: Hmac.sha256(), outputLength: 12);
    final secretKey = SecretKey(sharedSecret);

    final kA2bKey = await (await hkdf32.deriveKey(
      secretKey: secretKey,
      nonce: derivationSalt,
      info: utf8.encode('SLFT-v1-A2B-KEY'),
    )).extractBytes();

    final kB2aKey = await (await hkdf32.deriveKey(
      secretKey: secretKey,
      nonce: derivationSalt,
      info: utf8.encode('SLFT-v1-B2A-KEY'),
    )).extractBytes();

    final ivA2b = await (await hkdf12.deriveKey(
      secretKey: secretKey,
      nonce: derivationSalt,
      info: utf8.encode('SLFT-v1-A2B-IV'),
    )).extractBytes();

    final ivB2a = await (await hkdf12.deriveKey(
      secretKey: secretKey,
      nonce: derivationSalt,
      info: utf8.encode('SLFT-v1-B2A-IV'),
    )).extractBytes();

    final kMask = await (await hkdf32.deriveKey(
      secretKey: secretKey,
      nonce: derivationSalt,
      info: utf8.encode('SLFT-v1-MASK-KEY'),
    )).extractBytes();

    final Uint8List outboundKey;
    final Uint8List inboundKey;
    final Uint8List outboundBaseIv;
    final Uint8List inboundBaseIv;

    if (effectiveIsInitiator) {
      outboundKey = Uint8List.fromList(kA2bKey);
      inboundKey = Uint8List.fromList(kB2aKey);
      outboundBaseIv = Uint8List.fromList(ivA2b);
      inboundBaseIv = Uint8List.fromList(ivB2a);
    } else {
      outboundKey = Uint8List.fromList(kB2aKey);
      inboundKey = Uint8List.fromList(kA2bKey);
      outboundBaseIv = Uint8List.fromList(ivB2a);
      inboundBaseIv = Uint8List.fromList(ivA2b);
    }

    return SessionKeys(
      outboundKey: outboundKey,
      inboundKey: inboundKey,
      outboundBaseIv: outboundBaseIv,
      inboundBaseIv: inboundBaseIv,
      maskKey: Uint8List.fromList(kMask),
      transcriptHash: Uint8List.fromList(effectiveTranscriptHash),
      cipherType: cipherType,
    );
  }

  /// Securely overwrites all key material in memory with zeros.
  void zeroize() {
    outboundKey.fillRange(0, outboundKey.length, 0);
    inboundKey.fillRange(0, inboundKey.length, 0);
    outboundBaseIv.fillRange(0, outboundBaseIv.length, 0);
    inboundBaseIv.fillRange(0, inboundBaseIv.length, 0);
    maskKey.fillRange(0, maskKey.length, 0);
    transcriptHash.fillRange(0, transcriptHash.length, 0);
  }
}

/// Core cryptographic engine handling X25519, HKDF, ChaCha20-Poly1305, and AES-256-GCM.
class CipherSuite {
  final X25519 _x25519 = X25519();
  final Cipher _chacha20Poly1305 = Chacha20.poly1305Aead();
  final Cipher _aes256Gcm = AesGcm.with256bits();

  /// Generates a fresh ephemeral X25519 key pair and a 32-byte CSPRNG nonce.
  Future<EphemeralKeyPairData> generateEphemeralKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final random = Random.secure();
    final nonce = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      nonce[i] = random.nextInt(256);
    }

    return EphemeralKeyPairData(
      keyPair: keyPair,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
      nonce: nonce,
    );
  }

  /// Alias for generateEphemeralKeyPair.
  Future<EphemeralKeyPairData> generateKeyPair() => generateEphemeralKeyPair();

  /// Computes X25519 ECDH shared secret with weak public key validation.
  Future<Uint8List> computeSharedSecret({
    required SimpleKeyPair localKeyPair,
    required Uint8List remotePublicKeyBytes,
  }) async {
    if (remotePublicKeyBytes.length != 32) {
      throw ArgumentError('Remote public key must be exactly 32 bytes');
    }

    // Reject all-zero public key
    bool isAllZeros = true;
    for (int b in remotePublicKeyBytes) {
      if (b != 0) {
        isAllZeros = false;
        break;
      }
    }
    if (isAllZeros) {
      throw StateError('Invalid weak Curve25519 public key: all zeros');
    }

    final remotePk = SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    );

    final sharedSecretKey = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePk,
    );

    final secretBytes = Uint8List.fromList(await sharedSecretKey.extractBytes());

    // Verify derived secret is not all zeros
    bool secretIsAllZeros = true;
    for (int b in secretBytes) {
      if (b != 0) {
        secretIsAllZeros = false;
        break;
      }
    }
    if (secretIsAllZeros) {
      throw StateError('Invalid weak Curve25519 shared secret: all zeros');
    }

    return secretBytes;
  }

  /// Computes SHA-256 transcript hash: H = SHA256(pk_A || pk_B || N_A || N_B || Z)
  Future<Uint8List> computeTranscriptHash({
    required Uint8List initiatorPk,
    required Uint8List receiverPk,
    required Uint8List initiatorNonce,
    required Uint8List receiverNonce,
    required Uint8List sharedSecret,
  }) async {
    final sink = Sha256().newHashSink();
    sink.add(initiatorPk);
    sink.add(receiverPk);
    sink.add(initiatorNonce);
    sink.add(receiverNonce);
    sink.add(sharedSecret);
    sink.close();
    final hash = await sink.hash();
    return Uint8List.fromList(hash.bytes);
  }

  /// Derives session keys (convenience method on CipherSuite).
  Future<SessionKeys> deriveSessionKeys({
    required Uint8List sharedSecret,
    Uint8List? initiatorNonce,
    Uint8List? receiverNonce,
    Uint8List? salt,
    Uint8List? transcriptHash,
    TransferRole? role,
    bool? isInitiator,
    CipherType cipherType = CipherType.chacha20Poly1305,
  }) {
    return SessionKeys.derive(
      sharedSecret: sharedSecret,
      initiatorNonce: initiatorNonce,
      receiverNonce: receiverNonce,
      salt: salt,
      transcriptHash: transcriptHash,
      role: role,
      isInitiator: isInitiator,
      cipherType: cipherType,
    );
  }

  /// Deterministically derives a 96-bit nonce from a 12-byte base IV and a 64-bit sequence counter.
  /// Nonce_i = BaseIV XOR (0_4B || uint64_be(sequenceNumber))
  static Uint8List deriveNonce(Uint8List baseIv, int sequenceNumber) {
    if (baseIv.length != 12) {
      throw ArgumentError('Base IV must be exactly 12 bytes');
    }
    if (sequenceNumber < 0) {
      throw ArgumentError('Sequence number must be non-negative');
    }

    final nonce = Uint8List.fromList(baseIv);
    final counterData = ByteData(8)..setUint64(0, sequenceNumber, Endian.big);
    for (int i = 0; i < 8; i++) {
      nonce[4 + i] ^= counterData.getUint8(i);
    }
    return nonce;
  }

  /// Instance method for deriveNonce.
  Uint8List constructNonce(Uint8List baseIv, int sequenceNumber) =>
      deriveNonce(baseIv, sequenceNumber);

  /// Encrypts plaintext chunk with AEAD authenticated cipher.
  /// Returns concatenation: Ciphertext (N bytes) + Auth Tag (16 bytes).
  Future<Uint8List> encryptChunk({
    required Uint8List plaintext,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    CipherType cipherType = CipherType.chacha20Poly1305,
  }) async {
    final algorithm = (cipherType == CipherType.chacha20Poly1305)
        ? _chacha20Poly1305
        : _aes256Gcm;

    final secretKey = SecretKey(key);
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: aad,
    );

    // Concatenate ciphertext + 16-byte MAC tag
    final cipherText = secretBox.cipherText;
    final macBytes = secretBox.mac.bytes;
    final result = Uint8List(cipherText.length + macBytes.length);
    result.setRange(0, cipherText.length, cipherText);
    result.setRange(cipherText.length, result.length, macBytes);
    return result;
  }

  /// Positional overload for encryptChunk.
  Future<Uint8List> encryptChunkPositional(
    Uint8List plaintext,
    Uint8List key,
    Uint8List nonce,
    Uint8List aad, {
    CipherType cipherType = CipherType.chacha20Poly1305,
  }) =>
      encryptChunk(
        plaintext: plaintext,
        key: key,
        nonce: nonce,
        aad: aad,
        cipherType: cipherType,
      );

  /// Decrypts and verifies ciphertext chunk with AEAD authenticated cipher.
  /// Input: Ciphertext (N bytes) + Auth Tag (16 bytes).
  /// Throws SecretBoxAuthenticationError if tampered or invalid tag.
  Future<Uint8List> decryptChunk({
    Uint8List? ciphertextWithTag,
    Uint8List? ciphertextAndTag,
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    CipherType cipherType = CipherType.chacha20Poly1305,
  }) async {
    final input = ciphertextWithTag ?? ciphertextAndTag;
    if (input == null || input.length < 16) {
      throw ArgumentError('Ciphertext is too short to contain a 16-byte MAC tag');
    }

    final algorithm = (cipherType == CipherType.chacha20Poly1305)
        ? _chacha20Poly1305
        : _aes256Gcm;

    final cipherTextLen = input.length - 16;
    final cipherText = input.sublist(0, cipherTextLen);
    final macBytes = input.sublist(cipherTextLen);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final clearText = await algorithm.decrypt(
      secretBox,
      secretKey: SecretKey(key),
      aad: aad,
    );

    return Uint8List.fromList(clearText);
  }

  /// Positional overload for decryptChunk.
  Future<Uint8List> decryptChunkPositional(
    Uint8List ciphertextWithTag,
    Uint8List key,
    Uint8List nonce,
    Uint8List aad, {
    CipherType cipherType = CipherType.chacha20Poly1305,
  }) =>
      decryptChunk(
        ciphertextWithTag: ciphertextWithTag,
        key: key,
        nonce: nonce,
        aad: aad,
        cipherType: cipherType,
      );
}
