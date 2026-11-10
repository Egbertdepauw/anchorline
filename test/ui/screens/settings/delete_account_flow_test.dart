import 'dart:async';

import 'package:ccrlogger/sync/cloud/account_deleter.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart';
import 'package:ccrlogger/sync/cloud/cloud_sync_coordinator.dart';
import 'package:ccrlogger/ui/screens/settings/delete_account_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSession implements SessionSource {
  Object? refreshError;
  @override
  Session? get currentSession => Session(
        accessToken: 'token',
        tokenType: 'bearer',
        user: User(
          id: 'uid',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: '2026-11-08T00:00:00Z',
        ),
      );
  @override
  Future<void> refreshSession() async {
    final e = refreshError;
    if (e != null) throw e;
  }
}

class _FakeBackend implements AccountDeletionBackend {
  int rpcCalls = 0;
  List<String> serverKeys = const [];
  Object? listError;
  Object? rpcError;
  Completer<void>? rpcGate;

  @override
  Future<List<String>> listStorageKeys() async {
    final e = listError;
    if (e != null) throw e;
    return serverKeys;
  }

  @override
  Future<void> deleteAccount() async {
    rpcCalls++;
    await rpcGate?.future;
    final e = rpcError;
    if (e != null) throw e;
  }

  @override
  Future<bool> accountExists() async => true;
}

class _FakeSync implements SyncPause {
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

class _Harness {
  final session = _FakeSession();
  final backend = _FakeBackend();
  Object? wipeError;
  Future<void> Function()? onSignOut;
  Future<void> Function(String key)? onDelete;

  AccountDeleter build() => AccountDeleter(
        session: session,
        backend: backend,
        sync: _FakeSync(),
        localStorageKeys: () async => const [],
        deleteObject: (k) async => onDelete?.call(k),
        signOut: () async => onSignOut?.call(),
        wipeLocal: () async {
          final e = wipeError;
          if (e != null) throw e;
        },
      );
}

Future<void> _pumpButton(WidgetTester tester, AccountDeleter deleter) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => runDeleteAccountFlow(context, deleter),
          child: const Text('go'),
        ),
      ),
    ),
  ));
}

Future<void> _openConfirm(WidgetTester tester) async {
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

Future<void> _typeAndConfirm(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
  await tester.pumpAndSettle();
}

Finder _confirmButton() => find.widgetWithText(FilledButton, 'Delete account');

void main() {
  testWidgets('the confirm dialog shows the spec copy', (tester) async {
    await _pumpButton(tester, _Harness().build());
    await _openConfirm(tester);
    expect(find.text('Delete your Anchorline account?'), findsOneWidget);
    expect(find.textContaining('This permanently deletes:'), findsOneWidget);
    expect(find.textContaining('signed out within about an hour'),
        findsOneWidget);
    expect(find.textContaining("This can't be undone. Type DELETE"),
        findsOneWidget);
  });

  testWidgets('the Delete button is disabled until DELETE is typed',
      (tester) async {
    await _pumpButton(tester, _Harness().build());
    await _openConfirm(tester);
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'delet');
    await tester.pump();
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' delete ');
    await tester.pump();
    expect(tester.widget<FilledButton>(_confirmButton()).onPressed, isNotNull);
  });

  testWidgets('Cancel deletes nothing', (tester) async {
    final h = _Harness();
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your Anchorline account?'), findsNothing);
    expect(h.backend.rpcCalls, 0);
  });

  testWidgets('dismissing the confirm dialog deletes nothing', (tester) async {
    final h = _Harness();
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text('Delete your Anchorline account?'), findsNothing);
    expect(h.backend.rpcCalls, 0);
  });

  testWidgets('progress dialog follows the steps', (tester) async {
    final h = _Harness();
    h.backend.serverKeys = const ['attachments/uid/a', 'attachments/uid/b'];
    final gate = Completer<void>();
    h.onDelete =
        (k) => k == 'attachments/uid/b' ? gate.future : Future.value();
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirmNoSettle(tester, 'DELETE');
    await tester.pump();
    await tester.pump();
    expect(find.text('Deleting your account…'), findsOneWidget);
    expect(find.text('Removing attachment files (1 of 2)'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Account deleted'), findsOneWidget);
  });

  testWidgets('no attachments shows the step without a count', (tester) async {
    final h = _Harness();
    final gate = Completer<void>();
    h.backend.rpcGate = gate;
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirmNoSettle(tester, 'DELETE');
    await tester.pump();
    await tester.pump();
    expect(find.text('Deleting your account'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('success shows the Account deleted dialog', (tester) async {
    await _pumpButton(tester, _Harness().build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.text('Account deleted'), findsOneWidget);
    expect(find.textContaining('Quit and reopen Anchorline'), findsOneWidget);
  });

  testWidgets('offline failure says nothing was deleted', (tester) async {
    final h = _Harness()..session.refreshError = Exception('no network');
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.textContaining('Nothing was deleted.'), findsOneWidget);
    expect(find.textContaining('internet connection'), findsOneWidget);
  });

  testWidgets('an ended sign-in says to sign in again', (tester) async {
    final h = _Harness()
      ..session.refreshError = AuthApiException(
        'Invalid Refresh Token: Refresh Token Not Found',
        statusCode: '400',
        code: 'refresh_token_not_found',
      );
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.text('Could not delete account'), findsOneWidget);
    expect(
        find.text('Your sign-in has ended, so nothing was deleted. Sign in '
            'again, then try again.'),
        findsOneWidget);
    expect(h.backend.rpcCalls, 0);
  });

  testWidgets('attachments failure shows the count', (tester) async {
    final h = _Harness();
    h.backend.serverKeys = const [
      'attachments/uid/a',
      'attachments/uid/b',
      'attachments/uid/c',
    ];
    h.onDelete = (k) async {
      if (k != 'attachments/uid/a') throw Exception('r2 down');
    };
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.textContaining('Your account was not deleted.'),
        findsOneWidget);
    expect(find.textContaining('2 attachment files could not be removed'),
        findsOneWidget);
  });

  testWidgets('unreadable attachment list is reported as such',
      (tester) async {
    final h = _Harness();
    h.backend.listError = Exception('boom');
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.textContaining('Your account was not deleted.'),
        findsOneWidget);
    expect(find.textContaining('The list of attachment files could not be read.'),
        findsOneWidget);
  });

  testWidgets('account failure shows the error text', (tester) async {
    final h = _Harness();
    h.backend.rpcError = Exception('rpc exploded');
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.textContaining('Attachment files were already removed.'),
        findsOneWidget);
    expect(find.textContaining('rpc exploded'), findsOneWidget);
  });

  testWidgets('local wipe failure points at Reset local data', (tester) async {
    final h = _Harness()..wipeError = Exception('disk');
    await _pumpButton(tester, h.build());
    await _openConfirm(tester);
    await _typeAndConfirm(tester, 'DELETE');
    expect(find.textContaining('Your account was deleted'), findsOneWidget);
    expect(find.textContaining('Reset local data'), findsOneWidget);
  });
}

Future<void> _typeAndConfirmNoSettle(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
}
