import 'dart:async';

import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:ccrlogger/sync/cloud/sync_status_source.dart';
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

class _FakeStatusSource implements SyncStatusSource {
  _FakeStatusSource(this.snapshot);
  final SyncStatusSnapshot snapshot;

  @override
  SyncStatusSnapshot get currentStatus => snapshot;
  @override
  Stream<SyncStatusSnapshot> get statusStream => const Stream.empty();
}

const _helper =
    'The server refused a change. It uploads by itself once the server is fixed.';

Future<void> _pump(WidgetTester tester, SyncStatusSnapshot snapshot) async {
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
        syncStatusSource: _FakeStatusSource(snapshot),
        onReassign: () {},
        onPushStuck: () {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a blocked upload shows the blocked label and helper',
      (tester) async {
    await _pump(tester,
        const SyncStatusSnapshot(connected: true, uploadBlockedByServer: true));

    expect(find.textContaining('🔴 Upload blocked by the server'),
        findsOneWidget);
    expect(find.textContaining(_helper), findsOneWidget);
    expect(find.textContaining('🟡 Syncing…'), findsNothing);
  });

  testWidgets('a blocked upload outranks uploading', (tester) async {
    await _pump(
        tester,
        const SyncStatusSnapshot(
            connected: true, uploading: true, uploadBlockedByServer: true));

    expect(find.textContaining('🔴 Upload blocked by the server'),
        findsOneWidget);
    expect(find.textContaining('🟡 Syncing…'), findsNothing);
  });

  testWidgets('offline outranks blocked', (tester) async {
    await _pump(tester,
        const SyncStatusSnapshot(connected: false, uploadBlockedByServer: true));

    expect(find.textContaining('🔴 Offline'), findsOneWidget);
    expect(find.textContaining('Upload blocked'), findsNothing);
  });

  testWidgets('no block shows Synced', (tester) async {
    await _pump(tester, const SyncStatusSnapshot(connected: true));

    expect(find.textContaining('🟢 Synced'), findsOneWidget);
    expect(find.textContaining(_helper), findsNothing);
  });
}
