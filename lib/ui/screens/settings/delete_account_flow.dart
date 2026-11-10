import 'package:flutter/material.dart';

import '../../../sync/cloud/account_deleter.dart';

/// The in-app "Delete account" flow (spec 2026-11-08, section 7):
/// type-to-confirm dialog, a non-dismissible progress dialog, then a result
/// dialog.
///
/// Nothing is deleted unless the user confirms. The dialogs are shown on the
/// root navigator, captured before the first await, because the flow signs
/// the user out part-way through; that rebuilds the Sync tab and unmounts the
/// row that started it, but the success dialog must still appear.
Future<void> runDeleteAccountFlow(
  BuildContext context,
  AccountDeleter deleter,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  // The navigator's own context outlives the settings screen.
  final dialogContext = navigator.context;

  final confirmed = await showDialog<bool>(
    context: dialogContext,
    builder: (_) => const _ConfirmDeleteDialog(),
  );
  if (confirmed != true) return;

  final progress = ValueNotifier<AccountDeletionProgress>(
    const AccountDeletionProgress(AccountDeletionStep.checking),
  );
  // Not awaited: it completes when the dialog is popped below.
  showDialog<void>(
    // ignore: use_build_context_synchronously
    context: dialogContext,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(progress: progress),
  );

  final AccountDeletionResult result;
  try {
    result = await deleter.deleteAccount(onProgress: (p) => progress.value = p);
  } finally {
    navigator.pop();
    progress.dispose();
  }

  if (!navigator.mounted) return;
  await showDialog<void>(
    // ignore: use_build_context_synchronously
    context: dialogContext,
    builder: (_) => _ResultDialog(result: result),
  );
}

class _ConfirmDeleteDialog extends StatefulWidget {
  const _ConfirmDeleteDialog();

  @override
  State<_ConfirmDeleteDialog> createState() => _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends State<_ConfirmDeleteDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // macOS Flutter has a known race where TextFields inside dialogs
    // don't establish keyboard focus on first paint. Forcing it after
    // the frame settles is the standard workaround.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _matches => _ctrl.text.trim().toLowerCase() == 'delete';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your Anchorline account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes:\n'
              '• your account and sign-in\n'
              '• every dive, note, equipment item and gas analysis in '
              'the cloud\n'
              '• all attachment files\n'
              '• the dives and data on this device\n'
              '\n'
              'Other devices signed in to this account are signed out '
              'within about an hour. Dives in Subsurface Cloud and on your '
              'dive computer are not affected.\n'
              '\n'
              "This can't be undone. Type DELETE to confirm.",
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Type DELETE'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress});

  final ValueNotifier<AccountDeletionProgress> progress;

  static String _label(AccountDeletionProgress p) => switch (p.step) {
        AccountDeletionStep.checking => 'Checking your connection',
        AccountDeletionStep.removingAttachments => p.total == 0
            ? 'Removing attachment files'
            : 'Removing attachment files (${p.done} of ${p.total})',
        AccountDeletionStep.deletingAccount => 'Deleting your account',
        AccountDeletionStep.clearingDevice => 'Clearing this device',
      };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Deleting your account…'),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<AccountDeletionProgress>(
                valueListenable: progress,
                builder: (_, p, _) => Text(_label(p)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.result});

  final AccountDeletionResult result;

  @override
  Widget build(BuildContext context) {
    final (title, body) = switch (result) {
      AccountDeleted() => (
          'Account deleted',
          'Your Anchorline account and its data have been deleted. Quit and '
              'reopen Anchorline to finish clearing this device.',
        ),
      AccountDeletionFailed(
        stage: AccountDeletionStage.offline,
      ) =>
        (
          'Could not delete account',
          'You need an internet connection to delete your account. Nothing '
              'was deleted.',
        ),
      AccountDeletionFailed(
        stage: AccountDeletionStage.sessionEnded,
      ) =>
        (
          'Could not delete account',
          'Your sign-in has ended, so nothing was deleted. Sign in again, '
              'then try again.',
        ),
      AccountDeletionFailed(
        stage: AccountDeletionStage.attachments,
        failedAttachments: final n,
      ) =>
        (
          'Could not delete account',
          n == 0
              ? 'Your account was not deleted. The list of attachment files '
                  'could not be read. Check your connection and try again.'
              : 'Your account was not deleted. $n attachment '
                  '${n == 1 ? 'file' : 'files'} could not be removed. Check '
                  'your connection and try again.',
        ),
      AccountDeletionFailed(
        stage: AccountDeletionStage.account,
        message: final m,
      ) =>
        (
          'Could not delete account',
          'Your account was not deleted. Attachment files were already '
              'removed. Try again later.\n\n$m',
        ),
      AccountDeletionFailed(stage: AccountDeletionStage.localWipe) => (
          'Account deleted',
          'Your account was deleted, but clearing this device failed. Use '
              'Reset local data in Settings → Sync.',
        ),
    };
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
