/// Test helper for opening a real [PowerSyncDatabase] backed by a tmpdir
/// SQLite file. PowerSync's native open factory does not accept `:memory:`
/// — it loads its sync extension into a real on-disk file — so each test
/// gets its own temp directory that is cleaned up on tear-down.
library;

import 'dart:io';

import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart'
    show SessionSource;
import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session, User;

/// In-memory [SessionSource] for tests; defaults to "no session".
class FakeSessionSource implements SessionSource {
  Session? _session;
  FakeSessionSource([this._session]);

  void setUserId(String userId, {String email = 'test@test.test'}) {
    final user = User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );
    _session = Session(accessToken: 't', tokenType: 'bearer', user: user);
  }

  void clear() => _session = null;

  @override
  Session? get currentSession => _session;
}

/// Opens a fresh PowerSync database in a unique tmpdir and registers
/// teardown via [addTearDown] so callers don't have to clean up manually.
Future<PowerSyncDatabase> openPowerSyncForTest() async {
  final tmpDir = await Directory.systemTemp.createTemp('ccrlogger_psync_');
  final db = PowerSyncDatabase(
    schema: appSchema,
    path: p.join(tmpDir.path, 'powersync.db'),
  );
  await db.initialize();
  addTearDown(() async {
    await db.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });
  return db;
}
