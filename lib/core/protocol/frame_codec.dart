import 'dart:math';
import 'dart:typed_data';
import '../crypto/cipher_suite.dart';
import '../crypto/obfuscation.dart';
import 'packet_types.dart';
import 'wire_inspector.dart';

/// Exception thrown when encountering wire frame parsing or encoding violations.
class FrameCodecException implements Exception {
  final String message;
  const FrameCodecException(this.message);

  @override
  String toString() => 'FrameCodecException: $message';
}

/// Codec handling deterministic binary serialization, AEAD authentication,
/// ChaCha20 length masking, and de-serialization of 34-byte wire frames.
class FrameCodec {
  static const int magicValue = 0x534C4654; // ASCII 'SLFT'
  static const int protocolVersion = 0x01;
  static const int headerSize = 34;
  static const int aadSize = 18; // Bytes 0..17
  static const int macTagSize = 16; // Bytes 18..33
  static const int maxPayloadSize = 16 * 1024 * 1024; // 16 MB

  final CipherSuite _cipherSuite;

  FrameCodec({CipherSuite? cipherSuite})
      : _cipherSuite = cipherSuite ?? CipherSuite();

  /// Masks a 4-byte payload length with ChaCha20 block 0 keystream mask.
  static Uint8List maskLength(int length, Uint8List maskKey, Uint8List nonce) {
    final mask = ChaCha20KeystreamGenerator.generateBlock0Mask4Bytes(maskKey, nonce);
    final lengthBytes = Uint8List(4);
    ByteData.sublistView(lengthBytes).setUint32(0, length, Endian.big);

    final masked = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      masked[i] = lengthBytes[i] ^ mask[i];
    }
    return masked;
  }

  /// Unmasks a 4-byte wire length prefix to recover original payload length.
  static int unmaskLength(Uint8List maskedPrefix, Uint8List maskKey, Uint8List nonce) {
    if (maskedPrefix.length != 4) {
      throw const FrameCodecException('Masked prefix must be 4 bytes');
    }
    final mask = ChaCha20KeystreamGenerator.generateBlock0Mask4Bytes(maskKey, nonce);
    final unmaskedBytes = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      unmaskedBytes[i] = maskedPrefix[i] ^ mask[i];
    }
    return ByteData.sublistView(unmaskedBytes).getUint32(0, Endian.big);
  }

  /// Serializes a [Frame] into a wire-ready [Uint8List] buffer.
  /// If [keys] is provided, payload is encrypted with [keys.outboundKey],
  /// authenticated with Poly1305 MAC tag over header AAD (bytes 0..17),
  /// and payload length prefix is masked with [keys.maskKey].
  Future<Uint8List> encodeFrame(
    Frame frame, {
    SessionKeys? keys,
    int targetTotalSize = 0,
  }) async {
    final payloadLen = frame.payload.length;
    if (payloadLen > maxPayloadSize) {
      throw FrameCodecException(
        'Payload length ($payloadLen bytes) exceeds maximum allowable frame cap ($maxPayloadSize bytes)',
      );
    }

    // Determine padding length
    int paddingLen = frame.paddingLen;
    if (targetTotalSize > 0) {
      final needed = targetTotalSize - headerSize - payloadLen;
      paddingLen = max(0, needed);
    }
    if (paddingLen < 0 || paddingLen > 65535) {
      throw FrameCodecException('Padding length ($paddingLen) outside bounds [0, 65535]');
    }

    // Prepare 18-byte AAD header
    final aadBuffer = Uint8List(aadSize);
    final aadData = ByteData.sublistView(aadBuffer);

    // 1. Magic (4B)
    aadData.setUint32(0, magicValue, Endian.big);
    // 2. Version (1B)
    aadData.setUint8(4, protocolVersion);
    // 3. Type (1B)
    aadData.setUint8(5, frame.type.opcode);
    // 4. Stream ID (2B)
    aadData.setUint16(6, frame.streamId, Endian.big);
    // 5. Sequence (4B)
    aadData.setUint32(8, frame.sequence, Endian.big);

    // 6. Masked Payload Length (4B) & Nonce derivation
    final Uint8List nonce;
    if (keys != null) {
      nonce = CipherSuite.deriveNonce(keys.outboundBaseIv, frame.sequence);
      final maskedLengthBytes = maskLength(
        payloadLen,
        keys.maskKey,
        nonce,
      );
      aadBuffer.setRange(12, 16, maskedLengthBytes);
    } else {
      nonce = Uint8List(12);
      aadData.setUint32(12, payloadLen, Endian.big);
    }

    // 7. Padding Length (2B)
    aadData.setUint16(16, paddingLen, Endian.big);

    // 8. Encrypt payload and compute MAC Tag
    final Uint8List ciphertext;
    final Uint8List macTag;

    if (keys != null) {
      final encryptedWithTag = await _cipherSuite.encryptChunk(
        plaintext: frame.payload,
        key: keys.outboundKey,
        nonce: nonce,
        aad: aadBuffer,
        cipherType: keys.cipherType,
      );

      final ctLen = encryptedWithTag.length - macTagSize;
      ciphertext = Uint8List.sublistView(encryptedWithTag, 0, ctLen);
      macTag = Uint8List.sublistView(encryptedWithTag, ctLen);
    } else {
      ciphertext = frame.payload;
      macTag = Uint8List(macTagSize); // Zero tag for unencrypted frames
    }

    // 9. Generate random padding bytes
    final paddingBytes = paddingLen > 0
        ? TrafficObfuscator.generateRandomNoise(paddingLen)
        : Uint8List(0);

    // 10. Assemble complete wire frame
    final wireFrame = Uint8List(headerSize + ciphertext.length + paddingLen);
    wireFrame.setRange(0, aadSize, aadBuffer);
    wireFrame.setRange(aadSize, headerSize, macTag);
    wireFrame.setRange(headerSize, headerSize + ciphertext.length, ciphertext);
    if (paddingLen > 0) {
      wireFrame.setRange(
        headerSize + ciphertext.length,
        wireFrame.length,
        paddingBytes,
      );
    }

    // Record real wire sample
    WireTrafficInspector.instance.recordFrame(
      direction: 'OUTBOUND (ENVIADO)',
      frameType: frame.type.name,
      sequence: frame.sequence,
      streamId: frame.streamId,
      totalWireBytes: wireFrame.length,
      aadHeader: aadBuffer,
      macTag: macTag,
      ciphertext: ciphertext,
    );

    return wireFrame;
  }

  /// Deserializes and authenticates a single complete wire frame [Uint8List].
  Future<Frame> decodeFrame(
    Uint8List wireBytes, {
    SessionKeys? keys,
  }) async {
    if (wireBytes.length < headerSize) {
      throw FrameCodecException(
        'Wire buffer too short (${wireBytes.length} bytes). Minimum header size is $headerSize bytes.',
      );
    }

    final headerData = ByteData.sublistView(wireBytes, 0, headerSize);

    // 1. Verify Magic
    final magic = headerData.getUint32(0, Endian.big);
    if (magic != magicValue) {
      throw FrameCodecException(
        'Invalid frame magic: 0x${magic.toRadixString(16).padLeft(8, '0')} (expected 0x${magicValue.toRadixString(16)})',
      );
    }

    // 2. Verify Version
    final version = headerData.getUint8(4);
    if (version != protocolVersion) {
      throw FrameCodecException(
        'Unsupported protocol version: $version (expected $protocolVersion)',
      );
    }

    // 3. Extract Type, Stream ID, Sequence
    final opcode = headerData.getUint8(5);
    final type = FrameType.fromOpcode(opcode);
    final streamId = headerData.getUint16(6, Endian.big);
    final sequence = headerData.getUint32(8, Endian.big);

    // 4. Derive Nonce & Unmask Payload Length
    final Uint8List nonce;
    final int payloadLen;
    if (keys != null) {
      nonce = CipherSuite.deriveNonce(keys.inboundBaseIv, sequence);
      final maskedLengthBytes = Uint8List.sublistView(wireBytes, 12, 16);
      payloadLen = unmaskLength(
        maskedLengthBytes,
        keys.maskKey,
        nonce,
      );
    } else {
      nonce = Uint8List(12);
      payloadLen = headerData.getUint32(12, Endian.big);
    }

    if (payloadLen < 0 || payloadLen > maxPayloadSize) {
      throw FrameCodecException('Payload length out of bounds: $payloadLen bytes');
    }

    // 5. Extract Padding Length
    final paddingLen = headerData.getUint16(16, Endian.big);
    final totalExpectedSize = headerSize + payloadLen + paddingLen;

    if (wireBytes.length < totalExpectedSize) {
      throw FrameCodecException(
        'Incomplete wire frame. Expected $totalExpectedSize bytes, got ${wireBytes.length} bytes.',
      );
    }

    // 6. Extract AAD, MAC tag, Ciphertext
    final aad = Uint8List.sublistView(wireBytes, 0, aadSize);
    final macTag = Uint8List.sublistView(wireBytes, aadSize, headerSize);
    final ciphertext = Uint8List.sublistView(wireBytes, headerSize, headerSize + payloadLen);

    // 7. Decrypt & Authenticate Payload
    final Uint8List plaintext;
    if (keys != null) {
      final ciphertextWithTag = Uint8List(payloadLen + macTagSize);
      ciphertextWithTag.setRange(0, payloadLen, ciphertext);
      ciphertextWithTag.setRange(payloadLen, ciphertextWithTag.length, macTag);

      plaintext = await _cipherSuite.decryptChunk(
        ciphertextWithTag: ciphertextWithTag,
        key: keys.inboundKey,
        nonce: nonce,
        aad: aad,
        cipherType: keys.cipherType,
      );
    } else {
      plaintext = Uint8List.fromList(ciphertext);
    }

    return Frame(
      type: type,
      streamId: streamId,
      sequence: sequence,
      payload: plaintext,
      paddingLen: paddingLen,
      authTag: macTag,
      rawHeader: Uint8List.sublistView(wireBytes, 0, headerSize),
    );
  }
}
