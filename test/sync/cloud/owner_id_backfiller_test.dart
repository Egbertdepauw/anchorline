import 'dart:async';
import 'dart:convert';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../_helpers/powersync_test_helper.dart';

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

User _user(String id, String email) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('copies sync-eligible rows from Drift into PowerSync stamped with userId', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Two annotations + one cell — three rows total.
    await db.customStatement('''
      INSERT INTO dive_annotations
        (dive_id, created_at, updated_at, version, sync_status)
      VALUES ('d1', $now, $now, 1, 0), ('d2', $now, $now, 1, 0)
    ''');
    await db.customStatement('''
      INSERT INTO oxygen_cells
        (id, slot, created_at, updated_at, version, sync_status)
      VALUES ('c1', 1, $now, $now, 1, 0)
    ''');

    final backfiller = OwnerIdBackfiller(db, ps);
    final n = await backfiller.backfillIfNeeded('uid-123');
    expect(n, 3);

    // Verify the rows landed in PowerSync with the correct owner_id.
    final psAnnotations = await ps.getAll('SELECT id, owner_id FROM dive_annotations');
    expect(psAnnotations, hasLength(2));
    expect(psAnnotations.every((r) => r['owner_id'] == 'uid-123'), isTrue);

    final psCells = await ps.getAll('SELECT id, owner_id FROM oxygen_cells');
    expect(psCells, hasLength(1));
    expect(psCells.single['owner_id'], 'uid-123');
  });

  test('is idempotent: a second run copies zero rows', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement('''
      INSERT INTO oxygen_cells
        (id, slot, created_at, updated_at, version, sync_status)
      VALUES ('c1', 1, $now, $now, 1, 0)
    ''');

    final backfiller = OwnerIdBackfiller(db, ps);
    expect(await backfiller.backfillIfNeeded('uid'), 1);
    expect(await backfiller.backfillIfNeeded('uid'), 0);
  });

  test(
      'stamps owner_id on every synced table whose rows lack it '
      '(simulating pre-sign-in writes)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Pre-sign-in writes: every synced PowerSync table has at least one
    // row with NULL owner_id. PowerSync's CRUD trigger queues a PUT for
    // each — those queue entries omit the null owner_id field.
    await ps.execute(
      'INSERT INTO dive_computers '
      '(id, owner_id, serial, model, created_at, updated_at, version, '
      'sync_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['dc1', null, 12345, 1, now, now, 1, 0],
    );
    await ps.execute(
      'INSERT INTO oxygen_cells (id, owner_id, slot, created_at, '
      'updated_at, version, sync_status) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ['c1', null, 1, now, now, 1, 0],
    );
    await ps.execute(
      'INSERT INTO dives (id, owner_id, dc_serial, dc_dive_number, '
      'start_time, end_time, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['d1', null, 12345, 1, now, now + 60, 1, 0],
    );

    final n =
        await OwnerIdBackfiller(db, ps).backfillIfNeeded('uid-123');

    // The three pre-existing rows now carry the correct owner_id.
    final dc = await ps.getAll('SELECT owner_id FROM dive_computers');
    expect(dc.single['owner_id'], 'uid-123');
    final cells = await ps.getAll('SELECT owner_id FROM oxygen_cells');
    expect(cells.single['owner_id'], 'uid-123');
    final dives = await ps.getAll('SELECT owner_id FROM dives');
    expect(dives.single['owner_id'], 'uid-123');
    expect(n, greaterThanOrEqualTo(3));
  });

  test(
      'claims a gas analysis saved while signed out, so the analysis log '
      'shows it after sign-in (#149)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();

    final session = FakeSessionSource();
    final dao = GasAnalysesDao(ps, session);
    await dao.add(NewGasAnalysis(
      analysedAt: DateTime.utc(2026, 11, 3, 9),
      o2Percent: 32.0,
      hePercent: 0.0,
      stable: true,
    ));

    // Signed in, the log filters on owner_id, so the NULL-owner row is
    // hidden until something claims it.
    session.setUserId('uid-123');
    expect(await dao.list(), isEmpty);

    await OwnerIdBackfiller(db, ps).backfillIfNeeded('uid-123');

    final rows = await ps.getAll('SELECT owner_id FROM gas_analyses');
    expect(rows.single['owner_id'], 'uid-123');
    expect(await dao.list(), hasLength(1));
  });

  // Same gap as gas_analyses (#149): these tables hold an owner_id column
  // that RLS checks, are written with the session's user id (NULL when
  // signed out), and were never listed in the backfiller.
  const signedOutRows = {
    'dive_plans': 'INSERT INTO dive_plans '
        '(id, owner_id, name, mode, created_at, updated_at, version, '
        'sync_status) VALUES (?, NULL, NULL, ?, ?, ?, 1, 0)',
    'dive_bailout_carry': 'INSERT INTO dive_bailout_carry '
        '(id, owner_id, dive_id, cylinder_id, created_at, updated_at, '
        'version, sync_status) VALUES (?, NULL, ?, ?, ?, ?, 1, 0)',
    'dive_merge_links': 'INSERT INTO dive_merge_links '
        '(id, owner_id, group_id, created_at, updated_at, version, '
        'sync_status) VALUES (?, NULL, ?, ?, ?, 1, 0)',
  };
  for (final entry in signedOutRows.entries) {
    test('stamps owner_id on ${entry.key} rows written while signed out (#149)',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ps = await openPowerSyncForTest();

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final args = switch (entry.key) {
        'dive_plans' => ['row1', 'ccr', now, now],
        'dive_bailout_carry' => ['d1:cyl1', 'd1', 'cyl1', now, now],
        _ => ['d1', 'group1', now, now],
      };
      await ps.execute(entry.value, args);

      await OwnerIdBackfiller(db, ps).backfillIfNeeded('uid-123');

      final rows = await ps.getAll('SELECT owner_id FROM ${entry.key}');
      expect(rows.single['owner_id'], 'uid-123');
    });
  }

  test(
      'rewrites already-queued ps_crud PUT payloads to inject owner_id, '
      'so RLS upserts stop failing after sign-in', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await ps.execute(
      'INSERT INTO dive_computers '
      '(id, owner_id, serial, model, created_at, updated_at, version, '
      'sync_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      ['dc1', null, 12345, 1, now, now, 1, 0],
    );

    // Sanity: PowerSync's trigger queued a PUT op, and the data payload
    // does not carry owner_id (null columns are omitted from the JSON).
    final crudBefore =
        await ps.getAll("SELECT data FROM ps_crud ORDER BY id");
    expect(crudBefore, isNotEmpty);
    final dcPutBefore = crudBefore
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .firstWhere((m) => m['type'] == 'dive_computers' && m['op'] == 'PUT');
    expect((dcPutBefore['data'] as Map).containsKey('owner_id'), isFalse);

    await OwnerIdBackfiller(db, ps).backfillIfNeeded('uid-123');

    // After backfill, the queued PUT now carries owner_id = uid-123.
    final crudAfter = await ps.getAll("SELECT data FROM ps_crud ORDER BY id");
    final dcPutAfter = crudAfter
        .map((r) => jsonDecode(r['data'] as String) as Map<String, dynamic>)
        .firstWhere((m) => m['type'] == 'dive_computers' && m['op'] == 'PUT');
    expect((dcPutAfter['data'] as Map)['owner_id'], 'uid-123');
  });

  test('AuthService.signIn invokes the backfiller and logs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement('''
      INSERT INTO dive_annotations
        (dive_id, created_at, updated_at, version, sync_status)
      VALUES ('d1', $now, $now, 1, 0), ('d2', $now, $now, 1, 0)
    ''');
    await db.customStatement('''
      INSERT INTO oxygen_cells
        (id, slot, created_at, updated_at, version, sync_status)
      VALUES ('c1', 1, $now, $now, 1, 0)
    ''');

    final fake = _FakeAuthClient();
    final u = _user('uid-123', 'me@test.test');
    fake.signInResponder = () => AuthResponse(
          session: Session(accessToken: 't', tokenType: 'bearer', user: u),
          user: u,
        );

    final svc = AuthService(
      client: fake,
      backfiller: OwnerIdBackfiller(db, ps),
    );
    addTearDown(() {
      svc.dispose();
      fake.dispose();
    });

    final logs = <String>[];
    final prevPrint = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      if (msg != null) logs.add(msg);
    };
    try {
      final res = await svc.signIn(email: 'me@test.test', password: 'pw');
      expect(res, isA<AuthSuccess>());
    } finally {
      debugPrint = prevPrint;
    }

    expect(
      logs.any((m) => m.contains('copied 3 rows')),
      isTrue,
      reason: 'expected backfill log; got: $logs',
    );
  });
}
