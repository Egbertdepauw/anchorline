/// The dialog for an upload the Worker refused because the account's
/// attachment storage is full (issue #196).
library;

import 'package:flutter/material.dart';

import '../format/attachment_usage_format.dart';
import '../notifiers/dive_attachments_notifier.dart';

/// Shown in the attachments error banner while the Worker has uploads
/// switched off.
const kUploadsPausedMessage =
    'Uploads are paused right now. Your existing attachments are fine.';

/// What the user chose in the storage-full dialog.
enum StorageFullChoice { freeSpace, ok }

/// Shows the storage-full dialog for [state]. "Free space now" is only
/// offered when [StorageFullState.canFreeSpace]; dismissing the dialog
/// counts as [StorageFullChoice.ok].
Future<StorageFullChoice> showStorageFullDialog(
  BuildContext context, {
  required StorageFullState state,
}) async {
  final choice = await showDialog<StorageFullChoice>(
    context: context,
    builder: (_) => _StorageFullDialog(state: state),
  );
  return choice ?? StorageFullChoice.ok;
}

class _StorageFullDialog extends StatelessWidget {
  const _StorageFullDialog({required this.state});

  final StorageFullState state;

  @override
  Widget build(BuildContext context) {
    final u = state.usage;
    // The files of a multi-file add after the refused one.
    final more = switch (state.remainingFiles) {
      <= 0 => '',
      1 => " 1 more file wasn't added.",
      final n => " ${formatCount(n)} more files weren't added.",
    };
    return AlertDialog(
      title: const Text('Attachment storage full'),
      content: Text(
        '${formatGb(u.usedBytes)} of ${formatGb(u.limitBytes)} used '
        '(${formatCount(u.usedFiles)} of ${formatCount(u.limitFiles)} files). '
        'This file needs ${formatMb(state.fileSizeBytes)}. '
        'Delete attachments you no longer need to make room.$more',
      ),
      actions: [
        if (state.canFreeSpace)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(StorageFullChoice.freeSpace),
            child: const Text('Free space now'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(StorageFullChoice.ok),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
