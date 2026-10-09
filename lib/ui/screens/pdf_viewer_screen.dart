/// In-app full-screen PDF viewer for attached documents — same shape
/// as [ImageViewerScreen] so opening a PDF from the Media tab feels
/// like opening a photo, not like dropping into the OS share sheet.
///
/// Backed by `pdfx`, which uses PDFKit on iOS/macOS, PdfRenderer on
/// Android, and MuPDF on Windows/Linux. The pinch viewport gives us
/// zoom + pan + page swipe out of the box.
///
/// AppBar mirrors the image viewer: Info → Share → Delete. Info pops a
/// bottom sheet with file metadata; Share hands off to share_plus;
/// Delete fires the caller-supplied onDelete (which the parent wires
/// to soft-delete + pop). The viewer pops itself after onDelete.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/dive_attachment.dart';
import '../theme/media_colors.dart';
import '../widgets/background_watermark.dart' show SuppressWatermark;

class PdfViewerScreen extends StatefulWidget {
  final File file;
  final String title;
  final FileAttachment attachment;
  final VoidCallback onDelete;

  const PdfViewerScreen({
    super.key,
    required this.file,
    required this.title,
    required this.attachment,
    required this.onDelete,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late final PdfControllerPinch _controller;

  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openFile(widget.file.path),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _showInfo(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _PdfInfoSheet(attachment: widget.attachment),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this attachment?'),
        content: const Text(
          'The PDF will be removed from this dive. You can re-upload it later if you change your mind.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    // SuppressWatermark (#70): this route lives on the Dives tab's nested
    // navigator, so the app shell's brand watermark would otherwise
    // composite a visible tint over the (mostly white) PDF pages.
    return SuppressWatermark(
      child: Scaffold(
        backgroundColor: MediaColors.viewerBackground,
        appBar: AppBar(
          backgroundColor: MediaColors.scrim(0.6),
          foregroundColor: MediaColors.viewerForeground,
          title: Text(widget.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: 'Info',
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showInfo(context),
            ),
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: () {
                  final box = ctx.findRenderObject() as RenderBox?;
                  final origin = box != null
                      ? box.localToGlobal(Offset.zero) & box.size
                      : null;
                  Share.shareXFiles(
                    [XFile(widget.file.path)],
                    sharePositionOrigin: origin,
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(context),
            ),
          ],
        ),
        body: PdfViewPinch(controller: _controller),
      ),
    );
  }
}

/// Bottom sheet rendering filename / MIME / size / upload time / and
/// the description, if any. Mirrors `_ImageInfoSheet` in
/// [ImageViewerScreen]; the two are close enough that a future
/// extraction into a shared widget is reasonable but not urgent.
class _PdfInfoSheet extends StatelessWidget {
  final FileAttachment attachment;

  const _PdfInfoSheet({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = attachment.sizeBytes;
    final rows = <_InfoRow>[
      _InfoRow('Filename', attachment.originalFilename ?? '—'),
      _InfoRow('Type', attachment.mimeType),
      if (size != null) _InfoRow('Size', _humanSize(size)),
      _InfoRow('Uploaded', _formatTimestamp(attachment.createdAt)),
      if (attachment.description?.trim().isNotEmpty == true)
        _InfoRow('Description', attachment.description!.trim()),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('PDF info',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final row in rows) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        row.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        row.value,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}

String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unit = -1;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final formatted = size.toStringAsFixed(1);
  final trimmed = formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
  return '$trimmed ${units[unit]}';
}

String _formatTimestamp(DateTime dt) {
  final local = dt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
