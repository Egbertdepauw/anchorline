// Widget tests for [SubsurfaceSyncSection]. We deliberately decouple
// this test from the real [SubsurfaceSyncOrchestrator] — the section
// takes a callback (`onSync`) instead of the orchestrator instance, so
// we can fabricate any sync result or thrown exception without booting
// libgit2.
//
// Pattern is the same as `dive_attachments_section_test.dart`: an
// in-memory fake credential store, a closure-style sync runner, a
// closure-style "last synced at" reader. Each test wires whatever it
// needs.

import 'package:ccrlogger/sync/subsurface_git/bootstrap_importer.dart';
import 'package:ccrlogger/sync/subsurface_git/credentials.dart';
import 'package:ccrlogger/sync/subsurface_git/sync_orchestrator.dart';
import 'package:ccrlogger/ui/widgets/subsurface_sync_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryCredentials implements SubsurfaceCredentialsSource {
  String? email;
  String? password;
  final List<({String email, String password})> saveCalls = [];

  _InMemoryCredentials({this.email, this.password});

  @override
  Future<({String email, String password})?> read() async {
    if (email == null || password == null) return null;
    if (email!.isEmpty || password!.isEmpty) return null;
    return (email: email!, password: password!);
  }

  @override
  Future<void> save(String email, String password) async {
    this.email = email;
    this.password = password;
    saveCalls.add((email: email, password: password));
  }

  @override
  Future<void> clear() async {
    email = null;
    password = null;
  }
}

SubsurfaceSyncResult _ok({int divesPushed = 1, String? sha = 'abc'}) =>
    SubsurfaceSyncResult(
      divesPushed: divesPushed,
      divesSkipped: 0,
      commitSha: sha,
      completedAt: DateTime(2026, 5, 8, 10),
    );

Widget _harness({
  required _InMemoryCredentials creds,
  bool isPlatformSupported = true,
  Future<SubsurfaceSyncResult> Function()? onSync,
  Future<int?> Function()? lastSyncedAt,
  DateTime Function()? now,
  Stream<SubsurfaceBootstrapEvent> Function()? onBootstrapImport,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SubsurfaceSyncSection(
          credentials: creds,
          onSync: onSync ?? () async => _ok(),
          isPlatformSupported: isPlatformSupported,
          lastSyncedAt: lastSyncedAt ?? () async => null,
          now: now,
          onBootstrapImport: onBootstrapImport,
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders email + password + Save + Sync buttons on supported '
      'platforms', (tester) async {
    final creds = _InMemoryCredentials();
    await tester.pumpWidget(_harness(creds: creds));
    await tester.pumpAndSettle();

    expect(find.text('Subsurface sync'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Subsurface email'),
        findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Subsurface password'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save credentials'),
        findsOneWidget);
    expect(find.widgetWithIcon(FilledButton, Icons.sync), findsOneWidget);
    // iOS notice should NOT be there.
    expect(find.textContaining("isn't supported on iPhone yet"), findsNothing);
  });

  testWidgets('iOS notice renders when isPlatformSupported is false; '
      'Sync button is hidden', (tester) async {
    final creds = _InMemoryCredentials();
    await tester.pumpWidget(_harness(
      creds: creds,
      isPlatformSupported: false,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining("isn't supported on iPhone yet"), findsOneWidget);
    expect(find.textContaining('Mac, Windows, or Linux'), findsOneWidget);
    // Save form still visible — users can pre-enter creds.
    expect(find.widgetWithText(FilledButton, 'Save credentials'),
        findsOneWidget);
    // Sync button gone.
    expect(find.widgetWithIcon(FilledButton, Icons.sync), findsNothing);
  });

  testWidgets('hydrates fields from stored credentials', (tester) async {
    final creds =
        _InMemoryCredentials(email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(creds: creds));
    await tester.pumpAndSettle();

    final emailField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Subsurface email'));
    expect(emailField.controller!.text, 'me@example.com');
    final pwField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Subsurface password'));
    expect(pwField.controller!.text, 'hunter2');
  });

  testWidgets('Save credentials calls credentials.save with typed values',
      (tester) async {
    final creds = _InMemoryCredentials();
    await tester.pumpWidget(_harness(creds: creds));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subsurface email'),
        'diver@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Subsurface password'),
        'secret');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save credentials'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(creds.saveCalls, hasLength(1));
    expect(creds.saveCalls.single.email, 'diver@example.com');
    expect(creds.saveCalls.single.password, 'secret');
    expect(find.text('Credentials saved'), findsOneWidget);
  });

  testWidgets('Sync now invokes onSync and shows the success SnackBar',
      (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    var syncCalls = 0;
    await tester.pumpWidget(_harness(
      creds: creds,
      onSync: () async {
        syncCalls++;
        return _ok(divesPushed: 3);
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.sync));
    await tester.pump(); // dispatch the future
    await tester.pumpAndSettle();

    expect(syncCalls, 1);
    expect(find.text('Pushed 3 dives to Subsurface'), findsOneWidget);
  });

  testWidgets('NoCredentialsException from sync surfaces a friendly message',
      (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(
      creds: creds,
      onSync: () async => throw NoCredentialsException(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.sync));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.text('Enter your Subsurface email + password first.'),
      findsOneWidget,
    );
  });

  testWidgets('AuthFailedSyncException from sync surfaces a friendly message',
      (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(
      creds: creds,
      onSync: () async => throw AuthFailedSyncException('401'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.sync));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Subsurface rejected your credentials'),
      findsOneWidget,
    );
  });

  testWidgets('UnresolvedConflictException from sync surfaces a friendly '
      'message', (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(
      creds: creds,
      onSync: () async => throw UnresolvedConflictException('boom'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.sync));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.textContaining("Couldn't reconcile with Subsurface"),
      findsOneWidget,
    );
  });

  testWidgets('Last-synced row shows "never" when reader returns null',
      (tester) async {
    final creds = _InMemoryCredentials();
    await tester.pumpWidget(_harness(
      creds: creds,
      lastSyncedAt: () async => null,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Last synced: never'), findsOneWidget);
  });

  testWidgets('Last-synced row formats a relative timestamp from epoch '
      'seconds', (tester) async {
    final creds = _InMemoryCredentials();
    final fixedNow = DateTime(2026, 5, 8, 10, 0, 0);
    final tenMinAgo =
        fixedNow.subtract(const Duration(minutes: 10)).millisecondsSinceEpoch ~/
            1000;
    await tester.pumpWidget(_harness(
      creds: creds,
      lastSyncedAt: () async => tenMinAgo,
      now: () => fixedNow,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Last synced: 10 min ago'), findsOneWidget);
  });

  testWidgets('Sync button is disabled when no credentials are stored',
      (tester) async {
    final creds = _InMemoryCredentials();
    await tester.pumpWidget(_harness(creds: creds));
    await tester.pumpAndSettle();

    final syncBtn = tester.widget<FilledButton>(
        find.widgetWithIcon(FilledButton, Icons.sync));
    expect(syncBtn.onPressed, isNull);
  });

  // ── Bootstrap-import button ───────────────────────────────────────

  testWidgets('Import-from-Subsurface button is hidden when '
      'onBootstrapImport is null', (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(creds: creds));
    await tester.pumpAndSettle();

    expect(find.text('Import from Subsurface'), findsNothing);
  });

  testWidgets('Import-from-Subsurface button renders when '
      'onBootstrapImport is provided', (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(
      creds: creds,
      onBootstrapImport: () => const Stream<SubsurfaceBootstrapEvent>.empty(),
    ));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Import from Subsurface'),
      findsOneWidget,
    );
  });

  testWidgets('Import-from-Subsurface button is disabled when no '
      'credentials are stored', (tester) async {
    final creds = _InMemoryCredentials();
    await tester.pumpWidget(_harness(
      creds: creds,
      onBootstrapImport: () => const Stream<SubsurfaceBootstrapEvent>.empty(),
    ));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import from Subsurface'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('Import-from-Subsurface button is disabled on unsupported '
      'platforms', (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(
      creds: creds,
      isPlatformSupported: false,
      onBootstrapImport: () => const Stream<SubsurfaceBootstrapEvent>.empty(),
    ));
    await tester.pumpAndSettle();

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import from Subsurface'),
    );
    expect(btn.onPressed, isNull);
  });

  testWidgets('Import button shows confirmation dialog and runs the '
      'stream on confirm', (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    var subscriptionCount = 0;
    Stream<SubsurfaceBootstrapEvent> mkStream() {
      subscriptionCount++;
      return Stream<SubsurfaceBootstrapEvent>.fromIterable([
        const CloningRepo(),
        const WalkingRepo(totalCandidateDives: 3),
        const ImportingDive(index: 1, total: 3, diveLabel: 'Dive #1'),
        const ImportingDive(index: 2, total: 3, diveLabel: 'Dive #2'),
        const ImportingDive(index: 3, total: 3, diveLabel: 'Dive #3'),
        BootstrapDone(SubsurfaceBootstrapResult(
          divesImported: 2,
          divesSkipped: 1,
          divesUnmappable: 0,
          completedAt: DateTime(2026, 5, 8),
        )),
      ]);
    }

    await tester.pumpWidget(_harness(
      creds: creds,
      onBootstrapImport: mkStream,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import from Subsurface'));
    await tester.pumpAndSettle();

    // Confirmation dialog visible.
    expect(find.text('Import from Subsurface?'), findsOneWidget);
    // Confirm.
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    // Drain the synchronous stream events. We don't pumpAndSettle()
    // because the success SnackBar uses a multi-second duration that
    // would push pumpAndSettle past its timeout — the SnackBar's
    // intrinsic clock keeps firing frames until it dismisses.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(subscriptionCount, 1);
    expect(
      find.text('Imported 2 dives. 1 already in CCRLog.'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel on the confirmation dialog does not invoke the stream',
      (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    var subscriptionCount = 0;
    await tester.pumpWidget(_harness(
      creds: creds,
      onBootstrapImport: () {
        subscriptionCount++;
        return const Stream<SubsurfaceBootstrapEvent>.empty();
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import from Subsurface'));
    await tester.pumpAndSettle();

    expect(find.text('Import from Subsurface?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(subscriptionCount, 0);
  });

  testWidgets('BootstrapFailed(NoCredentials) surfaces a friendly snackbar',
      (tester) async {
    final creds = _InMemoryCredentials(
        email: 'me@example.com', password: 'hunter2');
    await tester.pumpWidget(_harness(
      creds: creds,
      onBootstrapImport: () => Stream<SubsurfaceBootstrapEvent>.fromIterable([
        BootstrapFailed(NoCredentialsBootstrapException()),
      ]),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Import from Subsurface'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Save credentials first.'), findsOneWidget);
  });
}
