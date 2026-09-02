import 'dart:async';
import 'dart:io';
import '../models/peer_device.dart';
import 'dns_codec.dart';

/// Multicast DNS protocol constants (RFC 6762 / RFC 6763).
class MdnsConstants {
  static const String multicastIpv4 = '224.0.0.251';
  static const int mdnsPort = 5353;
  static const String serviceType = '_securetransfer._tcp.local';
}

/// Pure Dart mDNS Service Advertiser.
class MdnsAdvertiser {
  final Set<(InternetAddress, int)> _knownQueriers = {};
  RawDatagramSocket? _socket;
  String? _id;
  String? _name;
  String? _os;
  int _port = 42385;
  Map<String, dynamic>? _customMetadata;
  bool _isAdvertising = false;
  Timer? _burstTimer;

  bool get isAdvertising => _isAdvertising;

  /// Starts advertising local presence via mDNS.
  Future<void> start({
    required String id,
    required String name,
    required String os,
    required int port,
    Map<String, dynamic>? customMetadata,
  }) async {
    if (_isAdvertising) await stop();

    _id = id;
    _name = name;
    _os = os;
    _port = port;
    _customMetadata = customMetadata;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        MdnsConstants.mdnsPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    } catch (_) {
      // Fallback to ephemeral port if 5353 is strictly held
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
    }

    try {
      _socket!.joinMulticast(InternetAddress(MdnsConstants.multicastIpv4));
      _socket!.multicastLoopback = true;
      _socket!.multicastHops = 255;
    } catch (_) {}

    _isAdvertising = true;

    _socket!.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          _handleIncomingDatagram();
        }
      },
      onError: (_) {},
    );

    // Gratuitous announcement burst: t=0, t=300ms, t=1000ms
    await broadcastAnnouncement();
    _burstTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_isAdvertising) await broadcastAnnouncement();
    });
  }

  void _handleIncomingDatagram() {
    final dg = _socket?.receive();
    if (dg == null || !_isAdvertising) return;

    try {
      final msg = DnsCodec.decode(dg.data);
      if (msg.isResponse) return; // Ignore responses

      for (final q in msg.questions) {
        final queryMatch = q.name == MdnsConstants.serviceType ||
            q.name == '$_name.${MdnsConstants.serviceType}' ||
            q.name == '_services._dns-sd._udp.local';

        if (queryMatch) {
          _knownQueriers.add((dg.address, dg.port));
          if (dg.port != MdnsConstants.mdnsPort || q.unicastResponse) {
            // Direct unicast reply (RFC 6762 §5.4)
            _sendResponse(targetAddress: dg.address, targetPort: dg.port);
          } else {
            // Multicast reply
            _sendResponse();
          }
          break;
        }
      }
    } catch (_) {
      // Gracefully ignore corrupt/malformed queries
    }
  }

  /// Sends mDNS response records.
  Future<void> _sendResponse({
    InternetAddress? targetAddress,
    int targetPort = MdnsConstants.mdnsPort,
    int ttl = 120,
  }) async {
    if (_socket == null || _id == null || _name == null) return;

    final instanceName = '$_name.${MdnsConstants.serviceType}';
    final hostTarget = '${_name!.replaceAll(' ', '-').toLowerCase()}.local';

    final txtAttrs = <String, String>{
      'id': _id!,
      'name': _name!,
      'os': _os ?? 'unknown',
      'port': _port.toString(),
      'proto': '1',
    };

    if (_customMetadata != null) {
      for (final e in _customMetadata!.entries) {
        txtAttrs[e.key] = e.value.toString();
      }
    }

    final answers = <DnsRecord>[
      PtrRecord(
        name: MdnsConstants.serviceType,
        domainName: instanceName,
        ttl: ttl > 0 ? 4500 : 0,
      ),
      SrvRecord(
        name: instanceName,
        port: _port,
        target: hostTarget,
        ttl: ttl,
      ),
      TxtRecord(
        name: instanceName,
        attributes: txtAttrs,
        ttl: ttl,
      ),
    ];

    // Include local IP addresses in A records
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          answers.add(ARecord(
            name: hostTarget,
            address: addr,
            ttl: ttl,
          ));
        }
      }
    } catch (_) {}

    final msg = DnsMessage(
      isResponse: true,
      isAuthoritative: true,
      answers: answers,
    );

    final bytes = DnsCodec.encode(msg);

    if (targetAddress != null) {
      try {
        _socket?.send(bytes, targetAddress, targetPort);
      } catch (_) {}
    } else {
      // Multicast group
      try {
        _socket?.send(
            bytes,
            InternetAddress(MdnsConstants.multicastIpv4),
            MdnsConstants.mdnsPort);
      } catch (_) {}

      // Also send to all known unicast queriers
      for (final querier in _knownQueriers) {
        try {
          _socket?.send(bytes, querier.$1, querier.$2);
        } catch (_) {}
      }
    }
  }

  /// Broadcasts an active announcement to all peers on the multicast group.
  Future<void> broadcastAnnouncement({int ttl = 120}) async {
    await _sendResponse(
      ttl: ttl,
    );
  }

  /// Broadcasts RFC 6762 Goodbye packet (TTL = 0) and closes sockets.
  Future<void> stop() async {
    _isAdvertising = false;
    _burstTimer?.cancel();
    _burstTimer = null;

    if (_socket != null) {
      // Send RFC 6762 §10.1 Goodbye announcement with TTL 0
      try {
        await broadcastAnnouncement(ttl: 0);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      } catch (_) {}

      _socket?.close();
      _socket = null;
    }
    _knownQueriers.clear();
  }
}

/// Pure Dart mDNS Service Browser / Querier.
class MdnsBrowser {
  RawDatagramSocket? _socket;
  Timer? _queryTimer;
  Timer? _burstTimer;
  String? _localDeviceId;
  bool _isBrowsing = false;

  final StreamController<PeerDevice> _deviceController =
      StreamController<PeerDevice>.broadcast();
  final StreamController<String> _lostController =
      StreamController<String>.broadcast();

  Stream<PeerDevice> get onDeviceDiscovered => _deviceController.stream;
  Stream<String> get onDeviceLost => _lostController.stream;
  bool get isBrowsing => _isBrowsing;

  /// Starts mDNS browsing.
  Future<void> start({
    String? localDeviceId,
    Duration queryInterval = const Duration(seconds: 10),
  }) async {
    if (_isBrowsing) await stop();

    _localDeviceId = localDeviceId;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0, // Ephemeral port for browser queries
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );

    try {
      _socket!.joinMulticast(InternetAddress(MdnsConstants.multicastIpv4));
      _socket!.multicastLoopback = true;
    } catch (_) {}

    _isBrowsing = true;

    _socket!.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          _handleIncomingDatagram();
        }
      },
      onError: (_) {},
    );

    // Initial query bursts for instant discovery (<50ms)
    await queryNow();
    _burstTimer = Timer(const Duration(milliseconds: 300), () async {
      if (_isBrowsing) await queryNow();
    });

    // Periodic query
    _queryTimer = Timer.periodic(queryInterval, (_) async {
      if (_isBrowsing) await queryNow();
    });
  }

  void _handleIncomingDatagram() {
    final dg = _socket?.receive();
    if (dg == null || !_isBrowsing) return;

    try {
      final msg = DnsCodec.decode(dg.data);
      if (!msg.isResponse) return;

      Map<String, String>? txtAttrs;
      int? srvPort;
      final addresses = <String>[dg.address.address];
      int minTtl = 120;

      for (final record in msg.answers) {
        if (record.ttl < minTtl) {
          minTtl = record.ttl;
        }

        if (record is TxtRecord) {
          txtAttrs = record.attributes;
        } else if (record is SrvRecord) {
          srvPort = record.port;
        } else if (record is ARecord) {
          addresses.add(record.address.address);
        } else if (record is AaaaRecord) {
          addresses.add(record.address.address);
        }
      }

      if (txtAttrs == null || !txtAttrs.containsKey('id')) return;

      final deviceId = txtAttrs['id']!;
      if (deviceId == _localDeviceId) return; // Suppress self-discovery

      // Check if this is an RFC 6762 Goodbye packet (TTL = 0)
      if (minTtl == 0) {
        _lostController.add(deviceId);
        return;
      }

      final name = txtAttrs['name'] ?? 'Unknown Device';
      final os = txtAttrs['os'] ?? 'unknown';
      final port = int.tryParse(txtAttrs['port'] ?? '') ?? srvPort ?? 42385;

      final custom = <String, dynamic>{};
      for (final entry in txtAttrs.entries) {
        if (!['id', 'name', 'os', 'port', 'proto'].contains(entry.key)) {
          custom[entry.key] = entry.value;
        }
      }

      final device = PeerDevice(
        id: deviceId,
        name: name,
        os: os,
        addresses: addresses.toSet().toList(),
        port: port,
        discoveryMethod: DiscoveryMethod.mdns,
        lastSeen: DateTime.now(),
        isStale: false,
        customMetadata: custom,
      );

      _deviceController.add(device);
    } catch (_) {
      // Gracefully ignore corrupt response datagrams
    }
  }

  /// Sends a multicast PTR query for `_securetransfer._tcp.local`.
  Future<void> queryNow() async {
    if (_socket == null || !_isBrowsing) return;

    const query = DnsMessage(
      questions: [
        DnsQuestion(
          name: MdnsConstants.serviceType,
          type: DnsType.ptr,
          unicastResponse: true,
        ),
      ],
    );

    final bytes = DnsCodec.encode(query);
    try {
      _socket?.send(
        bytes,
        InternetAddress(MdnsConstants.multicastIpv4),
        MdnsConstants.mdnsPort,
      );
    } catch (_) {}
  }

  /// Stops browsing and closes sockets.
  Future<void> stop() async {
    _isBrowsing = false;
    _queryTimer?.cancel();
    _queryTimer = null;
    _burstTimer?.cancel();
    _burstTimer = null;
    _socket?.close();
    _socket = null;
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await stop();
    await _deviceController.close();
    await _lostController.close();
  }
}

/// Unified mDNS Discovery Service combining Advertiser and Browser.
class MdnsDiscovery {
  final MdnsAdvertiser advertiser;
  final MdnsBrowser browser;

  MdnsDiscovery({
    MdnsAdvertiser? advertiser,
    MdnsBrowser? browser,
  })  : advertiser = advertiser ?? MdnsAdvertiser(),
        browser = browser ?? MdnsBrowser();

  Stream<PeerDevice> get onDeviceDiscovered => browser.onDeviceDiscovered;
  Stream<String> get onDeviceLost => browser.onDeviceLost;

  Future<void> startAdvertising({
    required String id,
    required String name,
    required String os,
    required int port,
    Map<String, dynamic>? customMetadata,
  }) async {
    await advertiser.start(
      id: id,
      name: name,
      os: os,
      port: port,
      customMetadata: customMetadata,
    );
  }

  Future<void> stopAdvertising() async {
    await advertiser.stop();
  }

  Future<void> startBrowsing({String? localDeviceId}) async {
    await browser.start(localDeviceId: localDeviceId);
  }

  Future<void> stopBrowsing() async {
    await browser.stop();
  }

  Future<void> queryNow() async {
    await browser.queryNow();
  }

  Future<void> dispose() async {
    await advertiser.stop();
    await browser.dispose();
  }
}
