// Round-trip tests for SecureStorageSubsurfaceCredentials.
//
// We swap the backing store for an in-memory map via the
// [SecureKeyValueStore] seam, so these tests don't touch the platform
// keychain plugin. (Whether the keychain plugin itself works is an
// integration concern, not a unit-test concern.)

import 'package:ccrlogger/sync/subsurface_git/credentials.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

void main() {
  late _FakeKeyValueStore fake;
  late SecureStorageSubsurfaceCredentials creds;

  setUp(() {
    fake = _FakeKeyValueStore();
    creds = SecureStorageSubsurfaceCredentials(store: fake);
  });

  test('read returns null when nothing is stored', () async {
    expect(await creds.read(), isNull);
  });

  test('save then read round-trips email + password', () async {
    await creds.save('diver@example.com', 'hunter2');
    final out = await creds.read();
    expect(out, isNotNull);
    expect(out!.email, 'diver@example.com');
    expect(out.password, 'hunter2');
  });

  test('save preserves email and password byte-exactly (case + spaces)',
      () async {
    // Subsurface Cloud's auth is case-sensitive; round-tripping must
    // not normalize anything.
    const email = 'Diver+Tag@Example.COM';
    const password = '  pass with spaces and üñîçødé  ';
    await creds.save(email, password);
    final out = await creds.read();
    expect(out!.email, email);
    expect(out.password, password);
  });

  test('save overwrites previously stored values', () async {
    await creds.save('first@example.com', 'first-pw');
    await creds.save('second@example.com', 'second-pw');
    final out = await creds.read();
    expect(out!.email, 'second@example.com');
    expect(out.password, 'second-pw');
  });

  test('clear deletes both keys', () async {
    await creds.save('diver@example.com', 'hunter2');
    await creds.clear();
    expect(await creds.read(), isNull);
    expect(fake.data, isEmpty);
  });

  test('clear is idempotent on an empty store', () async {
    await creds.clear();
    await creds.clear();
    expect(await creds.read(), isNull);
  });

  test('read returns null when only the email is set', () async {
    // Defensive: the store could be in a half-written state if the
    // process died between writes. We treat that as "no creds".
    await fake.write(SecureStorageSubsurfaceCredentials.emailKey,
        'diver@example.com');
    expect(await creds.read(), isNull);
  });

  test('read returns null when password is empty string', () async {
    // Some keychains return '' instead of null for cleared values; treat
    // empty as "no creds" so the orchestrator surfaces the auth prompt
    // rather than sending blank credentials to the server.
    await creds.save('diver@example.com', '');
    expect(await creds.read(), isNull);
  });

  test('uses the documented storage keys', () async {
    await creds.save('a@b.com', 'pw');
    expect(fake.data.keys, containsAll(<String>[
      SecureStorageSubsurfaceCredentials.emailKey,
      SecureStorageSubsurfaceCredentials.passwordKey,
    ]));
  });
}
