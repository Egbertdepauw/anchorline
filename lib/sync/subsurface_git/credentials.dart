/// Credentials store for the Subsurface Cloud git remote.
///
/// Subsurface Cloud uses HTTP basic auth — username = email, password =
/// the same string the user types into Subsurface's "Cloud Storage" panel.
/// We persist it via [flutter_secure_storage] so the OS keychain (Keychain
/// on Apple, Keystore on Android, libsecret on Linux, DPAPI on Windows)
/// guards the secret rather than our own SQLite/SharedPreferences.
///
/// The interface is split off ([SubsurfaceCredentialsSource]) so tests and
/// the Phase D orchestrator can swap in fakes without booting the
/// platform plugin. The concrete implementation
/// ([SecureStorageSubsurfaceCredentials]) is the production path; in
/// tests we use an in-memory fake of `FlutterSecureStorage` and
/// construct the production class against that.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Read/write/delete contract for the user's Subsurface Cloud credentials.
///
/// Returns `null` from [read] when the user has never saved credentials
/// (or after [clear]). Implementations MUST round-trip the email/password
/// pair byte-exact — Subsurface Cloud's auth is case-sensitive and
/// trims nothing.
abstract class SubsurfaceCredentialsSource {
  /// Returns the stored email/password pair, or null if none was saved.
  Future<({String email, String password})?> read();

  /// Persists [email]/[password]. Overwrites any existing values.
  Future<void> save(String email, String password);

  /// Removes any stored credentials. Idempotent — calling on an empty
  /// store is not an error.
  Future<void> clear();
}

/// Minimal key/value-store seam for [SecureStorageSubsurfaceCredentials].
/// Production wraps [FlutterSecureStorage]; tests pass a Map-backed
/// in-memory implementation. Going through this seam means the
/// credentials test never has to import `flutter_secure_storage`'s
/// platform-interface package (which isn't a direct dependency).
abstract class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Default [SecureKeyValueStore] that delegates to a real
/// [FlutterSecureStorage]. The OS-keychain options are intentionally
/// left at their library defaults — Subsurface Cloud creds aren't more
/// sensitive than other auth tokens we already keep there.
class FlutterSecureStorageKeyValueStore implements SecureKeyValueStore {
  FlutterSecureStorageKeyValueStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Production [SubsurfaceCredentialsSource] backed by
/// [FlutterSecureStorage] (or an injected [SecureKeyValueStore] in
/// tests). Two keys are used: `subsurface_email` and
/// `subsurface_password`.
class SecureStorageSubsurfaceCredentials implements SubsurfaceCredentialsSource {
  /// Storage key for the email (Subsurface basic-auth username).
  static const String emailKey = 'subsurface_email';

  /// Storage key for the password.
  static const String passwordKey = 'subsurface_password';

  /// Default-constructs against the platform secure storage. Pass
  /// [store] in tests to swap the backing store for an in-memory fake.
  SecureStorageSubsurfaceCredentials({SecureKeyValueStore? store})
      : _store = store ?? FlutterSecureStorageKeyValueStore();

  final SecureKeyValueStore _store;

  @override
  Future<({String email, String password})?> read() async {
    final email = await _store.read(emailKey);
    final password = await _store.read(passwordKey);
    if (email == null || password == null) return null;
    if (email.isEmpty || password.isEmpty) return null;
    return (email: email, password: password);
  }

  @override
  Future<void> save(String email, String password) async {
    await _store.write(emailKey, email);
    await _store.write(passwordKey, password);
  }

  @override
  Future<void> clear() async {
    await _store.delete(emailKey);
    await _store.delete(passwordKey);
  }
}
