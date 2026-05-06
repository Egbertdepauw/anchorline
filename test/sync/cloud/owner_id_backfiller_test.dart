import 'dart:async';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('counts null-owner rows across sync-eligible tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Two null-owner annotations.
    await db.customStatement('''
      INSERT INTO dive_annotations
        (dive_id, created_at, updated_at, version, sync_status)
      VALUES ('d1', $now, $now, 1, 0), ('d2', $now, $now, 1, 0)
    ''');
    // One null-owner cell.
    await db.customStatement('''
      INSERT INTO oxygen_cells
        (id, slot, created_at, updated_at, version, sync_status)
      VALUES ('c1', 1, $now, $now, 1, 0)
    ''');
    // One row that already has an owner — should not be counted.
    await db.customStatement('''
      INSERT INTO oxygen_cells
        (id, slot, created_at, updated_at, version, sync_status, owner_id)
      VALUES ('c2', 2, $now, $now, 1, 0, 'someone')
    ''');

    final backfiller = OwnerIdBackfiller(db);
    final n = await backfiller.backfillIfNeeded('uid-123');
    expect(n, 3);
  });

  test('AuthService.signIn invokes the backfiller and logs', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

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
      backfiller: OwnerIdBackfiller(db),
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
      logs.any((m) => m.contains('would stamp 3 rows')),
      isTrue,
      reason: 'expected total log; got: $logs',
    );
  });
}
