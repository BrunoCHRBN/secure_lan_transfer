import 'dart:math';
import 'dart:typed_data';

double calculateShannonEntropy(Uint8List data) {
  if (data.isEmpty) return 0.0;
  final freqs = List<int>.filled(256, 0);
  for (var b in data) {
    freqs[b]++;
  }
  double entropy = 0.0;
  final n = data.length.toDouble();
  for (var f in freqs) {
    if (f > 0) {
      final p = f / n;
      entropy -= p * (log(p) / ln2);
    }
  }
  return entropy;
}

void main() {
  final random = Random.secure();
  
  // Test 1: Uniform random 64KB
  final rand64k = Uint8List(65536);
  for (int i = 0; i < rand64k.length; i++) {
    rand64k[i] = random.nextInt(256);
  }
  final entropy64k = calculateShannonEntropy(rand64k);
  print('64KB CSPRNG Entropy: $entropy64k (Pass >= 7.995: ${entropy64k >= 7.995})');

  // Test 2: Uniform random 1024B
  final rand1k = Uint8List(1024);
  for (int i = 0; i < rand1k.length; i++) {
    rand1k[i] = random.nextInt(256);
  }
  final entropy1k = calculateShannonEntropy(rand1k);
  print('1024B CSPRNG Entropy: $entropy1k (Pass >= 7.900: ${entropy1k >= 7.900})');

  // Test 3: Structured ASCII data
  final ascii = Uint8List.fromList('Hello World, this is plain ASCII text repeated many times!'.codeUnits);
  final entropyAscii = calculateShannonEntropy(ascii);
  print('ASCII text Entropy: $entropyAscii (should be low, ~4.0)');

  // Test 4: All zeroes
  final zeroes = Uint8List(1024);
  final entropyZeroes = calculateShannonEntropy(zeroes);
  print('All Zeroes Entropy: $entropyZeroes (should be 0.0)');
}
