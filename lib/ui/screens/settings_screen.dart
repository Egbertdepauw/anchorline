import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:powersync/powersync.dart' hide SyncStatus, Column;

import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../../dev/fixture_seeder.dart';
import '../../sync/attachments/attachment_object_wiper.dart';
import '../../sync/cloud/auth_service.dart';
import '../../sync/cloud/cloud_data_wiper.dart';
import '../../sync/cloud/sync_status_source.dart';
import '../../sync/subsurface_git/bootstrap_importer.dart';
import '../../sync/subsurface_git/credentials.dart';
import '../../sync/subsurface_git/sync_orchestrator.dart';
import '../dev/widgetbook_screen.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/background_watermark.dart';
import '../widgets/subsurface_sync_section.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsNotifier notifier;
  final AuthService? authService;
  final SyncStatusSource? syncStatusSource;
  /// Optional — when both are provided, the Danger zone "Reset local data"
  /// tile is rendered. Tests typically omit them.
  final AppDatabase? db;
  final PowerSyncDatabase? powerSyncDb;
  /// Optional — wires the "also delete cloud data" checkbox in the reset
  /// dialog. Without it the checkbox is hidden and reset stays local-only.
  final CloudDataWiper? cloudDataWiper;

  /// Optional — when present, the Reset-Everything path also sweeps R2
  /// objects so the user's storage bill doesn't carry orphans after the
  /// cloud rows are gone. Best-effort; failures are logged.
  final AttachmentObjectWiper? attachmentObjectWiper;

  /// Optional — when all three of [subsurfaceOrchestrator],
  /// [subsurfaceCredentials], and [diveDao] are non-null, the
  /// "Subsurface sync" card is rendered. Tests omit them and the section
  /// is hidden, so existing settings-screen tests stay unchanged.
  final SubsurfaceSyncOrchestrator? subsurfaceOrchestrator;
  final SubsurfaceCredentialsSource? subsurfaceCredentials;
  final DiveDao? diveDao;

  /// Optional — when present (and the rest of the Subsurface trio is
  /// also wired), the section renders a second "Import from Subsurface"
  /// button that triggers a one-shot bootstrap import. The shell
  /// instantiates this alongside the orchestrator at app boot.
  final SubsurfaceBootstrapImporter? subsurfaceBootstrapImporter;

  const SettingsScreen({
    super.key,
    required this.notifier,
    this.authService,
    this.syncStatusSource,
    this.db,
    this.powerSyncDb,
    this.cloudDataWiper,
    this.attachmentObjectWiper,
    this.subsurfaceOrchestrator,
    this.subsurfaceCredentials,
    this.diveDao,
    this.subsurfaceBootstrapImporter,
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
      body: ListenableBuilder(
        listenable: widget.notifier,
        builder: (context, _) {
          return BackgroundWatermark(
            opacity: widget.notifier.watermarkOpacity,
            child: ListView(
              children: [
          if (auth != null)
            ListenableBuilder(
              listenable: auth,
              builder: (_, _) => _AccountSection(
                authService: auth,
                syncStatusSource: widget.syncStatusSource,
              ),
            ),
          SwitchListTile(
            title: const Text('Use speed coloured graph'),
            subtitle: const Text(
                'Colour the depth trace by vertical speed (red above 9 m/min)'),
            value: widget.notifier.useSpeedColoredGraph,
            onChanged: (v) => widget.notifier.setUseSpeedColoredGraph(v),
          ),
          ListenableBuilder(
            listenable: widget.notifier,
            builder: (context, _) {
              return SwitchListTile(
                title: const Text('Count O₂ as narcotic in END'),
                subtitle: const Text(
                    'On: N₂ + O₂ both count (TDI/IANTD/US-Navy). Off: only N₂ counts (GUE/DIR).'),
                value: widget.notifier.endCountsOxygen,
                onChanged: (v) => widget.notifier.setEndCountsOxygen(v),
              );
            },
          ),
          ListenableBuilder(
            listenable: widget.notifier,
            builder: (context, _) {
              final value = widget.notifier.watermarkOpacity;
              return ListTile(
                title: const Text('Watermark opacity'),
                subtitle: Text(value == 0
                    ? 'Hidden'
                    : '${(value * 100).toStringAsFixed(0)}%'),
                trailing: SizedBox(
                  width: 180,
                  child: Slider(
                    value: value,
                    min: 0,
                    max: 0.20,
                    divisions: 20,
                    onChanged: (v) => widget.notifier.setWatermarkOpacity(v),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Bailout planning',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            title: const Text('Bailout SAC — bottom phase'),
            subtitle: Text(
                '${widget.notifier.bailoutSacBottom} L/min — used until ascent slows at first switch or half-pressure'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutSacBottom.toDouble(),
                min: 10,
                max: 60,
                divisions: 50,
                onChanged: (v) =>
                    widget.notifier.setBailoutSacBottom(v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Bailout SAC — deco phase'),
            subtitle: Text(
                '${widget.notifier.bailoutSacDeco} L/min — used from first deco stop to surface'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutSacDeco.toDouble(),
                min: 10,
                max: 60,
                divisions: 50,
                onChanged: (v) =>
                    widget.notifier.setBailoutSacDeco(v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Ascent rate — fast (bottom to first stop)'),
            subtitle: Text(
                '${widget.notifier.bailoutAscentRateFast} m/min — used from depth to first deco stop'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutAscentRateFast.toDouble(),
                min: 3,
                max: 30,
                divisions: 27,
                onChanged: (v) =>
                    widget.notifier.setBailoutAscentRateFast(v.round()),
              ),
            ),
          ),
          ListTile(
            title: const Text('Ascent rate — slow (deco stops)'),
            subtitle: Text(
                '${widget.notifier.bailoutAscentRateSlow} m/min — used between deco stops and to the surface'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: widget.notifier.bailoutAscentRateSlow.toDouble(),
                min: 3,
                max: 30,
                divisions: 27,
                onChanged: (v) =>
                    widget.notifier.setBailoutAscentRateSlow(v.round()),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Diluent is bailout-capable (GUE / D7 config)'),
            subtitle: const Text(
                'Off: assumes 2–3 L diluent, recommends a bottom-mix BO cylinder. '
                'On: assumes diluent is sized for OC bailout.'),
            value: widget.notifier.gueDiluentConfig,
            onChanged: (v) => widget.notifier.setGueDiluentConfig(v),
          ),
          SwitchListTile(
            title: const Text('6.8 L / 300 bar stage available'),
            subtitle: const Text(
                'Include a 6.8 L 300 bar stage when computing bailout gas volumes.'),
            value: widget.notifier.tank68L300Available,
            onChanged: (v) => widget.notifier.setTank68L300Available(v),
          ),
          SwitchListTile(
            title: const Text('12 L / 300 bar stage available'),
            subtitle: const Text(
                'Include a 12 L 300 bar stage when computing bailout gas volumes.'),
            value: widget.notifier.tank12L300Available,
            onChanged: (v) => widget.notifier.setTank12L300Available(v),
          ),
          if (widget.subsurfaceOrchestrator != null &&
              widget.subsurfaceCredentials != null &&
              widget.diveDao != null) ...[
            const Divider(height: 32),
            SubsurfaceSyncSection(
              credentials: widget.subsurfaceCredentials!,
              isPlatformSupported:
                  widget.subsurfaceOrchestrator!.isPlatformSupported,
              onSync: widget.subsurfaceOrchestrator!.syncNow,
              lastSyncedAt: widget.diveDao!.lastSubsurfaceUploadedAt,
              onBootstrapImport: widget.subsurfaceBootstrapImporter == null
                  ? null
                  : () => widget.subsurfaceBootstrapImporter!.import(),
            ),
          ],
          if (widget.db != null && widget.powerSyncDb != null) ...[
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Danger zone',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Reset local data'),
              subtitle: const Text(
                  'Wipes imported dives + local sync state. Cloud data is unaffected; if signed in, it re-syncs after restart.'),
              onTap: _confirmAndResetLocalData,
            ),
          ],
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: GestureDetector(
              onLongPress: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const WidgetbookScreen()),
              ),
              child: Text(
                'CCRLog',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmAndResetLocalData() async {
    final db = widget.db;
    final psDb = widget.powerSyncDb;
    if (db == null || psDb == null) return;

    final wiper = widget.cloudDataWiper;
    final canWipeCloud =
        wiper != null && (widget.authService?.isSignedIn ?? false);

    var alsoWipeCloud = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Reset data?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deletes every imported dive on this device and clears the '
                'local PowerSync cache.\n\n'
                'You will need to quit and reopen the app afterwards.',
              ),
              if (canWipeCloud) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: alsoWipeCloud,
                  onChanged: (v) =>
                      setLocal(() => alsoWipeCloud = v ?? false),
                  title: const Text('Also delete cloud data'),
                  subtitle: const Text(
                      'Permanent. Wipes annotations, cylinders, cells, '
                      'scrubbers, dive computers and pressure mappings '
                      'from your account on every device.'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.errorContainer,
                foregroundColor: Theme.of(ctx).colorScheme.onErrorContainer,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(alsoWipeCloud ? 'Reset everything' : 'Reset'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // R2 objects first — once `wiper.wipeAllForCurrentUser()` deletes
      // the dive_attachments rows in Postgres, PowerSync replicates
      // those deletes down and the local cache loses the storage_keys
      // we'd need to delete the objects.
      if (alsoWipeCloud) {
        await widget.attachmentObjectWiper?.wipeAllForCurrentUser();
      }
      // Cloud rows next so logical-replication deletes propagate to
      // other devices before this device cuts itself off from sync.
      if (alsoWipeCloud && wiper != null) {
        await wiper.wipeAllForCurrentUser();
      }
      // Drift: clear all imported-dive related rows. Equipment / annotation
      // tables in Drift are no longer used (PowerSync owns them), but
      // we still wipe them to keep the local file fully fresh.
      await db.transaction(() async {
        await db.customStatement('DELETE FROM dive_samples');
        await db.customStatement('DELETE FROM dives');
        await db.customStatement('DELETE FROM import_states');
        await db.customStatement('DELETE FROM dive_annotations');
        await db.customStatement('DELETE FROM dive_computers');
        await db.customStatement('DELETE FROM oxygen_cells');
        await db.customStatement('DELETE FROM scrubber_sessions');
        await db.customStatement('DELETE FROM cylinders');
        await db.customStatement('DELETE FROM pressure_mappings');
        await db.customStatement('DELETE FROM dive_cylinders');
      });
      // PowerSync: disconnect + clear local SQLite. Re-sync on next start.
      //
      // `disconnectAndClear()` is supposed to remove every `ps_data__*`
      // row but has been observed leaving rows behind (2026-05-10
      // incident: 13 dives survived a Reset Everything). We follow it
      // with an explicit DELETE of every PowerSync-managed local table
      // as a fallback, so a fresh bootstrap-import sees an empty DB and
      // re-parses everything with the current mapper instead of
      // dedup-skipping stale rows. Wrapping in try/catch because the
      // table list isn't part of any contract — if PowerSync renames
      // its local tables in a future SDK rev, the explicit DELETE
      // becomes a no-op rather than blocking the reset.
      await psDb.disconnectAndClear();
      try {
        const psTables = [
          'ps_data__dives',
          'ps_data__dive_samples',
          'ps_data__dive_annotations',
          'ps_data__dive_attachments',
          'ps_data__dive_computers',
          'ps_data__dive_cylinders',
          'ps_data__cylinders',
          'ps_data__oxygen_cells',
          'ps_data__pressure_mappings',
          'ps_data__scrubber_sessions',
          'ps_crud',
          'ps_oplog',
          'ps_buckets',
        ];
        for (final t in psTables) {
          await psDb.execute('DELETE FROM $t');
        }
      } catch (e) {
        debugPrint('Belt-and-braces PowerSync wipe partial: $e');
      }
      // Stop fixture re-seeding from re-populating the empty DB on next
      // launch. Reinstalling the app clears this flag.
      await markFixturesBlocked();
    } catch (e, st) {
      debugPrint('Reset data failed: $e\n$st');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Reset failed: $e')));
      return;
    }
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(alsoWipeCloud
          ? 'Local + cloud data cleared. Please quit and reopen the app.'
          : 'Local data cleared. Please quit and reopen the app.'),
      duration: const Duration(seconds: 8),
    ));
  }
}

class _AccountSection extends StatelessWidget {
  final AuthService authService;
  final SyncStatusSource? syncStatusSource;
  const _AccountSection({
    required this.authService,
    this.syncStatusSource,
  });

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
                ? _SignedInTile(
                    authService: authService,
                    syncStatusSource: syncStatusSource,
                  )
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
  final SyncStatusSource? syncStatusSource;
  const _SignedInTile({
    required this.authService,
    this.syncStatusSource,
  });

  @override
  Widget build(BuildContext context) {
    final email = authService.currentUser?.email ?? '(unknown)';
    final source = syncStatusSource;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_done_outlined),
          title: Text(email),
          subtitle: source == null
              ? const Text('Last synced: never')
              : _SyncStatusRow(source: source),
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

class _SyncStatusRow extends StatelessWidget {
  final SyncStatusSource source;
  const _SyncStatusRow({required this.source});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatusSnapshot>(
      stream: source.statusStream,
      initialData: source.currentStatus,
      builder: (_, snapshot) {
        final s = snapshot.data ?? source.currentStatus;
        return Text(_formatSyncStatus(s));
      },
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
