import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db/dive_dao.dart';
import '../../../sync/cloud/auth_service.dart';
import '../../../sync/cloud/sync_status_source.dart';
import '../../../sync/subsurface_git/bootstrap_importer.dart';
import '../../../sync/subsurface_git/credentials.dart';
import '../../../sync/subsurface_git/sync_orchestrator.dart';
import '../../components/setting_row.dart';
import '../../widgets/subsurface_sync_section.dart';

/// Sync: your account, Subsurface Cloud, and the repair tools.
///
/// The repair actions (and their confirm dialogs and result sheets) live with
/// the screen, which owns the databases they work on; this tab only lists
/// them. [onReset] is null when there is no local database to reset, and the
/// row is then not shown.
class SyncTab extends StatelessWidget {
  const SyncTab({
    super.key,
    this.authService,
    this.syncStatusSource,
    this.subsurfaceOrchestrator,
    this.subsurfaceCredentials,
    this.diveDao,
    this.subsurfaceBootstrapImporter,
    required this.onReassign,
    required this.onPushStuck,
    this.onReset,
  });

  final AuthService? authService;
  final SyncStatusSource? syncStatusSource;
  final SubsurfaceSyncOrchestrator? subsurfaceOrchestrator;
  final SubsurfaceCredentialsSource? subsurfaceCredentials;
  final DiveDao? diveDao;
  final SubsurfaceBootstrapImporter? subsurfaceBootstrapImporter;
  final VoidCallback onReassign;
  final VoidCallback onPushStuck;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final auth = authService;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (auth != null)
          SettingsGroup(
            title: 'Anchorline account',
            children: [
              ListenableBuilder(
                listenable: auth,
                builder: (_, _) => auth.isSignedIn
                    ? _SignedInRow(
                        authService: auth,
                        syncStatusSource: syncStatusSource,
                      )
                    : _SignInRow(authService: auth),
              ),
            ],
          ),
        if (subsurfaceOrchestrator != null &&
            subsurfaceCredentials != null &&
            diveDao != null)
          SettingsGroup(
            title: 'Subsurface Cloud',
            children: [
              SubsurfaceSyncSection(
                showHeading: false,
                credentials: subsurfaceCredentials!,
                isPlatformSupported: subsurfaceOrchestrator!.isPlatformSupported,
                onSync: subsurfaceOrchestrator!.syncNow,
                lastSyncedAt: diveDao!.lastSubsurfaceUploadedAt,
                onBootstrapImport: subsurfaceBootstrapImporter == null
                    ? null
                    : () => subsurfaceBootstrapImporter!.import(),
              ),
            ],
          ),
        SettingsGroup(
          title: 'Repair',
          children: [
            SettingRow(
              key: const ValueKey('settings-repair-reassign'),
              title: 'Re-assign dives to this account',
              helper: 'For dives imported while signed out or under another account',
              onTap: onReassign,
            ),
            SettingRow(
              key: const ValueKey('settings-repair-push'),
              title: 'Push stuck uploads',
              helper: 'When "Syncing…" never finishes',
              onTap: onPushStuck,
            ),
            if (onReset != null)
              SettingRow(
                key: const ValueKey('settings-repair-reset'),
                title: 'Reset local data',
                helper: 'Wipes this device; cloud data stays and syncs back',
                danger: true,
                onTap: onReset,
              ),
          ],
        ),
      ],
    );
  }
}

class _SignInRow extends StatelessWidget {
  final AuthService authService;
  const _SignInRow({required this.authService});

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: 'Sign in to enable cloud sync',
      helper: 'Optional. The app works fully offline.',
      onTap: () => _openAuthSheet(context, authService),
    );
  }
}

class _SignedInRow extends StatelessWidget {
  final AuthService authService;
  final SyncStatusSource? syncStatusSource;
  const _SignedInRow({
    required this.authService,
    this.syncStatusSource,
  });

  @override
  Widget build(BuildContext context) {
    final email = authService.currentUser?.email ?? '(unknown)';
    final source = syncStatusSource;
    Widget row(String status) => SettingRow(
          title: email,
          helper: status,
          control: TextButton(
            onPressed: () => _confirmSignOut(context, authService),
            child: const Text('Sign out'),
          ),
        );
    if (source == null) return row('Last synced: never');
    return StreamBuilder<SyncStatusSnapshot>(
      stream: source.statusStream,
      initialData: source.currentStatus,
      builder: (_, snapshot) =>
          row(_formatSyncStatus(snapshot.data ?? source.currentStatus)),
    );
  }
}

String _formatSyncStatus(SyncStatusSnapshot s) {
  final state = _statusLabel(s);
  final last = s.lastSyncedAt;
  if (last == null) return state;
  return '$state  Last synced: ${_relativeTime(last, DateTime.now())}';
}

String _statusLabel(SyncStatusSnapshot s) {
  if (!s.connected) return '🔴 Offline';
  if (s.uploading || s.downloading) return '🟡 Syncing…';
  return '🟢 Synced';
}

/// Compact relative-time formatting suitable for a status row. Falls back
/// to an absolute date once we cross a day boundary.
String _relativeTime(DateTime when, DateTime now) {
  final diff = now.difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds} sec ago';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m min ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  return DateFormat.yMd().add_Hm().format(when);
}

Future<void> _openAuthSheet(BuildContext context, AuthService auth) {
  // Dialog (rather than modal bottom sheet) avoids a macOS Flutter focus
  // quirk that prevents text-field keyboard input inside a bottom sheet.
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: _AuthSheet(authService: auth),
      ),
    ),
  );
}

Future<void> _confirmSignOut(BuildContext context, AuthService auth) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
          'Your local dives stay on the device. Cloud sync will pause until you sign in again.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await auth.signOut();
  messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
}

class _AuthSheet extends StatefulWidget {
  final AuthService authService;
  const _AuthSheet({required this.authService});

  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // macOS Flutter has a known race where TextFields inside dialogs
    // don't establish keyboard focus on first paint. Forcing it after
    // the frame settles is the standard workaround.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthResult> Function() op) async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are both required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final res = await op();
    if (!mounted) return;
    setState(() => _busy = false);
    switch (res) {
      case AuthSuccess(:final user):
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Signed in as ${user.email ?? user.id}')),
        );
      case AuthEmailConfirmationRequired():
        messenger.showSnackBar(
          const SnackBar(content: Text('Check your inbox to confirm your email')),
        );
      case AuthFailure(:final message):
        setState(() => _error = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Cloud sync sign-in',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordCtrl,
            focusNode: _passwordFocus,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: 'Password'),
            enabled: !_busy,
            textInputAction: TextInputAction.done,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.authService.signUp(
                            email: _emailCtrl.text.trim(),
                            password: _passwordCtrl.text,
                          )),
                  child: const Text('Create account'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.authService.signIn(
                            email: _emailCtrl.text.trim(),
                            password: _passwordCtrl.text,
                          )),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign in'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
