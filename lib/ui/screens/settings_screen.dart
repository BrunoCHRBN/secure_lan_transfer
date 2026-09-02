import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// Settings & Preferences Screen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _nameController = TextEditingController(text: settings.deviceName);
    _portController =
        TextEditingController(text: settings.transferPort.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _pickDownloadDir(SettingsProvider settings) async {
    try {
      final selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Download Folder',
        initialDirectory: settings.downloadDirectoryPath,
      );
      if (selected != null && selected.trim().isNotEmpty) {
        settings.setDownloadDirectory(selected.trim());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not set directory: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Settings & Preferences',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // 1. Device Profile Section
            _buildSectionHeader(
              context,
              icon: Icons.perm_identity_rounded,
              title: 'Device Identity',
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Friendly Device Name',
                        hintText: 'e.g. Alice Laptop',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      onChanged: (val) => settings.setDeviceName(val),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Device UUID',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                settings.deviceId,
                                style: AppTheme.monospace(
                                  fontSize: 12,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy UUID',
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: settings.deviceId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('UUID copied to clipboard')),
                            );
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      'SLFT Engine: v1.0.0 • Protocol Spec: SLFT/1.0 • E2EE ChaCha20-Poly1305',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Storage & Downloads Section
            _buildSectionHeader(
              context,
              icon: Icons.folder_outlined,
              title: 'Storage & Staging',
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Download Destination Directory',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                settings.downloadDirectoryPath.isNotEmpty
                                    ? settings.downloadDirectoryPath
                                    : 'Default Downloads directory',
                                style: AppTheme.monospace(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: const Text('Browse'),
                          onPressed: () => _pickDownloadDir(settings),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Open Folder on Completion'),
                      subtitle: const Text(
                        'Automatically open directory when a received file finishes verification',
                      ),
                      value: settings.openFolderOnComplete,
                      onChanged: (val) => settings.setOpenFolderOnComplete(val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Security & Privacy Section
            _buildSectionHeader(
              context,
              icon: Icons.shield_outlined,
              title: 'Security & Zero-Metadata Privacy',
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Zero-Metadata Staging & History'),
                      subtitle: const Text(
                        'All staging metadata and transfer history is held exclusively in volatile RAM',
                      ),
                      value: settings.zeroMetadataMode,
                      onChanged: (val) => settings.setZeroMetadataMode(val),
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Cryptographic Secure Wipe on Abort'),
                      subtitle: const Text(
                        'Overwrites incomplete temporary .part files with zeros before unlinking',
                      ),
                      value: settings.secureWipeOnAbort,
                      onChanged: (val) => settings.setSecureWipeOnAbort(val),
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Traffic Obfuscation Padding'),
                      subtitle: const Text(
                        'Pads network packets with CSPRNG noise to thwart packet length analysis',
                      ),
                      value: settings.enableTrafficPadding,
                      onChanged: (val) => settings.setEnableTrafficPadding(val),
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Accept Paired Peers'),
                      subtitle: const Text(
                        'Accept incoming file connections without prompting on each request',
                      ),
                      value: settings.autoAcceptPairedDevices,
                      onChanged: (val) =>
                          settings.setAutoAcceptPairedDevices(val),
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Verify SAS Code'),
                      subtitle: const Text(
                        'Bypasses manual out-of-band SAS code confirmation (Not recommended)',
                      ),
                      value: settings.autoVerifySas,
                      onChanged: (val) => settings.setAutoVerifySas(val),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 4. Network & Throughput Section
            _buildSectionHeader(
              context,
              icon: Icons.network_check_rounded,
              title: 'Network & Performance',
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Listening TCP Transfer Port',
                        hintText: '42385',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                      onChanged: (val) {
                        final p = int.tryParse(val.trim());
                        if (p != null) settings.setTransferPort(p);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bandwidth Rate Limiter: ${settings.maxSpeedLimitBytesPerSec == 0 ? "Unlimited" : "${(settings.maxSpeedLimitBytesPerSec / (1024 * 1024)).toStringAsFixed(0)} MB/s"}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: (settings.maxSpeedLimitBytesPerSec / (1024 * 1024))
                          .clamp(0, 100),
                      min: 0,
                      max: 100,
                      divisions: 10,
                      label: settings.maxSpeedLimitBytesPerSec == 0
                          ? 'Unlimited'
                          : '${(settings.maxSpeedLimitBytesPerSec / (1024 * 1024)).toInt()} MB/s',
                      onChanged: (val) {
                        final bytes = (val * 1024 * 1024).toInt();
                        settings.setSpeedLimit(bytes);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tamanho do Bloco (Chunk Size):'),
                        DropdownButton<int>(
                          value: settings.chunkSize,
                          items: const [
                            DropdownMenuItem(value: 65536, child: Text('64 KB (Básico)')),
                            DropdownMenuItem(value: 131072, child: Text('128 KB')),
                            DropdownMenuItem(value: 262144, child: Text('256 KB (Padrão Otimizado)')),
                            DropdownMenuItem(value: 524288, child: Text('512 KB (Alta Performance)')),
                            DropdownMenuItem(value: 1048576, child: Text('1 MB (Modo Turbo)')),
                          ],
                          onChanged: (val) {
                            if (val != null) settings.setChunkSize(val);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Janela de Envio (Sliding Window):'),
                        DropdownButton<int>(
                          value: settings.creditWindowSize,
                          items: const [
                            DropdownMenuItem(value: 4, child: Text('4 slots')),
                            DropdownMenuItem(value: 8, child: Text('8 slots')),
                            DropdownMenuItem(value: 16, child: Text('16 slots (Padrão Otimizado)')),
                            DropdownMenuItem(value: 32, child: Text('32 slots (Modo Turbo)')),
                          ],
                          onChanged: (val) {
                            if (val != null) settings.setCreditWindowSize(val);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 5. Appearance & Themes Section
            _buildSectionHeader(
              context,
              icon: Icons.palette_outlined,
              title: 'Appearance & Themes',
            ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Theme Mode',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<AppThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: AppThemeMode.light,
                          label: Text('Light'),
                          icon: Icon(Icons.light_mode_outlined),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.dark,
                          label: Text('Dark'),
                          icon: Icon(Icons.dark_mode_outlined),
                        ),
                        ButtonSegment(
                          value: AppThemeMode.oled,
                          label: Text('OLED Pitch Black'),
                          icon: Icon(Icons.contrast_rounded),
                        ),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (selected) {
                        if (selected.isNotEmpty) {
                          settings.setThemeMode(selected.first);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Cyber Accent Seed Color',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      children: AppPalettes.allPalettes.map((pal) {
                        final isSelected =
                            settings.accentColor.toARGB32() == pal.color.toARGB32();
                        return ChoiceChip(
                          avatar: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: pal.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          label: Text(pal.name),
                          selected: isSelected,
                          onSelected: (_) => settings.setAccentColor(pal.color),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Reset Settings Action
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset All Settings to Defaults'),
                onPressed: () {
                  settings.resetToDefaults();
                  _nameController.text = settings.deviceName;
                  _portController.text = settings.transferPort.toString();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Settings reset to defaults')),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
