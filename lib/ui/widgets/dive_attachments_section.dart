/// Section widget rendering the per-dive attachments list, the
/// reorder-by-drag affordance, and the "+ Add file" / "+ Add link"
/// entry points. Mirrors the shape of [DiveAnnotationsSection] —
/// listens to a notifier, hydrates from initState, calls notifier
/// mutators on user actions, surfaces loading/error states inline.
///
/// The section is platform-agnostic. Platform integrations (download
/// + share for files, url_launcher for links, the actual file picker)
/// are injected as callbacks so the section stays testable in pure
/// widget tests without mocking the platform channels.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models/dive_attachment.dart';
import '../../sync/attachments/attachment_uploader.dart';
import '../notifiers/dive_attachments_notifier.dart';
import '../screens/add_link_sheet.dart';
import '../screens/edit_attachment_sheet.dart';
import 'attachment_tile.dart';
import 'storage_full_dialog.dart';

class DiveAttachmentsSection extends StatefulWidget {
  final DiveAttachmentsNotifier notifier;

  /// File-picker callback — the parent screen owns the platform
  /// integration so the section can be unit-tested without touching
  /// `image_picker` / `file_picker`. Returns null if the user
  /// dismissed the picker; an empty list if every pick was filtered.
  final Future<List<PickedAttachmentFile>?> Function(BuildContext)
      pickFiles;

  /// Open callback — the parent screen wires the file branch to
  /// AttachmentDownloader + Share, and the link branch to url_launcher.
  /// The section never opens anything itself.
  final void Function(DiveAttachment attachment) onOpen;

  /// Optional thumbnail loader — image file rows render an actual
  /// 40×40 thumbnail when this is supplied. The parent screen wires
  /// it to [AttachmentDownloader.fetch]; tests omit it and the rows
  /// fall back to the MIME-typed icon.
  final Future<File> Function(String storageKey)? loadFile;

  const DiveAttachmentsSection({
    super.key,
    required this.notifier,
    required this.pickFiles,
    required this.onOpen,
    this.loadFile,
  });

  @override
  State<DiveAttachmentsSection> createState() => _DiveAttachmentsSectionState();
}

class _DiveAttachmentsSectionState extends State<DiveAttachmentsSection> {
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
    for (final p in picked) {
      // Sequential: the uploader serialises naturally and a parallel
      // burst would race the DAO's display_order computation.
      await _n.addFile(p);
      // Storage is full: the rest would be refused too, each with its
      // own dialog on top of the first.
      if (_n.storageFull != null) break;
    }
  }

  Future<void> _addLink() async {
    await showAddLinkSheet(context, notifier: _n);
  }

  Future<void> _delete(DiveAttachment a) async {
    final messenger = ScaffoldMessenger.of(context);
    await _n.softDelete(a.id);
    if (!mounted) return;
    // Floating + bottom margin so the UNDO toast doesn't cover the
    // "Add file" / "Add link" buttons that sit at the section's foot.
    // The close-icon gives the user a manual dismiss in case the 5s
    // auto-timeout feels too long, especially when they've already
    // navigated back and the toast is hanging around at the root.
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
    await showEditAttachmentSheet(
      context,
      notifier: _n,
      attachment: a,
    );
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
                'ATTACHMENTS',
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
          const SizedBox(height: 8),
          if (attachments.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: attachments.length,
              onReorderItem: _n.reorder,
              itemBuilder: (context, index) {
                final a = attachments[index];
                final dragHandle = ReorderableDragStartListener(
                  key: ValueKey('drag-${a.id}'),
                  index: index,
                  child: Icon(
                    Icons.drag_handle,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                );
                return Padding(
                  key: ValueKey(a.id),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: AttachmentTile(
                    attachment: a,
                    dragHandle: dragHandle,
                    onOpen: () => widget.onOpen(a),
                    onEdit: () => _edit(a),
                    onDelete: () => _delete(a),
                    onRetry: a is FileAttachment &&
                            a.uploadState == UploadState.failed
                        ? () => _retry(a)
                        : null,
                    storageFull: _n.isStorageFull(a.id),
                    loadFile: widget.loadFile,
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
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
