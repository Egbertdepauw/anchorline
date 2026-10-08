/// Full-screen image viewer for attached photos. Wraps the file in an
/// `InteractiveViewer` so the user gets pinch-to-zoom + pan for free,
/// without pulling in a third-party gallery widget for v1.
///
/// The AppBar exposes three actions: Info (bottom sheet with the
/// attachment metadata that the grid no longer surfaces inline),
/// Share (system share sheet), and Delete (confirmation dialog →
/// caller-supplied callback). The delete callback is the parent's
/// responsibility — the viewer just confirms, fires it, and pops.
///
/// We deliberately avoid the iOS share sheet for image previews — the
/// share sheet is the right exit for "send this to someone", but it
/// makes the simple "let me see the photo full-size" path two extra
/// taps. The viewer keeps Share available via the AppBar action so
/// neither path is lost.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/dive_attachment.dart';
import '../theme/media_colors.dart';
import '../widgets/background_watermark.dart' show SuppressWatermark;

class ImageViewerScreen extends StatelessWidget {
  final File file;
  final String title;

  /// The attachment row backing this viewer. Required so the Info
  /// popup can render filename / MIME / size / upload time without
  /// the parent having to format strings up-front.
  final FileAttachment attachment;

  /// Fired after the user confirms deletion. The parent typically
  /// calls `notifier.softDelete(id)` and pops the route. The viewer
  /// itself pops immediately after invoking the callback so the
  /// user lands back on the dive-detail screen without an extra tap.
  final VoidCallback onDelete;

  const ImageViewerScreen({
    super.key,
    required this.file,
    required this.title,
    required this.attachment,
    required this.onDelete,
  });

  Future<void> _showInfo(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _ImageInfoSheet(attachment: attachment),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this attachment?'),
        content: const Text(
          'The photo will be removed from this dive. You can re-upload it later if you change your mind.',
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
    onDelete();
  }

  @override
  Widget build(BuildContext context) {
    // SuppressWatermark (#70): this route lives on the Dives tab's nested
    // navigator, so the app shell's brand watermark would otherwise
    // composite a visible tint over the full-screen photo.
    return SuppressWatermark(
      child: Scaffold(
        backgroundColor: MediaColors.viewerBackground,
        appBar: AppBar(
          backgroundColor: MediaColors.scrim(0.6),
          foregroundColor: MediaColors.viewerForeground,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    [XFile(file.path)],
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
        body: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.file(file, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet rendering filename / MIME / size / upload time / and
/// the description, if any. Reads only from the [FileAttachment]
/// model so it stays trivially testable.
class _ImageInfoSheet extends StatelessWidget {
  final FileAttachment attachment;

  const _ImageInfoSheet({required this.attachment});

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
            Text('Image info',
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

/// Hand-rolled human-readable size — twelve lines beats a new dep.
/// 1024-base, single-decimal, trimmed-trailing-zero.
/// Identical to the formatter in attachment_tile.dart; copied here
/// to keep the viewer self-contained.
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

/// `YYYY-MM-DD HH:MM` — no timezone math (the row is local time as
/// written by the notifier) and no `intl` for one formatter.
String _formatTimestamp(DateTime when) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${when.year}-${two(when.month)}-${two(when.day)} '
      '${two(when.hour)}:${two(when.minute)}';
}
