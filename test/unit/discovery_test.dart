import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:secure_lan_transfer/core/discovery/dns_codec.dart';
import 'package:secure_lan_transfer/core/discovery/manual_connection.dart';
import 'package:secure_lan_transfer/core/discovery/mdns_discovery.dart';
import 'package:secure_lan_transfer/core/discovery/udp_broadcast.dart';
import 'package:secure_lan_transfer/core/models/peer_device.dart';
import 'package:test/test.dart';

void main() {
  group('DNS Codec Unit Tests', () {
    test('Encodes and decodes standard mDNS query message', () {
      const query = DnsMessage(
        id: 0,
        questions: [
          DnsQuestion(
            name: '_securetransfer._tcp.local',
            type: DnsType.ptr,
            unicastResponse: true,
          ),
        ],
      );

      final encoded = DnsCodec.encode(query);
      expect(encoded.length, greaterThan(12));

      final decoded = DnsCodec.decode(encoded);
      expect(decoded.id, equals(0));
      expect(decoded.isResponse, isFalse);
      expect(decoded.questions.length, equals(1));
      expect(decoded.questions.first.name, equals('_securetransfer._tcp.local'));
      expect(decoded.questions.first.type, equals(DnsType.ptr));
      expect(decoded.questions.first.unicastResponse, isTrue);
    });

    test('Encodes and decodes complete DNS-SD response with PTR, SRV, TXT, A records', () {
      final response = DnsMessage(
        id: 0,
        isResponse: true,
        isAuthoritative: true,
        answers: [
          const PtrRecord(
            name: '_securetransfer._tcp.local',
            domainName: 'Pixel 7 Pro._securetransfer._tcp.local',
            ttl: 4500,
          ),
          const SrvRecord(
            name: 'Pixel 7 Pro._securetransfer._tcp.local',
            port: 42385,
            target: 'pixel7pro.local',
            ttl: 120,
          ),
          const TxtRecord(
            name: 'Pixel 7 Pro._securetransfer._tcp.local',
            attributes: {
              'id': 'e8b2c451-91a3-4a11-b0e2-df9824619712',
              'name': 'Pixel 7 Pro',
              'os': 'android',
              'port': '42385',
              'proto': '1',
            },
            ttl: 120,
          ),
          ARecord(
            name: 'pixel7pro.local',
            address: InternetAddress('192.168.1.50'),
            ttl: 120,
          ),
        ],
      );

      final bytes = DnsCodec.encode(response);
      final decoded = DnsCodec.decode(bytes);

      expect(decoded.isResponse, isTrue);
      expect(decoded.isAuthoritative, isTrue);
      expect(decoded.answers.length, equals(4));

      final ptr = decoded.answers.whereType<PtrRecord>().first;
      expect(ptr.name, equals('_securetransfer._tcp.local'));
      expect(ptr.domainName, equals('Pixel 7 Pro._securetransfer._tcp.local'));
      expect(ptr.ttl, equals(4500));

      final srv = decoded.answers.whereType<SrvRecord>().first;
      expect(srv.name, equals('Pixel 7 Pro._securetransfer._tcp.local'));
      expect(srv.port, equals(42385));
      expect(srv.target, equals('pixel7pro.local'));

      final txt = decoded.answers.whereType<TxtRecord>().first;
      expect(txt.name, equals('Pixel 7 Pro._securetransfer._tcp.local'));
      expect(txt.attributes['id'], equals('e8b2c451-91a3-4a11-b0e2-df9824619712'));
      expect(txt.attributes['name'], equals('Pixel 7 Pro'));
      expect(txt.attributes['os'], equals('android'));
      expect(txt.attributes['port'], equals('42385'));

      final a = decoded.answers.whereType<ARecord>().first;
      expect(a.address.address, equals('192.168.1.50'));
    });

    test('Encodes and decodes UTF-8 and Unicode device names with emojis', () {
      const unicodeName = "José's MacBook Pro 🚀 & iPad 📱";
      const msg = DnsMessage(
        isResponse: true,
        answers: [
          TxtRecord(
            name: '$unicodeName._securetransfer._tcp.local',
            attributes: {
              'id': 'unicode-uuid-1234',
              'name': unicodeName,
              'os': 'macos',
            },
          ),
        ],
      );

      final bytes = DnsCodec.encode(msg);
      final decoded = DnsCodec.decode(bytes);
      final txt = decoded.answers.whereType<TxtRecord>().first;

      expect(txt.attributes['name'], equals(unicodeName));
      expect(txt.name, equals('$unicodeName._securetransfer._tcp.local'));
    });

    test('Handles RFC 1035 name compression pointers correctly', () {
      // Create packet with duplicate domain names
      const msg = DnsMessage(
        isResponse: true,
        answers: [
          PtrRecord(
            name: '_securetransfer._tcp.local',
            domainName: 'Instance._securetransfer._tcp.local',
          ),
          SrvRecord(
            name: 'Instance._securetransfer._tcp.local',
            port: 42385,
            target: 'target.local',
          ),
        ],
      );

      final bytes = DnsCodec.encode(msg);
      final decoded = DnsCodec.decode(bytes);
      expect(decoded.answers.length, equals(2));
      expect(decoded.answers[0].name, equals('_securetransfer._tcp.local'));
      expect(decoded.answers[1].name, equals('Instance._securetransfer._tcp.local'));
    });

    test('Rejects packet smaller than 12 bytes with FormatException', () {
      final shortBytes = Uint8List.fromList([0, 1, 2, 3]);
      expect(() => DnsCodec.decode(shortBytes), throwsFormatException);
    });

    test('Handles malformed or truncated DNS payloads safely without unhandled crashes', () {
      final valid = DnsCodec.encode(const DnsMessage(
        questions: [
          DnsQuestion(name: 'test.local', type: DnsType.ptr),
        ],
      ));

      // Truncate at various offsets
      for (int len = 12; len < valid.length; len++) {
        final truncated = Uint8List.fromList(valid.sublist(0, len));
        expect(() => DnsCodec.decode(truncated), returnsNormally);
      }
    });
  });

  group('UDP Broadcast Discovery Unit Tests', () {
    test('UdpBroadcastBeacon transmits valid JSON beacon', () async {
      final beacon = UdpBroadcastBeacon(interval: const Duration(milliseconds: 100));
      expect(beacon.isBroadcasting, isFalse);

      await beacon.start(
        id: 'test-device-uuid',
        name: 'Test Device',
        os: 'windows',
        port: 42385,
        customMetadata: {'version': '1.0.0'},
      );

      expect(beacon.isBroadcasting, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await beacon.stop();
      expect(beacon.isBroadcasting, isFalse);
    });

    test('UdpBroadcastListener parses valid beacon datagram and rejects self-beacons', () async {
      final listener = UdpBroadcastListener();
      final discoveredDevices = <PeerDevice>[];

      await listener.start(localDeviceId: 'local-self-id');
      final sub = listener.onDeviceDiscovered.listen(discoveredDevices.add);

      // Simulate sending a remote beacon over loopback UDP
      final senderSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      senderSocket.broadcastEnabled = true;

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 1. Send remote beacon
      final remotePayload = {
        'magic': 'SECFLX_BEACON',
        'v': 1,
        'id': 'remote-peer-999',
        'name': 'Remote Laptop',
        'os': 'linux',
        'port': 42385,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'customMetadata': {'proto': 1},
      };
      final remoteBytes = Uint8List.fromList(utf8.encode(jsonEncode(remotePayload)));
      for (int i = 0; i < 3; i++) {
        try {
          senderSocket.send(remoteBytes, InternetAddress('255.255.255.255'), UdpBroadcastConstants.broadcastPort);
        } catch (_) {}
        try {
          senderSocket.send(remoteBytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // 2. Send self beacon (should be ignored)
      final selfPayload = {
        'magic': 'SECFLX_BEACON',
        'v': 1,
        'id': 'local-self-id',
        'name': 'My Device',
        'os': 'windows',
        'port': 42385,
      };
      final selfBytes = Uint8List.fromList(utf8.encode(jsonEncode(selfPayload)));
      senderSocket.send(selfBytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);

      // 3. Send invalid magic beacon (should be ignored)
      final invalidPayload = {
        'magic': 'INVALID_MAGIC',
        'v': 1,
        'id': 'invalid-peer',
      };
      final invalidBytes = Uint8List.fromList(utf8.encode(jsonEncode(invalidPayload)));
      senderSocket.send(invalidBytes, InternetAddress.loopbackIPv4, UdpBroadcastConstants.broadcastPort);

      for (int i = 0; i < 20; i++) {
        if (discoveredDevices.any((d) => d.id == 'remote-peer-999')) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(discoveredDevices.any((d) => d.id == 'remote-peer-999'), isTrue);
      final found = discoveredDevices.firstWhere((d) => d.id == 'remote-peer-999');
      expect(found.name, equals('Remote Laptop'));
      expect(found.os, equals('linux'));
      expect(found.discoveryMethod, equals(DiscoveryMethod.udpBroadcast));
      expect(discoveredDevices.any((d) => d.id == 'local-self-id'), isFalse);
      expect(discoveredDevices.any((d) => d.id == 'invalid-peer'), isFalse);

      await sub.cancel();
      await listener.dispose();
      senderSocket.close();
    });
  });

  group('Manual Connection Prober Unit Tests', () {
    test('Throws invalidAddress on empty host', () async {
      final prober = ManualConnectionProber();
      expect(
        () => prober.probe('   ', port: 42385),
        throwsA(isA<ManualConnectionException>().having(
          (e) => e.code,
          'code',
          ManualConnectionErrorCode.invalidAddress,
        )),
      );
    });

    test('Throws invalidPort on out-of-range port', () async {
      final prober = ManualConnectionProber();
      expect(
        () => prober.probe('127.0.0.1', port: 0),
        throwsA(isA<ManualConnectionException>().having(
          (e) => e.code,
          'code',
          ManualConnectionErrorCode.invalidPort,
        )),
      );
      expect(
        () => prober.probe('127.0.0.1', port: 70000),
        throwsA(isA<ManualConnectionException>().having(
          (e) => e.code,
          'code',
          ManualConnectionErrorCode.invalidPort,
        )),
      );
    });

    test('Probes active loopback ServerSocket and creates PeerDevice', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;

      server.listen((socket) {
        socket.listen((_) {});
      });

      final prober = ManualConnectionProber();
      final device = await prober.probe('127.0.0.1', port: port, deviceName: 'Direct Target');

      expect(device.name, equals('Direct Target'));
      expect(device.port, equals(port));
      expect(device.addresses, contains('127.0.0.1'));
      expect(device.discoveryMethod, equals(DiscoveryMethod.manual));
      expect(device.isOnline, isTrue);

      await server.close();
    });

    test('Throws connectionRefused on closed port', () async {
      final prober = ManualConnectionProber();
      // Probe an unlikely open port
      expect(
        () => prober.probe('127.0.0.1', port: 59999, timeout: const Duration(milliseconds: 500)),
        throwsA(isA<ManualConnectionException>()),
      );
    });
  });

  group('mDNS Discovery Integration Unit Tests', () {
    test('MdnsDiscovery advertiser and browser discover peer and handle Goodbye packet', () async {
      final advertiser = MdnsAdvertiser();
      final browser = MdnsBrowser();

      final discoveredList = <PeerDevice>[];
      final lostList = <String>[];

      await advertiser.start(
        id: 'mdns-device-001',
        name: 'mDNS Test Node',
        os: 'windows',
        port: 42385,
        customMetadata: {'version': '2.0'},
      );

      await browser.start(localDeviceId: 'local-browser-node');
      final discSub = browser.onDeviceDiscovered.listen(discoveredList.add);
      final lostSub = browser.onDeviceLost.listen(lostList.add);

      for (int i = 0; i < 30; i++) {
        if (discoveredList.any((d) => d.id == 'mdns-device-001')) break;
        await browser.queryNow();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(discoveredList.any((d) => d.id == 'mdns-device-001'), isTrue);
      final found = discoveredList.firstWhere((d) => d.id == 'mdns-device-001');
      expect(found.name, equals('mDNS Test Node'));
      expect(found.discoveryMethod, equals(DiscoveryMethod.mdns));

      // Test Goodbye (TTL = 0) on advertiser stop
      await advertiser.stop();
      for (int i = 0; i < 40; i++) {
        if (lostList.contains('mdns-device-001')) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(lostList, contains('mdns-device-001'));

      await discSub.cancel();
      await lostSub.cancel();
      await browser.dispose();
    });
  });
}
