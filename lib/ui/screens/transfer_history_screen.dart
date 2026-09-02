import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/transfer_progress.dart';
import '../../core/protocol/session_state.dart';
import '../providers/transfer_session_provider.dart';

/// Screen displaying volatile in-RAM transfer history conforming to zero-metadata policy.
class TransferHistoryScreen extends StatefulWidget {
  const TransferHistoryScreen({super.key});

  @override
  State<TransferHistoryScreen> createState() => _TransferHistoryScreenState();
}

class _TransferHistoryScreenState extends State<TransferHistoryScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = context.watch<TransferSessionProvider>();
    final history = session.history;

    final filtered = history.where((item) {
      if (_selectedFilter == 'Completed') {
        return item.finalState == TransferState.completed;
      }
      if (_selectedFilter == 'Failed') {
        return item.finalState == TransferState.error;
      }
      if (_selectedFilter == 'Cancelled') {
        return item.finalState == TransferState.cancelled;
      }
      return true;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar & Zero-Metadata Policy Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Transfer History',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (history.isNotEmpty)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_sweep_rounded,
                              size: 18),
                          label: const Text('Wipe RAM History'),
                          onPressed: () {
                            session.clearHistory();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('In-memory transfer logs wiped'),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Privacy Policy Banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.security_rounded,
                            color: colorScheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Zero-Metadata Mode Active: Transfer logs exist solely in volatile RAM and leave zero trace on disk.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children:
                          ['All', 'Completed', 'Failed', 'Cancelled'].map((f) {
                        final isSelected = _selectedFilter == f;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(f),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() {
                                _selectedFilter = f;
                              });
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // History List or Empty State
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.history_toggle_off_rounded,
                              size: 56,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No transfer history recorded',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Transfers in this session will appear here ephemerally until the app is closed.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final isSent = item.role == TransferRole.initiator;
                        final isCompleted =
                            item.finalState == TransferState.completed;
                        final isFailed =
                            item.finalState == TransferState.error;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: isCompleted
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : isFailed
                                      ? colorScheme.error
                                          .withValues(alpha: 0.3)
                                      : colorScheme.outlineVariant
                                          .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isSent
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      size: 18,
                                      color: isSent
                                          ? Colors.cyanAccent
                                          : Colors.tealAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.fileName,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? Colors.green
                                                .withValues(alpha: 0.2)
                                            : isFailed
                                                ? colorScheme.error
                                                    .withValues(alpha: 0.2)
                                                : Colors.grey
                                                    .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        item.finalState.name.toUpperCase(),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isCompleted
                                              ? Colors.greenAccent[400]
                                              : isFailed
                                                  ? colorScheme.error
                                                  : Colors.grey[400],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${TransferProgress.formatBytes(item.totalBytes)} • ${item.peerName}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('HH:mm:ss')
                                          .format(item.timestamp),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.committedFilePath != null) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.committedFilePath!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontFamily: 'Courier',
                                            fontSize: 10,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                       IconButton(
                                         icon: const Icon(Icons.folder_open_rounded,
                                             size: 18),
                                         tooltip: 'Open folder',
                                         onPressed: () {
                                           final filePath = item.committedFilePath!;
                                           if (Platform.isWindows) {
                                             Process.run('explorer.exe', ['/select,', filePath]);
                                           } else if (Platform.isMacOS) {
                                             Process.run('open', ['-R', filePath]);
                                           } else if (Platform.isLinux) {
                                             Process.run('xdg-open', [File(filePath).parent.path]);
                                           }
                                         },
                                       ),
                                       IconButton(
                                         icon: const Icon(Icons.copy_rounded,
                                             size: 16),
                                         tooltip: 'Copy path',
                                         onPressed: () {
                                           Clipboard.setData(ClipboardData(
                                               text: item.committedFilePath!));
                                           ScaffoldMessenger.of(context)
                                               .showSnackBar(
                                             const SnackBar(
                                                 content: Text(
                                                     'File path copied to clipboard')),
                                           );
                                         },
                                       ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
