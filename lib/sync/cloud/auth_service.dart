/// Email/password authentication for cloud sync (Phase 2.1).
///
/// The app remains fully usable offline without sign-in. Authentication
/// is opt-in and gates only the cloud-sync layer that lands in Phase 2.2.
///
/// [AuthService] is a [ChangeNotifier] so the UI rebuilds on sign-in/out.
/// It talks to a thin [AuthClient] abstraction which in production wraps
/// the Supabase client; tests inject a fake.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a sign-in / sign-up attempt.
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  final User user;
  const AuthSuccess(this.user);
}

class AuthFailure extends AuthResult {
  final String message;
  const AuthFailure(this.message);
}

/// Returned from [AuthService.signUp] when Supabase is configured to
/// require email confirmation before issuing a session.
class AuthEmailConfirmationRequired extends AuthResult {
  final String email;
  const AuthEmailConfirmationRequired(this.email);
}

/// Thin abstraction over the parts of `supabase.auth` we use, so tests
/// can inject a fake without hitting the network.
abstract class AuthClient {
  User? get currentUser;
  Session? get currentSession;
  Stream<AuthState> get onAuthStateChange;

  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  });

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// Default [AuthClient] backed by the global Supabase client.
class SupabaseAuthClient implements AuthClient {
  final GoTrueClient _auth;

  SupabaseAuthClient([GoTrueClient? auth])
      : _auth = auth ?? Supabase.instance.client.auth;

  @override
  User? get currentUser => _auth.currentUser;

  @override
  Session? get currentSession => _auth.currentSession;

  @override
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) =>
      _auth.signInWithPassword(email: email, password: password);

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) =>
      _auth.signUp(email: email, password: password);

  @override
  Future<void> signOut() => _auth.signOut();
}

class AuthService extends ChangeNotifier {
  final AuthClient _client;
  final OwnerIdBackfiller? _backfiller;
  StreamSubscription<AuthState>? _sub;

  AuthService({AuthClient? client, OwnerIdBackfiller? backfiller})
      : _client = client ?? SupabaseAuthClient(),
        _backfiller = backfiller {
    _sub = _client.onAuthStateChange.listen((_) => notifyListeners());
  }

  User? get currentUser => _client.currentUser;
  Session? get currentSession => _client.currentSession;
  bool get isSignedIn => _client.currentSession != null;

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.signInWithPassword(
        email: email,
        password: password,
      );
      final user = res.user;
      if (user == null) {
        return const AuthFailure('Sign-in failed: no user returned');
      }
      await _runBackfill(user.id);
      notifyListeners();
      return AuthSuccess(user);
    } on AuthException catch (e) {
      return AuthFailure(e.message);
    } catch (e) {
      return AuthFailure(e.toString());
    }
  }

  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.signUp(email: email, password: password);
      // Supabase returns user-without-session when email confirmation is on.
      if (res.session == null && res.user != null) {
        return AuthEmailConfirmationRequired(email);
      }
      final user = res.user;
      if (user == null) {
        return const AuthFailure('Sign-up failed: no user returned');
      }
      await _runBackfill(user.id);
      notifyListeners();
      return AuthSuccess(user);
    } on AuthException catch (e) {
      return AuthFailure(e.message);
    } catch (e) {
      return AuthFailure(e.toString());
    }
  }

  Future<void> signOut() async {
    await _client.signOut();
    notifyListeners();
  }

  Future<void> _runBackfill(String userId) async {
    final b = _backfiller;
    if (b == null) return;
    try {
      final n = await b.backfillIfNeeded(userId);
      debugPrint('OwnerIdBackfiller: $n rows would be stamped for $userId');
    } catch (e, st) {
      debugPrint('OwnerIdBackfiller failed: $e\n$st');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Stamps `owner_id` on rows that lack one after a user signs in for the
/// first time. Phase 2.1 only counts and logs — actual writing is wired
/// up in Phase 2.2 once PowerSync is live.
class OwnerIdBackfiller {
  Future<int> backfillIfNeeded(String userId) async => 0;
}
