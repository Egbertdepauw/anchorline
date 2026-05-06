import 'package:flutter/material.dart';

import '../../sync/cloud/auth_service.dart';
import '../notifiers/settings_notifier.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsNotifier notifier;
  final AuthService? authService;

  const SettingsScreen({
    super.key,
    required this.notifier,
    this.authService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final auth = widget.authService;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (auth != null)
            ListenableBuilder(
              listenable: auth,
              builder: (_, _) => _AccountSection(authService: auth),
            ),
          SwitchListTile(
            title: const Text('Use speed coloured graph'),
            subtitle: const Text(
                'Colour the depth trace by vertical speed (red above 9 m/min)'),
            value: widget.notifier.useSpeedColoredGraph,
            onChanged: (v) => widget.notifier.setUseSpeedColoredGraph(v),
          ),
        ],
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  final AuthService authService;
  const _AccountSection({required this.authService});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Account', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: authService.isSignedIn
                ? _SignedInTile(authService: authService)
                : _SignInTile(authService: authService),
          ),
        ],
      ),
    );
  }
}

class _SignInTile extends StatelessWidget {
  final AuthService authService;
  const _SignInTile({required this.authService});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: const Text('Sign in to enable cloud sync'),
      subtitle: const Text('Optional. The app works fully offline.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openAuthSheet(context, authService),
    );
  }
}

class _SignedInTile extends StatelessWidget {
  final AuthService authService;
  const _SignedInTile({required this.authService});

  @override
  Widget build(BuildContext context) {
    final email = authService.currentUser?.email ?? '(unknown)';
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text(email),
          subtitle: const Text('Last synced: never'),
        ),
        const Divider(height: 0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              onPressed: () => _confirmSignOut(context, authService),
            ),
          ),
        ),
      ],
    );
  }
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
