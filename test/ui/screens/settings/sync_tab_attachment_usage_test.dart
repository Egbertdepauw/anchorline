import 'dart:async';

import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:ccrlogger/ui/screens/settings/sync_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthClient implements AuthClient {
  User? user;
  Session? session;
  final _ctrl = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => user;
  @override
  Session? get currentSession => session;
  @override
  Stream<AuthState> get onAuthStateChange => _ctrl.stream;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async =>
      AuthResponse();

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async =>
      AuthResponse();

  @override
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
  }) async =>
      AuthResponse();

  @override
  Future<void> resendEmailCode({required String email}) async {}

  @override
  Future<void> setPassword(String password) async {}

  @override
  Future<void> signOut() async {
    user = null;
    session = null;
  }

  void dispose() => _ctrl.close();
}

({AuthService auth, _FakeAuthClient client}) _signedIn({bool signedIn = true}) {
  final client = _FakeAuthClient();
  if (signedIn) {
    final u = User(
      id: 'uid',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: 'me@example.test',
      createdAt: DateTime.now().toIso8601String(),
    );
    client.user = u;
    client.session =
        Session(accessToken: 'token', tokenType: 'bearer', user: u);
  }
  return (auth: AuthService(client: client), client: client);
}

Future<void> _pump(
  WidgetTester tester,
  AuthService auth,
  Future<AttachmentUsage> Function()? loader,
) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SyncTab(
        authService: auth,
        loadAttachmentUsage: loader,
        onReassign: () {},
        onPushStuck: () {},
      ),
    ),
  ));
}

const _rowKey = ValueKey('settings-account-attachments');

void main() {
  testWidgets('shows the usage line once loaded', (tester) async {
    final h = _signedIn();
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    var calls = 0;
    final completer = Completer<AttachmentUsage>();
    await _pump(tester, h.auth, () {
      calls++;
      return completer.future;
    });

    expect(find.byKey(_rowKey), findsOneWidget);
    expect(find.text('Attachments'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);

    completer.complete(const AttachmentUsage(
      usedBytes: 400000000,
      limitBytes: 1000000000,
      usedFiles: 120,
      limitFiles: 1000,
    ));
    await tester.pumpAndSettle();

    expect(find.text('0.4 GB of 1 GB · 120 of 1,000 files'), findsOneWidget);
    expect(find.text('…'), findsNothing);
    expect(calls, 1);
  });

  testWidgets('shows Unavailable when the loader throws', (tester) async {
    final h = _signedIn();
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await _pump(tester, h.auth, () async => throw Exception('offline'));
    await tester.pumpAndSettle();

    expect(find.byKey(_rowKey), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('has no row without a loader', (tester) async {
    final h = _signedIn();
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await _pump(tester, h.auth, null);
    await tester.pumpAndSettle();

    expect(find.byKey(_rowKey), findsNothing);
  });

  testWidgets('has no row when signed out, and does not load',
      (tester) async {
    final h = _signedIn(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    var calls = 0;
    await _pump(tester, h.auth, () async {
      calls++;
      throw StateError('should not be called');
    });
    await tester.pumpAndSettle();

    expect(find.byKey(_rowKey), findsNothing);
    expect(calls, 0);
  });
}
