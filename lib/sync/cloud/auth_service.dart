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

import 'owner_id_backfiller.dart';

export 'owner_id_backfiller.dart' show OwnerIdBackfiller;

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

/// Returned from [AuthService.signUp], and from [AuthService.signIn] for an
/// account that was never confirmed, when Supabase requires email
/// confirmation before issuing a session. The user finishes by entering
/// the emailed code in [AuthService.verifyEmailCode].
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

  /// Confirms a new account with the code from its "Confirm signup" email.
  /// Returns a session on success.
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
  });

  /// Sends a fresh "Confirm signup" email with a new code.
  Future<void> resendEmailCode({required String email});

  /// Sets the signed-in user's password.
  Future<void> setPassword(String password);

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
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
  }) =>
      _auth.verifyOTP(email: email, token: code, type: OtpType.signup);

  @override
  Future<void> resendEmailCode({required String email}) =>
      _auth.resend(email: email, type: OtpType.signup);

  @override
  Future<void> setPassword(String password) =>
      _auth.updateUser(UserAttributes(password: password));

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
      if (_isEmailNotConfirmed(e)) {
        // The account exists but was never confirmed. Send a fresh code so
        // the code step has one to check. If this send is refused (the
        // 60-second limit, say), the user can still press Resend code.
        await resendEmailCode(email: email);
        return AuthEmailConfirmationRequired(email);
      }
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
        // For an address that already has a confirmed account, Supabase
        // hides that fact: it returns a user with no identities and sends
        // no email. Say so instead of waiting for a code that never comes.
        if (res.user!.identities?.isEmpty ?? false) {
          return const AuthFailure(
              'An account with this email already exists. Sign in instead.');
        }
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

  /// Finishes sign-up with the code from the "Confirm signup" email and
  /// signs the user in.
  ///
  /// [password] is the one typed in the sign-in form. Supabase keeps the
  /// password from the first sign-up for an address that was never
  /// confirmed, so someone who signed up earlier with another person's
  /// address would still know the password once the owner confirms it.
  /// Setting it here means whoever proves they own the address chooses it.
  Future<AuthResult> verifyEmailCode({
    required String email,
    required String code,
    String? password,
  }) async {
    try {
      final res = await _client.verifyEmailCode(
        email: email,
        code: code.replaceAll(RegExp(r'\s'), ''),
      );
      final user = res.user;
      if (res.session == null || user == null) {
        return const AuthFailure(
            'That code did not sign you in. Ask for a new one with Resend code.');
      }
      if (password != null && password.isNotEmpty) {
        await _applyPassword(password);
      }
      await _runBackfill(user.id);
      notifyListeners();
      return AuthSuccess(user);
    } on AuthException catch (e) {
      if (e.code == 'otp_expired') {
        return const AuthFailure(
            'That code is wrong or has expired. If you already clicked the '
            'link in the email, press Back and sign in. Otherwise check the '
            'code, or ask for a new one with Resend code.');
      }
      return AuthFailure(e.message);
    } catch (e) {
      return AuthFailure(e.toString());
    }
  }

  /// Sends a new confirmation code. Returns null when sent, or a message
  /// to show when Supabase refused (for example within 60 seconds of the
  /// previous one).
  Future<String?> resendEmailCode({required String email}) async {
    try {
      await _client.resendEmailCode(email: email);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> _applyPassword(String password) async {
    try {
      await _client.setPassword(password);
    } on AuthException catch (e) {
      // `same_password` is the normal case: one person, one sign-up.
      if (e.code != 'same_password') {
        debugPrint('Setting the password after confirmation failed: $e');
      }
    } catch (e) {
      debugPrint('Setting the password after confirmation failed: $e');
    }
  }

  static bool _isEmailNotConfirmed(AuthException e) =>
      e.code == 'email_not_confirmed' ||
      e.message == 'Email not confirmed';

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

