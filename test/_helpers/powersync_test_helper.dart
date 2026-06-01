/// Test helper for opening a real [PowerSyncDatabase] backed by a tmpdir
/// SQLite file. PowerSync's native open factory does not accept `:memory:`
/// — it loads its sync extension into a real on-disk file — so each test
/// gets its own temp directory that is cleaned up on tear-down.
library;

import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
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
  @override
  Future<void> refreshSession() async {}
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

/// Convenience: build an [EquipmentDao] wired to fresh Drift + PowerSync
/// instances, with a [FakeSessionSource] (signed-in test user by default
/// so `owner_id` gets stamped on writes).
Future<EquipmentDaoTestRig> openEquipmentDaoForTest(AppDatabase drift) async {
  final ps = await openPowerSyncForTest();
  final session = FakeSessionSource()..setUserId('test-user');
  final dao = EquipmentDao(drift, ps, session);
  return EquipmentDaoTestRig(dao: dao, ps: ps, session: session);
}

class EquipmentDaoTestRig {
  final EquipmentDao dao;
  final PowerSyncDatabase ps;
  final FakeSessionSource session;
  EquipmentDaoTestRig({
    required this.dao,
    required this.ps,
    required this.session,
  });
}

/// Convenience: build a [DiveDao] wired to fresh Drift + PowerSync
/// instances, with a [FakeSessionSource] (signed-in test user by default).
Future<DiveDaoTestRig> openDiveDaoForTest(AppDatabase drift) async {
  final ps = await openPowerSyncForTest();
  final session = FakeSessionSource()..setUserId('test-user');
  final dao = DiveDao(drift, ps, session);
  return DiveDaoTestRig(dao: dao, ps: ps, session: session);
}

class DiveDaoTestRig {
  final DiveDao dao;
  final PowerSyncDatabase ps;
  final FakeSessionSource session;
  DiveDaoTestRig({
    required this.dao,
    required this.ps,
    required this.session,
  });
}

Future<DiveMergeDaoTestRig> openDiveMergeDaoForTest(AppDatabase drift) async {
  final ps = await openPowerSyncForTest();
  final session = FakeSessionSource()..setUserId('test-user');
  final dao = DiveMergeDao(drift, ps, session);
  return DiveMergeDaoTestRig(dao: dao, ps: ps, session: session);
}

class DiveMergeDaoTestRig {
  final DiveMergeDao dao;
  final PowerSyncDatabase ps;
  final FakeSessionSource session;
  DiveMergeDaoTestRig({
    required this.dao,
    required this.ps,
    required this.session,
  });
}
