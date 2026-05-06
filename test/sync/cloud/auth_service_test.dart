import 'dart:async';

import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthClient implements AuthClient {
  User? user;
  Session? session;
  final _ctrl = StreamController<AuthState>.broadcast();

  AuthResponse Function()? signInResponder;
  AuthResponse Function()? signUpResponder;

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
  }) async {
    final r = signUpResponder!();
    if (r.session != null) {
      session = r.session;
      user = r.user;
    }
    return r;
  }

  @override
  Future<void> signOut() async {
    user = null;
    session = null;
  }

  void dispose() => _ctrl.close();
}

User _user(String id, String email) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );

Session _session(User u) => Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: u,
    );

void main() {
  group('AuthService.signIn', () {
    test('success returns AuthSuccess and flips isSignedIn', () async {
      final fake = _FakeAuthClient();
      final u = _user('abc', 'a@b.test');
      fake.signInResponder = () => AuthResponse(session: _session(u), user: u);

      final svc = AuthService(client: fake);
      var notified = 0;
      svc.addListener(() => notified++);

      final res = await svc.signIn(email: 'a@b.test', password: 'pw');
      expect(res, isA<AuthSuccess>());
      expect((res as AuthSuccess).user.id, 'abc');
      expect(svc.isSignedIn, isTrue);
      expect(svc.currentUser?.email, 'a@b.test');
      expect(notified, greaterThanOrEqualTo(1));

      svc.dispose();
      fake.dispose();
    });

    test('AuthException becomes AuthFailure with the same message', () async {
      final fake = _FakeAuthClient();
      fake.signInResponder = () => throw const AuthException('Invalid login');

      final svc = AuthService(client: fake);
      final res = await svc.signIn(email: 'x@y.test', password: 'wrong');
      expect(res, isA<AuthFailure>());
      expect((res as AuthFailure).message, 'Invalid login');
      expect(svc.isSignedIn, isFalse);

      svc.dispose();
      fake.dispose();
    });
  });

  group('AuthService.signUp', () {
    test('email confirmation pending returns AuthEmailConfirmationRequired',
        () async {
      final fake = _FakeAuthClient();
      final u = _user('abc', 'a@b.test');
      fake.signUpResponder = () => AuthResponse(user: u); // no session

      final svc = AuthService(client: fake);
      final res = await svc.signUp(email: 'a@b.test', password: 'pw');
      expect(res, isA<AuthEmailConfirmationRequired>());
      expect((res as AuthEmailConfirmationRequired).email, 'a@b.test');
      expect(svc.isSignedIn, isFalse);

      svc.dispose();
      fake.dispose();
    });

    test('immediate session returns AuthSuccess', () async {
      final fake = _FakeAuthClient();
      final u = _user('abc', 'a@b.test');
      fake.signUpResponder = () => AuthResponse(session: _session(u), user: u);

      final svc = AuthService(client: fake);
      final res = await svc.signUp(email: 'a@b.test', password: 'pw');
      expect(res, isA<AuthSuccess>());
      expect(svc.isSignedIn, isTrue);

      svc.dispose();
      fake.dispose();
    });
  });

  test('signOut clears session', () async {
    final fake = _FakeAuthClient();
    final u = _user('abc', 'a@b.test');
    fake.session = _session(u);
    fake.user = u;

    final svc = AuthService(client: fake);
    expect(svc.isSignedIn, isTrue);
    await svc.signOut();
    expect(svc.isSignedIn, isFalse);

    svc.dispose();
    fake.dispose();
  });
}
