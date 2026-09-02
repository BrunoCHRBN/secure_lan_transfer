/// Centralized application identity for Secure LAN File Transfer (SLFT).
///
/// Pure-Dart (no Flutter dependency) so it can be imported by both the CLI
/// (`bin/`) and the desktop UI (`lib/ui/`). Keeping identity in one place
/// prevents the version/name drift that previously existed across
/// `main.dart`, `settings_screen.dart`, and `bin/secure_transfer_cli.dart`.
class AppIdentity {
  static const String name = 'Secure LAN File Transfer';
  static const String acronym = 'SLFT';
  static const String version = '1.0.0';
  static const String protocol = 'SLFT/1.0';

  /// Primary brand color (cyberEmerald) used for the CLI banner and UI accent.
  /// Stored as separate RGB components so it can be emitted as an ANSI 24-bit
  /// escape sequence (`\x1b[38;2;R;G;Bm`) without string parsing.
  static const int brandColorRed = 0x00;
  static const int brandColorGreen = 0xD2;
  static const int brandColorBlue = 0x6A;

  static const String tagline =
      'Cross-platform E2EE file transfer with zero metadata and high-speed streaming.';

  static const String cipherSuite =
      'X25519 · HKDF-SHA256 · ChaCha20-Poly1305';

  /// Convenience string: `${name} (${acronym}) v${version}`.
  static String get displayName => '$name ($acronym) v$version';

  /// ANSI 24-bit escape prefix for the brand color, e.g. `\x1b[38;2;0;210;106m`.
  static String get brandAnsiPrefix =>
      '\x1b[38;2;$brandColorRed;$brandColorGreen;${brandColorBlue}m';

  /// ANSI reset sequence.
  static const String ansiReset = '\x1b[0m';
}
