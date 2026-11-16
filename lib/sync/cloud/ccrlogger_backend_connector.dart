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
import 'powersync_schema.dart' show kSyncedTableNames;

/// Told once per (table, op type) when the server refuses an upload with
/// 42501. See [CcrloggerBackendConnector.replayCrud].
typedef UploadPermissionReporter = Future<void> Function(
    String table, UpdateType opType, Object error, StackTrace stack);

/// Whether [error] is a Postgres 42501 (insufficient privilege / RLS), or a
/// [CrudUploadException] wrapping one.
bool isPermissionDenied(Object? error) {
  if (error is CrudUploadException) return isPermissionDenied(error.cause);
  return error is PostgrestException && error.code == '42501';
}

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
  final CrudQuarantine? _quarantine;
  final String _endpoint;
  final UploadPermissionReporter? _onPermissionDenied;

  /// `'$table/${opType.name}'` keys already reported by this instance.
  final Set<String> _reportedPermissionDenied = {};

  CcrloggerBackendConnector(
    SupabaseClient supabase, {
    String endpoint = CloudConfig.powerSyncEndpoint,
    CrudQuarantine? quarantine,
    UploadPermissionReporter? onPermissionDenied,
  })  : _sessions = SupabaseAuthSessionSource(supabase),
        _uploader = SupabaseClientRestUploader(supabase),
        _quarantine = quarantine,
        _onPermissionDenied = onPermissionDenied,
        _endpoint = endpoint;

  /// Test-only: inject the auth + REST seams directly.
  CcrloggerBackendConnector.forTesting({
    required SessionSource sessions,
    required SupabaseRestUploader uploader,
    CrudQuarantine? quarantine,
    UploadPermissionReporter? onPermissionDenied,
    String endpoint = 'https://test.powersync.invalid',
  })  : _sessions = sessions,
        _uploader = uploader,
        _quarantine = quarantine,
        _onPermissionDenied = onPermissionDenied,
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
    try {
      await replayCrud(
        batch.crud,
        // Self-heal lookup: fetch a parent row from the LOCAL PowerSync DB so a
        // child op whose parent never reached the cloud can re-upload it. The
        // table comes only from the hard-coded [_fkParents] map (never user
        // input) — and, for the PATCH owner check, from an op's table, which
        // [_patchOfAnotherAccount] validates against [kSyncedTableNames]
        // before calling — so the interpolation is safe.
        fetchLocalRow: (table, id) =>
            database.getOptional('SELECT * FROM $table WHERE id = ?', [id]),
      );
    } catch (e, st) {
      // The batch is NOT completed — PowerSync keeps it queued and retries.
      // A single rejected op therefore blocks the whole queue (issue #2);
      // log which op so the failure is diagnosable rather than silent. The
      // wrapped [CrudUploadException] also names it in `status.uploadError`.
      debugPrint('uploadData: $e\n$st');
      rethrow;
    }
    await batch.complete();
  }

  /// Replays a list of [CrudEntry]s onto the Supabase REST surface.
  /// Public for tests; production code reaches it via [uploadData].
  ///
  /// A per-op failure is rethrown as a [CrudUploadException] that names the
  /// offending table/id/op, so the error PowerSync stores (and our diagnostic
  /// report shows) identifies the "poison" op instead of a bare
  /// `PostgrestException`.
  ///
  /// Self-heal: when a `dive_*` child op fails with a foreign-key violation
  /// (Postgres 23503) because its parent row never reached the cloud — an
  /// orphaned local dive/cylinder, e.g. one imported while signed-out whose
  /// `dives` row never uploaded — re-upsert the parent from [fetchLocalRow] and
  /// retry once. That drains the queue and recovers the orphan instead of
  /// wedging sync forever (issue #2, Part 2).
  ///
  /// Drop: when the FK parent doesn't exist locally *either* — a child row
  /// whose dive was deleted/re-hashed but never cascaded (e.g. a
  /// `dive_bailout_carry` pointing at a `dives` id that exists in no layer) —
  /// the op can never satisfy its FK no matter how many times it's retried.
  /// Skip it so the caller's `batch.complete()` clears it, instead of letting
  /// it sit at the head of the FIFO queue and block every op behind it forever
  /// (issue #2, Part 3).
  ///
  /// Account switch: signing out keeps the upload queue, so a PUT queued by
  /// the previous account can reach this one. It names that account as
  /// `owner_id`; RLS rejects it with 42501, which is retried, so sent as-is
  /// it would block the queue forever. It is quarantined unsent instead.
  ///
  /// Since 0027 the server keys every row by (owner_id, id), so two accounts
  /// can own the same id and a PATCH queued by account A would update B's
  /// same-id row under B's session. A PATCH carries only the changed columns,
  /// but its row is still local, and the local row names A. PowerSync does not
  /// publish downloaded data while the upload queue holds anything (priority 0
  /// excepted; `can_apply_sync_changes` in powersync-sqlite-core's
  /// `crates/core/src/sync/sync_local.rs`), and local updates keep an existing
  /// owner (`owner_id = COALESCE(owner_id, ?)`), so while A's ops wait the
  /// local row keeps A as `owner_id`, even after a signed-out edit or an edit
  /// under B's session.
  /// A PATCH whose local row names another account is quarantined unsent. An
  /// ownerless row (a signed-out import, claimed by the sign-in backfill) or a
  /// row that no longer exists uploads as before.
  ///
  /// A DELETE carries no data and its local row is gone, so it has no owner
  /// to read and uploads as before. The only hard deletes are on `dive_plans`
  /// (random ids), `oxygen_cells` (`cell_<ms>_<slot>`) and
  /// `dive_bailout_carry` (`<diveId>:<cylinderId>`, the cylinder id being per
  /// account), whose ids do not repeat across accounts in practice, so a
  /// DELETE can only reach the signed-in account's own row. Revisit this if a
  /// table with repeating ids ever gets hard deletes.
  Future<void> replayCrud(
    List<CrudEntry> entries, {
    Future<Map<String, dynamic>?> Function(String table, String id)?
        fetchLocalRow,
  }) async {
    final signedInUserId = _sessions.currentSession?.user.id;
    for (final op in entries) {
      if (await isQueuedByAnotherAccount(
        op: op.op,
        table: op.table,
        id: op.id,
        data: op.opData,
        signedInUserId: signedInUserId,
        fetchLocalRow: fetchLocalRow,
      )) {
        await _quarantine?.record(op, OtherAccountOpException());
        debugPrint('replayCrud: quarantined ${op.op.name} ${op.table} '
            'id=${op.id} — queued by another account');
        continue;
      }
      try {
        await _applyOp(op);
      } on PostgrestException catch (e, st) {
        // After 0027 a 42501 on the user's own row is a server defect. It is
        // still retried below; it is reported once so we find out. An
        // ownerless PUT is the signed-out-import case the sign-in backfill
        // claims, so it is expected and not reported.
        if (e.code == '42501' &&
            !(op.op == UpdateType.put && op.opData?['owner_id'] == null)) {
          await _reportPermissionDenied(op.table, op.op, e, st);
        }
        if (e.code == '23503' &&
            fetchLocalRow != null &&
            _fkParents.containsKey(op.table)) {
          try {
            final heal = await _healMissingParents(op, fetchLocalRow);
            if (heal.missingLocally) {
              // A required parent doesn't exist locally either — this child is
              // orphaned referential garbage that can never upload. Drop it so
              // it can't wedge the queue forever. (Its row may linger locally,
              // invisible without its parent; it won't re-queue unless edited.)
              debugPrint('replayCrud: dropping orphaned ${op.op.name} '
                  '${op.table} id=${op.id} — FK parent missing locally: $e');
              continue;
            }
            if (heal.uploadedAny) {
              await _applyOp(op);
              continue;
            }
          } catch (e2) {
            throw CrudUploadException(op, e2);
          }
        }
        // Permanent backend rejection (constraint / oversized body / bad
        // data): retrying the same payload can never succeed, so it would
        // wedge the FIFO queue forever (issue #2). Quarantine it — record it
        // for the "N changes couldn't sync" surface, then skip so the caller's
        // batch.complete() clears it and the ops behind it drain. Transient
        // errors (5xx / network) fall through to rethrow so PowerSync retries.
        if (_isPermanent(e)) {
          await _quarantine?.record(op, e);
          debugPrint('replayCrud: quarantined ${op.op.name} ${op.table} '
              'id=${op.id} — permanent backend rejection: $e');
          continue;
        }
        throw CrudUploadException(op, e);
      } catch (e) {
        // Anything we cannot positively classify as a permanent rejection
        // (network errors, timeouts, non-Postgrest failures) is treated as
        // transient and retried — never silently dropped.
        if (e is CrudUploadException) rethrow;
        throw CrudUploadException(op, e);
      }
    }
  }

  /// Whether an op belongs to an account other than [signedInUserId], so it
  /// must not be sent under this session. Shared by [replayCrud] and the
  /// Settings "Push stuck uploads" drain, which would otherwise bypass it.
  ///
  /// - PUT: its [data] names an `owner_id` other than [signedInUserId]. An
  ///   ownerless PUT is not: the sign-in backfill claims it, and until it
  ///   runs the RLS rejection is retried.
  /// - PATCH: the local row's `owner_id` (via [fetchLocalRow]) names another
  ///   account. Without a session or a [fetchLocalRow] there is nothing to
  ///   compare, and a table outside [kSyncedTableNames] is never looked up,
  ///   since the name goes into SQL. A missing or ownerless row is not
  ///   another account's.
  /// - DELETE: never (see [replayCrud]).
  static Future<bool> isQueuedByAnotherAccount({
    required UpdateType op,
    required String table,
    required String id,
    Map<String, dynamic>? data,
    required String? signedInUserId,
    Future<Map<String, dynamic>?> Function(String table, String id)?
        fetchLocalRow,
  }) async {
    if (signedInUserId == null) return false;
    switch (op) {
      case UpdateType.put:
        final owner = data?['owner_id'];
        return owner != null && owner != signedInUserId;
      case UpdateType.patch:
        if (fetchLocalRow == null || !kSyncedTableNames.contains(table)) {
          return false;
        }
        final owner = (await fetchLocalRow(table, id))?['owner_id'];
        return owner != null && owner != signedInUserId;
      case UpdateType.delete:
        return false;
    }
  }

  /// SQLSTATE codes for backend rejections that a retry of the same payload
  /// can never fix (so the op must be quarantined, not retried forever).
  /// Deliberately EXCLUDES 23503 (foreign-key — handled by self-heal/drop
  /// above) and 42501 (RLS). Since 0027 keys every table by (owner_id, id),
  /// a 42501 on the user's own row means a server defect that a server fix
  /// resolves, so it is retried, shown in the Sync tab and reported once
  /// ([_reportPermissionDenied]). The ownerless case (sign-in backfill
  /// pending) still resolves on the client.
  static const _permanentSqlStates = {
    '23505', // unique_violation
    '23502', // not_null_violation
    '23514', // check_violation
    '22001', // string_data_right_truncation (value too long)
    '22003', // numeric_value_out_of_range
    '22P02', // invalid_text_representation
  };

  /// Permanent HTTP client errors (4xx) that won't change on retry — notably
  /// 413 for an oversized `dive_samples` body, the prime suspect in #2.
  static const _permanentHttpStatuses = {400, 409, 413, 422};

  /// Whether [e] is a permanent backend rejection. Conservative by design:
  /// only a [PostgrestException] whose code is a known-permanent SQLSTATE or
  /// 4xx status counts. Everything else is transient (retry, never drop).
  static bool _isPermanent(PostgrestException e) {
    final code = e.code;
    if (code == null) return false;
    if (_permanentSqlStates.contains(code)) return true;
    final status = int.tryParse(code);
    return status != null && _permanentHttpStatuses.contains(status);
  }

  /// Reports a 42501 once per (table, op type) for this connector. A failing
  /// reporter must never change the upload outcome.
  Future<void> _reportPermissionDenied(
      String table, UpdateType opType, Object error, StackTrace stack) async {
    final reporter = _onPermissionDenied;
    if (reporter == null) return;
    if (!_reportedPermissionDenied.add('$table/${opType.name}')) return;
    try {
      await reporter(table, opType, error, stack);
    } catch (_) {}
  }

  Future<void> _applyOp(CrudEntry op) async {
    switch (op.op) {
      case UpdateType.put:
        await _uploader
            .upsert(op.table, {..._decodeJsonColumns(op.table, op.opData), 'id': op.id});
      case UpdateType.patch:
        if (op.opData != null) {
          await _uploader.update(
              op.table, op.id, _decodeJsonColumns(op.table, op.opData));
        }
      case UpdateType.delete:
        await _uploader.delete(op.table, op.id);
    }
  }

  /// Re-uploads any FK parents of [op] (per [_fkParents]) found locally, and
  /// reports the outcome so [replayCrud] can decide between retry and drop:
  ///
  /// - `uploadedAny`   — at least one parent was found locally and upserted, so
  ///   retrying the child op is worth a shot.
  /// - `missingLocally` — at least one required parent row is absent from the
  ///   local DB too, so the child can never satisfy its FK and must be dropped.
  ///
  /// A `null` parent id (e.g. a PATCH whose opData doesn't carry the FK column)
  /// is neither uploaded nor counted missing — such ops don't FK-fault anyway
  /// (an UPDATE matching no cloud row is a harmless no-op).
  Future<({bool uploadedAny, bool missingLocally})> _healMissingParents(
    CrudEntry op,
    Future<Map<String, dynamic>?> Function(String, String) fetchLocalRow,
  ) async {
    var uploadedAny = false;
    var missingLocally = false;
    for (final (column, parentTable) in _fkParents[op.table]!) {
      final parentId =
          column == 'id' ? op.id : op.opData?[column] as String?;
      if (parentId == null) continue;
      final row = await fetchLocalRow(parentTable, parentId);
      if (row == null) {
        missingLocally = true;
        continue;
      }
      try {
        await _uploader.upsert(parentTable,
            {..._decodeJsonColumns(parentTable, row), 'id': parentId});
      } on PostgrestException catch (e, st) {
        if (e.code == '42501' && row['owner_id'] != null) {
          await _reportPermissionDenied(parentTable, UpdateType.put, e, st);
        }
        rethrow;
      }
      uploadedAny = true;
    }
    return (uploadedAny: uploadedAny, missingLocally: missingLocally);
  }
}

/// Child table → its FK parents as `(local id column, parent table)`. Used by
/// the self-heal path to re-upload an orphaned parent before retrying a child.
/// `'id'` means the child's own id IS the parent id (1:1 tables). Mirrors the
/// Postgres FKs in supabase/migrations (`dive_bailout_carry`, `dive_samples`,
/// `dive_merge_links` reference `dives`; bailout also references `cylinders`).
const Map<String, List<(String, String)>> _fkParents = {
  'dive_bailout_carry': [('dive_id', 'dives'), ('cylinder_id', 'cylinders')],
  'dive_samples': [('id', 'dives')],
  'dive_merge_links': [('id', 'dives')],
};

/// Sink for CRUD ops the backend permanently rejected, so a single "poison"
/// op can't wedge the FIFO upload queue forever (issue #2). Implementations
/// persist the op durably so it can be surfaced ("N changes couldn't sync")
/// and re-driven once the underlying cause (e.g. an oversized `dive_samples`
/// body) is fixed. [replayCrud] records here, then skips the op so the batch
/// can complete and the ops behind it drain.
abstract class CrudQuarantine {
  Future<void> record(CrudEntry op, Object cause);
}

/// Wraps the underlying error from a single failed CRUD upload op, tagging it
/// with the op's table/id/type so a stalled upload queue (issue #2) is
/// diagnosable from `SyncStatus.uploadError` instead of a bare backend error.
class CrudUploadException implements Exception {
  final CrudEntry op;
  final Object cause;
  CrudUploadException(this.op, this.cause);

  @override
  String toString() =>
      'CRUD upload failed on ${op.op.name} ${op.table} id=${op.id}: $cause';
}

/// The quarantine cause for a PUT the previous account queued before
/// signing out ([CcrloggerBackendConnector.replayCrud]). A future re-drive
/// must replay it only while that account is signed in.
class OtherAccountOpException implements Exception {
  @override
  String toString() =>
      'Queued while another account was signed in; not uploaded to this '
      'account';
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
