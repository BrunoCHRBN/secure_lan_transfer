/// Provenance channel through which the peer device was discovered.
enum DiscoveryMethod {
  mdns,
  udpBroadcast,
  manual;

  String get displayName {
    switch (this) {
      case DiscoveryMethod.mdns:
        return 'mDNS';
      case DiscoveryMethod.udpBroadcast:
        return 'UDP Broadcast';
      case DiscoveryMethod.manual:
        return 'Manual Direct';
    }
  }
}

/// Immutable representation of a discovered LAN peer device.
class PeerDevice {
  /// Unique device identifier (UUID v4 or stable unique string).
  final String id;

  /// Human-readable friendly display name (e.g. "Alice's MacBook Pro").
  final String name;

  /// Operating system identifier ('android', 'ios', 'windows', 'macos', 'linux', 'unknown').
  final String os;

  /// List of reachable IPv4 and IPv6 network addresses.
  final List<String> addresses;

  /// TCP transfer listening port (default 42385).
  final int port;

  /// Discovery channel that discovered or most recently refreshed this device.
  final DiscoveryMethod discoveryMethod;

  /// Timestamp when this device was first or most recently observed.
  final DateTime lastSeen;

  /// Flag indicating whether the device has not refreshed within the stale threshold (e.g. 12s).
  final bool isStale;

  /// Extensible custom metadata key-value dictionary (e.g. proto version, app version).
  final Map<String, dynamic> customMetadata;

  const PeerDevice({
    required this.id,
    required this.name,
    required this.os,
    required this.addresses,
    this.port = 42385,
    required this.discoveryMethod,
    required this.lastSeen,
    this.isStale = false,
    this.customMetadata = const {},
  });

  /// Convenient primary address getter (prefers first IPv4 address, falls back to first available).
  String? get primaryAddress {
    if (addresses.isEmpty) return null;
    return addresses.firstWhere(
      (addr) => !addr.contains(':'),
      orElse: () => addresses.first,
    );
  }

  /// Age since last observation.
  Duration get age => DateTime.now().difference(lastSeen);

  /// Whether the device is active and not stale.
  bool get isOnline => !isStale;

  /// Immutable clone helper with optional field overrides.
  PeerDevice copyWith({
    String? id,
    String? name,
    String? os,
    List<String>? addresses,
    int? port,
    DiscoveryMethod? discoveryMethod,
    DateTime? lastSeen,
    bool? isStale,
    Map<String, dynamic>? customMetadata,
  }) {
    return PeerDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      os: os ?? this.os,
      addresses: addresses ?? this.addresses,
      port: port ?? this.port,
      discoveryMethod: discoveryMethod ?? this.discoveryMethod,
      lastSeen: lastSeen ?? this.lastSeen,
      isStale: isStale ?? this.isStale,
      customMetadata: customMetadata ?? this.customMetadata,
    );
  }

  /// Serializes to JSON map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'os': os,
        'addresses': addresses,
        'port': port,
        'discoveryMethod': discoveryMethod.name,
        'lastSeen': lastSeen.millisecondsSinceEpoch,
        'isStale': isStale,
        'customMetadata': customMetadata,
      };

  /// Deserializes from JSON map.
  factory PeerDevice.fromJson(Map<String, dynamic> map) {
    return PeerDevice(
      id: map['id'] as String,
      name: map['name'] as String,
      os: (map['os'] as String?) ?? 'unknown',
      addresses: (map['addresses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      port: (map['port'] as num?)?.toInt() ?? 42385,
      discoveryMethod: DiscoveryMethod.values.firstWhere(
        (m) => m.name == map['discoveryMethod'],
        orElse: () => DiscoveryMethod.udpBroadcast,
      ),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        (map['lastSeen'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      isStale: (map['isStale'] as bool?) ?? false,
      customMetadata: (map['customMetadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  /// Equality based exclusively on unique device ID.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PeerDevice && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PeerDevice(id: $id, name: $name, os: $os, ip: $primaryAddress:$port, method: ${discoveryMethod.name}, stale: $isStale)';
}
