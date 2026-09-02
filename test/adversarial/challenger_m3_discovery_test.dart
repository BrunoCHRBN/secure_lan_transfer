import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:secure_lan_transfer/core/crypto/obfuscation.dart';
import 'package:secure_lan_transfer/core/discovery/device_registry.dart';
import 'package:secure_lan_transfer/core/discovery/discovery_manager.dart';
import 'package:secure_lan_transfer/core/discovery/dns_codec.dart';
import 'package:secure_lan_transfer/core/discovery/udp_broadcast.dart';
import 'package:secure_lan_transfer/core/models/peer_device.dart';
import 'package:secure_lan_transfer/core/protocol/frame_codec.dart';
import 'package:secure_lan_transfer/core/protocol/packet_types.dart';
import 'package:secure_lan_transfer/core/protocol/session_state.dart';
import 'package:secure_lan_transfer/core/session/handshake_protocol.dart';
import 'package:secure_lan_transfer/core/session/session_manager.dart';
import 'package:test/test.dart';

void main() {
  setUp(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  group('CHALLENGER M3 — GROUP 1: Adversarial DNS Codec & Malformed Packet Fuzzing', () {
    test('1.1. Self-referencing cyclic compression pointer terminates safely without infinite loop', () {
      final builder = BytesBuilder();
      final header = ByteData(12);
      header.setUint16(0, 0x1234, Endian.big);
      header.setUint16(2, 0x8400, Endian.big); // Response, Authoritative
      header.setUint16(4, 0, Endian.big);
      header.setUint16(6, 1, Endian.big); // 1 answer
      header.setUint16(8, 0, Endian.big);
      header.setUint16(10, 0, Endian.big);
      builder.add(header.buffer.asUint8List());

      // At offset 12: create pointer pointing to offset 12 (0xC00C)
      builder.add(Uint8List.fromList([0xC0, 0x0C]));

      // Type PTR (12), Class IN (1), TTL 120, RDLen 2, RData points to offset 12 (0xC00C)
      final rMeta = ByteData(10);
      rMeta.setUint16(0, 12, Endian.big);
      rMeta.setUint16(2, 1, Endian.big);
      rMeta.setUint32(4, 120, Endian.big);
      rMeta.setUint16(8, 2, Endian.big);
      builder.add(rMeta.buffer.asUint8List());
      builder.add(Uint8List.fromList([0xC0, 0x0C]));

      final cyclicPacket = builder.toBytes();

      final decoded = DnsCodec.decode(cyclicPacket);
      expect(decoded.isResponse, isTrue);
      expect(decoded.answers.length, equals(1));
      expect(decoded.answers.first, isA<PtrRecord>());
    });

    test('1.2. Two-node mutually recursive pointer loop (A -> B -> A) terminates safely', () {
      final builder = BytesBuilder();
      final header = ByteData(12);
      header.setUint16(0, 0x5678, Endian.big);
      header.setUint16(2, 0x8400, Endian.big);
      header.setUint16(4, 0, Endian.big);
      header.setUint16(6, 1, Endian.big);
      header.setUint16(8, 0, Endian.big);
      header.setUint16(10, 0, Endian.big);
      builder.add(header.buffer.asUint8List());

      // Offset 12: pointer to offset 14 (0xC00E)
      builder.add(Uint8List.fromList([0xC0, 0x0E]));
      // Offset 14: pointer to offset 12 (0xC00C)
      builder.add(Uint8List.fromList([0xC0, 0x0C]));

      // Record metadata at offset 16
      final rMeta = ByteData(10);
      rMeta.setUint16(0, 12, Endian.big);
      rMeta.setUint16(2, 1, Endian.big);
      rMeta.setUint32(4, 60, Endian.big);
      rMeta.setUint16(8, 2, Endian.big);
      builder.add(rMeta.buffer.asUint8List());
      builder.add(Uint8List.fromList([0xC0, 0x0E]));

      final packet = builder.toBytes();
      expect(() => DnsCodec.decode(packet), returnsNormally);
      final decoded = DnsCodec.decode(packet);
      expect(decoded.isResponse, isTrue);
    });

    test('1.3. Out-of-bounds pointer offsets (forward and backward) handle gracefully', () {
      final builder = BytesBuilder();
      final header = ByteData(12);
      header.setUint16(6, 1, Endian.big); // 1 answer
      builder.add(header.buffer.asUint8List());

      // Offset 12: Pointer to offset 0xFFFF (far beyond packet length)
      builder.add(Uint8List.fromList([0xFF, 0xFF]));

      final rMeta = ByteData(10);
      rMeta.setUint16(0, 1, Endian.big); // A record
      rMeta.setUint16(2, 1, Endian.big);
      rMeta.setUint32(4, 120, Endian.big);
      rMeta.setUint16(8, 4, Endian.big);
      builder.add(rMeta.buffer.asUint8List());
      builder.add(Uint8List.fromList([192, 168, 1, 1]));

      final packet = builder.toBytes();
      expect(() => DnsCodec.decode(packet), returnsNormally);
    });

    test('1.4. Truncated pointer with only high byte (0xC0) at EOF handles safely', () {
      final builder = BytesBuilder();
      final header = ByteData(12);
      header.setUint16(6, 1, Endian.big);
      builder.add(header.buffer.asUint8List());
      builder.addByte(0xC0); // Truncated pointer (missing second byte)

      final packet = builder.toBytes();
      expect(() => DnsCodec.decode(packet), returnsNormally);
    });

    test('1.5. Truncation stress test at every single byte offset (0 to N)', () {
      final fullValid = DnsCodec.encode(DnsMessage(
        id: 42,
        isResponse: true,
        isAuthoritative: true,
        questions: const [
          DnsQuestion(name: '_securetransfer._tcp.local', type: DnsType.ptr),
        ],
        answers: [
          const PtrRecord(
            name: '_securetransfer._tcp.local',
            domainName: 'AdversaryNode._securetransfer._tcp.local',
            ttl: 4500,
          ),
          const SrvRecord(
            name: 'AdversaryNode._securetransfer._tcp.local',
            port: 42385,
            target: 'node.local',
            ttl: 120,
          ),
          const TxtRecord(
            name: 'AdversaryNode._securetransfer._tcp.local',
            attributes: {
              'id': 'adv-uuid-001',
              'name': 'Adversary Node',
              'port': '42385',
              'os': 'linux',
            },
            ttl: 120,
          ),
          ARecord(
            name: 'node.local',
            address: InternetAddress('10.0.0.99'),
            ttl: 120,
          ),
          AaaaRecord(
            name: 'node.local',
            address: InternetAddress('fe80::1'),
            ttl: 120,
          ),
        ],
      ));

      expect(fullValid.length, greaterThan(100));

      // Packets < 12 bytes must throw FormatException
      for (int i = 0; i < 12; i++) {
        final slice = Uint8List.fromList(fullValid.sublist(0, i));
        expect(() => DnsCodec.decode(slice), throwsFormatException);
      }

      // Packets >= 12 bytes must not crash with uncaught RangeError/StateError
      for (int i = 12; i <= fullValid.length; i++) {
        final slice = Uint8List.fromList(fullValid.sublist(0, i));
        expect(() => DnsCodec.decode(slice), returnsNormally);
      }
    });

    test('1.6. Corrupted TXT records (malformed keys, no equals, invalid UTF-8, oversized values)', () {
      final builder = BytesBuilder();
      final header = ByteData(12);
      header.setUint16(6, 1, Endian.big);
      builder.add(header.buffer.asUint8List());

      // Domain name: "txtcorrupt.local"
      builder.add(Uint8List.fromList([10, ...utf8.encode('txtcorrupt'), 5, ...utf8.encode('local'), 0]));

      // TXT Record Header
      final rMeta = ByteData(10);
      rMeta.setUint16(0, 16, Endian.big); // TXT
      rMeta.setUint16(2, 1, Endian.big);
      rMeta.setUint32(4, 120, Endian.big);

      // Craft malicious TXT rdata
      final rdata = BytesBuilder();
      // Entry 1: key without =
      final e1 = utf8.encode('solo_flag');
      rdata.addByte(e1.length);
      rdata.add(e1);

      // Entry 2: = leading
      final e2 = utf8.encode('=leading_val');
      rdata.addByte(e2.length);
      rdata.add(e2);

      // Entry 3: multiple equals
      final e3 = utf8.encode('matrix=a=b=c=d');
      rdata.addByte(e3.length);
      rdata.add(e3);

      // Entry 4: invalid UTF-8 bytes
      rdata.addByte(4);
      rdata.add(Uint8List.fromList([0x61, 0xFF, 0xFE, 0x62]));

      // Entry 5: length byte 250 (exceeds buffer)
      rdata.addByte(250);
      rdata.add(Uint8List.fromList([1, 2, 3]));

      final rdataBytes = rdata.toBytes();
      rMeta.setUint16(8, rdataBytes.length, Endian.big);

      builder.add(rMeta.buffer.asUint8List());
      builder.add(rdataBytes);

      final packet = builder.toBytes();
      final decoded = DnsCodec.decode(packet);

      expect(decoded.answers.length, equals(1));
      final txt = decoded.answers.first as TxtRecord;
      expect(txt.attributes.containsKey('solo_flag'), isTrue);
      expect(txt.attributes['solo_flag'], equals(''));
      expect(txt.attributes['matrix'], equals('a=b=c=d'));
    });

    test('1.7. Malformed SRV, A, AAAA records with invalid RData length parse safely', () {
      final builder = BytesBuilder();
      final header = ByteData(12);
      header.setUint16(6, 3, Endian.big); // 3 answers
      builder.add(header.buffer.asUint8List());

      // Answer 1: SRV with only 3 bytes (requires at least 6)
      builder.add(Uint8List.fromList([3, 115, 114, 118, 0]));
      final srvMeta = ByteData(10);
      srvMeta.setUint16(0, 33, Endian.big);
      srvMeta.setUint16(2, 1, Endian.big);
      srvMeta.setUint32(4, 120, Endian.big);
      srvMeta.setUint16(8, 3, Endian.big);
      builder.add(srvMeta.buffer.asUint8List());
      builder.add(Uint8List.fromList([0, 1, 2]));

      // Answer 2: A record with 2 bytes instead of 4
      builder.add(Uint8List.fromList([1, 97, 0]));
      final aMeta = ByteData(10);
      aMeta.setUint16(0, 1, Endian.big);
      aMeta.setUint16(2, 1, Endian.big);
      aMeta.setUint32(4, 120, Endian.big);
      aMeta.setUint16(8, 2, Endian.big);
      builder.add(aMeta.buffer.asUint8List());
      builder.add(Uint8List.fromList([192, 168]));

      // Answer 3: AAAA record with 8 bytes instead of 16
      builder.add(Uint8List.fromList([4, 97, 97, 97, 97, 0]));
      final aaaaMeta = ByteData(10);
      aaaaMeta.setUint16(0, 28, Endian.big);
      aaaaMeta.setUint16(2, 1, Endian.big);
      aaaaMeta.setUint32(4, 120, Endian.big);
      aaaaMeta.setUint16(8, 8, Endian.big);
      builder.add(aaaaMeta.buffer.asUint8List());
      builder.add(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));

      final packet = builder.toBytes();
      expect(() => DnsCodec.decode(packet), returnsNormally);
    });

    test('1.8. Extreme DNS header claims (65535 questions & records) with 12-byte payload', () {
      final header = ByteData(12);
      header.setUint16(0, 0xAAAA, Endian.big);
      header.setUint16(2, 0x0000, Endian.big);
      header.setUint16(4, 65535, Endian.big);
      header.setUint16(6, 65535, Endian.big);
      header.setUint16(8, 65535, Endian.big);
      header.setUint16(10, 65535, Endian.big);

      final decoded = DnsCodec.decode(header.buffer.asUint8List());
      expect(decoded.questions.isEmpty, isTrue);
      expect(decoded.answers.isEmpty, isTrue);
      expect(decoded.authorities.isEmpty, isTrue);
      expect(decoded.additionals.isEmpty, isTrue);
    });
  });

  group('CHALLENGER M3 — GROUP 2: Adversarial UDP Broadcast Beacon Fuzzing & Flood Resilience', () {
    test('2.1. UdpBroadcastListener discards non-JSON binary junk and high-entropy noise safely', () async {
      final listener = UdpBroadcastListener();
      final discovered = <PeerDevice>[];

      await listener.start(localDeviceId: 'local-fuzz-target');
      final sub = listener.onDeviceDiscovered.listen(discovered.add);

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.broadcastEnabled = true;

      final rng = Random(42);
      for (int i = 0; i < 50; i++) {
        final junkLen = rng.nextInt(512) + 1;
        final junkBytes = Uint8List(junkLen);
        for (int j = 0; j < junkLen; j++) {
          junkBytes[j] = rng.nextInt(256);
        }
        sender.send(junkBytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);
      }

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(discovered.isEmpty, isTrue);

      await sub.cancel();
      await listener.dispose();
      sender.close();
    });

    test('2.2. UdpBroadcastListener discards malformed/truncated JSON and non-Map JSON roots', () async {
      final listener = UdpBroadcastListener();
      final discovered = <PeerDevice>[];

      await listener.start(localDeviceId: 'local-json-target');
      final sub = listener.onDeviceDiscovered.listen(discovered.add);

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.broadcastEnabled = true;

      final badPayloads = [
        '{"magic": "SECFLX_BEACON", "v": 1, "id": ',
        '{"magic": "SECFLX_BEACON"}',
        '{"magic": "SECFLX_BEACON", "v": "not_an_int", "id": "123"}',
        '{"magic": "SECFLX_BEACON", "v": 2, "id": "123"}',
        '{"magic": "SECFLX_BEACON", "v": 1, "id": ""}',
        '["SECFLX_BEACON", 1, "device-id"]',
        '"SECFLX_BEACON_STRING"',
        '123456789',
        'null',
        'true',
      ];

      for (final p in badPayloads) {
        final bytes = Uint8List.fromList(utf8.encode(p));
        sender.send(bytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);
      }

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(discovered.isEmpty, isTrue);

      await sub.cancel();
      await listener.dispose();
      sender.close();
    });

    test('2.3. UdpBroadcastListener handles oversized 64KB JSON payload without OOM or hang', () async {
      final listener = UdpBroadcastListener();
      final discovered = <PeerDevice>[];

      await listener.start(localDeviceId: 'local-giant-target');
      final sub = listener.onDeviceDiscovered.listen(discovered.add);

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.broadcastEnabled = true;

      final giantMeta = <String, dynamic>{};
      for (int i = 0; i < 200; i++) {
        giantMeta['key_$i'] = 'X' * 200;
      }

      final payload = {
        'magic': 'SECFLX_BEACON',
        'v': 1,
        'id': 'giant-peer-1',
        'name': 'G' * 500,
        'os': 'linux',
        'port': 42385,
        'customMetadata': giantMeta,
      };

      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      try {
        sender.send(bytes, InternetAddress('255.255.255.255'), UdpBroadcastConstants.broadcastPort);
      } catch (_) {}
      try {
        sender.send(bytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);
      } catch (_) {}

      for (int i = 0; i < 20; i++) {
        if (discovered.any((d) => d.id == 'giant-peer-1')) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(discovered.any((d) => d.id == 'giant-peer-1'), isTrue);
      final found = discovered.firstWhere((d) => d.id == 'giant-peer-1');
      expect(found.name.length, equals(500));

      await sub.cancel();
      await listener.dispose();
      sender.close();
    });

    test('2.4. UdpBroadcastListener flood resilience: 300 rapid-fire beacons processed cleanly', () async {
      final listener = UdpBroadcastListener();
      final discoveredMap = <String, PeerDevice>{};

      await listener.start(localDeviceId: 'flood-target-node');
      final sub = listener.onDeviceDiscovered.listen((dev) {
        discoveredMap[dev.id] = dev;
      });

      final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      sender.broadcastEnabled = true;

      for (int i = 0; i < 300; i++) {
        final peerNum = i % 50;
        final payload = {
          'magic': 'SECFLX_BEACON',
          'v': 1,
          'id': 'burst-peer-$peerNum',
          'name': 'Burst Node #$peerNum',
          'os': 'android',
          'port': 40000 + peerNum,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
        try {
          sender.send(bytes, InternetAddress('255.255.255.255'), UdpBroadcastConstants.broadcastPort);
        } catch (_) {}
        try {
          sender.send(bytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);
        } catch (_) {}
      }

      for (int i = 0; i < 30; i++) {
        if (discoveredMap.length >= 50) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(discoveredMap.length, equals(50));
      expect(discoveredMap.containsKey('burst-peer-0'), isTrue);
      expect(discoveredMap.containsKey('burst-peer-49'), isTrue);

      await sub.cancel();
      await listener.dispose();
      sender.close();
    });
  });

  group('CHALLENGER M3 — GROUP 3: Reactive DeviceRegistry Concurrency & Thrashing Stress', () {
    test('3.1. High-throughput parallel ingestion of 500 unique devices', () async {
      final registry = DeviceRegistry();
      final emittedCounts = <int>[];
      final sub = registry.devicesStream.listen((list) {
        emittedCounts.add(list.length);
      });

      final futures = <Future<void>>[];
      for (int i = 0; i < 500; i++) {
        futures.add(Future(() {
          registry.registerOrUpdate(PeerDevice(
            id: 'peer-$i',
            name: 'Device $i',
            os: i % 2 == 0 ? 'windows' : 'linux',
            addresses: ['192.168.1.${i % 250 + 1}'],
            port: 42385,
            discoveryMethod: DiscoveryMethod.mdns,
            lastSeen: DateTime.now(),
          ));
        }));
      }

      await Future.wait(futures);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(registry.currentDevices.length, equals(500));
      expect(registry.getDevice('peer-0'), isNotNull);
      expect(registry.getDevice('peer-499'), isNotNull);
      expect(emittedCounts.last, equals(500));

      await sub.cancel();
      registry.dispose();
    });

    test('3.2. Address union deduplication: Rapid 100 updates to single device merges all addresses', () {
      final registry = DeviceRegistry();

      for (int i = 0; i < 100; i++) {
        registry.registerOrUpdate(PeerDevice(
          id: 'multi-addr-peer',
          name: 'Multi IP Host',
          os: 'macos',
          addresses: ['10.0.0.$i', '192.168.1.1'],
          discoveryMethod: DiscoveryMethod.udpBroadcast,
          lastSeen: DateTime.now(),
        ));
      }

      expect(registry.currentDevices.length, equals(1));
      final dev = registry.getDevice('multi-addr-peer')!;
      expect(dev.addresses.length, equals(101));
      expect(dev.addresses, contains('192.168.1.1'));
      expect(dev.addresses, contains('10.0.0.0'));
      expect(dev.addresses, contains('10.0.0.99'));

      registry.dispose();
    });

    test('3.3. Fine-grained Stale & Prune multi-tier transitions under timed stress', () async {
      final registry = DeviceRegistry(
        staleThreshold: const Duration(milliseconds: 150),
        pruneThreshold: const Duration(milliseconds: 400),
        sweepInterval: const Duration(milliseconds: 20),
      );

      final now = DateTime.now();

      // Register 100 devices at t=0
      for (int i = 0; i < 100; i++) {
        registry.registerOrUpdate(PeerDevice(
          id: 'timed-$i',
          name: 'Timed Node $i',
          os: 'android',
          addresses: ['192.168.1.10'],
          discoveryMethod: DiscoveryMethod.mdns,
          lastSeen: now,
        ));
      }

      expect(registry.currentDevices.length, equals(100));
      expect(registry.currentDevices.every((d) => !d.isStale), isTrue);

      // At t=80ms: Keep 30 devices fresh by updating their lastSeen
      await Future<void>.delayed(const Duration(milliseconds: 80));
      for (int i = 0; i < 30; i++) {
        registry.registerOrUpdate(PeerDevice(
          id: 'timed-$i',
          name: 'Timed Node $i',
          os: 'android',
          addresses: ['192.168.1.10'],
          discoveryMethod: DiscoveryMethod.mdns,
          lastSeen: DateTime.now(),
        ));
      }

      // At t=220ms:
      // Untouched 70 devices age = 220ms (>= 150ms staleThreshold) -> isStale = true
      // Refreshed 30 devices age = 140ms (< 150ms staleThreshold) -> isStale = false
      await Future<void>.delayed(const Duration(milliseconds: 140));
      final snapshot220 = registry.currentDevices;
      expect(snapshot220.length, equals(100));

      final staleCount = snapshot220.where((d) => d.isStale).length;
      final freshCount = snapshot220.where((d) => !d.isStale).length;
      expect(staleCount, equals(70));
      expect(freshCount, equals(30));

      // At t=420ms (delayed 200ms from t=220ms):
      // Untouched 70 devices age = 420ms (>= 400ms pruneThreshold) -> PRUNED
      // Refreshed 30 devices age = 340ms (< 400ms pruneThreshold) -> REMAINS ALIVE (30 devices)
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final snapshot420 = registry.currentDevices;
      expect(snapshot420.length, equals(30));
      for (int i = 0; i < 30; i++) {
        expect(registry.getDevice('timed-$i'), isNotNull);
      }
      for (int i = 30; i < 100; i++) {
        expect(registry.getDevice('timed-$i'), isNull);
      }

      // At t=600ms (delayed 180ms from t=420ms):
      // Refreshed 30 devices age = 520ms (>= 400ms pruneThreshold) -> PRUNED (0 devices)
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(registry.currentDevices.isEmpty, isTrue);

      registry.dispose();
    });

    test('3.4. Concurrent clear/remove during active sweep does not cause ConcurrentModificationError', () async {
      final registry = DeviceRegistry(
        staleThreshold: const Duration(milliseconds: 20),
        pruneThreshold: const Duration(milliseconds: 50),
        sweepInterval: const Duration(milliseconds: 5),
      );

      for (int cycle = 0; cycle < 10; cycle++) {
        for (int i = 0; i < 50; i++) {
          registry.registerOrUpdate(PeerDevice(
            id: 'race-$i',
            name: 'Race Node $i',
            os: 'ios',
            addresses: ['192.168.1.5'],
            discoveryMethod: DiscoveryMethod.mdns,
            lastSeen: DateTime.now(),
          ));
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
        registry.remove('race-5');
        registry.remove('race-25');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        registry.clear();
      }

      expect(registry.currentDevices.isEmpty, isTrue);
      registry.dispose();
    });
  });

  group('CHALLENGER M3 — GROUP 4: Discovery Manager Lifecycle Thrashing', () {
    test('4.1. DiscoveryManager rapid lifecycle thrashing (start/stop/broadcast cycles)', () async {
      final manager = DiscoveryManager();
      manager.initialize(
        deviceId: 'thrash-manager-node',
        deviceName: 'Thrash Manager',
        os: 'windows',
      );

      for (int i = 0; i < 5; i++) {
        await manager.startDiscovery();
        await manager.startAdvertising();
        await manager.broadcastPresence();
        await manager.stopAdvertising();
        await manager.stopDiscovery();
      }

      expect(manager.isDiscovering, isFalse);
      expect(manager.isAdvertising, isFalse);

      await manager.dispose();
    });
  });

  group('CHALLENGER M3 — GROUP 5: Adversarial Session Handshake & Connection Resilience', () {
    test('5.1. SessionManager rejects second connection when already active', () async {
      final sessionManager = SessionManager(
        options: const SessionManagerOptions(
          autoAcceptInbound: true,
          autoVerifySas: true,
        ),
      );

      await sessionManager.startServer(port: 0);
      final port = sessionManager.serverPort!;

      sessionManager.stateMachine.transitionTo(TransferState.handshaking);
      sessionManager.stateMachine.transitionTo(TransferState.transferring);
      expect(sessionManager.currentState.isActive, isTrue);

      final clientSocket = await Socket.connect('127.0.0.1', port);

      final completer = Completer<void>();
      clientSocket.listen(
        (_) {},
        onDone: () => completer.complete(),
        onError: (_) => completer.complete(),
      );

      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('Client socket was not closed when server was busy'),
      );

      clientSocket.destroy();
      sessionManager.stateMachine.reset();
      await sessionManager.stopServer();
      sessionManager.dispose();
    });

    test('5.2. Handshake with corrupted HandshakeEnvelope throws Exception cleanly', () async {
      final handshake = HandshakeProtocol();
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      server.listen((socket) async {
        final codec = FrameCodec();
        final badFrame = Frame(
          type: FrameType.handshakeResp,
          streamId: 0,
          sequence: 0,
          payload: Uint8List.fromList([1, 2, 3, 4]),
        );
        final encoded = await codec.encodeFrame(badFrame, keys: null);
        socket.add(encoded);
        await socket.flush();
      });

      final clientSocket = await Socket.connect('127.0.0.1', server.port);

      expect(
        () => handshake.performClientHandshake(
          clientSocket,
          onVerifySas: (_) async => true,
        ),
        throwsA(anyOf(isA<HandshakeException>(), isA<ObfuscationException>())),
      );

      await server.close();
    });

    test('5.3. Abrupt socket close during client handshake triggers timeout or HandshakeException cleanly', () async {
      final handshake = HandshakeProtocol(
        options: const HandshakeOptions(
          timeout: Duration(milliseconds: 300),
        ),
      );

      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

      server.listen((socket) async {
        socket.destroy();
      });

      final clientSocket = await Socket.connect('127.0.0.1', server.port);

      expect(
        () => handshake.performClientHandshake(clientSocket),
        throwsA(isA<HandshakeException>()),
      );

      await server.close();
    });
  });
}
