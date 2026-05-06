/// Bridges PowerSync's sync engine to our Supabase backend.
///
/// PowerSync calls [fetchCredentials] when it needs to (re)authenticate
/// against the sync service, and [uploadData] when it has queued local
/// CRUD to replay against Postgres. We mirror PowerSync's CRUD ops onto
/// `supabase.from(table).upsert/update/delete` calls; RLS on the cloud
/// side ensures rows can only be touched by their owner.
///
/// The Supabase REST surface is wrapped in [SupabaseRestUploader] so
/// tests can swap it for a recording fake without faking the whole
/// `supabase.from(...)` query-builder chain.
library;

import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_config.dart';

abstract class SupabaseRestUploader {
  Future<void> upsert(String table, Map<String, dynamic> data);
  Future<void> update(String table, String id, Map<String, dynamic> data);
  Future<void> delete(String table, String id);
}

class SupabaseClientRestUploader implements SupabaseRestUploader {
  final SupabaseClient _client;
  SupabaseClientRestUploader(this._client);

  @override
  Future<void> upsert(String table, Map<String, dynamic> data) =>
      _client.from(table).upsert(data);

  @override
  Future<void> update(String table, String id, Map<String, dynamic> data) =>
      _client.from(table).update(data).eq('id', id);

  @override
  Future<void> delete(String table, String id) =>
      _client.from(table).delete().eq('id', id);
}

abstract class SessionSource {
  Session? get currentSession;
}

class SupabaseAuthSessionSource implements SessionSource {
  final SupabaseClient _client;
  SupabaseAuthSessionSource(this._client);
  @override
  Session? get currentSession => _client.auth.currentSession;
}

class CcrloggerBackendConnector extends PowerSyncBackendConnector {
  final SessionSource _sessions;
  final SupabaseRestUploader _uploader;
  final String _endpoint;

  CcrloggerBackendConnector(
    SupabaseClient supabase, {
    String endpoint = CloudConfig.powerSyncEndpoint,
  })  : _sessions = SupabaseAuthSessionSource(supabase),
        _uploader = SupabaseClientRestUploader(supabase),
        _endpoint = endpoint;

  /// Test-only: inject the auth + REST seams directly.
  CcrloggerBackendConnector.forTesting({
    required SessionSource sessions,
    required SupabaseRestUploader uploader,
    String endpoint = 'https://test.powersync.invalid',
  })  : _sessions = sessions,
        _uploader = uploader,
        _endpoint = endpoint;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final session = _sessions.currentSession;
    if (session == null) return null;
    return PowerSyncCredentials(
      endpoint: _endpoint,
      token: session.accessToken,
    );
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final batch = await database.getCrudBatch();
    if (batch == null) return;
    await replayCrud(batch.crud);
    await batch.complete();
  }

  /// Replays a list of [CrudEntry]s onto the Supabase REST surface.
  /// Public for tests; production code reaches it via [uploadData].
  Future<void> replayCrud(List<CrudEntry> entries) async {
    for (final op in entries) {
      switch (op.op) {
        case UpdateType.put:
          final data = {...?op.opData, 'id': op.id};
          await _uploader.upsert(op.table, data);
        case UpdateType.patch:
          if (op.opData != null) {
            await _uploader.update(op.table, op.id, op.opData!);
          }
        case UpdateType.delete:
          await _uploader.delete(op.table, op.id);
      }
    }
  }
}
