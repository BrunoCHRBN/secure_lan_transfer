import 'dart:typed_data';

class ChaCha20Keystream {
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

  static Uint8List generateBlock0Mask4Bytes(Uint8List key, Uint8List nonce) {
    if (key.length != 32) throw ArgumentError('Key must be 32 bytes');
    if (nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');

    final state = Uint32List(16);
    // Constants: "expand 32-byte k"
    state[0] = 0x61707865;
    state[1] = 0x3320646e;
    state[2] = 0x79622d32;
    state[3] = 0x6b206574;

    // Key (8 x 32-bit little-endian)
    final keyData = ByteData.sublistView(key);
    for (int i = 0; i < 8; i++) {
      state[4 + i] = keyData.getUint32(i * 4, Endian.little);
    }

    // Counter = 0
    state[12] = 0;

    // Nonce (3 x 32-bit little-endian)
    final nonceData = ByteData.sublistView(nonce);
    state[13] = nonceData.getUint32(0, Endian.little);
    state[14] = nonceData.getUint32(4, Endian.little);
    state[15] = nonceData.getUint32(8, Endian.little);

    final working = Uint32List.fromList(state);

    // 20 rounds (10 iterations of 4 column rounds + 4 diagonal rounds)
    for (int i = 0; i < 10; i++) {
      // Column rounds
      _quarterRound(working, 0, 4, 8, 12);
      _quarterRound(working, 1, 5, 9, 13);
      _quarterRound(working, 2, 6, 10, 14);
      _quarterRound(working, 3, 7, 11, 15);
      // Diagonal rounds
      _quarterRound(working, 0, 5, 10, 15);
      _quarterRound(working, 1, 6, 11, 12);
      _quarterRound(working, 2, 7, 8, 13);
      _quarterRound(working, 3, 4, 9, 14);
    }

    // Add state to working
    final firstWord = (working[0] + state[0]) & 0xFFFFFFFF;
    final out = Uint8List(4);
    ByteData.sublistView(out).setUint32(0, firstWord, Endian.little);
    return out;
  }
}

void main() {
  final key = Uint8List(32);
  final nonce = Uint8List(12);
  final mask = ChaCha20Keystream.generateBlock0Mask4Bytes(key, nonce);
  print('Mask for zero key/nonce: ${mask.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

  // Test mask and unmask
  final length = 65536;
  final lengthBytes = Uint8List(4);
  ByteData.sublistView(lengthBytes).setUint32(0, length, Endian.big);

  final masked = Uint8List(4);
  for (int i = 0; i < 4; i++) {
    masked[i] = lengthBytes[i] ^ mask[i];
  }
  print('Masked length: ${masked.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

  final unmasked = Uint8List(4);
  for (int i = 0; i < 4; i++) {
    unmasked[i] = masked[i] ^ mask[i];
  }
  final unmaskedLength = ByteData.sublistView(unmasked).getUint32(0, Endian.big);
  print('Unmasked length: $unmaskedLength (matches: ${unmaskedLength == length})');
}
