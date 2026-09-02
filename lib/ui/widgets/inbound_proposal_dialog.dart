import 'package:flutter/material.dart';
import '../../core/session/session_manager.dart';

/// Modal dialog prompting user to accept or reject an incoming connection request.
class InboundProposalDialog extends StatelessWidget {
  final InboundSessionProposal proposal;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const InboundProposalDialog({
    super.key,
    required this.proposal,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.downloading_rounded,
                color: colorScheme.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Incoming Transfer Request',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A remote device on your local network wants to establish an encrypted file transfer session:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lan_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${proposal.remoteAddress}:${proposal.remotePort}',
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Accepting will initiate ephemeral X25519 cryptographic key exchange.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.error,
              side: BorderSide(color: colorScheme.error),
            ),
            onPressed: onReject,
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: onAccept,
            child: const Text('Accept & Connect'),
          ),
        ],
      ),
    );
  }
}
