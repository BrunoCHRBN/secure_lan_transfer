import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/peer_device.dart';
import 'network_utils.dart';

/// UDP Broadcast Discovery Protocol Constants.
class UdpBroadcastConstants {
  static const int broadcastPort = 42386;
  static const String magic = 'SECFLX_BEACON';
  static const int protocolVersion = 1;
  static const Duration defaultInterval = Duration(milliseconds: 2000);
}

/// UDP Broadcast Discovery Transmitter (Beacon).
class UdpBroadcastBeacon {
  final Duration interval;
  Timer? _timer;
  RawDatagramSocket? _socket;
  bool _isBroadcasting = false;

  String _localId = '';
  String _localName = '';
  String _localOs = '';
  int _localPort = 42385;
  Map<String, dynamic>? _localMetadata;

  UdpBroadcastBeacon(
      {this.interval = UdpBroadcastConstants.defaultInterval});

  bool get isBroadcasting => _isBroadcasting;

  /// Starts broadcasting beacons at periodic intervals.
  Future<void> start({
    required String id,
    required String name,
    required String os,
    required int port,
    Map<String, dynamic>? customMetadata,
  }) async {
    if (_isBroadcasting) await stop();

    _localId = id;
    _localName = name;
    _localOs = os;
    _localPort = port;
    _localMetadata = customMetadata;

    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0, // Ephemeral sending port
    );
    _socket!.broadcastEnabled = true;
    _isBroadcasting = true;

    // Send first beacon immediately
    await _sendBeacon();

    // Schedule periodic beacon
    _timer = Timer.periodic(interval, (_) async {
      await _sendBeacon();
    });
  }

  Future<void> _sendBeacon() async {
    if (_socket == null || !_isBroadcasting) return;

    final payloadMap = {
      'magic': UdpBroadcastConstants.magic,
      'v': UdpBroadcastConstants.protocolVersion,
      'id': _localId,
      'name': _localName,
      'os': _localOs,
      'port': _localPort,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'customMetadata': _localMetadata ?? {},
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payloadMap)));
    final targets = await _resolveBroadcastTargets();

    for (final target in targets) {
      try {
        _socket?.send(bytes, target, UdpBroadcastConstants.broadcastPort);
      } catch (_) {
        // Suppress transient network interface unreachable errors
      }
    }
  }

  /// Sends a direct unicast beacon response to a specific discovered peer address.
  void sendDirectUnicastPong(InternetAddress targetAddress, {int? targetPort}) {
    if (_socket == null || !_isBroadcasting || _localId.isEmpty) return;

    try {
      final payloadMap = {
        'magic': UdpBroadcastConstants.magic,
        'v': UdpBroadcastConstants.protocolVersion,
        'id': _localId,
        'name': _localName,
        'os': _localOs,
        'port': _localPort,
        'isPong': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'customMetadata': _localMetadata ?? {},
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payloadMap)));
      _socket?.send(
        bytes,
        targetAddress,
        targetPort ?? UdpBroadcastConstants.broadcastPort,
      );
    } catch (_) {}
  }

  Future<List<InternetAddress>> _resolveBroadcastTargets() async {
    final targets = <InternetAddress>[
      InternetAddress('255.255.255.255'),
      InternetAddress.loopbackIPv4,
    ];

    try {
      final interfaces = await NetworkUtils.getFilteredInterfaces();
      for (final iface in interfaces) {
        if (NetworkUtils.isVirtualInterfaceName(iface.name)) continue;
        for (final addr in iface.addresses) {
          if (NetworkUtils.isVirtualSubnet(addr.address)) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            // Standard /24 broadcast (192.168.x.255 or 10.x.x.255)
            final subnet24 = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            try {
              targets.add(InternetAddress(subnet24));
            } catch (_) {}

            // Class B /16 broadcast (172.x.255.255 or 192.168.255.255)
            final subnet16 = '${parts[0]}.${parts[1]}.255.255';
            try {
              targets.add(InternetAddress(subnet16));
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return targets;
  }

  /// Stops broadcasting beacons.
  Future<void> stop() async {
    _isBroadcasting = false;
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }
}

/// UDP Broadcast Discovery Receiver (Listener).
class UdpBroadcastListener {
  final StreamController<PeerDevice> _deviceController =
      StreamController<PeerDevice>.broadcast();
  RawDatagramSocket? _socket;
  String? _localDeviceId;
  UdpBroadcastBeacon? _beaconRef;
  bool _isListening = false;

  Stream<PeerDevice> get onDeviceDiscovered => _deviceController.stream;
  bool get isListening => _isListening;

  /// Starts listening for UDP broadcast beacons on port 42386.
  Future<void> start({
    required String localDeviceId,
    UdpBroadcastBeacon? beaconRef,
  }) async {
    if (_isListening) await stop();

    _localDeviceId = localDeviceId;
    _beaconRef = beaconRef;
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      UdpBroadcastConstants.broadcastPort,
      reuseAddress: true,
      reusePort: !Platform.isWindows,
    );
    _socket!.broadcastEnabled = true;
    _isListening = true;

    _socket!.listen(
      (event) {
        if (event == RawSocketEvent.read) {
          _processIncomingDatagram();
        }
      },
      onError: (_) {},
    );
  }

  void _processIncomingDatagram() {
    final datagram = _socket?.receive();
    if (datagram == null || !_isListening) return;

    try {
      final rawString = utf8.decode(datagram.data);
      final json = jsonDecode(rawString) as Map<String, dynamic>;

      // 1. Verify Magic and Version
      if (json['magic'] != UdpBroadcastConstants.magic ||
          json['v'] != UdpBroadcastConstants.protocolVersion) {
        return;
      }

      final senderId = json['id'] as String?;
      if (senderId == null || senderId.isEmpty) return;

      // 2. Ignore self-beacons
      if (senderId == _localDeviceId) return;

      final senderIp = datagram.address.address;
      final port = (json['port'] as num?)?.toInt() ?? 42385;
      final name = (json['name'] as String?) ?? 'Unknown Device';
      final os = (json['os'] as String?) ?? 'unknown';
      final metadata = (json['customMetadata'] as Map<String, dynamic>?) ?? {};
      final isPong = json['isPong'] == true;

      final device = PeerDevice(
        id: senderId,
        name: name,
        os: os,
        addresses: [senderIp],
        port: port,
        discoveryMethod: DiscoveryMethod.udpBroadcast,
        lastSeen: DateTime.now(),
        isStale: false,
        customMetadata: metadata,
      );

      _deviceController.add(device);

      // If this is an incoming broadcast (not a pong), send a direct unicast pong back so the sender immediately discovers us!
      if (!isPong && _beaconRef != null) {
        _beaconRef!.sendDirectUnicastPong(datagram.address);
      }
    } catch (_) {
      // Gracefully ignore corrupt or unexpected packet data
    }
  }

  /// Stops listening for beacons.
  Future<void> stop() async {
    _isListening = false;
    _socket?.close();
    _socket = null;
  }

  /// Disposes resources.
  Future<void> dispose() async {
    await stop();
    await _deviceController.close();
  }
}
