import 'dart:async';

import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart';
import 'package:ccrlogger/sync/cloud/cloud_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthClient implements AuthClient {
  User? user;
  Session? session;
  final _ctrl = StreamController<AuthState>.broadcast();
  AuthResponse Function()? signInResponder;

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
  }) async {
    final r = signInResponder!();
    if (r.session != null) {
      session = r.session;
      user = r.user;
    }
    return r;
  }

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async =>
      AuthResponse();

  @override
  Future<void> signOut() async {
    user = null;
    session = null;
  }

  void dispose() => _ctrl.close();
}

class _RecordingTarget implements CloudSyncTarget {
  int connectCalls = 0;
  int disconnectCalls = 0;
  PowerSyncBackendConnector? lastConnector;

  @override
  Future<void> connect(PowerSyncBackendConnector connector) async {
    connectCalls++;
    lastConnector = connector;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }
}

class _FakeSessions implements SessionSource {
  Session? session;
  @override
  Session? get currentSession => session;
  @override
  Future<void> refreshSession() async {}
}

class _NoopUploader implements SupabaseRestUploader {
  @override
  Future<void> upsert(String table, Map<String, dynamic> data) async {}
  @override
  Future<void> update(String table, String id, Map<String, dynamic> data) async {}
  @override
  Future<void> delete(String table, String id) async {}
}

User _user(String id, String email) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );

({
  AuthService auth,
  _FakeAuthClient client,
  _RecordingTarget target,
  CloudSyncCoordinator coord,
}) _build({bool signedIn = false}) {
  final client = _FakeAuthClient();
  if (signedIn) {
    final u = _user('uid', 'me@test.test');
    client.user = u;
    client.session = Session(accessToken: 't', tokenType: 'bearer', user: u);
  }
  final auth = AuthService(client: client);
  final target = _RecordingTarget();
  final connector = CcrloggerBackendConnector.forTesting(
    sessions: _FakeSessions(),
    uploader: _NoopUploader(),
  );
  final coord = CloudSyncCoordinator.forTesting(
    target: target,
    connector: connector,
    authService: auth,
  );
  return (auth: auth, client: client, target: target, coord: coord);
}

void main() {
  test('start() with signed-out auth does nothing', () async {
    final h = _build(signedIn: false);
    addTearDown(() {
      h.coord.dispose();
      h.auth.dispose();
      h.client.dispose();
    });

    h.coord.start();
    await Future<void>.delayed(Duration.zero);

    expect(h.target.connectCalls, 0);
    expect(h.target.disconnectCalls, 0);
    expect(h.coord.isConnected, isFalse);
  });

  test('start() with already-signed-in user connects immediately', () async {
    final h = _build(signedIn: true);
    addTearDown(() {
      h.coord.dispose();
      h.auth.dispose();
      h.client.dispose();
    });

    h.coord.start();
    await Future<void>.delayed(Duration.zero);

    expect(h.target.connectCalls, 1);
    expect(h.target.lastConnector, isA<CcrloggerBackendConnector>());
    expect(h.coord.isConnected, isTrue);
  });

  test('successful sign-in triggers connect; sign-out triggers disconnect',
      () async {
    final h = _build(signedIn: false);
    addTearDown(() {
      h.coord.dispose();
      h.auth.dispose();
      h.client.dispose();
    });

    h.coord.start();
    await Future<void>.delayed(Duration.zero);
    expect(h.target.connectCalls, 0);

    final u = _user('uid', 'me@test.test');
    h.client.signInResponder =
        () => AuthResponse(session: Session(
              accessToken: 't',
              tokenType: 'bearer',
              user: u,
            ), user: u);
    await h.auth.signIn(email: 'me@test.test', password: 'pw');
    await Future<void>.delayed(Duration.zero);

    expect(h.target.connectCalls, 1);
    expect(h.target.disconnectCalls, 0);
    expect(h.coord.isConnected, isTrue);

    await h.auth.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(h.target.disconnectCalls, 1);
    expect(h.coord.isConnected, isFalse);
  });

  test('repeated sign-ins do not double-connect', () async {
    final h = _build(signedIn: true);
    addTearDown(() {
      h.coord.dispose();
      h.auth.dispose();
      h.client.dispose();
    });

    h.coord.start();
    await Future<void>.delayed(Duration.zero);
    expect(h.target.connectCalls, 1);

    // Force a redundant notify.
    final u = _user('uid', 'me@test.test');
    h.client.signInResponder =
        () => AuthResponse(session: Session(
              accessToken: 't',
              tokenType: 'bearer',
              user: u,
            ), user: u);
    await h.auth.signIn(email: 'me@test.test', password: 'pw');
    await Future<void>.delayed(Duration.zero);

    expect(h.target.connectCalls, 1, reason: 'still already connected');
  });
}
