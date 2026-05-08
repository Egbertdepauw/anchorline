/// One row in the attachments list. Switches on the [DiveAttachment]
/// sealed type so files render with size + MIME info and a pending /
/// failed badge while links render with a domain-derived title and a
/// truncated URL subtitle.
///
/// All side-effecting actions are delegated through callbacks — the
/// tile never opens a download, never launches a URL, never calls the
/// DAO. The parent section composes it with the right callbacks; the
/// dive-detail screen composes the section with the actual platform
/// integrations.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/dive_attachment.dart';

class AttachmentTile extends StatelessWidget {
  final DiveAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Non-null only when [attachment] is a [FileAttachment] in the
  /// `failed` upload state. The tile shows a retry button when this
  /// is supplied.
  final VoidCallback? onRetry;

  /// Optional drag-handle that the parent ReorderableListView wires
  /// up to its own index. When null the tile renders without a
  /// dedicated leading drag affordance (used in tests / non-reorder
  /// contexts).
  final Widget? dragHandle;

  /// Resolves an R2 storage key to a local [File], used by image-MIME
  /// rows to render an actual thumbnail instead of the generic icon.
  /// Tests omit it; the parent screen wires it to the
  /// [AttachmentDownloader] in production.
  final Future<File> Function(String storageKey)? loadFile;

  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.onRetry,
    this.dragHandle,
    this.loadFile,
  });

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return switch (a) {
      FileAttachment() => _FileTile(
          attachment: a,
          onOpen: onOpen,
          onEdit: onEdit,
          onDelete: onDelete,
          onRetry: onRetry,
          dragHandle: dragHandle,
          loadFile: loadFile,
        ),
      LinkAttachment() => _LinkTile(
          attachment: a,
          onOpen: onOpen,
          onEdit: onEdit,
          onDelete: onDelete,
          dragHandle: dragHandle,
        ),
    };
  }
}

class _FileTile extends StatelessWidget {
  final FileAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;
  final Widget? dragHandle;
  final Future<File> Function(String storageKey)? loadFile;

  const _FileTile({
    required this.attachment,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
    required this.dragHandle,
    required this.loadFile,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = attachment.uploadState == UploadState.pending;
    final failed = attachment.uploadState == UploadState.failed;
    final canOpen = attachment.uploadState == UploadState.uploaded;
    final isImage = attachment.mimeType.toLowerCase().startsWith('image/');

    final title = attachment.title?.trim().isNotEmpty == true
        ? attachment.title!.trim()
        : (attachment.originalFilename ?? 'Untitled');

    final size = attachment.sizeBytes;
    final subtitleParts = <String>[
      attachment.mimeType,
      if (size != null) _humanSize(size),
      _relativeUploaded(attachment.createdAt),
    ];

    // For uploaded image rows we render the actual photo as a 40x40
    // square thumbnail; everything else falls back to a MIME-typed
    // icon. The thumbnail FutureBuilder hits the AttachmentCache via
    // loadFile() — first view downloads, subsequent views are local.
    final fallbackIcon =
        Icon(_iconForMime(attachment.mimeType), color: scheme.primary);
    final Widget leadingArt;
    if (isImage && canOpen && loadFile != null) {
      leadingArt = _ImageThumbnail(
        storageKey: attachment.storageKey,
        loadFile: loadFile!,
        fallback: fallbackIcon,
      );
    } else {
      leadingArt = SizedBox(
        width: 40,
        height: 40,
        child: Center(child: fallbackIcon),
      );
    }
    final leadingIcon = Stack(
      alignment: Alignment.center,
      children: [
        leadingArt,
        if (pending)
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );

    return ListTile(
      leading: dragHandle == null
          ? leadingIcon
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dragHandle!,
                const SizedBox(width: 8),
                leadingIcon,
              ],
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (failed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Upload failed',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: canOpen ? onOpen : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (failed && onRetry != null)
            IconButton(
              tooltip: 'Retry upload',
              icon: Icon(Icons.refresh, color: scheme.error),
              onPressed: onRetry,
            ),
          PopupMenuButton<_TileAction>(
            tooltip: 'More',
            onSelected: (action) {
              switch (action) {
                case _TileAction.open:
                  onOpen();
                case _TileAction.edit:
                  onEdit();
                case _TileAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: _TileAction.open,
                enabled: canOpen,
                child: const Text('Open'),
              ),
              const PopupMenuItem(
                value: _TileAction.edit,
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                value: _TileAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final LinkAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Widget? dragHandle;

  const _LinkTile({
    required this.attachment,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.dragHandle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = attachment.title?.trim().isNotEmpty == true
        ? attachment.title!.trim()
        : (_domainOf(attachment.url) ?? attachment.url);

    final leadingIcon = Icon(Icons.link, color: scheme.primary);

    return ListTile(
      leading: dragHandle == null
          ? leadingIcon
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                dragHandle!,
                const SizedBox(width: 8),
                leadingIcon,
              ],
            ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        attachment.url,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onOpen,
      trailing: PopupMenuButton<_TileAction>(
        tooltip: 'More',
        onSelected: (action) {
          switch (action) {
            case _TileAction.open:
              onOpen();
            case _TileAction.edit:
              onEdit();
            case _TileAction.delete:
              onDelete();
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(
            value: _TileAction.open,
            child: Text('Open in browser'),
          ),
          PopupMenuItem(
            value: _TileAction.edit,
            child: Text('Edit'),
          ),
          PopupMenuItem(
            value: _TileAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}

enum _TileAction { open, edit, delete }

/// Async-loaded square image thumbnail with a graceful icon fallback
/// before bytes are on disk and on any error. Stateful so we can hold
/// the future across rebuilds (otherwise scrolling re-issues the load).
class _ImageThumbnail extends StatefulWidget {
  final String storageKey;
  final Future<File> Function(String storageKey) loadFile;
  final Widget fallback;
  const _ImageThumbnail({
    required this.storageKey,
    required this.loadFile,
    required this.fallback,
  });

  @override
  State<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends State<_ImageThumbnail> {
  late Future<File> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFile(widget.storageKey);
  }

  @override
  void didUpdateWidget(covariant _ImageThumbnail old) {
    super.didUpdateWidget(old);
    if (old.storageKey != widget.storageKey) {
      _future = widget.loadFile(widget.storageKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 40,
        height: 40,
        child: FutureBuilder<File>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.hasError || (snap.connectionState == ConnectionState.done &&
                !snap.hasData)) {
              return Center(child: widget.fallback);
            }
            if (!snap.hasData) {
              return Center(child: widget.fallback);
            }
            return Image.file(
              snap.data!,
              fit: BoxFit.cover,
              cacheWidth: 80, // 2x for retina
              errorBuilder: (_, _, _) => Center(child: widget.fallback),
            );
          },
        ),
      ),
    );
  }
}

/// Maps a MIME type to a Material icon. Wide nets — anything not
/// recognised falls through to [Icons.insert_drive_file].
IconData _iconForMime(String mimeType) {
  final m = mimeType.toLowerCase();
  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('video/')) return Icons.movie_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (m == 'application/msword' ||
      m == 'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
    return Icons.description_outlined;
  }
  if (m == 'application/vnd.ms-excel' ||
      m == 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
    return Icons.table_chart_outlined;
  }
  if (m == 'application/vnd.ms-powerpoint' ||
      m == 'application/vnd.openxmlformats-officedocument.presentationml.presentation') {
    return Icons.slideshow_outlined;
  }
  if (m == 'text/csv' || m == 'text/tab-separated-values') {
    return Icons.table_chart_outlined;
  }
  if (m.startsWith('text/')) return Icons.notes_outlined;
  if (m == 'application/zip' ||
      m == 'application/x-tar' ||
      m == 'application/gzip' ||
      m == 'application/x-7z-compressed') {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// Hand-rolled human-readable size — twelve lines beats a new dep.
/// Uses 1024-base units (KB / MB / GB) with one decimal place; sub-KB
/// values render as plain bytes.
String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unit = -1;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  // Trim trailing `.0` so "1.0 MB" reads as "1 MB" without bringing
  // intl in for a single number formatter.
  final formatted = size.toStringAsFixed(1);
  final trimmed =
      formatted.endsWith('.0') ? formatted.substring(0, formatted.length - 2) : formatted;
  return '$trimmed ${units[unit]}';
}

/// Relative-date formatter that just covers what the tile needs.
/// "Just now" / "Xm ago" / "Xh ago" / "Xd ago" / absolute date for
/// older items.
String _relativeUploaded(DateTime when) {
  final now = DateTime.now();
  final diff = now.difference(when);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';
}

/// Best-effort domain extraction for the link tile's fallback title.
/// Returns null if the URL can't be parsed; callers fall back to the
/// raw URL in that case.
String? _domainOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.host;
}
