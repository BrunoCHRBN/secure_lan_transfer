import 'package:flutter/material.dart';
import '../../core/models/peer_device.dart';

/// Modal dialog prompting the user to manually add and probe a peer IP and Port.
class ManualConnectDialog extends StatefulWidget {
  final Future<PeerDevice> Function(String host, {int port, String? name})
      onConnect;

  const ManualConnectDialog({
    super.key,
    required this.onConnect,
  });

  @override
  State<ManualConnectDialog> createState() => _ManualConnectDialogState();
}

class _ManualConnectDialogState extends State<ManualConnectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '42385');
  final _nameController = TextEditingController();

  bool _isProbing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProbing = true;
      _errorMessage = null;
    });

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 42385;
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : null;

    try {
      final device = await widget.onConnect(host, port: port, name: name);
      if (mounted) {
        Navigator.of(context).pop(device);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Could not connect to $host:$port: $e';
          _isProbing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.add_link_rounded,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Manual Peer Connect',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Directly probe a peer node via IPv4 or IPv6 address when mDNS/UDP broadcast is filtered by your network.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),

                // Host IP Input
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'Peer IP Address *',
                    hintText: 'e.g. 192.168.1.100 or 10.0.0.5',
                    prefixIcon: Icon(Icons.lan_outlined),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter target IP address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Port & Optional Alias Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port *',
                          hintText: '42385',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                        validator: (val) {
                          final p = int.tryParse(val?.trim() ?? '');
                          if (p == null || p <= 0 || p > 65535) {
                            return 'Valid port (1-65535)';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Alias (Optional)',
                          hintText: "e.g. Bob's PC",
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                    ),
                  ],
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed:
                          _isProbing ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _isProbing ? null : _submit,
                      child: _isProbing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Probe & Connect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
