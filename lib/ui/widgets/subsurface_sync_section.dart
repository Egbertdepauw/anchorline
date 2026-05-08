/// Settings card for the Subsurface Cloud git-sync feature (Phase E).
///
/// Renders:
///   - email + password text fields backed by [SubsurfaceCredentialsSource]
///   - "Save credentials" button
///   - "Sync now" button (hidden on iOS where in-process git is unavailable)
///   - status row with the most recent `subsurface_uploaded_at` formatted
///     as a relative time
///
/// Decoupled from [SubsurfaceSyncOrchestrator] for test ergonomics: the
/// section accepts an [onSync] callback that runs one sync attempt, plus
/// a flag for `isPlatformSupported`. Production (settings_screen.dart)
/// wires `onSync = orchestrator.syncNow`; tests pass a stub that returns
/// a fabricated [SubsurfaceSyncResult] or throws a typed exception.
///
/// Field hydration: on first build the section calls
/// [SubsurfaceCredentialsSource.read] and, if creds exist, populates
/// both fields directly. We could mask the loaded password with a
/// "•••• (saved)" hint instead, but that complicates round-tripping
/// (saving without re-typing the password requires special-casing).
/// Direct hydration matches the rest of the app's auth UI and the OS
/// keychain is the actual confidentiality boundary anyway — the field
/// is `obscureText: true` so it doesn't render visibly.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../sync/subsurface_git/bootstrap_importer.dart';
import '../../sync/subsurface_git/credentials.dart';
import '../../sync/subsurface_git/sync_orchestrator.dart';

/// Public type alias for the sync callback the section invokes when the
/// user taps "Sync now". Returning a [SubsurfaceSyncResult] is what
/// drives the post-sync SnackBar.
typedef SubsurfaceSyncRunner = Future<SubsurfaceSyncResult> Function();

/// Closure that returns the latest `subsurface_uploaded_at` epoch
/// seconds across all dives, or null if nothing's been synced yet.
typedef LastSyncedAtReader = Future<int?> Function();

/// Public type alias for the bootstrap-import callback. Returning the
/// stream lazily means the parent constructs the importer call on tap
/// (the Settings UI doesn't import [SubsurfaceBootstrapImporter] itself
/// — only the type alias and event types it needs to render progress).
typedef SubsurfaceBootstrapRunner = Stream<SubsurfaceBootstrapEvent>
    Function();

class SubsurfaceSyncSection extends StatefulWidget {
  const SubsurfaceSyncSection({
    super.key,
    required this.credentials,
    required this.onSync,
    required this.isPlatformSupported,
    required this.lastSyncedAt,
    this.onBootstrapImport,
    this.now,
  });

  /// Credentials store. Read on first build, written on "Save".
  final SubsurfaceCredentialsSource credentials;

  /// Runs one Subsurface sync. Should call into
  /// [SubsurfaceSyncOrchestrator.syncNow] in production, a stub in tests.
  final SubsurfaceSyncRunner onSync;

  /// Mirrors [SubsurfaceSyncOrchestrator.isPlatformSupported]. False on
  /// iOS — the section then renders a "use desktop" explainer and hides
  /// the Sync button. The save form stays visible so users can pre-enter
  /// their creds for the desktop session (creds don't sync between
  /// devices — flutter_secure_storage is per-device).
  final bool isPlatformSupported;

  /// Returns the most-recent `subsurface_uploaded_at` epoch-seconds
  /// timestamp. Re-read on every sync attempt so the status row stays
  /// fresh after a successful push.
  final LastSyncedAtReader lastSyncedAt;

  /// Optional read-direction "Import from Subsurface" callback. When
  /// non-null the section renders a separate button that triggers a
  /// one-shot bootstrap import. The parent (settings_screen.dart) wires
  /// this to [SubsurfaceBootstrapImporter.import]. When null the
  /// button is hidden — keeps existing tests / call sites unchanged.
  final SubsurfaceBootstrapRunner? onBootstrapImport;

  /// Override the "now" used for relative-time formatting. Tests pass a
  /// fixed value so the rendered string is deterministic.
  final DateTime Function()? now;

  @override
  State<SubsurfaceSyncSection> createState() => _SubsurfaceSyncSectionState();
}

class _SubsurfaceSyncSectionState extends State<SubsurfaceSyncSection> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;
  bool _busy = false;
  bool _credsLoaded = false;
  // Trackers for the "Save" button enable-state. Updated whenever the
  // controllers change so we can compare against the last-saved values.
  String _savedEmail = '';
  String _savedPassword = '';
  // Cached "last synced" timestamp; null = "Never". Refreshed in
  // [_refreshLastSynced] after sync attempts.
  int? _lastSyncedSeconds;

  // Bootstrap-import progress state. While `_bootstrapStatus` is non-
  // null we render a status block under the buttons and disable both
  // Sync + Import buttons so the user can't pile up overlapping
  // operations.
  String? _bootstrapStatus;
  StreamSubscription<SubsurfaceBootstrapEvent>? _bootstrapSub;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_onFieldChanged);
    _passwordCtrl.addListener(_onFieldChanged);
    _hydrate();
  }

  Future<void> _hydrate() async {
    final stored = await widget.credentials.read();
    if (!mounted) return;
    if (stored != null) {
      _emailCtrl.text = stored.email;
      _passwordCtrl.text = stored.password;
      _savedEmail = stored.email;
      _savedPassword = stored.password;
    }
    final last = await widget.lastSyncedAt();
    if (!mounted) return;
    setState(() {
      _credsLoaded = true;
      _lastSyncedSeconds = last;
    });
  }

  Future<void> _refreshLastSynced() async {
    final last = await widget.lastSyncedAt();
    if (!mounted) return;
    setState(() {
      _lastSyncedSeconds = last;
    });
  }

  @override
  void dispose() {
    _bootstrapSub?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    // setState only — we're computing button-enabled state from
    // controller values directly in build(), so we just need a rebuild.
    setState(() {});
  }

  bool get _hasSavedCreds =>
      _savedEmail.isNotEmpty && _savedPassword.isNotEmpty;

  bool get _saveEnabled {
    final e = _emailCtrl.text.trim();
    final p = _passwordCtrl.text;
    if (e.isEmpty || p.isEmpty) return false;
    return e != _savedEmail || p != _savedPassword;
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final pw = _passwordCtrl.text;
    if (email.isEmpty || pw.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.credentials.save(email, pw);
      if (!mounted) return;
      setState(() {
        _savedEmail = email;
        _savedPassword = pw;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Credentials saved')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSync() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await widget.onSync();
      if (!mounted) return;
      final msg = result.divesPushed == 0
          ? 'Already up-to-date with Subsurface'
          : 'Pushed ${result.divesPushed} '
              'dive${result.divesPushed == 1 ? '' : 's'} to Subsurface';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } on NoCredentialsException {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('Enter your Subsurface email + password first.'),
      ));
    } on AuthFailedSyncException {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Subsurface rejected your credentials. Check email + password and save again.'),
      ));
    } on UnresolvedConflictException {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text(
            "Couldn't reconcile with Subsurface after 3 retries. Try again in a moment."),
      ));
    } on SubsurfaceSyncException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      // Always re-read the timestamp — even on error the orchestrator
      // may have stamped some dives before throwing.
      await _refreshLastSynced();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirmation dialog + stream-driven status updates for the
  /// bootstrap-import button. Disables both buttons while running.
  Future<void> _runBootstrapImport() async {
    final runner = widget.onBootstrapImport;
    if (runner == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import from Subsurface?'),
        content: const Text(
          'Pulls every importable dive from your Subsurface Cloud repo '
          'into CCRLog. Existing CCRLog dives are not touched — only '
          'dives CCRLog doesn’t already have are added. The first '
          'import on a fresh account can take a couple of minutes for '
          'hundreds of dives.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _bootstrapStatus = 'Cloning repo…';
    });

    final completer = Completer<void>();
    final stream = runner();
    _bootstrapSub = stream.listen((event) {
      if (!mounted) return;
      switch (event) {
        case CloningRepo():
          setState(() => _bootstrapStatus = 'Cloning repo…');
        case WalkingRepo(:final totalCandidateDives):
          setState(() => _bootstrapStatus =
              'Walking $totalCandidateDives dive${totalCandidateDives == 1 ? '' : 's'}…');
        case ImportingDive(:final index, :final total, :final diveLabel):
          setState(() => _bootstrapStatus =
              'Importing $index / $total — $diveLabel');
        case BootstrapDone(:final result):
          setState(() => _bootstrapStatus = null);
          messenger.showSnackBar(SnackBar(
            content: Text(_formatBootstrapResult(result)),
            duration: const Duration(seconds: 6),
          ));
        case BootstrapFailed(:final exception):
          setState(() => _bootstrapStatus = null);
          messenger.showSnackBar(SnackBar(
            content: Text(_formatBootstrapError(exception)),
          ));
      }
    }, onDone: () {
      if (!completer.isCompleted) completer.complete();
    }, onError: (Object e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      if (!completer.isCompleted) completer.complete();
    });
    try {
      await completer.future;
    } finally {
      await _bootstrapSub?.cancel();
      _bootstrapSub = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _bootstrapStatus = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Subsurface sync',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.isPlatformSupported) _buildIosNotice(context),
                  if (!widget.isPlatformSupported) const SizedBox(height: 12),
                  _buildEmailField(),
                  const SizedBox(height: 8),
                  _buildPasswordField(),
                  const SizedBox(height: 12),
                  _buildButtonRow(),
                  const SizedBox(height: 12),
                  _buildStatusRow(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIosNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Subsurface sync isn't supported on iPhone yet (no Flutter "
              "library currently ships in-process git for iOS). Open CCRLog "
              "on your Mac, Windows, or Linux desktop and sign in there to "
              "configure and sync.",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailCtrl,
      enabled: !_busy,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      decoration: const InputDecoration(
        labelText: 'Subsurface email',
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordCtrl,
      enabled: !_busy,
      obscureText: !_passwordVisible,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: 'Subsurface password',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: _passwordVisible ? 'Hide password' : 'Show password',
          icon: Icon(_passwordVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined),
          onPressed: () =>
              setState(() => _passwordVisible = !_passwordVisible),
        ),
      ),
    );
  }

  Widget _buildButtonRow() {
    final saveBtn = FilledButton(
      onPressed: _busy || !_saveEnabled ? null : _save,
      child: const Text('Save credentials'),
    );

    if (!widget.isPlatformSupported) {
      // Even on iOS we still render the bootstrap-import button when the
      // parent provided one — but disabled, so the user can see the
      // capability exists when they switch to a desktop.
      if (widget.onBootstrapImport != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            saveBtn,
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: null,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Import from Subsurface'),
            ),
          ],
        );
      }
      return Align(alignment: Alignment.centerRight, child: saveBtn);
    }

    final syncBtn = FilledButton.icon(
      onPressed: _busy || !_hasSavedCreds ? null : _runSync,
      icon: _busy && _bootstrapStatus == null
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync),
      label: const Text('Sync now'),
    );

    final topRow = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        saveBtn,
        const SizedBox(width: 8),
        syncBtn,
      ],
    );

    if (widget.onBootstrapImport == null) {
      return topRow;
    }

    final importBtn = FilledButton.icon(
      onPressed: _busy || !_hasSavedCreds ? null : _runBootstrapImport,
      icon: _bootstrapStatus != null
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_download_outlined),
      label: const Text('Import from Subsurface'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        topRow,
        const SizedBox(height: 8),
        importBtn,
      ],
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    // While a bootstrap import is running, the live progress message
    // takes priority over the static last-synced row — it's what the
    // user is actively waiting on.
    final bootstrap = _bootstrapStatus;
    if (bootstrap != null) {
      return Text(
        bootstrap,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final last = _lastSyncedSeconds;
    final String text;
    if (!_credsLoaded) {
      text = 'Last synced: …';
    } else if (last == null) {
      text = 'Last synced: never';
    } else {
      final when = DateTime.fromMillisecondsSinceEpoch(last * 1000);
      text = 'Last synced: ${_relativeTime(when, _now())}';
    }
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  /// Phrase a [SubsurfaceBootstrapResult] for the post-import SnackBar.
  String _formatBootstrapResult(SubsurfaceBootstrapResult r) {
    final imported = r.divesImported;
    final skipped = r.divesSkipped;
    final unmappable = r.divesUnmappable;
    final parts = <String>[
      'Imported $imported dive${imported == 1 ? '' : 's'}.',
    ];
    if (skipped > 0) {
      parts.add('$skipped already in CCRLog.');
    }
    if (unmappable > 0) {
      parts.add('$unmappable unmappable (manual entries skipped).');
    }
    return parts.join(' ');
  }

  /// Friendly message for a [SubsurfaceBootstrapException].
  String _formatBootstrapError(SubsurfaceBootstrapException e) {
    if (e is NoCredentialsBootstrapException) {
      return 'Save credentials first.';
    }
    if (e is AuthFailedBootstrapException) {
      return 'Subsurface rejected your credentials.';
    }
    if (e is PlatformNotSupportedBootstrapException) {
      return 'Import isn’t supported on this platform.';
    }
    return e.message;
  }
}

/// Compact relative-time formatter. Mirrors the helper in
/// [settings_screen.dart] so the two status rows look consistent.
String _relativeTime(DateTime when, DateTime now) {
  final diff = now.difference(when);
  if (diff.isNegative) return DateFormat.yMd().add_Hm().format(when);
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
