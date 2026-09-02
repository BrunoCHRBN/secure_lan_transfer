import 'dart:typed_data';
import 'test_chacha.dart';

void main() {
  // RFC 8439 Section 2.3.2 Test Vector
  // Key: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  // Nonce: 00 00 00 09 00 00 00 4a 00 00 00 00
  final nonce = Uint8List.fromList([0x00, 0x00, 0x00, 0x09, 0x00, 0x00, 0x00, 0x4a, 0x00, 0x00, 0x00, 0x00]);

  final mask = ChaCha20Keystream.generateBlock0Mask4Bytes(key, nonce);
  print('RFC test mask: ${mask.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
}
