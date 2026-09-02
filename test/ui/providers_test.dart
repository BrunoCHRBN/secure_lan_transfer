import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_lan_transfer/core/crypto/sas_authenticator.dart';
import 'package:secure_lan_transfer/core/protocol/session_state.dart';
import 'package:secure_lan_transfer/core/session/session_manager.dart';
import 'package:secure_lan_transfer/ui/providers/device_discovery_provider.dart';
import 'package:secure_lan_transfer/ui/providers/settings_provider.dart';
import 'package:secure_lan_transfer/ui/providers/transfer_session_provider.dart';
import 'package:secure_lan_transfer/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsProvider Unit Tests', () {
    late SettingsProvider provider;

    setUp(() {
      provider = SettingsProvider();
    });

    test('Initial default values are properly configured', () {
      expect(provider.transferPort, equals(42385));
      expect(provider.themeMode, equals(AppThemeMode.oled));
      expect(provider.accentColor, equals(AppPalettes.cyberEmerald));
      expect(provider.openFolderOnComplete, isTrue);
      expect(provider.autoAcceptPairedDevices, isFalse);
      expect(provider.autoVerifySas, isFalse);
      expect(provider.enableTrafficPadding, isTrue);
      expect(provider.secureWipeOnAbort, isTrue);
      expect(provider.zeroMetadataMode, isTrue);
      expect(provider.maxSpeedLimitBytesPerSec, equals(0));
      expect(provider.creditWindowSize, equals(4));
      expect(provider.chunkSize, equals(65536));
      expect(provider.deviceId, isNotEmpty);
      expect(provider.deviceName, isNotEmpty);
    });

    test('Setters mutate state and notify listeners', () {
      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.setDeviceName('New Laptop');
      expect(provider.deviceName, equals('New Laptop'));
      expect(notifyCount, equals(1));

      provider.setTransferPort(45000);
      expect(provider.transferPort, equals(45000));
      expect(notifyCount, equals(2));

      provider.setThemeMode(AppThemeMode.light);
      expect(provider.themeMode, equals(AppThemeMode.light));
      expect(notifyCount, equals(3));

      provider.setAccentColor(AppPalettes.cyberCyan);
      expect(provider.accentColor, equals(AppPalettes.cyberCyan));
      expect(notifyCount, equals(4));

      provider.setDownloadDirectory('/custom/downloads');
      expect(provider.downloadDirectoryPath, equals('/custom/downloads'));
      expect(notifyCount, equals(5));

      provider.setOpenFolderOnComplete(false);
      expect(provider.openFolderOnComplete, isFalse);

      provider.setAutoAcceptPairedDevices(true);
      expect(provider.autoAcceptPairedDevices, isTrue);

      provider.setAutoVerifySas(true);
      expect(provider.autoVerifySas, isTrue);

      provider.setEnableTrafficPadding(false);
      expect(provider.enableTrafficPadding, isFalse);

      provider.setSecureWipeOnAbort(false);
      expect(provider.secureWipeOnAbort, isFalse);

      provider.setZeroMetadataMode(false);
      expect(provider.zeroMetadataMode, isFalse);

      provider.setSpeedLimit(10485760); // 10 MB/s
      expect(provider.maxSpeedLimitBytesPerSec, equals(10485760));

      provider.setCreditWindowSize(8);
      expect(provider.creditWindowSize, equals(8));

      provider.setChunkSize(131072);
      expect(provider.chunkSize, equals(131072));
    });

    test('Reset to defaults restores pristine configuration', () {
      provider.setThemeMode(AppThemeMode.light);
      provider.setTransferPort(50000);
      provider.setSpeedLimit(5000000);

      provider.resetToDefaults();

      expect(provider.themeMode, equals(AppThemeMode.oled));
      expect(provider.transferPort, equals(42385));
      expect(provider.maxSpeedLimitBytesPerSec, equals(0));
      expect(provider.creditWindowSize, equals(4));
    });
  });

  group('DeviceDiscoveryProvider Unit Tests', () {
    late DeviceDiscoveryProvider provider;
    late SettingsProvider settings;

    setUp(() {
      provider = DeviceDiscoveryProvider();
      settings = SettingsProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('Initialize starts discovery with settings profile', () async {
      await provider.initialize(settings);
      expect(provider.isScanning, isTrue);
      expect(provider.isAdvertising, isTrue);
    });

    test('Search and OS filtering works accurately', () async {
      provider.setSearchQuery('Alice');
      expect(provider.searchQuery, equals('Alice'));

      provider.setOsFilter('Windows');
      expect(provider.selectedOsFilter, equals('Windows'));

      provider.clearFilters();
      expect(provider.searchQuery, isEmpty);
      expect(provider.selectedOsFilter, isNull);
    });

    test('Manual device probing with unreachable IP records error message', () async {
      await expectLater(
        provider.addManualDevice('127.0.0.1', port: 59998),
        throwsA(anything),
      );
      expect(provider.errorMessage, isNotNull);
    });
  });

  group('TransferSessionProvider Unit Tests', () {
    late TransferSessionProvider provider;
    late SettingsProvider settings;

    setUp(() {
      settings = SettingsProvider();
      provider = TransferSessionProvider(settings: settings);
    });

    tearDown(() {
      provider.dispose();
    });

    test('Initial state is idle with empty history', () {
      expect(provider.currentState.state, equals(TransferState.idle));
      expect(provider.hasActiveTransfer, isFalse);
      expect(provider.history, isEmpty);
      expect(provider.pendingSasRequest, isNull);
      expect(provider.pendingProposal, isNull);
    });

    test('SAS verification confirm and reject state flow', () {
      final dummySas = SasCode(
        numericCode: '123-456',
        numericValue: 123456,
        emojis: const [
          SasEmoji(0, '🦊', 'Fox'),
          SasEmoji(1, '⚡', 'Lightning'),
          SasEmoji(2, '🪐', 'Saturn'),
          SasEmoji(3, '💎', 'Gem Stone'),
        ],
        rawBytes: Uint8List(4),
        transcriptHash: Uint8List(32),
      );

      final req = SasVerificationRequest(
        sasCode: dummySas,
        remoteAddress: '192.168.1.100',
        remotePort: 42385,
      );

      // Confirm flow
      req.confirm();
      expect(req.decision, completion(isTrue));

      // Reject flow
      final req2 = SasVerificationRequest(
        sasCode: dummySas,
        remoteAddress: '192.168.1.100',
        remotePort: 42385,
      );
      req2.reject();
      expect(req2.decision, completion(isFalse));
    });

    test('In-Memory RAM history records and clears correctly', () {
      expect(provider.history, isEmpty);
      provider.clearHistory();
      expect(provider.history, isEmpty);
    });

    test('Session reset restores idle state', () {
      provider.resetSession();
      expect(provider.currentState.state, equals(TransferState.idle));
      expect(provider.pendingSasRequest, isNull);
      expect(provider.pendingProposal, isNull);
    });
  });
}
