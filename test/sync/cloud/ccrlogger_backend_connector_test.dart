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
  });
}
