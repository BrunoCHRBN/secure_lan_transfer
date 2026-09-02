import 'dart:async';
import '../models/peer_device.dart';

/// Dynamic multi-channel device catalog that manages discovered peer devices,
/// deduplicates entries across discovery methods, marks stale devices,
/// and automatically prunes expired devices.
class DeviceRegistry {
  final Duration staleThreshold;
  final Duration pruneThreshold;
  final Duration sweepInterval;

  final Map<String, PeerDevice> _devices = {};
  final StreamController<List<PeerDevice>> _controller =
      StreamController<List<PeerDevice>>.broadcast();
  Timer? _sweepTimer;

  DeviceRegistry({
    this.staleThreshold = const Duration(seconds: 12),
    this.pruneThreshold = const Duration(seconds: 25),
    this.sweepInterval = const Duration(seconds: 1),
  }) {
    _startSweepTimer();
  }

  /// Reactive stream broadcasting the current list of registered devices.
  Stream<List<PeerDevice>> get devicesStream => _controller.stream;

  /// Current immutable snapshot of all registered devices.
  List<PeerDevice> get currentDevices => List.unmodifiable(_devices.values);

  /// Retrieves a specific device by its unique ID, or null if not registered.
  PeerDevice? getDevice(String id) => _devices[id];

  /// Inserts a newly discovered device or updates an existing device's metadata & lastSeen.
  void registerOrUpdate(PeerDevice device) {
    final existing = _devices[device.id];
    if (existing == null) {
      _devices[device.id] = device;
      _emit();
    } else {
      final mergedAddresses = <String>{
        ...existing.addresses,
        ...device.addresses,
      }.toList();

      final updated = existing.copyWith(
        name: device.name.isNotEmpty ? device.name : existing.name,
        os: device.os != 'unknown' ? device.os : existing.os,
        addresses: mergedAddresses,
        port: device.port != 0 ? device.port : existing.port,
        discoveryMethod: device.discoveryMethod,
        lastSeen: device.lastSeen.isAfter(existing.lastSeen)
            ? device.lastSeen
            : existing.lastSeen,
        isStale: false,
        customMetadata: {
          ...existing.customMetadata,
          ...device.customMetadata,
        },
      );
      _devices[device.id] = updated;
      _emit();
    }
  }

  /// Removes a specific device from registry (e.g. on goodbye packet or manual disconnect).
  void remove(String deviceId) {
    if (_devices.remove(deviceId) != null) {
      _emit();
    }
  }

  /// Clears all entries from the registry.
  void clear() {
    if (_devices.isNotEmpty) {
      _devices.clear();
      _emit();
    }
  }

  void _startSweepTimer() {
    _sweepTimer = Timer.periodic(sweepInterval, (_) => sweep());
  }

  /// Evaluates device ages against stale and prune thresholds, updating registry state.
  void sweep({DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    bool changed = false;
    final keysToRemove = <String>[];

    for (final entry in _devices.entries) {
      final device = entry.value;
      final age = currentTime.difference(device.lastSeen);

      if (age >= pruneThreshold) {
        keysToRemove.add(entry.key);
        changed = true;
      } else if (age >= staleThreshold && !device.isStale) {
        _devices[entry.key] = device.copyWith(isStale: true);
        changed = true;
      }
    }

    for (final key in keysToRemove) {
      _devices.remove(key);
    }

    if (changed) {
      _emit();
    }
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(currentDevices);
    }
  }

  /// Cleans up periodic timers and closes streams.
  void dispose() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _controller.close();
  }
}
