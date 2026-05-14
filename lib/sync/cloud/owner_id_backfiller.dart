/// One-shot Drift → PowerSync data migration, run on first sign-in.
///
/// Phase 2.0–2.2 wrote sync-eligible rows to Drift; Phase 2.2b/2.3 moved
/// them to PowerSync. Existing users have data in Drift that needs to
/// land in the PowerSync local DB so PowerSync can upload it to Postgres.
///
/// We copy each row, stamping `owner_id = userId` along the way. Idempotent:
/// if a row's `id` already exists in PowerSync we skip it (the user signed
/// in twice, or they re-installed and the second sign-in is a no-op
/// because PowerSync already pulled their cloud rows).
library;
import 'package:flutter/foundation.dart';
import 'package:powersync/powersync.dart';

import '../../data/db/database.dart';

class OwnerIdBackfiller {
  final AppDatabase _drift;
  final PowerSyncDatabase _ps;

  OwnerIdBackfiller(this._drift, this._ps);

  /// Copies every sync-eligible row from Drift into PowerSync, stamping
  /// [userId] as `owner_id`. Returns the total number of rows copied.
  ///
  /// Also stamps `owner_id` on existing PowerSync-resident rows in
  /// `dives` and `dive_samples` that were written while no auth session
  /// was active (RLS rejects every upload otherwise — the symptom is
  /// `new row violates row-level security policy for table "dives"` in
  /// the upload retry loop). Those two tables don't have Drift→PowerSync
  /// copies because they were always PowerSync-resident; the backfill
  /// is an in-place UPDATE rather than a copy.
  Future<int> backfillIfNeeded(String userId) async {
    var total = 0;
    total += await _copyDiveAnnotations(userId);
    total += await _copyDiveComputers(userId);
    total += await _copyOxygenCells(userId);
    total += await _copyScrubberSessions(userId);
    total += await _copyCylinders(userId);
    total += await _copyPressureMappings(userId);
    total += await _copyDiveCylinders(userId);
    total += await _stampOwnerIdInPlace('dives', userId);
    total += await _stampOwnerIdInPlace('dive_samples', userId);
    debugPrint('OwnerIdBackfiller: copied $total rows for user $userId');
    return total;
  }

  /// In-place owner_id stamp for tables that already live in PowerSync.
  /// Targets rows imported pre-sign-in (owner_id NULL) and leaves rows
  /// owned by other accounts on this device alone.
  Future<int> _stampOwnerIdInPlace(String table, String userId) async {
    final affected = await _ps.execute(
      'UPDATE $table SET owner_id = ? WHERE owner_id IS NULL',
      [userId],
    );
    // PowerSync's `execute` returns a `ResultSet` with `affectedRows`.
    return affected.length;
  }

  Future<bool> _exists(String table, String id) async {
    final row = await _ps.getOptional('SELECT id FROM $table WHERE id = ?', [id]);
    return row != null;
  }

  Future<int> _copyDiveAnnotations(String userId) async {
    final rows = await _drift.select(_drift.diveAnnotations).get();
    var n = 0;
    for (final r in rows) {
      if (await _exists('dive_annotations', r.diveId)) continue;
      await _ps.execute(
        'INSERT INTO dive_annotations '
        '(id, owner_id, dive_id, site_name, site_latitude_e5, '
        'site_longitude_e5, notes, buddies_json, tags_json, rating, '
        'conditions, created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [r.diveId, userId, r.diveId, r.siteName, r.siteLatitudeE5,
          r.siteLongitudeE5, r.notes, r.buddiesJson, r.tagsJson, r.rating,
          r.conditions, r.createdAt, r.updatedAt, r.deletedAt,
          r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }

  Future<int> _copyDiveComputers(String userId) async {
    final rows = await _drift.select(_drift.diveComputers).get();
    var n = 0;
    for (final r in rows) {
      if (await _exists('dive_computers', r.id)) continue;
      await _ps.execute(
        'INSERT INTO dive_computers '
        '(id, owner_id, serial, model, firmware_version, nickname, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [r.id, userId, r.serial, r.model, r.firmwareVersion, r.nickname,
          r.createdAt, r.updatedAt, r.deletedAt, r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }

  Future<int> _copyOxygenCells(String userId) async {
    final rows = await _drift.select(_drift.oxygenCells).get();
    var n = 0;
    for (final r in rows) {
      if (await _exists('oxygen_cells', r.id)) continue;
      await _ps.execute(
        'INSERT INTO oxygen_cells '
        '(id, owner_id, slot, label, installed_date, retired_date, notes, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [r.id, userId, r.slot, r.label, r.installedDate, r.retiredDate,
          r.notes, r.createdAt, r.updatedAt, r.deletedAt,
          r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }

  Future<int> _copyScrubberSessions(String userId) async {
    final rows = await _drift.select(_drift.scrubberSessions).get();
    var n = 0;
    for (final r in rows) {
      if (await _exists('scrubber_sessions', r.id)) continue;
      await _ps.execute(
        'INSERT INTO scrubber_sessions '
        '(id, owner_id, started_date, total_minutes, media_type, notes, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [r.id, userId, r.startedDate, r.totalMinutes, r.mediaType, r.notes,
          r.createdAt, r.updatedAt, r.deletedAt, r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }

  Future<int> _copyCylinders(String userId) async {
    final rows = await _drift.select(_drift.cylinders).get();
    var n = 0;
    for (final r in rows) {
      if (await _exists('cylinders', r.id)) continue;
      await _ps.execute(
        'INSERT INTO cylinders '
        '(id, owner_id, label, role, bailout_order, volume_liters, '
        'working_pressure_bar, notes, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [r.id, userId, r.label, r.role, r.bailoutOrder, r.volumeLiters,
          r.workingPressureBar, r.notes,
          r.createdAt, r.updatedAt, r.deletedAt, r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }

  Future<int> _copyPressureMappings(String userId) async {
    final rows = await _drift.select(_drift.pressureMappings).get();
    var n = 0;
    for (final r in rows) {
      final id = '${r.diveComputerId}:${r.channelIndex}';
      if (await _exists('pressure_mappings', id)) continue;
      await _ps.execute(
        'INSERT INTO pressure_mappings '
        '(id, owner_id, dive_computer_id, channel_index, cylinder_id, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, userId, r.diveComputerId, r.channelIndex, r.cylinderId,
          r.createdAt, r.updatedAt, r.deletedAt, r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }

  Future<int> _copyDiveCylinders(String userId) async {
    final rows = await _drift.select(_drift.diveCylinders).get();
    var n = 0;
    for (final r in rows) {
      final id = '${r.diveId}:${r.gasMixIndex}';
      if (await _exists('dive_cylinders', id)) continue;
      await _ps.execute(
        'INSERT INTO dive_cylinders '
        '(id, owner_id, dive_id, gas_mix_index, cylinder_id, '
        'created_at, updated_at, deleted_at, version, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [id, userId, r.diveId, r.gasMixIndex, r.cylinderId,
          r.createdAt, r.updatedAt, r.deletedAt, r.version, r.syncStatus],
      );
      n++;
    }
    return n;
  }
}
