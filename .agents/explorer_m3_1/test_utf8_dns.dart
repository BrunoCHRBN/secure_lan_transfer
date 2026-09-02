import 'dart:io';
import 'test_mdns_engine.dart';

void main() {
  print('--- Testing UTF-8 and Edge Cases in DNS-SD Codec ---');

  final complexAttributes = {
    'id': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
    'name': 'José\'s iPhone 15 Pro Max 🚀 (LAN-Transfer)',
    'os': 'ios',
    'port': '42385',
    'proto': '1',
    'custom': 'ключ=значение',
  };

  final resp = DnsMessage(
    isResponse: true,
    isAuthoritative: true,
    answers: [
      PtrRecord(
        name: '_securetransfer._tcp.local',
        domainName: '${complexAttributes['name']}._securetransfer._tcp.local',
        ttl: 4500,
      ),
      SrvRecord(
        name: '${complexAttributes['name']}._securetransfer._tcp.local',
        port: 42385,
        target: 'joses-iphone.local',
        ttl: 120,
      ),
      TxtRecord(
        name: '${complexAttributes['name']}._securetransfer._tcp.local',
        attributes: complexAttributes,
        ttl: 120,
      ),
      ARecord(
        name: 'joses-iphone.local',
        address: InternetAddress('192.168.1.123'),
        ttl: 120,
      ),
    ],
  );

  final encoded = DnsCodec.encode(resp);
  print('Encoded complex message length: ${encoded.length} bytes');

  final decoded = DnsCodec.decode(encoded);
  assert(decoded.answers.length == 4);

  final txt = decoded.answers.whereType<TxtRecord>().first;
  print('Decoded TXT name: ${txt.attributes['name']}');
  print('Decoded TXT custom: ${txt.attributes['custom']}');

  assert(txt.attributes['name'] == complexAttributes['name']);
  assert(txt.attributes['custom'] == complexAttributes['custom']);
  print('=== UTF-8 & SPECIAL CHARACTERS TEST PASSED ===');
}
