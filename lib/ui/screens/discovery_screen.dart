import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/discovery/network_utils.dart';
import '../../core/models/peer_device.dart';
import '../providers/device_discovery_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transfer_session_provider.dart';
import '../theme/breakpoints.dart';
import '../widgets/device_card.dart';
import '../widgets/file_drop_target.dart';
import '../widgets/manual_connect_dialog.dart';
import '../widgets/qr_display_dialog.dart';
import '../widgets/qr_scanner_dialog.dart';
import '../widgets/radar_view.dart';

/// Main Discovery & Peer Radar Screen.
class DiscoveryScreen extends StatefulWidget {
  final VoidCallback onNavigateToTransfer;

  const DiscoveryScreen({
    super.key,
    required this.onNavigateToTransfer,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  List<File> _stagedFiles = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _handleSendToDevice(PeerDevice device) async {
    List<File> filesToSend = List.of(_stagedFiles);

    if (filesToSend.isEmpty) {
      try {
        final result = await FilePicker.platform.pickFiles(
          allowMultiple: true,
          dialogTitle: 'Select File(s) to Send to ${device.name}',
        );

        if (result == null || result.files.isEmpty) return;
        filesToSend = result.files
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .where((f) => f.existsSync())
            .toList();
        if (filesToSend.isEmpty) return;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File selection failed: $e')),
          );
        }
        return;
      }
    }

    if (!mounted) return;

    final transferProvider = context.read<TransferSessionProvider>();
    widget.onNavigateToTransfer();

    try {
      await transferProvider.sendFiles(device, filesToSend);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showManualConnectDialog() {
    final discoveryProvider = context.read<DeviceDiscoveryProvider>();
    showDialog(
      context: context,
      builder: (context) => ManualConnectDialog(
        onConnect: (host, {int port = 42385, String? name}) async {
          return await discoveryProvider.addManualDevice(
            host,
            port: port,
            name: name,
          );
        },
      ),
    );
  }

  void _handleQrAction() async {
    final settings = context.read<SettingsProvider>();
    final discovery = context.read<DeviceDiscoveryProvider>();

    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: open QR scanner
      final result = await QrScannerDialog.show(context);
      if (result != null && mounted) {
        try {
          final dev = await discovery.addManualDevice(
            result.host,
            port: result.port,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Connected to ${dev.name}')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not connect to ${result.host}:${result.port}: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
      }
    } else {
      // Desktop: show QR Code for mobile to scan using real physical LAN IP
      final localIp = await NetworkUtils.getBestLocalIp();
      if (mounted) {
        QrDisplayDialog.show(
          context,
          address: localIp,
          port: settings.transferPort,
          deviceName: settings.deviceName,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompact = context.isCompact;

    final settings = context.watch<SettingsProvider>();
    final discovery = context.watch<DeviceDiscoveryProvider>();
    final devices = discovery.devices;

    const osOptions = ['All', 'Windows', 'Android', 'macOS', 'Linux', 'iOS'];

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top Header Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Node Identity Badge & Controls
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: discovery.isAdvertising
                                          ? Colors.greenAccent[400]
                                          : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      settings.deviceName,
                                      style:
                                          theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Transfer Port: ${settings.transferPort} • LAN Active',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              tooltip: discovery.isScanning
                                  ? 'Scanning Active'
                                  : 'Start Scanning',
                              icon: Icon(
                                discovery.isScanning
                                    ? Icons.radar_rounded
                                    : Icons.sync_disabled_rounded,
                              ),
                              onPressed: () {
                                if (discovery.isScanning) {
                                  discovery.stopDiscovery();
                                } else {
                                  discovery.startDiscovery();
                                }
                              },
                            ),
                            IconButton.filledTonal(
                              tooltip: (Platform.isAndroid || Platform.isIOS)
                                  ? 'Scan QR Code'
                                  : 'Show QR Code',
                              icon: Icon(
                                (Platform.isAndroid || Platform.isIOS)
                                    ? Icons.qr_code_scanner_rounded
                                    : Icons.qr_code_2_rounded,
                              ),
                              onPressed: _handleQrAction,
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.add_link_rounded,
                                  size: 18),
                              label: const Text('Manual IP'),
                              onPressed: _showManualConnectDialog,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Staged File Drop Zone
                    FileDropTarget(
                      selectedFiles: _stagedFiles,
                      onFilesSelected: (files) {
                        setState(() {
                          _stagedFiles = files;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Search & OS Filter Bar
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by device name or IP...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: () {
                                        _searchController.clear();
                                        discovery.setSearchQuery('');
                                      },
                                    )
                                  : null,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onChanged: (val) => discovery.setSearchQuery(val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // OS Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: osOptions.map((os) {
                          final isSelected = (os == 'All' &&
                                  discovery.selectedOsFilter == null) ||
                              discovery.selectedOsFilter?.toLowerCase() ==
                                  os.toLowerCase();
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: FilterChip(
                              label: Text(os),
                              selected: isSelected,
                              onSelected: (_) {
                                discovery.setOsFilter(
                                    os == 'All' ? null : os);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Discovered Peer Devices Header & Radar Animation
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Nearby Peer Devices (${devices.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (discovery.isScanning)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RadarView(
                            devices: devices,
                            isScanning: discovery.isScanning,
                            size: 28,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Scanning...',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Device List / Grid or Empty State
            if (devices.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RadarView(
                          devices: const [],
                          isScanning: discovery.isScanning,
                          size: 160,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Searching for peers on your Wi-Fi / LAN...',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Make sure other devices have the Secure LAN Transfer app open on the same network subnet.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.add_link_rounded),
                          label: const Text('Add Device by Direct IP'),
                          onPressed: _showManualConnectDialog,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (isCompact)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = devices[index];
                      return DeviceCard(
                        device: device,
                        onSendFile: () => _handleSendToDevice(device),
                      );
                    },
                    childCount: devices.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 140,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final device = devices[index];
                      return DeviceCard(
                        device: device,
                        onSendFile: () => _handleSendToDevice(device),
                      );
                    },
                    childCount: devices.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}
