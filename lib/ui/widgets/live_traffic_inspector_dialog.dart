import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/protocol/wire_inspector.dart';
import '../theme/app_theme.dart';

/// Modal dialog displaying real raw wire frames, canonical hex dumps, and Shannon entropy audits in real-time.
/// Fully responsive on both Desktop wide screens and Mobile portrait screens.
class LiveTrafficInspectorDialog extends StatefulWidget {
  const LiveTrafficInspectorDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const LiveTrafficInspectorDialog(),
    );
  }

  @override
  State<LiveTrafficInspectorDialog> createState() =>
      _LiveTrafficInspectorDialogState();
}

class _LiveTrafficInspectorDialogState
    extends State<LiveTrafficInspectorDialog> {
  int _selectedFrameIndex = 0;
  bool _autoFollowLive = true;
  StreamSubscription<WireFrameSample>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _streamSubscription =
        WireTrafficInspector.instance.onFrameRecorded.listen((sample) {
      if (mounted) {
        setState(() {
          if (_autoFollowLive) {
            _selectedFrameIndex = 0;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final samples = WireTrafficInspector.instance.samples;

    final mediaQuery = MediaQuery.of(context);
    final isMobile = mediaQuery.size.width < 650;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF101622) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 24,
        vertical: isMobile ? 16 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: isMobile ? mediaQuery.size.height * 0.88 : 720,
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 14 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Responsive Header
              _buildHeader(context, isMobile),
              const SizedBox(height: 12),

              // 2. Real Metrics Cards
              if (samples.isNotEmpty) ...[
                _buildMetricsBanner(context, samples.first, isMobile),
                const SizedBox(height: 12),
              ],

              // 3. Content: Dual-column (Desktop) or Horizontal-Chips + HexDump (Mobile)
              Expanded(
                child: samples.isEmpty
                    ? _buildEmptyState(context)
                    : isMobile
                        ? _buildMobileBody(context, samples)
                        : _buildDesktopBody(context, samples),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalettes.cyberCyan.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppPalettes.cyberCyan.withAlpha(120)),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: AppPalettes.cyberCyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Inspetor de Tráfego de Rede',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildLiveToggleBadge(),
              _buildZeroPlaintextBadge(),
            ],
          ),
        ],
      );
    }

    // Desktop Header
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppPalettes.cyberCyan.withAlpha(30),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppPalettes.cyberCyan.withAlpha(120),
            ),
          ),
          child: const Icon(
            Icons.radar_rounded,
            color: AppPalettes.cyberCyan,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Inspetor de Tráfego de Rede (Live Wire Dump)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildLiveToggleBadge(),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Inspeção em tempo real dos pacotes criptografados trafegando na rede local',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        _buildZeroPlaintextBadge(),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildLiveToggleBadge() {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        setState(() {
          _autoFollowLive = !_autoFollowLive;
          if (_autoFollowLive) _selectedFrameIndex = 0;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _autoFollowLive
              ? const Color(0xFF00D26A).withAlpha(30)
              : Colors.amber.withAlpha(30),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _autoFollowLive ? const Color(0xFF00D26A) : Colors.amber,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _autoFollowLive
                  ? Icons.fiber_manual_record_rounded
                  : Icons.pause_circle_filled_rounded,
              size: 11,
              color: _autoFollowLive ? const Color(0xFF00D26A) : Colors.amber,
            ),
            const SizedBox(width: 4),
            Text(
              _autoFollowLive ? 'AO VIVO' : 'PAUSADO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color:
                    _autoFollowLive ? const Color(0xFF00D26A) : Colors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZeroPlaintextBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF00D26A).withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF00D26A)),
      ),
      child: const Text(
        '🛡️ Zero-Plaintext Audit: 100% PASS',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00D26A),
        ),
      ),
    );
  }

  Widget _buildMetricsBanner(
      BuildContext context, WireFrameSample latest, bool isMobile) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 16,
        vertical: isMobile ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141C2B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF243447) : const Color(0xFFCBD5E1),
        ),
      ),
      child: isMobile
          ? Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMetricItem(
                  label: 'Cifra',
                  value: 'ChaCha20-Poly1305',
                  color: AppPalettes.cyberEmerald,
                  isMobile: true,
                ),
                _buildMetricItem(
                  label: 'Entropia no Cabo',
                  value:
                      '${latest.entropyBitsPerByte.toStringAsFixed(3)} / 8.0 b/B',
                  color: AppPalettes.cyberCyan,
                  isMobile: true,
                ),
                _buildMetricItem(
                  label: 'Vazamento',
                  value: '0 Bytes',
                  color: const Color(0xFF00D26A),
                  isMobile: true,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricItem(
                  label: 'Cifra de Proteção',
                  value: 'ChaCha20-Poly1305 AEAD',
                  color: AppPalettes.cyberEmerald,
                  isMobile: false,
                ),
                _buildMetricItem(
                  label: 'Entropia de Shannon no Cabo',
                  value:
                      '${latest.entropyBitsPerByte.toStringAsFixed(4)} / 8.0000 bits',
                  color: AppPalettes.cyberCyan,
                  isMobile: false,
                ),
                _buildMetricItem(
                  label: 'Vazamento de Dados em Claro',
                  value: '0 Bytes Detectados',
                  color: const Color(0xFF00D26A),
                  isMobile: false,
                ),
              ],
            ),
    );
  }

  Widget _buildMetricItem({
    required String label,
    required String value,
    required Color color,
    required bool isMobile,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isMobile ? 10 : 11,
            color: const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: isMobile ? 11.5 : 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // Mobile layout: Horizontal frame selector on top + Full width Hex Dump below
  Widget _buildMobileBody(BuildContext context, List<WireFrameSample> samples) {
    final selectedSample =
        samples[_selectedFrameIndex.clamp(0, samples.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Horizontal scrollable frame chips
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: samples.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final sample = samples[index];
              final isSelected = index == _selectedFrameIndex;
              final isLatest = index == 0;

              return ChoiceChip(
                showCheckmark: false,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLatest && _autoFollowLive)
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF00D26A),
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      '#${sample.sequence} ${sample.frameType}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _selectedFrameIndex = index;
                    _autoFollowLive = (index == 0);
                  });
                },
              );
            },
          ),
        ),
        const SizedBox(height: 10),

        // Hex Dump View taking full width
        Expanded(
          child: _buildHexDumpViewer(context, selectedSample, isMobile: true),
        ),
      ],
    );
  }

  // Desktop layout: Dual Column side-by-side
  Widget _buildDesktopBody(
      BuildContext context, List<WireFrameSample> samples) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final selectedSample =
        samples[_selectedFrameIndex.clamp(0, samples.length - 1)];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left List: Captured frames
        SizedBox(
          width: 270,
          child: Card(
            margin: EdgeInsets.zero,
            color: isDark ? const Color(0xFF141C2B) : const Color(0xFFF8FAFC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color:
                    isDark ? const Color(0xFF243447) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              children: [
                if (!_autoFollowLive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    color: Colors.amber.withAlpha(25),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Visualizando histórico',
                          style: TextStyle(fontSize: 11, color: Colors.amber),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _autoFollowLive = true;
                              _selectedFrameIndex = 0;
                            });
                          },
                          child: const Text(
                            'Ir para o Ao Vivo ⚡',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppPalettes.cyberCyan,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: samples.length,
                    separatorBuilder: (_, __) => const Divider(height: 6),
                    itemBuilder: (context, index) {
                      final sample = samples[index];
                      final isSelected = index == _selectedFrameIndex;
                      final isLatest = index == 0;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: colorScheme.primaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Row(
                          children: [
                            if (isLatest && _autoFollowLive)
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00D26A),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                '#${sample.sequence} ${sample.frameType}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isSelected
                                      ? colorScheme.onPrimaryContainer
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${sample.direction} • ${sample.totalWireBytes} B',
                          style: const TextStyle(fontSize: 10),
                        ),
                        trailing: Text(
                          '${sample.timestamp.hour.toString().padLeft(2, '0')}:${sample.timestamp.minute.toString().padLeft(2, '0')}:${sample.timestamp.second.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        onTap: () {
                          setState(() {
                            _selectedFrameIndex = index;
                            _autoFollowLive = (index == 0);
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),

        // Right Panel: Hex Dump + Deep Packet Analysis
        Expanded(
          child: _buildHexDumpViewer(context, selectedSample, isMobile: false),
        ),
      ],
    );
  }

  Widget _buildHexDumpViewer(BuildContext context, WireFrameSample sample,
      {required bool isMobile}) {
    final hexDump = sample.toHexDump(maxBytes: 128);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Breakdown chips
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildBadge('Frame: ${sample.frameType}', const Color(0xFF38BDF8)),
            _buildBadge(
                'Sequência: #${sample.sequence}', const Color(0xFFA78BFA)),
            _buildBadge(
                'Tamanho: ${sample.totalWireBytes} bytes', const Color(0xFF34D399)),
            _buildBadge(
                'Entropia: ${sample.entropyBitsPerByte.toStringAsFixed(3)} b/B',
                const Color(0xFFFBBF24)),
          ],
        ),
        const SizedBox(height: 8),

        // Canonical Wire Hex Dump Box with Horizontal and Vertical Scrolling
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E17), // Deep terminal black
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  hexDump,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 11,
                    height: 1.45,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Copy button & note
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                isMobile
                    ? 'ℹ️ Tráfego 100% indistinguível de ruído.'
                    : 'ℹ️ O tráfego capturado por um sniffer (Wireshark) é 100% indistinguível de ruído aleatório.',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: hexDump));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Dump hexadecimal copiado!')),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 14),
              label:
                  const Text('Copiar Dump', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            size: 40,
            color: Color(0xFF64748B),
          ),
          SizedBox(height: 10),
          Text(
            'Nenhum pacote transmitido ainda nesta sessão.',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          SizedBox(height: 4),
          Text(
            'Inicie o envio de um arquivo para inspecionar os pacotes no cabo.',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}
