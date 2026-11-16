import 'dart:convert';

import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds a minimally-valid JWT whose payload carries the given `exp`
/// (unix seconds). Session.expiresAt parses the access token's `exp`
/// claim, so this is the simplest way to make a Session that looks
/// like it expires at a chosen moment.
String _jwt({required int exp}) {
  String b64url(Map<String, Object?> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = b64url({'alg': 'HS256', 'typ': 'JWT'});
  final payload = b64url({'exp': exp, 'iat': exp - 3600, 'sub': 'uid'});
  return '$header.$payload.fake-signature';
}

class _FakeSessions implements SessionSource {
  Session? session;
  int refreshCount = 0;
  Object? refreshThrows;
  Session? refreshTo;

  @override
  Session? get currentSession => session;

  @override
  Future<void> refreshSession() async {
    refreshCount++;
    if (refreshThrows != null) throw refreshThrows!;
    if (refreshTo != null) session = refreshTo;
  }
}

sealed class _Call {
  const _Call();
}

class _Upsert extends _Call {
  final String table;
  final Map<String, dynamic> data;
  const _Upsert(this.table, this.data);
}

class _Update extends _Call {
  final String table;
  final String id;
  final Map<String, dynamic> data;
  const _Update(this.table, this.id, this.data);
}

class _Delete extends _Call {
  final String table;
  final String id;
  const _Delete(this.table, this.id);
}

class _RecordingUploader implements SupabaseRestUploader {
  final List<_Call> calls = [];

  @override
  Future<void> upsert(String table, Map<String, dynamic> data) async {
    calls.add(_Upsert(table, data));
  }

  @override
  Future<void> update(String table, String id, Map<String, dynamic> data) async {
    calls.add(_Update(table, id, data));
  }

  @override
  Future<void> delete(String table, String id) async {
    calls.add(_Delete(table, id));
  }
}

User _user(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

void main() {
  group('fetchCredentials', () {
    test('returns null when not signed in', () async {
      final sessions = _FakeSessions();
      final uploader = _RecordingUploader();
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: uploader,
      );

      expect(await connector.fetchCredentials(), isNull);
    });

    test('returns credentials carrying the access token when signed in',
        () async {
      final sessions = _FakeSessions()
        ..session = Session(
          accessToken: 'access-123',
          tokenType: 'bearer',
          user: _user('uid'),
        );
      final uploader = _RecordingUploader();
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: uploader,
        endpoint: 'https://example.powersync.invalid',
      );

      final creds = await connector.fetchCredentials();
      expect(creds, isNotNull);
      expect(creds!.token, 'access-123');
      expect(creds.endpoint, 'https://example.powersync.invalid');
    });

    test('refreshes proactively when token expires within 5 minutes',
        () async {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final sessions = _FakeSessions()
        ..session = Session(
          accessToken: _jwt(exp: nowSec + 120), // 2 min until expiry
          tokenType: 'bearer',
          user: _user('uid'),
        )
        ..refreshTo = Session(
          accessToken: _jwt(exp: nowSec + 3600), // fresh 1 h token
          tokenType: 'bearer',
          user: _user('uid'),
        );
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: _RecordingUploader(),
      );

      final creds = await connector.fetchCredentials();
      expect(sessions.refreshCount, 1,
          reason: 'should refresh when expiry is within the lead-time window');
      expect(creds, isNotNull);
      expect(creds!.token, sessions.session!.accessToken,
          reason: 'must hand PowerSync the refreshed token, not the old one');
    });

    test('does not refresh when token has plenty of time left', () async {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final sessions = _FakeSessions()
        ..session = Session(
          accessToken: _jwt(exp: nowSec + 3600), // 1 h until expiry
          tokenType: 'bearer',
          user: _user('uid'),
        );
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: _RecordingUploader(),
      );

      final creds = await connector.fetchCredentials();
      expect(sessions.refreshCount, 0);
      expect(creds, isNotNull);
    });

    test('returns null when refresh fails and token is already expired',
        () async {
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final sessions = _FakeSessions()
        ..session = Session(
          accessToken: _jwt(exp: nowSec - 60), // expired a minute ago
          tokenType: 'bearer',
          user: _user('uid'),
        )
        ..refreshThrows = Exception('refresh token revoked');
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: _RecordingUploader(),
      );

      final creds = await connector.fetchCredentials();
      expect(sessions.refreshCount, 1);
      expect(creds, isNull,
          reason:
              'returning the expired token would loop PowerSync forever; '
              'null signals "disconnected, retry later" instead');
    });

    test(
        'returns null when refresh succeeds but the new session is still '
        'past expiry',
        () async {
      // Edge case: refresh returns success but the Supabase server gave us
      // back a still-expired token (clock skew, replay protection, etc).
      // We still must not pass it to PowerSync.
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final sessions = _FakeSessions()
        ..session = Session(
          accessToken: _jwt(exp: nowSec - 60),
          tokenType: 'bearer',
          user: _user('uid'),
        )
        ..refreshTo = Session(
          accessToken: _jwt(exp: nowSec - 30), // still expired
          tokenType: 'bearer',
          user: _user('uid'),
        );
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: _RecordingUploader(),
      );

      final creds = await connector.fetchCredentials();
      expect(sessions.refreshCount, 1);
      expect(creds, isNull);
    });
  });

  group('replayCrud', () {
    late _RecordingUploader uploader;
    late CcrloggerBackendConnector connector;

    setUp(() {
      uploader = _RecordingUploader();
      connector = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: uploader,
      );
    });

    test('PUT becomes upsert with id merged into the data', () async {
      final entries = [
        CrudEntry(1, UpdateType.put, 'cylinders', 'cyl-1', null,
            {'label': 'Bailout 1', 'volume_liters': 11.1}),
      ];
      await connector.replayCrud(entries);

      expect(uploader.calls, hasLength(1));
      final call = uploader.calls.single as _Upsert;
      expect(call.table, 'cylinders');
      expect(call.data, {
        'label': 'Bailout 1',
        'volume_liters': 11.1,
        'id': 'cyl-1',
      });
    });

    test('PATCH becomes update with the id filter', () async {
      final entries = [
        CrudEntry(2, UpdateType.patch, 'dive_annotations', 'd1', null,
            {'rating': 4}),
      ];
      await connector.replayCrud(entries);

      expect(uploader.calls, hasLength(1));
      final call = uploader.calls.single as _Update;
      expect(call.table, 'dive_annotations');
      expect(call.id, 'd1');
      expect(call.data, {'rating': 4});
    });

    test('DELETE becomes delete with the id filter', () async {
      final entries = [
        CrudEntry(3, UpdateType.delete, 'oxygen_cells', 'cell-9', null, null),
      ];
      await connector.replayCrud(entries);

      expect(uploader.calls, hasLength(1));
      final call = uploader.calls.single as _Delete;
      expect(call.table, 'oxygen_cells');
      expect(call.id, 'cell-9');
    });

    test('preserves insertion order across mixed ops', () async {
      final entries = [
        CrudEntry(1, UpdateType.put, 't', 'a', null, {'x': 1}),
        CrudEntry(2, UpdateType.delete, 't', 'b', null, null),
        CrudEntry(3, UpdateType.patch, 't', 'c', null, {'y': 2}),
      ];
      await connector.replayCrud(entries);

      expect(uploader.calls, hasLength(3));
      expect(uploader.calls[0], isA<_Upsert>());
      expect(uploader.calls[1], isA<_Delete>());
      expect(uploader.calls[2], isA<_Update>());
    });

    test('PATCH with null opData is skipped (no rest call)', () async {
      final entries = [
        CrudEntry(4, UpdateType.patch, 't', 'd', null, null),
      ];
      await connector.replayCrud(entries);
      expect(uploader.calls, isEmpty);
    });

    test('a rejected op is rethrown as a CrudUploadException naming it', () async {
      // The "poison op" of issue #2: one op the backend rejects. The error
      // must identify table/id/op so a stalled queue is diagnosable.
      final throwing = _ThrowingUploader(failTable: 'dive_samples');
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: throwing,
      );
      final entries = [
        CrudEntry(10, UpdateType.put, 'dives', 'dive-1', null, {'x': 1}),
        CrudEntry(11, UpdateType.put, 'dive_samples', 'dive-1', null, {'b': 1}),
      ];

      Object? caught;
      try {
        await c.replayCrud(entries);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<CrudUploadException>());
      final ex = caught as CrudUploadException;
      expect(ex.op.table, 'dive_samples');
      expect(ex.op.id, 'dive-1');
      expect(ex.cause, isA<StateError>());
      // The string form names the op (what lands in status.uploadError).
      expect(ex.toString(), contains('dive_samples'));
      expect(ex.toString(), contains('id=dive-1'));
      // The first (valid) op uploaded before the poison op threw.
      expect(throwing.upserted, ['dives']);
    });

    test('FK 23503 on a dive-child op self-heals by upserting the parent',
        () async {
      // Issue #2 orphaned-parent case: a dive_bailout_carry op fails FK because
      // its parent dive isn't in the cloud. The connector re-uploads the
      // parent(s) from local and retries — instead of wedging the queue.
      final up = _FkPoisonUploader(failTable: 'dive_bailout_carry', failTimes: 1);
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
      );
      final op = CrudEntry(20, UpdateType.put, 'dive_bailout_carry',
          'dive-x:cyl-1', null,
          {'dive_id': 'dive-x', 'cylinder_id': 'cyl-1', 'gas_mix': '21/35'});

      await c.replayCrud([op], fetchLocalRow: (table, id) async {
        if (table == 'dives' && id == 'dive-x') {
          return {'id': 'dive-x', 'dc_serial': 1, 'owner_id': 'u'};
        }
        if (table == 'cylinders' && id == 'cyl-1') {
          return {'id': 'cyl-1', 'label': 'AL40'};
        }
        return null;
      });

      // Parents uploaded from local, then the child op retried successfully.
      expect(up.upserted, containsAll(['dives', 'cylinders']));
      expect(up.upserted.where((t) => t == 'dive_bailout_carry').length, 1);
    });

    test('FK 23503 drops the op when a required parent is missing locally too',
        () async {
      // Issue #2, Part 3: a dive_bailout_carry op references a dive that exists
      // in no layer (deleted/re-hashed, never cascaded). The parent can't be
      // healed, so the op can NEVER upload — it must be dropped, not thrown, or
      // it wedges the FIFO queue forever.
      final up = _FkPoisonUploader(failTable: 'dive_bailout_carry', failTimes: 99);
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
      );
      final op = CrudEntry(21, UpdateType.put, 'dive_bailout_carry', 'd:c',
          null, {'dive_id': 'd', 'cylinder_id': 'c'});
      // No parent exists locally → does not throw; the op is dropped.
      await c.replayCrud([op], fetchLocalRow: (_, _) async => null);
      expect(up.upserted, isEmpty);
    });

    test('a dropped orphan op does not block good ops behind it', () async {
      // The whole point: the poison op at the head of the queue is skipped and
      // the ops behind it still apply, so batch.complete() drains everything.
      final up = _FkPoisonUploader(failTable: 'dive_bailout_carry', failTimes: 99);
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
      );
      final entries = [
        CrudEntry(30, UpdateType.put, 'dive_bailout_carry', 'ghost:c', null,
            {'dive_id': 'ghost', 'cylinder_id': 'c'}),
        CrudEntry(31, UpdateType.patch, 'dives', 'real-dive', null, {'version': 2}),
      ];
      await c.replayCrud(entries, fetchLocalRow: (_, _) async => null);
      // Orphan PUT dropped (no upsert), the dives PATCH still went through.
      expect(up.upserted, isEmpty);
      expect(up.updated, contains('dives'));
    });

    // ── Issue #2 Part 2: permanent-error quarantine ─────────────────────
    // A permanently-rejected op (e.g. an oversized dive_samples blob, or a
    // constraint violation) must NOT wedge the FIFO queue forever. Quarantine
    // it (record + skip) so the ops behind it drain and batch.complete()
    // clears the poison op. Transient errors must still rethrow so PowerSync
    // retries rather than silently dropping recoverable data.

    test('a permanent PostgrestException quarantines the op, drains the rest',
        () async {
      final q = _RecordingQuarantine();
      final up = _CodePoisonUploader(failTable: 'dive_samples', code: '22001');
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
        quarantine: q,
      );
      final entries = [
        CrudEntry(40, UpdateType.put, 'dive_samples', 'dive-1', null, {'b': 1}),
        CrudEntry(41, UpdateType.put, 'dives', 'dive-2', null, {'x': 1}),
      ];

      // Must not throw — the poison op is quarantined, not rethrown.
      await c.replayCrud(entries);

      expect(q.records.map((e) => e.id), ['dive-1'],
          reason: 'the permanent op is quarantined');
      expect(up.upserted, ['dives'],
          reason: 'the op behind the poison one still uploaded');
    });

    test('an oversized-body (HTTP 413) op is treated as permanent', () async {
      final q = _RecordingQuarantine();
      final up = _CodePoisonUploader(failTable: 'dive_samples', code: '413');
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
        quarantine: q,
      );
      await c.replayCrud([
        CrudEntry(42, UpdateType.put, 'dive_samples', 'dive-9', null, {'b': 1}),
      ]);
      expect(q.records.single.table, 'dive_samples');
    });

    test('a transient error is rethrown to retry, not quarantined', () async {
      final q = _RecordingQuarantine();
      // 503 Service Unavailable — transient; retrying later should succeed.
      final up = _CodePoisonUploader(failTable: 'dives', code: '503');
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
        quarantine: q,
      );

      Object? caught;
      try {
        await c.replayCrud(
            [CrudEntry(43, UpdateType.put, 'dives', 'd', null, {'x': 1})]);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<CrudUploadException>(),
          reason: 'transient errors rethrow so PowerSync retries the batch');
      expect(q.records, isEmpty,
          reason: 'must not quarantine recoverable data');
    });

    test('an unknown (non-Postgrest) error is treated as transient', () async {
      // Conservative: anything we cannot positively classify as a permanent
      // backend rejection is retried, never dropped.
      final q = _RecordingQuarantine();
      final up = _ThrowingUploader(failTable: 'dives');
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions(),
        uploader: up,
        quarantine: q,
      );
      Object? caught;
      try {
        await c.replayCrud(
            [CrudEntry(44, UpdateType.put, 'dives', 'd', null, {'x': 1})]);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<CrudUploadException>());
      expect(q.records, isEmpty);
    });

    // ── Account switch ─────────────────────────────────────────────────
    // Signing out keeps the upload queue. A PUT the previous account queued
    // carries that account's owner_id: RLS rejects it for the new account
    // (42501, which is retried), so sent as-is it would block the queue
    // forever. It is quarantined instead, and never re-owned.

    test('a PUT another account queued is quarantined, not uploaded',
        () async {
      final q = _RecordingQuarantine();
      final up = _RecordingUploader();
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions()..session = _sessionFor('uid-b'),
        uploader: up,
        quarantine: q,
      );

      await c.replayCrud([
        CrudEntry(50, UpdateType.put, 'dives', 'dive-a', null,
            {'owner_id': 'uid-a', 'x': 1}),
        CrudEntry(51, UpdateType.put, 'dives', 'dive-b', null,
            {'owner_id': 'uid-b', 'x': 2}),
      ]);

      expect(q.records.map((e) => e.id), ['dive-a']);
      expect(up.calls.whereType<_Upsert>().map((u) => u.data['id']),
          ['dive-b'],
          reason: 'the op behind it still uploads');
    });

    test('an ownerless PUT is still uploaded, for the sign-in claim to fix',
        () async {
      final q = _RecordingQuarantine();
      final up = _RecordingUploader();
      final c = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions()..session = _sessionFor('uid-b'),
        uploader: up,
        quarantine: q,
      );

      await c.replayCrud(
          [CrudEntry(52, UpdateType.put, 'dives', 'dive-c', null, {'x': 1})]);

      expect(q.records, isEmpty);
      expect(up.calls.whereType<_Upsert>().map((u) => u.data['id']),
          ['dive-c']);
    });

    // A PATCH carries no owner; the owner is on its local row, which still
    // names the previous account while that account's ops wait in the queue.

    group('PATCH of another account\'s row', () {
      late _RecordingQuarantine q;
      late _RecordingUploader up;
      late List<(String, String)> lookups;

      CcrloggerBackendConnector connector({
        String? signedIn = 'uid-b',
      }) {
        final sessions = _FakeSessions();
        if (signedIn != null) sessions.session = _sessionFor(signedIn);
        return CcrloggerBackendConnector.forTesting(
          sessions: sessions,
          uploader: up,
          quarantine: q,
        );
      }

      Future<Map<String, dynamic>?> Function(String, String) localRows(
          Map<(String, String), Map<String, dynamic>> rows) {
        return (table, id) async {
          lookups.add((table, id));
          return rows[(table, id)];
        };
      }

      setUp(() {
        q = _RecordingQuarantine();
        up = _RecordingUploader();
        lookups = [];
      });

      test('a PATCH whose local row names another account is quarantined '
          'unsent', () async {
        await connector().replayCrud([
          CrudEntry(60, UpdateType.patch, 'dive_annotations', 'd1', null,
              {'notes': 'x'}),
          CrudEntry(61, UpdateType.put, 'dives', 'd2', null,
              {'owner_id': 'uid-b', 'x': 1}),
        ],
            fetchLocalRow: localRows({
              ('dive_annotations', 'd1'): {'owner_id': 'uid-a'},
            }));

        expect(q.records.map((e) => e.id), ['d1']);
        expect(q.causes.single, isA<OtherAccountOpException>());
        expect(up.calls.whereType<_Update>(), isEmpty);
        expect(up.calls.whereType<_Upsert>().map((u) => u.data['id']), ['d2']);
      });

      test('a PATCH whose local row is ownerless, the signed-in account\'s, '
          'or missing is uploaded', () async {
        await connector().replayCrud([
          CrudEntry(62, UpdateType.patch, 'dive_annotations', 'p1', null,
              {'notes': 'a'}),
          CrudEntry(63, UpdateType.patch, 'dive_annotations', 'p2', null,
              {'notes': 'b'}),
          CrudEntry(64, UpdateType.patch, 'dive_annotations', 'p3', null,
              {'notes': 'c'}),
        ],
            fetchLocalRow: localRows({
              ('dive_annotations', 'p1'): {'owner_id': null},
              ('dive_annotations', 'p2'): {'owner_id': 'uid-b'},
            }));

        expect(up.calls.whereType<_Update>().map((u) => u.id),
            ['p1', 'p2', 'p3']);
        expect(q.records, isEmpty);
      });

      test('a DELETE is uploaded and never looks up the local row', () async {
        await connector().replayCrud([
          CrudEntry(65, UpdateType.delete, 'oxygen_cells', 'c1', null, null),
        ], fetchLocalRow: localRows({}));

        expect(up.calls.whereType<_Delete>().map((d) => d.id), ['c1']);
        expect(lookups, isEmpty);
      });

      test('a PATCH on a table outside the synced tables never reaches the '
          'local-row lookup', () async {
        await connector().replayCrud([
          CrudEntry(66, UpdateType.patch, 'ps_untyped', 'u1', null, {'x': 1}),
        ], fetchLocalRow: localRows({}));

        expect(lookups, isEmpty);
        expect(up.calls.whereType<_Update>().map((u) => u.table),
            ['ps_untyped']);
      });

      test('with no session, a PATCH uploads without a local lookup',
          () async {
        await connector(signedIn: null).replayCrud([
          CrudEntry(67, UpdateType.patch, 'dive_annotations', 'n1', null,
              {'notes': 'x'}),
        ],
            fetchLocalRow: localRows({
              ('dive_annotations', 'n1'): {'owner_id': 'uid-a'},
            }));

        expect(lookups, isEmpty);
        expect(up.calls.whereType<_Update>().map((u) => u.id), ['n1']);
        expect(q.records, isEmpty);
      });
    });
    group('isQueuedByAnotherAccount', () {
      Future<bool> check(
        UpdateType op, {
        String table = 'dive_annotations',
        Map<String, dynamic>? data,
        String? signedIn = 'uid-b',
        Map<String, dynamic>? Function(String, String)? local,
        List<(String, String)>? lookups,
      }) =>
          CcrloggerBackendConnector.isQueuedByAnotherAccount(
            op: op,
            table: table,
            id: 'x1',
            data: data,
            signedInUserId: signedIn,
            fetchLocalRow: local == null
                ? null
                : (t, i) async {
                    lookups?.add((t, i));
                    return local(t, i);
                  },
          );

      test('PUT: another account, own account, ownerless', () async {
        expect(await check(UpdateType.put, data: {'owner_id': 'uid-a'}), isTrue);
        expect(await check(UpdateType.put, data: {'owner_id': 'uid-b'}), isFalse);
        expect(await check(UpdateType.put, data: {'x': 1}), isFalse);
        expect(await check(UpdateType.put, data: {'owner_id': 'uid-a'}, signedIn: null),
            isFalse);
      });

      test('PATCH: another account, own, ownerless, missing', () async {
        expect(await check(UpdateType.patch, local: (_, _) => {'owner_id': 'uid-a'}),
            isTrue);
        expect(await check(UpdateType.patch, local: (_, _) => {'owner_id': 'uid-b'}),
            isFalse);
        expect(await check(UpdateType.patch, local: (_, _) => {'owner_id': null}),
            isFalse);
        expect(await check(UpdateType.patch, local: (_, _) => null), isFalse);
      });

      test('PATCH: non-synced table and null session never look up', () async {
        final lookups = <(String, String)>[];
        expect(
            await check(UpdateType.patch,
                table: 'ps_untyped',
                local: (_, _) => {'owner_id': 'uid-a'},
                lookups: lookups),
            isFalse);
        expect(
            await check(UpdateType.patch,
                signedIn: null,
                local: (_, _) => {'owner_id': 'uid-a'},
                lookups: lookups),
            isFalse);
        expect(lookups, isEmpty);
      });

      test('DELETE is never another account\'s', () async {
        final lookups = <(String, String)>[];
        expect(
            await check(UpdateType.delete,
                local: (_, _) => {'owner_id': 'uid-a'}, lookups: lookups),
            isFalse);
        expect(lookups, isEmpty);
      });
    });
  });

  group('permission-denied reporting', () {
    late _RecordingReporter reporter;
    late _RecordingQuarantine quarantine;

    setUp(() {
      reporter = _RecordingReporter();
      quarantine = _RecordingQuarantine();
    });

    CcrloggerBackendConnector connectorFor(SupabaseRestUploader uploader,
        {String? signedIn = 'uid-b'}) {
      final sessions = _FakeSessions();
      if (signedIn != null) sessions.session = _sessionFor(signedIn);
      return CcrloggerBackendConnector.forTesting(
        sessions: sessions,
        uploader: uploader,
        quarantine: quarantine,
        onPermissionDenied: reporter.call,
      );
    }

    CrudEntry ownedPut(String table, String id) => CrudEntry(
        1, UpdateType.put, table, id, null, {'owner_id': 'uid-b', 'x': 1});

    test('a 42501 on an owned PUT is rethrown and reported once', () async {
      final connector = connectorFor(
          _CodePoisonUploader(failTable: 'dive_computers', code: '42501'));
      await expectLater(
        connector.replayCrud([ownedPut('dive_computers', 'dc_b89641e4')]),
        throwsA(isA<CrudUploadException>()),
      );
      expect(reporter.reports, [('dive_computers', UpdateType.put)]);
      expect(quarantine.records, isEmpty);
    });

    test('a repeated 42501 on the same table and op is not reported again',
        () async {
      final connector = connectorFor(
          _CodePoisonUploader(failTable: 'dive_computers', code: '42501'));
      for (var i = 0; i < 2; i++) {
        await expectLater(
          connector.replayCrud([ownedPut('dive_computers', 'dc_b89641e4')]),
          throwsA(isA<CrudUploadException>()),
        );
      }
      expect(reporter.reports, hasLength(1));
    });

    test("an ownerless PUT's 42501 is rethrown but not reported", () async {
      final connector = connectorFor(
          _CodePoisonUploader(failTable: 'dive_computers', code: '42501'));
      await expectLater(
        connector.replayCrud([
          CrudEntry(1, UpdateType.put, 'dive_computers', 'dc_x', null,
              {'x': 1}),
        ]),
        throwsA(isA<CrudUploadException>()),
      );
      expect(reporter.reports, isEmpty);
    });

    test('a 42501 on a PATCH is reported', () async {
      final connector = connectorFor(
          _CodePoisonUploader(failTable: 'dives', code: '42501'));
      await expectLater(
        connector.replayCrud([
          CrudEntry(1, UpdateType.patch, 'dives', 'd1', null, {'x': 1}),
        ]),
        throwsA(isA<CrudUploadException>()),
      );
      expect(reporter.reports, [('dives', UpdateType.patch)]);
    });

    test('a 42501 from the self-heal parent upsert is reported under the '
        "parent's table", () async {
      final connector = connectorFor(_HealDeniedUploader());
      await expectLater(
        connector.replayCrud(
          [ownedPut('dive_samples', 'd1')],
          fetchLocalRow: (table, id) async =>
              table == 'dives' ? {'owner_id': 'uid-b'} : null,
        ),
        throwsA(isA<CrudUploadException>()),
      );
      expect(reporter.reports, [('dives', UpdateType.put)]);
    });

    for (final code in ['22001', '503']) {
      test('a $code is not reported', () async {
        final connector = connectorFor(
            _CodePoisonUploader(failTable: 'dives', code: code));
        try {
          await connector.replayCrud([ownedPut('dives', 'd1')]);
        } on CrudUploadException {
          // 503 is retried; 22001 is quarantined.
        }
        expect(reporter.reports, isEmpty);
      });
    }

    test('a 42P10 is retried, not quarantined or reported', () async {
      final connector = connectorFor(
          _CodePoisonUploader(failTable: 'dives', code: '42P10'));
      await expectLater(
        connector.replayCrud([ownedPut('dives', 'd1')]),
        throwsA(isA<CrudUploadException>()),
      );
      expect(quarantine.records, isEmpty);
      expect(reporter.reports, isEmpty);
    });

    test('a throwing reporter does not change the outcome', () async {
      final connector = CcrloggerBackendConnector.forTesting(
        sessions: _FakeSessions()..session = _sessionFor('uid-b'),
        uploader:
            _CodePoisonUploader(failTable: 'dive_computers', code: '42501'),
        quarantine: quarantine,
        onPermissionDenied: (t, o, e, s) async => throw StateError('boom'),
      );
      await expectLater(
        connector.replayCrud([ownedPut('dive_computers', 'dc_1')]),
        throwsA(isA<CrudUploadException>()
            .having((e) => isPermissionDenied(e), 'denied', isTrue)),
      );
      expect(quarantine.records, isEmpty);
    });
  });

  group('isPermissionDenied', () {
    final op = CrudEntry(1, UpdateType.put, 'dives', 'd1', null, {'x': 1});
    test('true for a 42501 PostgrestException', () {
      expect(
          isPermissionDenied(PostgrestException(message: 'm', code: '42501')),
          isTrue);
    });
    test('true for a CrudUploadException wrapping one', () {
      expect(
          isPermissionDenied(CrudUploadException(
              op, PostgrestException(message: 'm', code: '42501'))),
          isTrue);
    });
    test('false for a string, another code and null', () {
      expect(isPermissionDenied('42501'), isFalse);
      expect(
          isPermissionDenied(PostgrestException(message: 'm', code: '23503')),
          isFalse);
      expect(isPermissionDenied(null), isFalse);
    });
  });
}

class _RecordingReporter {
  final List<(String, UpdateType)> reports = [];

  Future<void> call(
      String table, UpdateType opType, Object error, StackTrace stack) async {
    reports.add((table, opType));
  }
}

/// 23503 for `dive_samples` (so self-heal runs), 42501 for the `dives`
/// parent upsert.
class _HealDeniedUploader implements SupabaseRestUploader {
  @override
  Future<void> upsert(String table, Map<String, dynamic> data) async {
    if (table == 'dive_samples') {
      throw PostgrestException(message: 'fk', code: '23503');
    }
    if (table == 'dives') {
      throw PostgrestException(message: 'rls', code: '42501');
    }
  }

  @override
  Future<void> update(String t, String id, Map<String, dynamic> d) async {}

  @override
  Future<void> delete(String t, String id) async {}
}

Session _sessionFor(String userId) =>
    Session(accessToken: 'token', tokenType: 'bearer', user: _user(userId));

class _RecordingQuarantine implements CrudQuarantine {
  final List<CrudEntry> records = [];
  final List<Object> causes = [];

  @override
  Future<void> record(CrudEntry op, Object cause) async {
    records.add(op);
    causes.add(cause);
  }
}

/// Uploader that rejects [failTable] with a PostgrestException carrying a
/// chosen [code] (SQLSTATE like '22001' or an HTTP status like '413'/'503').
class _CodePoisonUploader implements SupabaseRestUploader {
  final String failTable;
  final String code;
  final List<String> upserted = [];
  _CodePoisonUploader({required this.failTable, required this.code});

  void _maybeFail(String table) {
    if (table == failTable) {
      throw PostgrestException(message: 'rejected $table', code: code);
    }
  }

  @override
  Future<void> upsert(String table, Map<String, dynamic> data) async {
    _maybeFail(table);
    upserted.add(table);
  }

  @override
  Future<void> update(String table, String id, Map<String, dynamic> data) async {
    _maybeFail(table);
  }

  @override
  Future<void> delete(String table, String id) async {
    _maybeFail(table);
  }
}

class _FkPoisonUploader implements SupabaseRestUploader {
  final String failTable;
  final int failTimes;
  int _fails = 0;
  final List<String> upserted = [];
  final List<String> updated = [];
  _FkPoisonUploader({required this.failTable, this.failTimes = 1});

  @override
  Future<void> upsert(String table, Map<String, dynamic> data) async {
    if (table == failTable && _fails < failTimes) {
      _fails++;
      throw PostgrestException(
          message: 'violates foreign key constraint', code: '23503');
    }
    upserted.add(table);
  }

  @override
  Future<void> update(String t, String id, Map<String, dynamic> d) async {
    updated.add(t);
  }

  @override
  Future<void> delete(String t, String id) async {}
}

class _ThrowingUploader implements SupabaseRestUploader {
  final String failTable;
  final List<String> upserted = [];
  _ThrowingUploader({required this.failTable});

  @override
  Future<void> upsert(String table, Map<String, dynamic> data) async {
    if (table == failTable) throw StateError('backend rejected $table');
    upserted.add(table);
  }

  @override
  Future<void> update(String table, String id, Map<String, dynamic> data) async {
    if (table == failTable) throw StateError('backend rejected $table');
  }

  @override
  Future<void> delete(String table, String id) async {
    if (table == failTable) throw StateError('backend rejected $table');
  }
}
