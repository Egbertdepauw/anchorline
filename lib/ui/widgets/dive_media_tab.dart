/// Phase-3 Media tab for the dive-detail screen — a thumbnail grid
/// rendering of the per-dive [DiveAttachment] list. Replaces the
/// list-style [DiveAttachmentsSection] in the Media tab; the legacy
/// section is still in use elsewhere (cell-detail screen) so this is
/// a parallel widget rather than a refactor.
///
/// Layout: a [LayoutBuilder] picks a cross-axis count from the tab
/// width (≤600 dp → 2 columns; ≤900 → 3; ≤1200 → 4; else 6) so the
/// grid expands cleanly from a phone in portrait to an iPad / desktop
/// window. Each tile is a 1:1 square; image files render the full
/// photo as the tile, document files render a centered MIME icon over
/// the basename, and links render a Google-favicon-proxy icon over the
/// user-typed title and the host domain.
///
/// Side effects (open, edit, delete, retry, file pick) are delegated
/// to the parent through the same callbacks the legacy section uses;
/// this widget never touches the DAO or the network directly.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/models/dive_attachment.dart';
import '../../sync/attachments/attachment_uploader.dart';
import '../notifiers/dive_attachments_notifier.dart';
import '../screens/add_link_sheet.dart';
import '../screens/edit_attachment_sheet.dart';
import '../theme/media_colors.dart';
import 'storage_full_dialog.dart';

class DiveMediaTab extends StatefulWidget {
  final DiveAttachmentsNotifier notifier;

  /// File-picker callback — owned by the parent screen so this widget
  /// can be unit-tested without touching `image_picker` / `file_picker`.
  final Future<List<PickedAttachmentFile>?> Function(BuildContext) pickFiles;

  /// Open callback — the parent wires the file branch to the in-app
  /// image viewer / share sheet, the link branch to url_launcher.
  final void Function(DiveAttachment attachment) onOpen;

  /// Resolves an R2 storage key to a local [File]. When non-null the
  /// image tiles render the full photo as their thumbnail; when null
  /// they fall back to the generic image icon (used in tests).
  final Future<File> Function(String storageKey)? loadFile;

  const DiveMediaTab({
    super.key,
    required this.notifier,
    required this.pickFiles,
    required this.onOpen,
    this.loadFile,
  });

  /// Picks the cross-axis count for the grid given the available
  /// width. The breakpoints match common form-factors: phone portrait
  /// (≈360), phone landscape / small tablet (≈600–900), large tablet
  /// (≈900–1200), desktop window (>1200). Public so tests can pin
  /// the breakpoints without having to lay out the full widget.
  static int crossAxisCountFor(double width) {
    if (width <= 600) return 2;
    if (width <= 900) return 3;
    if (width <= 1200) return 4;
    return 6;
  }

  @override
  State<DiveMediaTab> createState() => _DiveMediaTabState();
}

class _DiveMediaTabState extends State<DiveMediaTab> {
  DiveAttachmentsNotifier get _n => widget.notifier;

  /// The refusal whose dialog this widget already showed, so a rebuild
  /// doesn't show it again.
  StorageFullState? _shownStorageFull;

  @override
  void initState() {
    super.initState();
    _n.addListener(_onNotifierChanged);
    // A refusal that landed while this widget wasn't mounted.
    if (_n.storageFull != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeShowStorageFull());
    }
  }

  @override
  void dispose() {
    _n.removeListener(_onNotifierChanged);
    super.dispose();
  }

  void _onNotifierChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeShowStorageFull();
  }

  Future<void> _maybeShowStorageFull() async {
    final state = _n.storageFull;
    if (!mounted || state == null || identical(state, _shownStorageFull)) {
      return;
    }
    _shownStorageFull = state;
    final choice = await showStorageFullDialog(context, state: state);
    if (!mounted || !identical(_n.storageFull, state)) return;
    if (choice == StorageFullChoice.freeSpace) {
      await _n.freeSpaceAndRetry();
    } else {
      _n.dismissStorageFull();
    }
  }

  Future<void> _addFiles() async {
    final picked = await widget.pickFiles(context);
    if (picked == null || picked.isEmpty) return;
    // One after another; a storage-full refusal stops the batch and
    // keeps the rest for "Free space now".
    await _n.addFiles(picked);
  }

  Future<void> _addLink() async {
    await showAddLinkSheet(context, notifier: _n);
  }

  Future<void> _delete(DiveAttachment a) async {
    final messenger = ScaffoldMessenger.of(context);
    await _n.softDelete(a.id);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: const Text('Attachment deleted'),
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () => _n.restore(a.id),
      ),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
    ));
  }

  Future<void> _edit(DiveAttachment a) async {
    await showEditAttachmentSheet(context, notifier: _n, attachment: a);
  }

  Future<void> _retry(FileAttachment a) async {
    await _n.retryUpload(a.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attachments = _n.attachments;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'MEDIA',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${attachments.length} ${attachments.length == 1 ? 'item' : 'items'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
              ),
            ],
          ),
          if (_n.loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (_n.error != null || _n.uploadsPaused)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 18, color: scheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _n.uploadsPaused ? kUploadsPausedMessage : _n.error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    if (_n.uploadsPaused)
                      TextButton(
                        onPressed: _n.dismissUploadsPaused,
                        child: const Text('Dismiss'),
                      )
                    else
                      TextButton(
                        onPressed: _n.reload,
                        child: const Text('Retry'),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (attachments.isNotEmpty)
            LayoutBuilder(builder: (context, constraints) {
              final count =
                  DiveMediaTab.crossAxisCountFor(constraints.maxWidth);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: attachments.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: count,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemBuilder: (ctx, i) {
                  final a = attachments[i];
                  return _MediaTile(
                    key: ValueKey(a.id),
                    attachment: a,
                    loadFile: widget.loadFile,
                    onOpen: () => widget.onOpen(a),
                    onEdit: () => _edit(a),
                    onDelete: () => _delete(a),
                    onRetry: a is FileAttachment &&
                            a.uploadState == UploadState.failed
                        ? () => _retry(a)
                        : null,
                    storageFull: _n.isStorageFull(a.id),
                  );
                },
              );
            }),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add file'),
                onPressed: _addFiles,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_link, size: 18),
                label: const Text('Add link'),
                onPressed: _addLink,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One grid cell. Switches on the [DiveAttachment] sealed type so
/// images, documents, and links each get the right shape without a
/// chain of nullable fields.
class _MediaTile extends StatelessWidget {
  final DiveAttachment attachment;
  final Future<File> Function(String storageKey)? loadFile;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;

  /// A `failed` file the Worker refused because storage is full.
  final bool storageFull;

  const _MediaTile({
    super.key,
    required this.attachment,
    required this.loadFile,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
    required this.storageFull,
  });

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return switch (a) {
      FileAttachment() => _FileMediaTile(
          attachment: a,
          loadFile: loadFile,
          onOpen: onOpen,
          onEdit: onEdit,
          onDelete: onDelete,
          onRetry: onRetry,
          storageFull: storageFull,
        ),
      LinkAttachment() => _LinkMediaTile(
          attachment: a,
          onOpen: onOpen,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
    };
  }
}

class _FileMediaTile extends StatelessWidget {
  final FileAttachment attachment;
  final Future<File> Function(String storageKey)? loadFile;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRetry;
  final bool storageFull;

  const _FileMediaTile({
    required this.attachment,
    required this.loadFile,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onRetry,
    required this.storageFull,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = attachment.uploadState == UploadState.pending;
    final failed = attachment.uploadState == UploadState.failed;
    final canOpen = attachment.uploadState == UploadState.uploaded;
    final isImage = attachment.mimeType.toLowerCase().startsWith('image/');

    final Widget body;
    if (isImage) {
      body = _ImageBody(
        storageKey: attachment.storageKey,
        loadFile: canOpen ? loadFile : null,
        scheme: scheme,
      );
    } else {
      body = _DocumentBody(attachment: attachment, scheme: scheme);
    }

    final overlays = <Widget>[];
    if (pending) {
      overlays.add(Container(
        color: MediaColors.scrim(0.35),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ));
    } else if (failed) {
      overlays.add(Container(
        color: MediaColors.scrim(0.45),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  storageFull ? 'Storage full' : 'Upload failed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 6),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ));
    }

    return _TileFrame(
      onTap: canOpen ? onOpen : null,
      onEdit: onEdit,
      onDelete: onDelete,
      onOpen: canOpen ? onOpen : null,
      child: Stack(fit: StackFit.expand, children: [body, ...overlays]),
    );
  }
}

/// Square image body — fills the tile with `BoxFit.cover`. Identical
/// FutureBuilder pattern to `_ImageThumbnail` in attachment_tile.dart;
/// kept here as a separate widget so it can render at full tile size
/// (the legacy thumbnail is fixed at 40×40).
class _ImageBody extends StatefulWidget {
  final String storageKey;
  final Future<File> Function(String storageKey)? loadFile;
  final ColorScheme scheme;

  const _ImageBody({
    required this.storageKey,
    required this.loadFile,
    required this.scheme,
  });

  @override
  State<_ImageBody> createState() => _ImageBodyState();
}

class _ImageBodyState extends State<_ImageBody> {
  Future<File>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadFile?.call(widget.storageKey);
  }

  @override
  void didUpdateWidget(covariant _ImageBody old) {
    super.didUpdateWidget(old);
    if (old.storageKey != widget.storageKey ||
        old.loadFile != widget.loadFile) {
      _future = widget.loadFile?.call(widget.storageKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: widget.scheme.surfaceContainerHigh,
      child: Center(
        child: Icon(Icons.image_outlined,
            size: 48, color: widget.scheme.primary),
      ),
    );
    if (_future == null) return fallback;
    return FutureBuilder<File>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.hasError) return fallback;
        if (!snap.hasData) {
          return Container(
            color: widget.scheme.surfaceContainerHigh,
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Image.file(
          snap.data!,
          fit: BoxFit.cover,
          // 2x for retina; the actual tile size depends on column
          // count, but 360 is a comfortable upper bound for a 6-column
          // grid on a desktop window.
          cacheWidth: 360,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}

/// Document body — MIME-typed icon over the basename, on a tinted
/// surface so the tile reads as a card. Filename is the *original*
/// filename (per user requirement) with any path stripped.
class _DocumentBody extends StatelessWidget {
  final FileAttachment attachment;
  final ColorScheme scheme;

  const _DocumentBody({required this.attachment, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final raw = attachment.originalFilename;
    final filename = (raw != null && raw.isNotEmpty)
        ? p.basename(raw)
        : (attachment.title?.trim().isNotEmpty == true
            ? attachment.title!.trim()
            : 'File');

    return Container(
      color: scheme.surfaceContainer,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Icon(
                _iconForMime(attachment.mimeType),
                size: 56,
                color: scheme.primary,
              ),
            ),
          ),
          Text(
            filename,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkMediaTile extends StatelessWidget {
  final LinkAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LinkMediaTile({
    required this.attachment,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final domain = _domainOf(attachment.url);
    final userTitle = attachment.title?.trim();
    final hasUserTitle = userTitle != null && userTitle.isNotEmpty;
    final primary = hasUserTitle
        ? userTitle
        : (domain ?? attachment.url);
    // Show domain as a faded second line — but only if it isn't
    // already the primary line (avoid "example.com / example.com").
    final secondary = (hasUserTitle && domain != null) ? domain : null;

    return _TileFrame(
      onTap: onOpen,
      onEdit: onEdit,
      onDelete: onDelete,
      onOpen: onOpen,
      child: Container(
        color: scheme.surfaceContainer,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: domain == null
                      ? Icon(Icons.link, color: scheme.primary)
                      : Image.network(
                          'https://www.google.com/s2/favicons?domain=$domain&sz=64',
                          width: 32,
                          height: 32,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Icon(Icons.link, color: scheme.primary);
                          },
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.link, color: scheme.primary),
                        ),
                ),
              ),
            ),
            Text(
              primary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            if (secondary != null) ...[
              const SizedBox(height: 2),
              Text(
                secondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tile chrome: rounded clip, tap target, long-press-or-3-dot popup
/// with Open / Edit / Delete. Single source of truth so the three
/// tile types stay in lock-step.
class _TileFrame extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TileFrame({
    required this.child,
    required this.onTap,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  void _showActionMenu(BuildContext context, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<_MediaTileAction>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (onOpen != null)
          const PopupMenuItem(
            value: _MediaTileAction.open,
            child: Text('Open'),
          ),
        const PopupMenuItem(
          value: _MediaTileAction.edit,
          child: Text('Edit'),
        ),
        const PopupMenuItem(
          value: _MediaTileAction.delete,
          child: Text('Delete'),
        ),
      ],
    );
    switch (selected) {
      case _MediaTileAction.open:
        onOpen?.call();
      case _MediaTileAction.edit:
        onEdit();
      case _MediaTileAction.delete:
        onDelete();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: () {
                final box = context.findRenderObject() as RenderBox?;
                final origin = box != null
                    ? box.localToGlobal(box.size.center(Offset.zero))
                    : Offset.zero;
                _showActionMenu(context, origin);
              },
              child: child,
            ),
          ),
          // Top-right 3-dot affordance — reachable on desktop where
          // long-press doesn't fire, and discoverable on mobile.
          Positioned(
            top: 2,
            right: 2,
            child: _TileMenuButton(
              onOpen: onOpen,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _TileMenuButton extends StatelessWidget {
  final VoidCallback? onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TileMenuButton({
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MediaColors.scrim(0.35),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<_MediaTileAction>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert, size: 18, color: MediaColors.onScrim),
        padding: EdgeInsets.zero,
        iconSize: 18,
        onSelected: (action) {
          switch (action) {
            case _MediaTileAction.open:
              onOpen?.call();
            case _MediaTileAction.edit:
              onEdit();
            case _MediaTileAction.delete:
              onDelete();
          }
        },
        itemBuilder: (ctx) => [
          if (onOpen != null)
            const PopupMenuItem(
              value: _MediaTileAction.open,
              child: Text('Open'),
            ),
          const PopupMenuItem(
            value: _MediaTileAction.edit,
            child: Text('Edit'),
          ),
          const PopupMenuItem(
            value: _MediaTileAction.delete,
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}

enum _MediaTileAction { open, edit, delete }

/// Maps a MIME type to a Material icon. Wide nets — anything not
/// recognised falls through to [Icons.insert_drive_file_outlined].
/// Duplicated from attachment_tile.dart on purpose: extracting a
/// shared helper would force a third file for two callers, and the
/// table is short enough that the cost of two copies is lower than
/// the cost of the abstraction.
IconData _iconForMime(String mimeType) {
  final m = mimeType.toLowerCase();
  if (m.startsWith('image/')) return Icons.image_outlined;
  if (m.startsWith('video/')) return Icons.movie_outlined;
  if (m.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (m == 'application/pdf') return Icons.picture_as_pdf_outlined;
  if (m == 'application/msword' ||
      m ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
    return Icons.description_outlined;
  }
  if (m == 'application/vnd.ms-excel' ||
      m ==
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet') {
    return Icons.table_chart_outlined;
  }
  if (m == 'application/vnd.ms-powerpoint' ||
      m ==
          'application/vnd.openxmlformats-officedocument.presentationml.presentation') {
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

/// Best-effort domain extraction. Returns null when the URL has no
/// host (e.g. `mailto:`, malformed input); callers fall back to the
/// generic link icon.
String? _domainOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.host;
}
