import 'package:flutter/material.dart';
import '../../core/models/peer_device.dart';

/// Card widget rendering a discovered LAN peer device with OS icon, status chip, and quick send action.
class DeviceCard extends StatelessWidget {
  final PeerDevice device;
  final VoidCallback onSendFile;
  final VoidCallback? onTap;

  const DeviceCard({
    super.key,
    required this.device,
    required this.onSendFile,
    this.onTap,
  });

  IconData _getOsIcon(String os) {
    switch (os.toLowerCase()) {
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'windows':
        return Icons.laptop_windows_rounded;
      case 'macos':
        return Icons.laptop_mac_rounded;
      case 'linux':
        return Icons.terminal_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  Color _getChannelBadgeColor(DiscoveryMethod method, ColorScheme colorScheme) {
    switch (method) {
      case DiscoveryMethod.mdns:
        return Colors.teal;
      case DiscoveryMethod.udpBroadcast:
        return Colors.indigoAccent;
      case DiscoveryMethod.manual:
        return Colors.deepOrangeAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final ipDisplay = device.primaryAddress ?? 'Unknown IP';
    final isOnline = device.isOnline;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOnline
              ? colorScheme.outlineVariant.withValues(alpha: 0.4)
              : colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? onSendFile,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: OS Icon + Status Dot + Discovery Method Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getOsIcon(device.os),
                      size: 24,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                device.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Liveness status dot
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline
                                    ? Colors.greenAccent[400]
                                    : Colors.amber,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$ipDisplay:${device.port}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Bottom Row: Badges + Send Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      // Discovery Channel Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _getChannelBadgeColor(
                                  device.discoveryMethod, colorScheme)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getChannelBadgeColor(
                                    device.discoveryMethod, colorScheme)
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          device.discoveryMethod.displayName,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _getChannelBadgeColor(
                                device.discoveryMethod, colorScheme),
                          ),
                        ),
                      ),
                      if (device.isStale)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Stale',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber[800],
                            ),
                          ),
                        ),
                    ],
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('Send'),
                    onPressed: onSendFile,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
