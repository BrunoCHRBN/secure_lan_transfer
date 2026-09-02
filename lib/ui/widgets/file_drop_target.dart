import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/models/transfer_progress.dart';
import '../../core/transfer/directory_archive.dart';

/// Container widget supporting native OS desktop drag-and-drop / file picker selection for single or multiple files and folders.
class FileDropTarget extends StatefulWidget {
  final List<File>? selectedFiles;
  final File? selectedFile;
  final ValueChanged<List<File>>? onFilesSelected;
  final ValueChanged<File?>? onFileSelected;
  final Widget? child;

  const FileDropTarget({
    super.key,
    this.selectedFiles,
    this.selectedFile,
    this.onFilesSelected,
    this.onFileSelected,
    this.child,
  });

  /// Convenience constructor for single file compatibility.
  FileDropTarget.single({
    super.key,
    File? selectedFile,
    required this.onFileSelected,
    this.child,
  })  : selectedFile = selectedFile,
        selectedFiles = selectedFile != null ? [selectedFile] : [],
        onFilesSelected = null;

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  bool _isDragging = false;
  bool _isCompressingFolder = false;

  List<File> get _effectiveFiles =>
      widget.selectedFiles ??
      (widget.selectedFile != null ? [widget.selectedFile!] : []);

  void _notifyFilesSelected(List<File> files) {
    widget.onFilesSelected?.call(files);
    widget.onFileSelected?.call(files.isNotEmpty ? files.first : null);
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        dialogTitle: 'Select File(s) to Send',
      );

      if (result != null && result.files.isNotEmpty) {
        final files = result.files
            .where((f) => f.path != null)
            .map((f) => File(f.path!))
            .toList();
        if (files.isNotEmpty) {
          _notifyFilesSelected(files);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick file(s): $e')),
        );
      }
    }
  }

  Future<void> _handleDroppedUris(List<DropItem> items) async {
    final List<File> resolvedFiles = [];

    for (final item in items) {
      final path = item.path;
      if (path.isEmpty) continue;

      if (FileSystemEntity.isDirectorySync(path)) {
        setState(() => _isCompressingFolder = true);
        try {
          final zip = await DirectoryArchive.packDirectory(Directory(path));
          resolvedFiles.add(zip);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to compress folder: $e')),
            );
          }
        } finally {
          if (mounted) {
            setState(() => _isCompressingFolder = false);
          }
        }
      } else if (FileSystemEntity.isFileSync(path)) {
        resolvedFiles.add(File(path));
      }
    }

    if (resolvedFiles.isNotEmpty) {
      _notifyFilesSelected(resolvedFiles);
    }
  }

  int get _totalSize => _effectiveFiles.fold(
        0,
        (sum, f) => sum + (f.existsSync() ? f.lengthSync() : 0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final files = _effectiveFiles;
    final hasFiles = files.isNotEmpty;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (detail) async {
        setState(() => _isDragging = false);
        await _handleDroppedUris(detail.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isDragging
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isDragging
                ? colorScheme.primary
                : hasFiles
                    ? colorScheme.primary.withValues(alpha: 0.6)
                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: _isDragging ? 2.2 : 1.2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: _isCompressingFolder
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2),
                    const SizedBox(height: 12),
                    Text(
                      'Compressing folder into secure stream archive...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            : hasFiles
                ? files.length == 1
                    ? Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.insert_drive_file_rounded,
                              color: colorScheme.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  files.first.uri.pathSegments.last,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  files.first.existsSync()
                                      ? TransferProgress.formatBytes(
                                          files.first.lengthSync())
                                      : 'Unknown size',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Clear selection',
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => _notifyFilesSelected([]),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                            label: const Text('Change'),
                            onPressed: _pickFiles,
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.folder_zip_rounded,
                                  color: colorScheme.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${files.length} files selected',
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      TransferProgress.formatBytes(_totalSize),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Clear selection',
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () => _notifyFilesSelected([]),
                              ),
                              const SizedBox(width: 4),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.swap_horiz_rounded,
                                    size: 16),
                                label: const Text('Change'),
                                onPressed: _pickFiles,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: files.take(5).map((f) {
                              return Chip(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                label: Text(
                                  f.uri.pathSegments.last,
                                  style: theme.textTheme.bodySmall,
                                ),
                              );
                            }).toList()
                              ..addAll(files.length > 5
                                  ? [
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text('+${files.length - 5} more'),
                                      ),
                                    ]
                                  : []),
                          ),
                        ],
                      )
                : InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickFiles,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 36,
                            color: _isDragging
                                ? colorScheme.primary
                                : colorScheme.primary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isDragging
                                ? 'Drop files or folders here!'
                                : 'Click to browse or drop files/folders here',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _isDragging
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Drag & Drop from Desktop/Explorer supported',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
