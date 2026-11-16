import 'dart:async';

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

/// Pumps a signed-in Sync tab whose upload queue holds [pending] changes,
/// and opens the sign-out dialog.
Future<void> _openSignOut(WidgetTester tester, int pending) async {
  final client = _FakeAuthClient();
  final u = User(
    id: 'uid',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    email: 'me@example.test',
    createdAt: DateTime.now().toIso8601String(),
  );
  client.user = u;
  client.session = Session(accessToken: 'token', tokenType: 'bearer', user: u);
  final auth = AuthService(client: client);
  addTearDown(() {
    auth.dispose();
    client.dispose();
  });

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SyncTab(
        authService: auth,
        countPendingUploads: () async => pending,
        onReassign: () {},
        onPushStuck: () {},
      ),
    ),
  ));
  await tester.tap(find.text('Sign out'));
  await tester.pumpAndSettle();
}

/// Finds text inside the open sign-out dialog only: the tab behind it has
/// its own lines about other accounts.
Finder _inDialog(String text) => find.descendant(
    of: find.byType(AlertDialog), matching: find.textContaining(text));

void main() {
  testWidgets('warns when changes still wait to upload', (tester) async {
    await _openSignOut(tester, 3);

    expect(_inDialog("3 changes haven't uploaded yet"), findsOneWidget);
    expect(_inDialog('another account'), findsOneWidget);
  });

  testWidgets('says "1 change hasn\'t" for a single change', (tester) async {
    await _openSignOut(tester, 1);

    expect(_inDialog("1 change hasn't uploaded yet"), findsOneWidget);
  });

  testWidgets('does not warn when nothing waits to upload', (tester) async {
    await _openSignOut(tester, 0);

    expect(_inDialog('uploaded yet'), findsNothing);
    expect(_inDialog('Your local dives stay on the device'), findsOneWidget);
  });
}
