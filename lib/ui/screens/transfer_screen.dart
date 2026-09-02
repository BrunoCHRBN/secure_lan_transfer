import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/transfer_progress.dart';
import '../../core/protocol/session_state.dart';
import '../providers/settings_provider.dart';
import '../providers/transfer_session_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/chunk_progress_bar.dart';
import '../widgets/live_traffic_inspector_dialog.dart';
import '../widgets/speedometer_widget.dart';

/// Extension providing formatted display names for TransferState.
extension TransferStateDisplayName on TransferState {
  String get displayName {
    switch (this) {
      case TransferState.idle:
        return 'Idle';
      case TransferState.connecting:
        return 'Connecting';
      case TransferState.handshaking:
        return 'Handshaking';
      case TransferState.transferring:
        return 'Transferring';
      case TransferState.paused:
        return 'Paused';
      case TransferState.verifying:
        return 'Verifying SHA-256';
      case TransferState.completed:
        return 'Completed';
      case TransferState.error:
        return 'Error';
      case TransferState.cancelled:
        return 'Cancelled';
    }
  }
}

/// Real-Time Transfer Cockpit Screen with Speedometer, Chunk Pipeline, and Controls.
class TransferScreen extends StatelessWidget {
  final VoidCallback onNavigateToDiscovery;

  const TransferScreen({
    super.key,
    required this.onNavigateToDiscovery,
  });

  void _confirmCancel(BuildContext context, TransferSessionProvider session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Transfer?'),
        content: const Text(
          'Are you sure you want to cancel the ongoing file transfer? Any incomplete temporary files will be wiped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Transfer'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(context);
              session.cancelTransfer('Cancelled by user');
            },
            child: const Text('Cancel Transfer'),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String? fileName) {
    if (fileName == null) return Icons.insert_drive_file_rounded;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image_rounded;
      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
        return Icons.movie_rounded;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return Icons.music_note_rounded;
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
        return Icons.description_rounded;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.folder_zip_rounded;
      case 'apk':
      case 'exe':
      case 'dmg':
        return Icons.extension_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final session = context.watch<TransferSessionProvider>();
    final settings = context.watch<SettingsProvider>();

    final state = session.currentState;
    final progress = state.progress;
    final transferState = state.state;

    if (transferState == TransferState.idle && !session.hasActiveTransfer) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.swap_horizontal_circle_outlined,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Active Transfer Session',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a discovered peer on the Discovery tab to send a file, or wait for an incoming connection.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: const Icon(Icons.radar_rounded),
                  label: const Text('Open Peer Discovery'),
                  onPressed: onNavigateToDiscovery,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isInbound = state.role == TransferRole.receiver;
    final isPaused = transferState == TransferState.paused;
    final isVerifying = transferState == TransferState.verifying;
    final isCompleted = transferState == TransferState.completed;
    final isError = transferState == TransferState.error;
    final isCancelled = transferState == TransferState.cancelled;

    final fileName = state.fileName ??
        (state.committedFilePath != null
            ? File(state.committedFilePath!).uri.pathSegments.last
            : 'File Transfer');

    final transferredBytes = progress?.transferredBytes ?? 0;
    final totalBytes = state.totalBytes ?? progress?.totalBytes ?? 0;
    final speedBytesPerSec = progress?.speedBytesPerSec ?? 0.0;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Direction & Security Header Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCompleted
                        ? Colors.green.withValues(alpha: 0.6)
                        : isError
                            ? colorScheme.error.withValues(alpha: 0.6)
                            : colorScheme.outlineVariant
                                .withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isInbound
                                  ? Icons.download_rounded
                                  : Icons.upload_rounded,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isInbound
                                  ? 'Receiving from ${state.remoteDeviceName ?? "Peer"}'
                                  : 'Sending to ${state.remoteDeviceName ?? "Peer"}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        // State Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? Colors.green.withValues(alpha: 0.2)
                                : isError
                                    ? colorScheme.error
                                        .withValues(alpha: 0.2)
                                    : isPaused
                                        ? Colors.amber.withValues(alpha: 0.2)
                                        : colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            transferState.displayName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isCompleted
                                  ? Colors.greenAccent[400]
                                  : isError
                                      ? colorScheme.error
                                      : isPaused
                                          ? Colors.amber
                                          : colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 14, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              'ChaCha20-Poly1305 AEAD • X25519 E2EE',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => LiveTrafficInspectorDialog.show(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppPalettes.cyberCyan.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppPalettes.cyberCyan.withAlpha(120)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.radar_rounded,
                                    size: 13, color: AppPalettes.cyberCyan),
                                SizedBox(width: 4),
                                Text(
                                  '📡 Inspecionar Tráfego (Live Wire)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppPalettes.cyberCyan,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // File Information Card
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _getFileIcon(fileName),
                          color: colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${TransferProgress.formatBytes(transferredBytes)} of ${TransferProgress.formatBytes(totalBytes)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Multi-File Batch Queue Card (when transmitting multiple files)
              if (session.isMultiFileTransfer) ...[
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Transfer Queue (${session.queueProgress.completedFiles}/${session.queueProgress.totalFiles} Completed)',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${(session.queueProgress.overallFraction * 100).toStringAsFixed(0)}%',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: session.queueProgress.overallFraction,
                            minHeight: 6,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: session.queueJobs.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 8),
                            itemBuilder: (context, idx) {
                              final job = session.queueJobs[idx];
                              return Row(
                                children: [
                                  Icon(
                                    job.isCompleted
                                        ? Icons.check_circle_rounded
                                        : job.isTransferring
                                            ? Icons.sync_rounded
                                            : job.isFailed
                                                ? Icons.error_rounded
                                                : Icons.schedule_rounded,
                                    color: job.isCompleted
                                        ? Colors.greenAccent[400]
                                        : job.isTransferring
                                            ? colorScheme.primary
                                            : job.isFailed
                                                ? colorScheme.error
                                                : colorScheme.onSurfaceVariant,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      job.fileName,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: job.isTransferring
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    TransferProgress.formatBytes(job.fileSize),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Speedometer & Visualizer Cockpit
              Center(
                child: SpeedometerWidget(
                  speedBytesPerSec: speedBytesPerSec,
                  peakSpeedBytesPerSec: progress?.speedBytesPerSec ?? 0.0,
                  size: 190,
                ),
              ),
              const SizedBox(height: 16),

              // Chunk Sliding Window Pipeline Progress Bar
              ChunkProgressBar(
                transferredBytes: transferredBytes,
                totalBytes: totalBytes,
                chunkSize: settings.chunkSize,
                creditWindowSize: settings.creditWindowSize,
                isPaused: isPaused,
              ),
              const SizedBox(height: 20),

              // Metrics Grid (4 Summary Cards)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      title: 'Current Speed',
                      value: progress?.speedFormatted ?? '0.0 MB/s',
                      icon: Icons.speed_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      title: 'Estimated ETA',
                      value: isPaused
                          ? 'Paused'
                          : progress?.isStalled == true
                              ? 'Stalled'
                              : progress?.etaFormatted ?? '--:--',
                      icon: Icons.timer_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      title: 'Elapsed Time',
                      value: progress != null
                          ? TransferProgress.formatDuration(
                              progress.elapsedTime)
                          : '00:00',
                      icon: Icons.hourglass_bottom_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricCard(
                      context,
                      title: 'Integrity Root',
                      value: isCompleted
                          ? 'SHA-256 Verified ✓'
                          : isVerifying
                              ? 'Verifying...'
                              : 'Incremental SHA-256',
                      icon: Icons.verified_user_outlined,
                      isHighlight: isCompleted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Terminal States / Action Controls
              if (isVerifying)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Computing & Verifying Root SHA-256 Digest...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else if (isCompleted)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Colors.green, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Transfer Complete & Cryptographically Verified!',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent[400],
                            ),
                          ),
                        ],
                      ),
                      if (state.committedFilePath != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Saved to: ${state.committedFilePath}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'Courier',
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (state.committedFilePath != null) ...[
                            OutlinedButton.icon(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copy Path'),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text: state.committedFilePath!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Path copied to clipboard'),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          FilledButton.icon(
                            icon: const Icon(Icons.done_all_rounded, size: 18),
                            label: const Text('Done / Reset'),
                            onPressed: () {
                              session.resetSession();
                              onNavigateToDiscovery();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else if (isError)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colorScheme.error),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_rounded,
                              color: colorScheme.error, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Transfer Failed: ${state.error?.code.name ?? "Error"}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.error?.message ?? 'An unexpected error occurred.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.tonal(
                            onPressed: () {
                              session.resetSession();
                              onNavigateToDiscovery();
                            },
                            child: const Text('Dismiss & Return'),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else if (isCancelled)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Transfer was cancelled by user. Temporary staging files were securely unlinked.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          session.resetSession();
                          onNavigateToDiscovery();
                        },
                        child: const Text('Return to Discovery'),
                      ),
                    ],
                  ),
                )
              else
                // In-Progress Transfer Controls
                Row(
                  children: [
                    if (!isInbound) ...[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                          ),
                          label: Text(isPaused ? 'Resume' : 'Pause'),
                          onPressed: isPaused
                              ? session.resumeTransfer
                              : session.pauseTransfer,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.cancel_rounded),
                        label: const Text('Cancel Transfer'),
                        onPressed: () => _confirmCancel(context, session),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    bool isHighlight = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlight
              ? Colors.green.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isHighlight ? Colors.green : colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlight ? Colors.greenAccent[400] : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
