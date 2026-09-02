import 'dart:async';
import 'dart:io';
import 'test_mdns_engine.dart';

void main() async {
  print('--- Testing Live Pure Dart mDNS Advertiser & Browser ---');
  
  final stopwatch = Stopwatch()..start();

  // 1. Start Advertiser (Simulates Device A: Windows Desktop listening on 5353)
  final advSocket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    5353,
    reuseAddress: true,
    reusePort: false,
  );
  advSocket.joinMulticast(InternetAddress('224.0.0.251'));
  advSocket.multicastLoopback = true;
  advSocket.multicastHops = 255;

  final deviceA = {
    'id': 'device-uuid-aaaa-1111',
    'name': 'Windows Workstation',
    'os': 'windows',
    'port': '42385',
    'proto': '1',
  };

  void sendResponse({InternetAddress? targetAddress, int targetPort = 5353, int ttl = 120}) {
    final resp = DnsMessage(
      isResponse: true,
      isAuthoritative: true,
      answers: [
        PtrRecord(
          name: '_securetransfer._tcp.local',
          domainName: '${deviceA['name']}._securetransfer._tcp.local',
          ttl: ttl > 0 ? 4500 : 0,
        ),
        SrvRecord(
          name: '${deviceA['name']}._securetransfer._tcp.local',
          port: 42385,
          target: 'workstation.local',
          ttl: ttl,
        ),
        TxtRecord(
          name: '${deviceA['name']}._securetransfer._tcp.local',
          attributes: deviceA,
          ttl: ttl,
        ),
      ],
    );
    final bytes = DnsCodec.encode(resp);
    final dest = targetAddress ?? InternetAddress('224.0.0.251');
    advSocket.send(bytes, dest, targetPort);
    print('Advertiser sent response (${bytes.length} bytes) to ${dest.address}:$targetPort');
  }

  advSocket.listen((event) {
    if (event == RawSocketEvent.read) {
      final dg = advSocket.receive();
      if (dg != null) {
        try {
          final msg = DnsCodec.decode(dg.data);
          print('Advertiser received message from ${dg.address.address}:${dg.port}, isResponse=${msg.isResponse}');
          if (!msg.isResponse) {
            for (final q in msg.questions) {
              if (q.name == '_securetransfer._tcp.local' ||
                  q.name == '${deviceA['name']}._securetransfer._tcp.local') {
                // If query came from ephemeral port (dg.port != 5353) or unicast bit set:
                if (dg.port != 5353 || q.unicastResponse) {
                  sendResponse(targetAddress: dg.address, targetPort: dg.port);
                } else {
                  sendResponse();
                }
                break;
              }
            }
          }
        } catch (e, st) {
          print('Adv decode error: $e');
        }
      }
    }
  });

  // 2. Start Browser (Simulates Device B: querying on ephemeral or shared port)
  final browserSocket = await RawDatagramSocket.bind(
    InternetAddress.anyIPv4,
    0, // Ephemeral port for browser
    reuseAddress: true,
    reusePort: false,
  );
  browserSocket.joinMulticast(InternetAddress('224.0.0.251'));
  browserSocket.multicastLoopback = true;
  print('Browser bound to port ${browserSocket.port}');

  final completer = Completer<Map<String, String>>();

  browserSocket.listen((event) {
    if (event == RawSocketEvent.read) {
      final dg = browserSocket.receive();
      if (dg != null) {
        try {
          print('Browser received ${dg.data.length} bytes from ${dg.address.address}:${dg.port}');
          final msg = DnsCodec.decode(dg.data);
          if (msg.isResponse) {
            for (final ans in msg.answers) {
              if (ans is TxtRecord && ans.attributes.containsKey('id')) {
                if (!completer.isCompleted) {
                  completer.complete(ans.attributes);
                }
              }
            }
          }
        } catch (e) {
          print('Browser decode error: $e');
        }
      }
    }
  });

  // Browser sends query
  final query = DnsMessage(
    questions: [
      const DnsQuestion(
        name: '_securetransfer._tcp.local',
        type: DnsType.ptr,
        unicastResponse: true,
      ),
    ],
  );
  final qBytes = DnsCodec.encode(query);
  final sent = browserSocket.send(qBytes, InternetAddress('224.0.0.251'), 5353);
  print('Browser sent query ($sent bytes) to 224.0.0.251:5353');

  final discovered = await completer.future.timeout(const Duration(seconds: 2));
  final elapsedMs = stopwatch.elapsedMilliseconds;
  print('Discovered Device in ${elapsedMs}ms: $discovered');

  assert(discovered['id'] == 'device-uuid-aaaa-1111');
  assert(discovered['name'] == 'Windows Workstation');
  assert(discovered['os'] == 'windows');
  assert(discovered['port'] == '42385');
  assert(elapsedMs < 2000, 'Discovery latency must be under 2000ms');

  // 3. Test Goodbye Packet
  sendResponse(ttl: 0);
  print('Sent Goodbye packet with TTL 0');

  // Teardown
  advSocket.close();
  browserSocket.close();
  print('Sockets cleanly closed.');
  print('=== LIVE MDNS DISCOVERY BENCHMARK PASSED (<2s latency)! ===');
}
