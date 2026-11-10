import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.onDeleteAccount,
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

  /// Null hides the Delete account row.
  final VoidCallback? onDeleteAccount;

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
                    ? Column(
                        children: [
                          _SignedInRow(
                            authService: auth,
                            syncStatusSource: syncStatusSource,
                          ),
                          if (onDeleteAccount != null)
                            SettingRow(
                              key: const ValueKey('settings-account-delete'),
                              title: 'Delete account',
                              helper: 'Deletes your account and all its data',
                              danger: true,
                              onTap: onDeleteAccount,
                            ),
                        ],
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
  final _codeCtrl = TextEditingController();
  final _codeFocus = FocusNode();
  bool _busy = false;
  String? _error;

  /// Set while the sheet asks for the code from the "Confirm signup" email.
  String? _pendingEmail;

  /// A non-error note on the code step, such as "New code sent".
  String? _info;

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
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<AuthResult> Function() op) async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are both required');
      return;
    }
    await _submit(op);
  }

  Future<void> _verify() async {
    final email = _pendingEmail!;
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the code from the email');
      return;
    }
    await _submit(() => widget.authService.verifyEmailCode(
          email: email,
          code: code,
          password: _passwordCtrl.text,
        ));
  }

  Future<void> _resend() async {
    final email = _pendingEmail!;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final err = await widget.authService.resendEmailCode(email: email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) {
        _info = 'New code sent to $email.';
      } else {
        _error = err;
      }
    });
  }

  void _backToForm() => setState(() {
        _pendingEmail = null;
        _error = null;
        _info = null;
      });

  Future<void> _submit(Future<AuthResult> Function() op) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
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
      case AuthEmailConfirmationRequired(:final email):
        _codeCtrl.clear();
        setState(() => _pendingEmail = email);
        // Same macOS dialog focus workaround as the email field.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _codeFocus.requestFocus();
        });
      case AuthFailure(:final message):
        setState(() => _error = message);
        // The disabled field lost focus while busy; put the cursor back so
        // a mistyped code can be fixed straight away.
        if (_pendingEmail != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _codeFocus.requestFocus();
          });
        }
    }
  }

  Widget? _messages(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_error != null) {
      return Text(_error!, style: TextStyle(color: scheme.error));
    }
    if (_info != null) return Text(_info!);
    return null;
  }

  Widget _busyOr(String label) => _busy
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(label);

  Widget _buildCodeStep(BuildContext context, String email) {
    final messages = _messages(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Confirm your email',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Text('Enter the code from the newest email we sent to $email. '
              'No email after a few minutes? Check your spam folder, or '
              'press Resend code.'),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('auth-code-field'),
            controller: _codeCtrl,
            focusNode: _codeFocus,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Code'),
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_busy) _verify();
            },
          ),
          if (messages != null) ...[
            const SizedBox(height: 8),
            messages,
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _resend,
                  child: const Text('Resend code'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: _busyOr('Verify'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _backToForm,
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingEmail;
    if (pending != null) return _buildCodeStep(context, pending);
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
                  child: _busyOr('Sign in'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
