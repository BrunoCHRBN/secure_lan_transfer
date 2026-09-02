import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// Result record returned when a QR code is successfully scanned or
/// an address is manually entered.
typedef QrScanResult = ({String host, int port});

/// Fullscreen dialog that uses the device camera to scan QR codes containing
/// `slft://host:port` payloads. On desktop platforms without a camera or if camera
/// is unavailable, it provides a manual IP:port text entry form.
class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({super.key});

  /// Convenience method to show this dialog.
  static Future<QrScanResult?> show(BuildContext context) {
    return showDialog<QrScanResult>(
      context: context,
      useSafeArea: false,
      builder: (_) => const QrScannerDialog(),
    );
  }

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  bool _preferManual = !(Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    if (_preferManual) {
      return _ManualEntryView(
        canSwitchToCamera: Platform.isAndroid || Platform.isIOS,
        onSwitchToCamera: () => setState(() => _preferManual = false),
      );
    }
    return _CameraScannerView(
      onSwitchToManual: () => setState(() => _preferManual = true),
    );
  }
}

// ---------------------------------------------------------------------------
// Camera scanner (mobile)
// ---------------------------------------------------------------------------

class _CameraScannerView extends StatefulWidget {
  final VoidCallback onSwitchToManual;
  const _CameraScannerView({required this.onSwitchToManual});

  @override
  State<_CameraScannerView> createState() => _CameraScannerViewState();
}

class _CameraScannerViewState extends State<_CameraScannerView> {
  MobileScannerController? _controller;
  bool _scanned = false;
  bool _hasCameraPermission = false;
  bool _isPermissionChecking = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndInit();
  }

  Future<void> _checkPermissionAndInit() async {
    setState(() {
      _isPermissionChecking = true;
      _errorMessage = null;
    });

    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        _hasCameraPermission = true;
        _controller = MobileScannerController(
          formats: const [BarcodeFormat.qrCode],
          detectionSpeed: DetectionSpeed.normal,
          returnImage: false,
        );
      } else {
        _hasCameraPermission = false;
        _errorMessage = 'Permissão de câmera necessária para escanear QR Code.';
      }
    } catch (e) {
      _hasCameraPermission = false;
      _errorMessage = 'Não foi possível inicializar a câmera: $e';
    } finally {
      if (mounted) {
        setState(() => _isPermissionChecking = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final result = _parsePayload(raw);
      if (result != null) {
        _scanned = true;
        Navigator.of(context).pop(result);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isPermissionChecking) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (!_hasCameraPermission || _controller == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Leitor de QR Code',
              style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_rounded,
                    size: 64, color: Color(0xFF94A3B8)),
                const SizedBox(height: 16),
                Text(
                  _errorMessage ?? 'Acesso à câmera indisponível',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: _checkPermissionAndInit,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar Novamente'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: widget.onSwitchToManual,
                      icon: const Icon(Icons.keyboard_rounded),
                      label: const Text('Digitar IP'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          MobileScanner(
            controller: _controller!,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        error.errorDetails?.message ??
                            'Erro ao acessar a câmera do dispositivo.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: widget.onSwitchToManual,
                        icon: const Icon(Icons.keyboard_rounded),
                        label: const Text('Entrar IP Manualmente'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Semi-transparent overlay with viewfinder cutout
          _ScanOverlay(colorScheme: colorScheme),

          // Top actions: Close + Switch to Manual IP
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: widget.onSwitchToManual,
                  icon: const Icon(Icons.keyboard_rounded, size: 18),
                  label: const Text('Digitar IP', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scan overlay with viewfinder
// ---------------------------------------------------------------------------

class _ScanOverlay extends StatelessWidget {
  final ColorScheme colorScheme;

  const _ScanOverlay({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanSize = constraints.maxWidth * 0.65;

        return Stack(
          children: [
            // Dark semi-transparent background
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        color: Colors.red, // any opaque color for cutout
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Viewfinder border
            Center(
              child: Container(
                width: scanSize,
                height: scanSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00D26A),
                    width: 3,
                  ),
                ),
              ),
            ),

            // Instruction text
            Positioned(
              left: 24,
              right: 24,
              bottom: constraints.maxHeight * 0.18,
              child: const Text(
                'Aponte a câmera para o QR Code do Secure LAN Transfer',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Manual entry fallback (Desktop or Mobile fallback)
// ---------------------------------------------------------------------------

class _ManualEntryView extends StatefulWidget {
  final bool canSwitchToCamera;
  final VoidCallback? onSwitchToCamera;

  const _ManualEntryView({
    this.canSwitchToCamera = false,
    this.onSwitchToCamera,
  });

  @override
  State<_ManualEntryView> createState() => _ManualEntryViewState();
}

class _ManualEntryViewState extends State<_ManualEntryView> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final input = _addressController.text.trim();
    // Accept both raw "host:port" and "slft://host:port"
    final result = _parsePayload(input) ??
        _parsePayload('slft://$input');

    if (result != null) {
      Navigator.of(context).pop(result);
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
                      Icons.qr_code_scanner_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Conectar ao Dispositivo',
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
                'Digite o endereço IP e Porta exibidos no outro dispositivo (ou escaneie o QR Code).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Endereço do Dispositivo *',
                  hintText: 'Ex: 192.168.1.100:42385',
                  prefixIcon: Icon(Icons.lan_outlined),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Digite o endereço IP:Porta';
                  }
                  final input = val.trim();
                  final parsed = _parsePayload(input) ??
                      _parsePayload('slft://$input');
                  if (parsed == null) {
                    return 'Digite um IP e Porta válidos (ex: 192.168.1.5:42385)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (widget.canSwitchToCamera)
                    TextButton.icon(
                      onPressed: widget.onSwitchToCamera,
                      icon: const Icon(Icons.camera_alt_rounded, size: 16),
                      label: const Text('Usar Câmera'),
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submit,
                        child: const Text('Conectar'),
                      ),
                    ],
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

// ---------------------------------------------------------------------------
// Shared payload parser
// ---------------------------------------------------------------------------

/// Parses a `slft://host:port` payload string.
/// Returns null if the format doesn't match.
QrScanResult? _parsePayload(String raw) {
  final clean = raw.trim();
  final patternWithScheme = RegExp(r'^slft://(.+):(\d+)$');
  final match = patternWithScheme.firstMatch(clean);
  if (match != null) {
    final host = match.group(1)!;
    final port = int.tryParse(match.group(2)!);
    if (port != null && port > 0 && port <= 65535) {
      return (host: host, port: port);
    }
  }

  // Also support plain "192.168.1.100:42385"
  final patternPlain = RegExp(r'^([0-9a-zA-Z\.\-]+):(\d+)$');
  final plainMatch = patternPlain.firstMatch(clean);
  if (plainMatch != null) {
    final host = plainMatch.group(1)!;
    final port = int.tryParse(plainMatch.group(2)!);
    if (port != null && port > 0 && port <= 65535) {
      return (host: host, port: port);
    }
  }

  return null;
}
