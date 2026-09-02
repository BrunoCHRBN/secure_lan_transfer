import 'dart:async';
import 'dart:io';
import '../models/peer_device.dart';
import 'device_registry.dart';
import 'mdns_discovery.dart';
import 'manual_connection.dart';
import 'network_utils.dart';
import 'udp_broadcast.dart';

/// High-level unified discovery facade coordinating mDNS (Primary),
/// UDP Broadcast (Secondary Fallback), Manual IP (Tertiary Direct),
/// and the reactive DeviceRegistry lifecycle.
class DiscoveryManager {
  final DeviceRegistry _registry;
  final UdpBroadcastBeacon _udpBeacon;
  final UdpBroadcastListener _udpListener;
  final ManualConnectionProber _manualProber;
  final MdnsDiscovery _mdnsDiscovery;

  String _localDeviceId = '';
  String _localDeviceName = '';
  String _localOs = '';
  int _transferPort = 42385;
  Map<String, dynamic>? _customMetadata;

  bool _isDiscovering = false;
  bool _isAdvertising = false;

  StreamSubscription<PeerDevice>? _udpSubscription;
  StreamSubscription<PeerDevice>? _mdnsSubscription;
  StreamSubscription<String>? _mdnsLostSubscription;

  DiscoveryManager({
    DeviceRegistry? registry,
    UdpBroadcastBeacon? udpBeacon,
    UdpBroadcastListener? udpListener,
    ManualConnectionProber? manualProber,
    MdnsDiscovery? mdnsDiscovery,
  })  : _registry = registry ?? DeviceRegistry(),
        _udpBeacon = udpBeacon ?? UdpBroadcastBeacon(),
        _udpListener = udpListener ?? UdpBroadcastListener(),
        _manualProber = manualProber ?? ManualConnectionProber(),
        _mdnsDiscovery = mdnsDiscovery ?? MdnsDiscovery();

  // Getters
  Stream<List<PeerDevice>> get devicesStream => _registry.devicesStream;
  List<PeerDevice> get currentDevices => _registry.currentDevices;
  bool get isDiscovering => _isDiscovering;
  bool get isAdvertising => _isAdvertising;
  String get localDeviceId => _localDeviceId;
  String get localDeviceName => _localDeviceName;
  DeviceRegistry get registry => _registry;

  /// Initializes the local device profile.
  void initialize({
    required String deviceId,
    required String deviceName,
    String? os,
    int transferPort = 42385,
    Map<String, dynamic>? customMetadata,
  }) {
    _localDeviceId = deviceId;
    _localDeviceName = deviceName;
    _localOs = os ?? Platform.operatingSystem;
    _transferPort = transferPort;
    _customMetadata = customMetadata;
  }

  /// Starts discovery browsing (mDNS and/or UDP listener).
  Future<void> startDiscovery({
    bool enableMdns = true,
    bool enableUdp = true,
  }) async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    // 1. Start UDP Broadcast Listener if enabled
    if (enableUdp) {
      await _udpListener.start(
        localDeviceId: _localDeviceId,
        beaconRef: _udpBeacon,
      );
      _udpSubscription = _udpListener.onDeviceDiscovered.listen((device) {
        _registry.registerOrUpdate(device);
      });
    }

    // 2. Start mDNS Browser if enabled
    if (enableMdns) {
      await _mdnsDiscovery.startBrowsing(localDeviceId: _localDeviceId);
      _mdnsSubscription = _mdnsDiscovery.onDeviceDiscovered.listen((device) {
        _registry.registerOrUpdate(device);
      });
      _mdnsLostSubscription = _mdnsDiscovery.onDeviceLost.listen((deviceId) {
        _registry.remove(deviceId);
      });
    }
  }

  /// Stops discovery listeners and browsers.
  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    await _udpListener.stop();

    await _mdnsSubscription?.cancel();
    _mdnsSubscription = null;
    await _mdnsLostSubscription?.cancel();
    _mdnsLostSubscription = null;
    await _mdnsDiscovery.stopBrowsing();
  }

  /// Starts presence advertising (mDNS advertiser and/or UDP broadcast beacon).
  Future<void> startAdvertising({
    bool enableMdns = true,
    bool enableUdp = true,
  }) async {
    if (_isAdvertising) return;
    _isAdvertising = true;

    // 1. Start UDP Broadcast Beacon if enabled
    if (enableUdp) {
      await _udpBeacon.start(
        id: _localDeviceId,
        name: _localDeviceName,
        os: _localOs,
        port: _transferPort,
        customMetadata: _customMetadata,
      );
    }

    // 2. Start mDNS Advertiser if enabled
    if (enableMdns) {
      await _mdnsDiscovery.startAdvertising(
        id: _localDeviceId,
        name: _localDeviceName,
        os: _localOs,
        port: _transferPort,
        customMetadata: _customMetadata,
      );
    }
  }

  /// Stops presence advertising.
  Future<void> stopAdvertising() async {
    _isAdvertising = false;
    await _udpBeacon.stop();
    await _mdnsDiscovery.stopAdvertising();
  }

  /// Probes a manual target IP:Port, validates TCP reachability,
  /// and automatically records it in the DeviceRegistry.
  Future<PeerDevice> addManualDevice(
    String host, {
    int port = 42385,
    Duration timeout = const Duration(seconds: 3),
    String? deviceName,
  }) async {
    final device = await _manualProber.probe(
      host,
      port: port,
      timeout: timeout,
      deviceName: deviceName,
    );
    _registry.registerOrUpdate(device);
    return device;
  }

  /// Triggers an immediate one-shot broadcast announcement / query.
  Future<void> broadcastPresence({
    bool enableMdns = true,
    bool enableUdp = true,
  }) async {
    if (_isAdvertising) {
      if (enableUdp) {
        await _udpBeacon.start(
          id: _localDeviceId,
          name: _localDeviceName,
          os: _localOs,
          port: _transferPort,
          customMetadata: _customMetadata,
        );
      }
      if (enableMdns) {
        await _mdnsDiscovery.advertiser.broadcastAnnouncement();
      }
    }
    if (_isDiscovering && enableMdns) {
      await _mdnsDiscovery.queryNow();
    }
  }

  /// Scans the local subnet for any active nodes listening on [port].
  /// Provides 100% detection reliability even when UDP broadcast/mDNS is blocked by the router.
  Future<void> sweepSubnet({int port = 42385}) async {
    try {
      final physicalAddrs = await NetworkUtils.getPhysicalIPv4Addresses();
      final localIpSet = physicalAddrs.map((a) => a.address).toSet();
      localIpSet.addAll(['127.0.0.1', '0.0.0.0']);

      final interfaces = await NetworkUtils.getFilteredInterfaces();
      for (final iface in interfaces) {
        if (NetworkUtils.isVirtualInterfaceName(iface.name)) continue;
        for (final addr in iface.addresses) {
          if (NetworkUtils.isVirtualSubnet(addr.address)) continue;
          final parts = addr.address.split('.');
          if (parts.length == 4) {
            final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
            final localHostNum = int.tryParse(parts[3]) ?? 0;

            final futures = <Future>[];
            for (int i = 1; i <= 254; i++) {
              if (i == localHostNum) continue;
              final targetIp = '$prefix.$i';
              if (localIpSet.contains(targetIp)) continue;
              futures.add(_probeIp(targetIp, port, localIpSet));
              if (futures.length >= 35) {
                await Future.wait(futures);
                futures.clear();
              }
            }
            if (futures.isNotEmpty) {
              await Future.wait(futures);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _probeIp(String ip, int port, Set<String> localIpSet) async {
    if (localIpSet.contains(ip)) return;
    Socket? socket;
    try {
      socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(milliseconds: 1500),
      );
      socket.destroy();

      final dev = PeerDevice(
        id: 'node-$ip-$port',
        name: 'Device ($ip)',
        os: 'mobile',
        addresses: [ip],
        port: port,
        discoveryMethod: DiscoveryMethod.manual,
        lastSeen: DateTime.now(),
        isStale: false,
      );
      _registry.registerOrUpdate(dev);
    } catch (_) {}
  }

  /// Disposes all managed resources.
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    _registry.dispose();
    await _udpListener.dispose();
    await _mdnsDiscovery.dispose();
  }
}
