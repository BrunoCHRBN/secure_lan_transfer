import 'dart:io';

/// Utility to inspect, filter, and prioritize real physical LAN network interfaces over virtual adapters (WSL, Hyper-V, VMware).
class NetworkUtils {
  static const List<String> _virtualInterfaceKeywords = [
    'vethernet',
    'wsl',
    'hyper-v',
    'virtual',
    'vmware',
    'vbox',
    'docker',
    'loopback',
    'pseudo',
    'teredo',
    'isatap',
    'switch',
  ];

  /// Checks if an interface name indicates a virtual, container, or hypervisor bridge.
  static bool isVirtualInterfaceName(String name) {
    final lower = name.toLowerCase();
    for (final kw in _virtualInterfaceKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  /// Checks if an IP is in the typical WSL / Hyper-V default internal range (172.16..31.x.x).
  static bool isVirtualSubnet(String ip) {
    if (ip.startsWith('127.')) return true;
    if (ip.startsWith('169.254.')) return true; // Link-local
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? 0;
      if (second >= 16 && second <= 31) {
        return true; // WSL / Docker / Hyper-V bridge
      }
    }
    return false;
  }

  /// Returns sorted list of real physical IPv4 network interfaces (physical first, virtual last).
  static Future<List<NetworkInterface>> getFilteredInterfaces() async {
    try {
      final allInterfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final physical = <NetworkInterface>[];
      final secondary = <NetworkInterface>[];

      for (final iface in allInterfaces) {
        final isVirtualName = isVirtualInterfaceName(iface.name);
        final hasPhysicalIp = iface.addresses.any(
          (a) => a.type == InternetAddressType.IPv4 && !isVirtualSubnet(a.address),
        );

        if (!isVirtualName && hasPhysicalIp) {
          physical.add(iface);
        } else {
          secondary.add(iface);
        }
      }

      if (physical.isNotEmpty) {
        return [...physical, ...secondary];
      }
      return allInterfaces;
    } catch (_) {
      return [];
    }
  }

  /// Returns all real physical IPv4 addresses (e.g. 192.168.15.12).
  static Future<List<InternetAddress>> getPhysicalIPv4Addresses() async {
    final interfaces = await getFilteredInterfaces();
    final addresses = <InternetAddress>[];
    for (final iface in interfaces) {
      if (isVirtualInterfaceName(iface.name)) continue;
      for (final addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 &&
            !addr.isLoopback &&
            !isVirtualSubnet(addr.address)) {
          addresses.add(addr);
        }
      }
    }
    if (addresses.isEmpty) {
      // Fallback: return any non-loopback IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            addresses.add(addr);
          }
        }
      }
    }
    return addresses;
  }

  /// Returns the single best physical LAN IP address for QR codes and connection advertising.
  static Future<String> getBestLocalIp() async {
    final addrs = await getPhysicalIPv4Addresses();
    if (addrs.isNotEmpty) {
      return addrs.first.address;
    }
    return '127.0.0.1';
  }
}
