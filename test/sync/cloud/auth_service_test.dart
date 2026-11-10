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
  AuthResponse Function()? verifyResponder;
  void Function()? resendResponder;
  final verifyCalls = <({String email, String code})>[];
  final resendCalls = <String>[];

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
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    verifyCalls.add((email: email, code: code));
    final r = verifyResponder!();
    if (r.session != null) {
      session = r.session;
      user = r.user;
    }
    return r;
  }

  @override
  Future<void> resendEmailCode({required String email}) async {
    resendCalls.add(email);
    resendResponder?.call();
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

    test('unconfirmed account sends a fresh code and asks for it', () async {
      final fake = _FakeAuthClient();
      fake.signInResponder = () => throw const AuthException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed');

      final svc = AuthService(client: fake);
      final res = await svc.signIn(email: 'new@b.test', password: 'pw');
      expect(res, isA<AuthEmailConfirmationRequired>());
      expect((res as AuthEmailConfirmationRequired).email, 'new@b.test');
      expect(fake.resendCalls, ['new@b.test']);
      expect(svc.isSignedIn, isFalse);

      svc.dispose();
      fake.dispose();
    });

    test('unconfirmed account still asks for the code if the resend fails',
        () async {
      final fake = _FakeAuthClient();
      fake.signInResponder = () => throw const AuthException(
          'Email not confirmed',
          code: 'email_not_confirmed');
      fake.resendResponder = () => throw const AuthException(
          'For security purposes, you can only request this after 42 seconds.',
          code: 'over_email_send_rate_limit');

      final svc = AuthService(client: fake);
      final res = await svc.signIn(email: 'new@b.test', password: 'pw');
      expect(res, isA<AuthEmailConfirmationRequired>());

      svc.dispose();
      fake.dispose();
    });
  });

  group('AuthService.verifyEmailCode', () {
    test('a valid code signs in', () async {
      final fake = _FakeAuthClient();
      final u = _user('abc', 'a@b.test');
      fake.verifyResponder = () => AuthResponse(session: _session(u), user: u);

      final svc = AuthService(client: fake);
      var notified = 0;
      svc.addListener(() => notified++);
      final res = await svc.verifyEmailCode(email: 'a@b.test', code: ' 123 456 ');
      expect(res, isA<AuthSuccess>());
      expect(svc.isSignedIn, isTrue);
      expect(notified, greaterThan(0));
      expect(fake.verifyCalls.single, (email: 'a@b.test', code: '123456'));

      svc.dispose();
      fake.dispose();
    });

    test('a wrong or expired code gives a plain message', () async {
      final fake = _FakeAuthClient();
      fake.verifyResponder = () => throw const AuthException(
          'Token has expired or is invalid',
          statusCode: '403',
          code: 'otp_expired');

      final svc = AuthService(client: fake);
      final res = await svc.verifyEmailCode(email: 'a@b.test', code: '000000');
      expect(res, isA<AuthFailure>());
      expect((res as AuthFailure).message,
          contains('wrong or has expired'));
      expect(svc.isSignedIn, isFalse);

      svc.dispose();
      fake.dispose();
    });

    test('a response without a session is a failure', () async {
      final fake = _FakeAuthClient();
      final u = _user('abc', 'a@b.test');
      fake.verifyResponder = () => AuthResponse(user: u);

      final svc = AuthService(client: fake);
      final res = await svc.verifyEmailCode(email: 'a@b.test', code: '123456');
      expect(res, isA<AuthFailure>());
      expect(svc.isSignedIn, isFalse);

      svc.dispose();
      fake.dispose();
    });
  });

  group('AuthService.resendEmailCode', () {
    test('returns null when sent', () async {
      final fake = _FakeAuthClient();
      final svc = AuthService(client: fake);
      expect(await svc.resendEmailCode(email: 'a@b.test'), isNull);
      expect(fake.resendCalls, ['a@b.test']);

      svc.dispose();
      fake.dispose();
    });

    test('returns the server message when refused', () async {
      final fake = _FakeAuthClient();
      fake.resendResponder = () => throw const AuthException(
          'For security purposes, you can only request this after 42 seconds.',
          code: 'over_email_send_rate_limit');
      final svc = AuthService(client: fake);
      expect(await svc.resendEmailCode(email: 'a@b.test'),
          contains('after 42 seconds'));

      svc.dispose();
      fake.dispose();
    });
  });

  group('AuthService.signUp', () {
    test('an address that already has an account says so', () async {
      final fake = _FakeAuthClient();
      // Supabase's obfuscated reply for a confirmed address: a user with
      // no identities, no session, and no email sent.
      final u = User(
        id: 'fake',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        email: 'taken@b.test',
        createdAt: DateTime.now().toIso8601String(),
        identities: const [],
      );
      fake.signUpResponder = () => AuthResponse(user: u);

      final svc = AuthService(client: fake);
      final res = await svc.signUp(email: 'taken@b.test', password: 'pw');
      expect(res, isA<AuthFailure>());
      expect((res as AuthFailure).message, contains('already exists'));

      svc.dispose();
      fake.dispose();
    });

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
