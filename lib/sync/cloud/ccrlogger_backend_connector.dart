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

import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Forces a token refresh. Tests may no-op this. Real implementations
  /// call into Supabase's GoTrue refresh endpoint; on success
  /// [currentSession] returns a fresh token.
  Future<void> refreshSession();
}

class SupabaseAuthSessionSource implements SessionSource {
  final SupabaseClient _client;
  SupabaseAuthSessionSource(this._client);
  @override
  Session? get currentSession => _client.auth.currentSession;
  @override
  Future<void> refreshSession() async {
    await _client.auth.refreshSession();
  }
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

  /// Window before token expiry within which we try to refresh
  /// proactively. PowerSync caches the credential we return and reuses
  /// it past our return value; a tight (30-second) window means a
  /// session that PowerSync polls 35s before expiry still gets used past
  /// the cliff, the server replies with PSYNC_S2103 (JWT expired), and
  /// every upload + download in the queue stalls. Five minutes gives
  /// the refresh attempt a real budget on a slow / backgrounded link.
  static const _refreshLeadTime = Duration(minutes: 5);

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final initial = _sessions.currentSession;
    if (initial == null) return null;
    final now = DateTime.now().toUtc();
    final initialExpiry = initial.expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            initial.expiresAt! * 1000, isUtc: true);
    Session session = initial;
    final needsRefresh = initialExpiry != null &&
        initialExpiry.isBefore(now.add(_refreshLeadTime));
    if (needsRefresh) {
      try {
        await _sessions.refreshSession();
        final refreshed = _sessions.currentSession;
        if (refreshed != null) session = refreshed;
      } catch (e, st) {
        // Log instead of swallowing. Refresh failures are the root
        // cause of PSYNC_S2103 stalls and we want them visible in
        // Sentry / debug logs rather than silently retried forever.
        debugPrint('fetchCredentials: refreshSession failed: $e\n$st');
      }
    }
    // If, after the refresh attempt, the token is already past expiry,
    // we have nothing valid to hand PowerSync. Returning the expired
    // token would just cause the server to reject every request and
    // PowerSync would hammer fetchCredentials in a tight loop, never
    // recovering. Returning null tells PowerSync we're temporarily
    // disconnected — it backs off, and if the next call yields a
    // fresh token (re-sign-in, network recovery), sync resumes.
    final finalExpiry = session.expiresAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            session.expiresAt! * 1000, isUtc: true);
    if (finalExpiry != null && finalExpiry.isBefore(now)) {
      debugPrint('fetchCredentials: returning null — token expired at '
          '$finalExpiry and refresh did not produce a fresh one');
      return null;
    }
    return PowerSyncCredentials(
      endpoint: _endpoint,
      token: session.accessToken,
      userId: session.user.id,
      expiresAt: finalExpiry,
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
          final data = {..._decodeJsonColumns(op.table, op.opData), 'id': op.id};
          await _uploader.upsert(op.table, data);
        case UpdateType.patch:
          if (op.opData != null) {
            await _uploader.update(
                op.table, op.id, _decodeJsonColumns(op.table, op.opData));
          }
        case UpdateType.delete:
          await _uploader.delete(op.table, op.id);
      }
    }
  }
}

/// Per-table set of columns that hold JSON-encoded text in PowerSync's
/// local SQLite but need to land as parsed objects in Postgres `jsonb`.
/// Without this, Supabase wraps the string-of-array as a JSON-string
/// scalar and the value round-trips as a wrapped string — breaking
/// reads on every other device.
const Map<String, Set<String>> _jsonbColumns = {
  'dive_annotations': {'buddies_json', 'tags_json', 'weights_json'},
};

Map<String, dynamic> _decodeJsonColumns(
    String table, Map<String, dynamic>? data) {
  if (data == null) return const {};
  final cols = _jsonbColumns[table];
  if (cols == null) return Map<String, dynamic>.from(data);
  final out = Map<String, dynamic>.from(data);
  for (final c in cols) {
    final v = out[c];
    if (v is String) {
      try {
        out[c] = jsonDecode(v);
      } catch (_) {
        // Leave as-is if parsing fails; Supabase will surface a typed
        // error rather than silently corrupting the row.
      }
    }
  }
  return out;
}
