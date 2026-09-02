import 'dart:io';
import 'package:secure_lan_transfer/core/constants/app_identity.dart';
import 'package:test/test.dart';

/// Guards against version/name drift between the centralized [AppIdentity] and
/// the authoritative `pubspec.yaml` (the single source of truth for releases).
void main() {
  group('AppIdentity', () {
    test('version matches pubspec.yaml version name (before any build suffix)',
        () {
      final pubspec = File('pubspec.yaml');
      expect(pubspec.existsSync(), isTrue,
          reason: 'pubspec.yaml must exist at project root');

      final content = pubspec.readAsStringSync();
      final match = RegExp(r'^version:\s*([\d.]+)(?:\+(\d+))?',
              caseSensitive: false, multiLine: true)
          .firstMatch(content);
      expect(match, isNotNull, reason: 'version: key not found in pubspec.yaml');

      final pubspecVersionName = match!.group(1)!;
      expect(AppIdentity.version, equals(pubspecVersionName),
          reason: 'AppIdentity.version ($AppIdentity.version) must equal the '
              'version name in pubspec.yaml ($pubspecVersionName).');
    });

    test('brand color components form the cyberEmerald #00D26A', () {
      expect(AppIdentity.brandColorRed, equals(0x00));
      expect(AppIdentity.brandColorGreen, equals(0xD2));
      expect(AppIdentity.brandColorBlue, equals(0x6A));
    });

    test('displayName and ansi helpers are well-formed', () {
      expect(AppIdentity.displayName,
          equals('Secure LAN File Transfer (SLFT) v1.0.0'));
      expect(AppIdentity.brandAnsiPrefix,
          equals('\x1b[38;2;0;210;106m'));
      expect(AppIdentity.ansiReset, equals('\x1b[0m'));
    });
  });
}
