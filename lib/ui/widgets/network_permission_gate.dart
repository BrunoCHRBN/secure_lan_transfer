import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_discovery_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transfer_session_provider.dart';

/// Gate widget that ensures network access is explicitly authorized by the user.
///
/// If network authorization is granted, displays [child].
/// If pending on first launch, prompts the user to grant local network access.
/// If denied, displays an explicit blocking warning explaining that the app cannot function without it,
/// with a button to re-request authorization.
class NetworkPermissionGate extends StatefulWidget {
  final Widget child;

  const NetworkPermissionGate({
    super.key,
    required this.child,
  });

  @override
  State<NetworkPermissionGate> createState() => _NetworkPermissionGateState();
}

class _NetworkPermissionGateState extends State<NetworkPermissionGate> {
  bool _isRequesting = false;

  Future<void> _handleAuthorize(BuildContext context) async {
    setState(() => _isRequesting = true);

    try {
      final settings = context.read<SettingsProvider>();
      final discovery = context.read<DeviceDiscoveryProvider>();
      final transferSession = context.read<TransferSessionProvider>();

      // Record permission
      await settings.setNetworkPermission(true);

      // Start network background listeners
      await discovery.initialize(settings);
      await transferSession.startServer();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  Future<void> _handleDeny(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final discovery = context.read<DeviceDiscoveryProvider>();
    final transferSession = context.read<TransferSessionProvider>();

    // Stop discovery and server if active
    await discovery.stopDiscovery();
    await transferSession.stopServer();

    await settings.setNetworkPermission(false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (settings.isNetworkPermissionGranted) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDenied = settings.networkPermissionGranted == false;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F141C)
          : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isDenied
                    ? _buildDeniedView(context)
                    : _buildInitialPromptView(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// View shown on first launch requesting network access authorization.
  Widget _buildInitialPromptView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.watch<SettingsProvider>().accentColor;

    return Container(
      key: const ValueKey('initial_prompt'),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141B26) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 20),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon with glowing ring
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withAlpha(25),
                border: Border.all(color: accent, width: 2),
              ),
              child: Icon(
                Icons.wifi_tethering_rounded,
                size: 38,
                color: accent,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Autorização de Rede Local',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
          ),
          const SizedBox(height: 8),

          // Subtitle badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withAlpha(20),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accent.withAlpha(60)),
              ),
              child: Text(
                '🛡️ Rede Local P2P • Zero-Metadata',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Explanation
          Text(
            'Para descobrir aparelhos na sua rede Wi-Fi/Ethernet e transferir arquivos com criptografia ponta a ponta (E2EE), o aplicativo precisa de autorização para utilizar os adaptadores de rede local.\n\nNenhum dado é enviado para a Internet ou servidores externos.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),

          // Feature cards
          _buildFeatureTile(
            context,
            icon: Icons.radar_rounded,
            title: 'Descoberta Automática de Dispositivos',
            subtitle: 'Varredura mDNS e UDP Broadcast na sub-rede local.',
          ),
          const SizedBox(height: 10),
          _buildFeatureTile(
            context,
            icon: Icons.enhanced_encryption_rounded,
            title: 'Transmissão P2P Criptografada',
            subtitle: 'X25519 + ChaCha20-Poly1305 sem servidores intermediários.',
          ),
          const SizedBox(height: 24),

          // Action Buttons
          ElevatedButton.icon(
            onPressed: _isRequesting ? null : () => _handleAuthorize(context),
            icon: _isRequesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_rounded),
            label: Text(
              _isRequesting ? 'Iniciando Rede...' : 'Autorizar Acesso à Rede',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF0B0F17),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _isRequesting ? null : () => _handleDeny(context),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
  }

  /// View shown when network permission was refused by the user.
  Widget _buildDeniedView(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.watch<SettingsProvider>().accentColor;
    const warningColor = Color(0xFFF87171); // Soft Red / Coral

    return Container(
      key: const ValueKey('denied_view'),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141B26) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: warningColor.withAlpha(120), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: warningColor.withAlpha(isDark ? 40 : 15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Red warning icon
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: warningColor.withAlpha(25),
                border: Border.all(color: warningColor, width: 2),
              ),
              child: const Icon(
                Icons.signal_wifi_off_rounded,
                size: 38,
                color: warningColor,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Autorização de Rede Negada',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: warningColor,
                ),
          ),
          const SizedBox(height: 14),

          // Prominent Warning Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: warningColor.withAlpha(18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: warningColor.withAlpha(60)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: warningColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Não é possível utilizar a aplicação sem a autorização de rede.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Detailed reasoning
          Text(
            'O Secure LAN File Transfer é uma ferramenta puramente local. Ele depende exclusivamente da comunicação via Wi-Fi e Ethernet para descobrir outros dispositivos na rede e transmitir arquivos.\n\nSem esta autorização, nenhum aparelho pode ser encontrado e nenhum arquivo pode ser enviado ou recebido.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 24),

          // Prominent Re-Request Button
          ElevatedButton.icon(
            onPressed: _isRequesting ? null : () => _handleAuthorize(context),
            icon: _isRequesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              _isRequesting ? 'Conectando...' : 'Solicitar Autorização Novamente',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: const Color(0xFF0B0F17),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = context.watch<SettingsProvider>().accentColor;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2332) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF243447) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
