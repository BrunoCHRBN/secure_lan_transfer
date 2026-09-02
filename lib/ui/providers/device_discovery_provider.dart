import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/discovery/discovery_manager.dart';
import '../../core/models/peer_device.dart';
import 'settings_provider.dart';

/// Provider orchestrating real-time mDNS / UDP broadcast discovery, device cataloging,
/// manual IP probing, and UI filtering.
class DeviceDiscoveryProvider extends ChangeNotifier {
  final DiscoveryManager _discoveryManager;
  StreamSubscription<List<PeerDevice>>? _devicesSubscription;

  List<PeerDevice> _allDevices = [];
  String _searchQuery = '';
  String? _selectedOsFilter;
  bool _isScanning = false;
  bool _isAdvertising = false;
  String? _errorMessage;

  DeviceDiscoveryProvider({DiscoveryManager? discoveryManager})
      : _discoveryManager = discoveryManager ?? DiscoveryManager();

  // Getters
  DiscoveryManager get discoveryManager => _discoveryManager;
  List<PeerDevice> get allDevices => List.unmodifiable(_allDevices);
  List<PeerDevice> get devices => _filteredDevices();
  List<PeerDevice> get activeDevices =>
      devices.where((d) => d.isOnline).toList();
  List<PeerDevice> get staleDevices =>
      devices.where((d) => d.isStale).toList();
  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  String get searchQuery => _searchQuery;
  String? get selectedOsFilter => _selectedOsFilter;
  String? get errorMessage => _errorMessage;

  /// Initializes discovery with device profile and starts listeners.
  Future<void> initialize(SettingsProvider settings) async {
    _discoveryManager.initialize(
      deviceId: settings.deviceId,
      deviceName: settings.deviceName,
      transferPort: settings.transferPort,
    );

    await _devicesSubscription?.cancel();
    _devicesSubscription = _discoveryManager.devicesStream.listen((devs) {
      _allDevices = devs;
      notifyListeners();
    });

    await startDiscovery();
    await startAdvertising();
  }

  /// Starts listening for peer devices across all channels.
  Future<void> startDiscovery() async {
    try {
      _errorMessage = null;
      await _discoveryManager.startDiscovery();
      _isScanning = true;
      notifyListeners();

      // Run background subnet sweep to ensure 100% discovery even behind router isolation
      unawaited(_discoveryManager.sweepSubnet());
    } catch (e) {
      _errorMessage = 'Failed to start discovery: $e';
      notifyListeners();
    }
  }

  /// Stops listening for peer devices.
  Future<void> stopDiscovery() async {
    await _discoveryManager.stopDiscovery();
    _isScanning = false;
    notifyListeners();
  }

  /// Starts advertising this node's presence on the LAN.
  Future<void> startAdvertising() async {
    try {
      _errorMessage = null;
      await _discoveryManager.startAdvertising();
      _isAdvertising = true;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to start advertising: $e';
      notifyListeners();
    }
  }

  /// Stops advertising this node's presence.
  Future<void> stopAdvertising() async {
    await _discoveryManager.stopAdvertising();
    _isAdvertising = false;
    notifyListeners();
  }

  /// Triggers a one-shot presence announcement beacon.
  Future<void> triggerBroadcastScan() async {
    try {
      await _discoveryManager.broadcastPresence();
    } catch (e) {
      _errorMessage = 'Broadcast scan failed: $e';
      notifyListeners();
    }
  }

  /// Probes and adds a manual IP:Port device.
  Future<PeerDevice> addManualDevice(
    String host, {
    int port = 42385,
    String? name,
  }) async {
    try {
      _errorMessage = null;
      final device = await _discoveryManager.addManualDevice(
        host,
        port: port,
        deviceName: name,
      );
      notifyListeners();
      return device;
    } catch (e) {
      _errorMessage = 'Manual connection to $host:$port failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setOsFilter(String? os) {
    _selectedOsFilter = os;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedOsFilter = null;
    notifyListeners();
  }

  List<PeerDevice> _filteredDevices() {
    return _allDevices.where((device) {
      if (_selectedOsFilter != null && _selectedOsFilter!.isNotEmpty) {
        if (device.os.toLowerCase() != _selectedOsFilter!.toLowerCase()) {
          return false;
        }
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchName = device.name.toLowerCase().contains(q);
        final matchIp = device.addresses.any((a) => a.contains(q));
        return matchName || matchIp;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    unawaited(_discoveryManager.dispose());
    super.dispose();
  }
}
