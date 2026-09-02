import 'dart:async';
import 'dart:io';
import 'package:secure_lan_transfer/core/discovery/device_registry.dart';
import 'package:secure_lan_transfer/core/discovery/discovery_manager.dart';
import 'package:secure_lan_transfer/core/models/peer_device.dart';
import 'package:test/test.dart';

void main() {
  group('PeerDevice Model Unit Tests', () {
    test('JSON serialization and deserialization roundtrip', () {
      final now = DateTime.now();
      final device = PeerDevice(
        id: 'uuid-1234-abcd',
        name: 'Workstation Pro',
        os: 'windows',
        addresses: ['192.168.1.100', 'fe80::1'],
        port: 42385,
        discoveryMethod: DiscoveryMethod.mdns,
        lastSeen: now,
        isStale: false,
        customMetadata: {'version': '1.0.0', 'features': ['crypto', 'staging']},
      );

      final json = device.toJson();
      final fromJson = PeerDevice.fromJson(json);

      expect(fromJson.id, equals(device.id));
      expect(fromJson.name, equals(device.name));
      expect(fromJson.os, equals(device.os));
      expect(fromJson.addresses, equals(device.addresses));
      expect(fromJson.port, equals(device.port));
      expect(fromJson.discoveryMethod, equals(device.discoveryMethod));
      expect(fromJson.lastSeen.millisecondsSinceEpoch,
          equals(device.lastSeen.millisecondsSinceEpoch));
      expect(fromJson.isStale, equals(device.isStale));
      expect(fromJson.customMetadata, equals(device.customMetadata));
      expect(fromJson, equals(device));
      expect(fromJson.hashCode, equals(device.hashCode));
    });

    test('primaryAddress prefers IPv4 address over IPv6', () {
      final now = DateTime.now();
      final device = PeerDevice(
        id: 'device-1',
        name: 'Device 1',
        os: 'linux',
        addresses: const ['fe80::1234', '192.168.1.55', '10.0.0.1'],
        discoveryMethod: DiscoveryMethod.udpBroadcast,
        lastSeen: now,
      );

      expect(device.primaryAddress, equals('192.168.1.55'));
    });

    test('copyWith preserves unchanged properties', () {
      final dev = PeerDevice(
        id: 'id-1',
        name: 'Original',
        os: 'android',
        addresses: ['192.168.1.1'],
        port: 42385,
        discoveryMethod: DiscoveryMethod.manual,
        lastSeen: DateTime.now(),
      );

      final updated = dev.copyWith(name: 'Updated Name', isStale: true);
      expect(updated.id, equals('id-1'));
      expect(updated.name, equals('Updated Name'));
      expect(updated.os, equals('android'));
      expect(updated.isStale, isTrue);
      expect(updated.isOnline, isFalse);
    });
  });

  group('DeviceRegistry Unit Tests', () {
    test('Register fresh device emits update to devicesStream', () async {
      final registry = DeviceRegistry();
      final streamEvents = <List<PeerDevice>>[];
      final sub = registry.devicesStream.listen(streamEvents.add);

      final dev = PeerDevice(
        id: 'dev-100',
        name: 'Alpha Node',
        os: 'macos',
        addresses: ['192.168.1.20'],
        discoveryMethod: DiscoveryMethod.mdns,
        lastSeen: DateTime.now(),
      );

      registry.registerOrUpdate(dev);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(registry.currentDevices.length, equals(1));
      expect(registry.getDevice('dev-100')?.name, equals('Alpha Node'));
      expect(streamEvents.isNotEmpty, isTrue);
      expect(streamEvents.last.first.id, equals('dev-100'));

      await sub.cancel();
      registry.dispose();
    });

    test('Multi-source deduplication merges addresses and updates lastSeen', () async {
      final registry = DeviceRegistry();

      final t1 = DateTime.now();
      final dev1 = PeerDevice(
        id: 'dev-multi',
        name: 'Shared Device',
        os: 'android',
        addresses: ['192.168.1.30'],
        port: 42385,
        discoveryMethod: DiscoveryMethod.mdns,
        lastSeen: t1,
      );
      registry.registerOrUpdate(dev1);

      final t2 = t1.add(const Duration(seconds: 1));
      final dev2 = PeerDevice(
        id: 'dev-multi',
        name: 'Shared Device Renamed',
        os: 'android',
        addresses: ['192.168.1.31', '10.0.0.5'],
        port: 42385,
        discoveryMethod: DiscoveryMethod.udpBroadcast,
        lastSeen: t2,
        customMetadata: {'extra': 'value'},
      );
      registry.registerOrUpdate(dev2);

      expect(registry.currentDevices.length, equals(1));
      final merged = registry.getDevice('dev-multi')!;
      expect(merged.name, equals('Shared Device Renamed'));
      expect(merged.addresses, containsAll(['192.168.1.30', '192.168.1.31', '10.0.0.5']));
      expect(merged.lastSeen, equals(t2));
      expect(merged.customMetadata['extra'], equals('value'));

      registry.dispose();
    });

    test('Transitions to isStale when device age exceeds staleThreshold', () async {
      final registry = DeviceRegistry(
        staleThreshold: const Duration(milliseconds: 100),
        pruneThreshold: const Duration(milliseconds: 500),
        sweepInterval: const Duration(milliseconds: 20),
      );

      final streamHistory = <List<PeerDevice>>[];
      final sub = registry.devicesStream.listen(streamHistory.add);

      final dev = PeerDevice(
        id: 'stale-dev',
        name: 'Stale Candidate',
        os: 'windows',
        addresses: ['192.168.1.40'],
        discoveryMethod: DiscoveryMethod.mdns,
        lastSeen: DateTime.now(),
      );

      registry.registerOrUpdate(dev);
      expect(registry.getDevice('stale-dev')?.isStale, isFalse);

      // Wait past 100ms stale threshold
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(registry.getDevice('stale-dev')?.isStale, isTrue);
      expect(streamHistory.last.first.isStale, isTrue);

      await sub.cancel();
      registry.dispose();
    });

    test('Automatically prunes device when age exceeds pruneThreshold', () async {
      final registry = DeviceRegistry(
        staleThreshold: const Duration(milliseconds: 50),
        pruneThreshold: const Duration(milliseconds: 120),
        sweepInterval: const Duration(milliseconds: 20),
      );

      final streamHistory = <List<PeerDevice>>[];
      final sub = registry.devicesStream.listen(streamHistory.add);

      final dev = PeerDevice(
        id: 'prune-dev',
        name: 'Prune Candidate',
        os: 'linux',
        addresses: ['192.168.1.50'],
        discoveryMethod: DiscoveryMethod.udpBroadcast,
        lastSeen: DateTime.now(),
      );

      registry.registerOrUpdate(dev);
      expect(registry.currentDevices.length, equals(1));

      // Wait past 120ms prune threshold
      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(registry.currentDevices.isEmpty, isTrue);
      expect(registry.getDevice('prune-dev'), isNull);
      expect(streamHistory.last.isEmpty, isTrue);

      await sub.cancel();
      registry.dispose();
    });

    test('remove and clear methods work correctly', () {
      final registry = DeviceRegistry();
      final dev1 = PeerDevice(
        id: 'dev-1',
        name: 'Dev 1',
        os: 'ios',
        addresses: ['192.168.1.1'],
        discoveryMethod: DiscoveryMethod.manual,
        lastSeen: DateTime.now(),
      );
      final dev2 = PeerDevice(
        id: 'dev-2',
        name: 'Dev 2',
        os: 'ios',
        addresses: ['192.168.1.2'],
        discoveryMethod: DiscoveryMethod.manual,
        lastSeen: DateTime.now(),
      );

      registry.registerOrUpdate(dev1);
      registry.registerOrUpdate(dev2);
      expect(registry.currentDevices.length, equals(2));

      registry.remove('dev-1');
      expect(registry.currentDevices.length, equals(1));
      expect(registry.getDevice('dev-1'), isNull);

      registry.clear();
      expect(registry.currentDevices.isEmpty, isTrue);

      registry.dispose();
    });
  });

  group('DiscoveryManager Facade Unit Tests', () {
    test('Initializes profile and coordinates manual device addition', () async {
      final manager = DiscoveryManager();
      manager.initialize(
        deviceId: 'local-test-uuid',
        deviceName: 'Local Manager',
        os: 'windows',
        transferPort: 42385,
      );

      expect(manager.localDeviceId, equals('local-test-uuid'));
      expect(manager.localDeviceName, equals('Local Manager'));
      expect(manager.isDiscovering, isFalse);
      expect(manager.isAdvertising, isFalse);

      final testServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      testServer.listen((socket) => socket.listen((_) {}));

      final device = await manager.addManualDevice(
        '127.0.0.1',
        port: testServer.port,
        deviceName: 'Loopback Target',
      );

      expect(device.name, equals('Loopback Target'));
      expect(manager.currentDevices.length, equals(1));
      expect(manager.currentDevices.first.id, equals(device.id));

      await testServer.close();
      await manager.dispose();
    });

    test('Start and stop advertising/discovery toggles states cleanly', () async {
      final manager = DiscoveryManager();
      manager.initialize(
        deviceId: 'node-toggle-test',
        deviceName: 'Toggle Node',
      );

      await manager.startDiscovery();
      expect(manager.isDiscovering, isTrue);

      await manager.startAdvertising();
      expect(manager.isAdvertising, isTrue);

      await manager.broadcastPresence();

      await manager.stopAdvertising();
      expect(manager.isAdvertising, isFalse);

      await manager.stopDiscovery();
      expect(manager.isDiscovering, isFalse);

      await manager.dispose();
    });
  });
}
