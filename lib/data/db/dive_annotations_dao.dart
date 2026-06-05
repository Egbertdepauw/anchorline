/// Data Access Object for dive annotations.
///
/// PowerSync-backed (Phase 2.2b). Reads and writes go through the
/// `dive_annotations` view that PowerSync materialises from its local
/// SQLite store; the cloud Postgres schema is the authority once the user
/// signs in. Queries are raw SQL because PowerSync does not expose a
/// query-builder yet — JSON columns (`buddies_json`, `tags_json`) cross
/// the seam via `jsonEncode`/`jsonDecode`.
///
/// `owner_id` is stamped from the current Supabase session at write time;
/// nulls are tolerated locally for offline-without-account edits and get
/// stamped retroactively at upload time once the user signs in.
///
/// The dive-cylinder mapping (`dive_cylinders`) lives on [EquipmentDao]
/// for the duration of Phase 2.2 — it moves to PowerSync in Phase 2.3.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/annotation.dart';

/// Aggregated stats for one buddy across every dive that names them.
/// `firstDiveTime`/`lastDiveTime` are Unix-seconds `dives.start_time`
/// (min/max over the non-deleted dives the buddy appears on).
typedef BuddyStat = ({
  String name,
  int firstDiveTime,
  int lastDiveTime,
  int diveCount,
});

/// Aggregated stats for one dive site across every dive that names it.
/// `firstDiveTime`/`lastDiveTime` are Unix-seconds `dives.start_time`
/// (min/max over the non-deleted dives the site appears on). `lat`/`lon`
/// are the most-recent non-null coords recorded for the name, or null.
typedef SiteStat = ({
  String name,
  double? lat,
  double? lon,
  int firstDiveTime,
  int lastDiveTime,
  int diveCount,
});

class DiveAnnotationsDao {
  final PowerSyncDatabase _db;
  final SessionSource _session;

  DiveAnnotationsDao(this._db, this._session);

  /// Fires whenever any row in `dive_annotations` is inserted, updated, or
  /// deleted — including PowerSync-driven changes coming from the cloud.
  /// Emits an initial event on subscription so subscribers can do their
  /// first load via this stream alone if they want to.
  Stream<void> watchChanges() => _db
      .watch('SELECT 1 FROM dive_annotations LIMIT 1')
      .map((_) {});

  // ── DiveAnnotations ─────────────────────────────────────────────────────

  Future<DiveAnnotation?> get(String diveId) async {
    final row = await _db.getOptional(
      'SELECT * FROM dive_annotations WHERE dive_id = ? AND deleted_at IS NULL',
      [diveId],
    );
    if (row == null) return null;
    return _rowToModel(row);
  }

  Future<void> upsert(DiveAnnotation a) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM dive_annotations WHERE dive_id = ?',
        [a.diveId],
      );
      final ownerId = _session.currentSession?.user.id;
      final weightsEncoded = a.weights.isEmpty
          ? null
          : jsonEncode(a.weights.map((w) => w.toJson()).toList());
      if (existing == null) {
        await tx.execute(
          'INSERT INTO dive_annotations '
          '(id, owner_id, dive_id, site_name, site_latitude_e5, site_longitude_e5, '
          'notes, buddies_json, tags_json, rating, conditions, divemaster, '
          'display_deco_algorithm, user_dive_number, '
          'suit, undersuit, weight_system, dpv, camera, '
          'visibility, wavesize, current, surge, chill, '
          'air_temp_c, water_temp_c, weights_json, '
          'created_at, updated_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
          '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            a.diveId, // synthetic id == dive_id (one annotation per dive)
            ownerId,
            a.diveId,
            a.siteName,
            a.siteLatitude == null ? null : (a.siteLatitude! * 1e5).round(),
            a.siteLongitude == null ? null : (a.siteLongitude! * 1e5).round(),
            a.notes,
            a.buddies.isEmpty ? null : jsonEncode(a.buddies),
            a.tags.isEmpty ? null : jsonEncode(a.tags),
            a.rating,
            a.conditions,
            a.divemaster,
            a.displayDecoAlgorithm,
            a.userDiveNumber,
            a.suit,
            a.undersuit,
            a.weightSystem,
            a.dpv,
            a.camera,
            a.visibility,
            a.wavesize,
            a.current,
            a.surge,
            a.chill,
            a.airTempC,
            a.waterTempC,
            weightsEncoded,
            a.createdAt.millisecondsSinceEpoch,
            now,
            a.deletedAt?.millisecondsSinceEpoch,
            a.version,
            a.syncStatus.index,
          ],
        );
      } else {
        final newVersion = (existing['version'] as int? ?? 0) + 1;
        await tx.execute(
          'UPDATE dive_annotations SET '
          'owner_id = ?, '
          'site_name = ?, '
          'site_latitude_e5 = ?, '
          'site_longitude_e5 = ?, '
          'notes = ?, '
          'buddies_json = ?, '
          'tags_json = ?, '
          'rating = ?, '
          'conditions = ?, '
          'divemaster = ?, '
          'display_deco_algorithm = ?, '
          'user_dive_number = ?, '
          'suit = ?, '
          'undersuit = ?, '
          'weight_system = ?, '
          'dpv = ?, '
          'camera = ?, '
          'visibility = ?, '
          'wavesize = ?, '
          'current = ?, '
          'surge = ?, '
          'chill = ?, '
          'air_temp_c = ?, '
          'water_temp_c = ?, '
          'weights_json = ?, '
          'updated_at = ?, '
          'deleted_at = ?, '
          'version = ?, '
          'sync_status = ? '
          'WHERE dive_id = ?',
          [
            ownerId,
            a.siteName,
            a.siteLatitude == null ? null : (a.siteLatitude! * 1e5).round(),
            a.siteLongitude == null ? null : (a.siteLongitude! * 1e5).round(),
            a.notes,
            a.buddies.isEmpty ? null : jsonEncode(a.buddies),
            a.tags.isEmpty ? null : jsonEncode(a.tags),
            a.rating,
            a.conditions,
            a.divemaster,
            a.displayDecoAlgorithm,
            a.userDiveNumber,
            a.suit,
            a.undersuit,
            a.weightSystem,
            a.dpv,
            a.camera,
            a.visibility,
            a.wavesize,
            a.current,
            a.surge,
            a.chill,
            a.airTempC,
            a.waterTempC,
            weightsEncoded,
            now,
            a.deletedAt?.millisecondsSinceEpoch,
            newVersion,
            a.syncStatus.index,
            a.diveId,
          ],
        );
      }
    });
  }

  /// Returns the most recent (by updatedAt desc) lat/lon recorded for any
  /// annotation with this site name. Returns null if no match or both
  /// coords are null.
  Future<({double? lat, double? lon})?> getLatestSiteCoords(
      String siteName) async {
    if (siteName.trim().isEmpty) return null;
    final row = await _db.getOptional(
      'SELECT site_latitude_e5, site_longitude_e5 FROM dive_annotations '
      'WHERE site_name = ? AND deleted_at IS NULL '
      'AND (site_latitude_e5 IS NOT NULL OR site_longitude_e5 IS NOT NULL) '
      'ORDER BY updated_at DESC LIMIT 1',
      [siteName],
    );
    if (row == null) return null;
    final latE5 = row['site_latitude_e5'] as int?;
    final lonE5 = row['site_longitude_e5'] as int?;
    return (
      lat: latE5 == null ? null : latE5 / 1e5,
      lon: lonE5 == null ? null : lonE5 / 1e5,
    );
  }

  /// Batch-loads annotations for a list of dive ids. Returns a map keyed
  /// by diveId; dives without an annotation row are absent from the map.
  Future<Map<String, DiveAnnotation>> getAnnotationsForDives(
      Iterable<String> diveIds) async {
    final ids = diveIds.toList();
    if (ids.isEmpty) return const {};
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.getAll(
      'SELECT * FROM dive_annotations '
      'WHERE dive_id IN ($placeholders) AND deleted_at IS NULL',
      ids,
    );
    final out = <String, DiveAnnotation>{};
    for (final r in rows) {
      final m = _rowToModel(r);
      out[m.diveId] = m;
    }
    return out;
  }

  /// Returns one entry per distinct (lat, lon) pair across all non-deleted
  /// annotations where both coords are non-null. Coords are rounded to 5dp
  /// before deduping (matches the storage precision). Site name is taken
  /// from the most-recent annotation at those coords (may be null).
  /// Sorted alphabetically by site name with null-named entries last.
  Future<List<({String? siteName, double lat, double lon})>>
      distinctSiteCoords() async {
    final rows = await _db.getAll(
      'SELECT site_name, site_latitude_e5, site_longitude_e5 '
      'FROM dive_annotations '
      'WHERE deleted_at IS NULL '
      'AND site_latitude_e5 IS NOT NULL '
      'AND site_longitude_e5 IS NOT NULL '
      'ORDER BY updated_at DESC',
    );
    final byKey = <String, ({String? siteName, double lat, double lon})>{};
    for (final r in rows) {
      final lat = (r['site_latitude_e5'] as int) / 1e5;
      final lon = (r['site_longitude_e5'] as int) / 1e5;
      final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
      byKey.putIfAbsent(
        key,
        () => (siteName: r['site_name'] as String?, lat: lat, lon: lon),
      );
    }
    final list = byKey.values.toList();
    list.sort((a, b) {
      if (a.siteName == null && b.siteName == null) return 0;
      if (a.siteName == null) return 1;
      if (b.siteName == null) return -1;
      return a.siteName!.toLowerCase().compareTo(b.siteName!.toLowerCase());
    });
    return list;
  }

  Future<List<String>> distinctSiteNames() async {
    final rows = await _db.getAll(
      'SELECT DISTINCT site_name FROM dive_annotations '
      'WHERE site_name IS NOT NULL AND deleted_at IS NULL',
    );
    return rows
        .map((r) => r['site_name'] as String?)
        .whereType<String>()
        .toList();
  }

  Future<List<String>> distinctBuddies() async {
    final rows = await _db.getAll(
      'SELECT buddies_json FROM dive_annotations '
      'WHERE deleted_at IS NULL AND buddies_json IS NOT NULL',
    );
    final all = <String>{};
    for (final r in rows) {
      all.addAll(_decodeStringList(r['buddies_json'] as String?));
    }
    return all.toList();
  }

  // ── Buddies (the "Buddies list" feature) ────────────────────────────────
  //
  // Buddies are not a table — they're a JSON array of names per annotation
  // (`buddies_json`). "The list of buddies" is the distinct set of names
  // across all live annotations; editing a buddy is a bulk operation across
  // every dive that names them. Stats join those names against
  // `dives.start_time` so the UI can show first/last dive + a dive count.

  /// One [BuddyStat] per distinct buddy name, sorted by `diveCount`
  /// descending then `name` ascending. Only counts non-deleted dives and
  /// non-deleted annotations; a buddy whose only dive is soft-deleted (or
  /// who has no matching live dive at all) does not appear. Names are
  /// trimmed and empty strings ignored. Decode happens in Dart to mirror
  /// [distinctBuddies].
  Future<List<BuddyStat>> buddyStats() async {
    final annRows = await _db.getAll(
      'SELECT dive_id, buddies_json FROM dive_annotations '
      'WHERE deleted_at IS NULL AND buddies_json IS NOT NULL',
    );
    final diveRows = await _db.getAll(
      'SELECT id, start_time FROM dives WHERE deleted_at IS NULL',
    );
    final startByDive = <String, int>{
      for (final r in diveRows) r['id'] as String: r['start_time'] as int,
    };

    // Accumulate per buddy across all dives they appear on (live dives only).
    final agg = <String, ({int first, int last, int count})>{};
    for (final r in annRows) {
      final diveId = r['dive_id'] as String;
      final start = startByDive[diveId];
      if (start == null) continue; // dive missing or soft-deleted → skip
      // Dedupe names within a single dive so a doubled name doesn't
      // inflate the count.
      final names = _decodeStringList(r['buddies_json'] as String?)
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .toSet();
      for (final name in names) {
        final prev = agg[name];
        if (prev == null) {
          agg[name] = (first: start, last: start, count: 1);
        } else {
          agg[name] = (
            first: start < prev.first ? start : prev.first,
            last: start > prev.last ? start : prev.last,
            count: prev.count + 1,
          );
        }
      }
    }

    final out = agg.entries
        .map((e) => (
              name: e.key,
              firstDiveTime: e.value.first,
              lastDiveTime: e.value.last,
              diveCount: e.value.count,
            ))
        .toList();
    out.sort((a, b) {
      final byCount = b.diveCount.compareTo(a.diveCount);
      if (byCount != 0) return byCount;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// Renames buddy [from] → [to] across every live annotation that names
  /// them (case-sensitive exact match after trim). If [to] is already
  /// present in a dive the result is deduped (preserving order, dropping
  /// the duplicate) — this is how a diver merges "Jon"/"John". Persists
  /// via [upsert] so version / updated_at / owner_id / sync_status stay
  /// correct. Returns the number of annotations changed. No-op when
  /// [from] == [to] (after trim) or [to] is empty.
  Future<int> renameBuddy(String from, String to) async {
    final fromName = from.trim();
    final toName = to.trim();
    if (fromName.isEmpty || toName.isEmpty || fromName == toName) return 0;

    final rows = await _db.getAll(
      'SELECT dive_id FROM dive_annotations '
      'WHERE deleted_at IS NULL AND buddies_json IS NOT NULL',
    );
    var changed = 0;
    for (final r in rows) {
      final diveId = r['dive_id'] as String;
      final existing = await get(diveId);
      if (existing == null) continue;
      if (!existing.buddies.contains(fromName)) continue;

      final next = <String>[];
      for (final b in existing.buddies) {
        final name = b == fromName ? toName : b;
        if (next.contains(name)) continue; // dedupe (preserve first wins)
        next.add(name);
      }
      await upsert(existing.copyWith(buddies: next));
      changed++;
    }
    return changed;
  }

  /// Removes buddy [name] from every live annotation that names them
  /// (case-sensitive exact match after trim). Persists via [upsert].
  /// Returns the number of annotations changed.
  Future<int> deleteBuddy(String name) async {
    final target = name.trim();
    if (target.isEmpty) return 0;

    final rows = await _db.getAll(
      'SELECT dive_id FROM dive_annotations '
      'WHERE deleted_at IS NULL AND buddies_json IS NOT NULL',
    );
    var changed = 0;
    for (final r in rows) {
      final diveId = r['dive_id'] as String;
      final existing = await get(diveId);
      if (existing == null) continue;
      if (!existing.buddies.contains(target)) continue;

      final next = existing.buddies.where((b) => b != target).toList();
      await upsert(existing.copyWith(buddies: next));
      changed++;
    }
    return changed;
  }

  // ── Sites (the "Dive sites list" feature) ───────────────────────────────
  //
  // Dive sites, like buddies, are not a table — they live on each annotation
  // as `site_name` (+ `site_latitude_e5`/`site_longitude_e5`). "The list of
  // sites" is the distinct set of trimmed non-empty names across all live
  // annotations; editing a site is a bulk operation across every dive that
  // names it. Stats join those names against `dives.start_time` so the UI can
  // show first/last dive + a dive count, plus the latest coords recorded for
  // that name so the list can show a marker / the map can look it up.

  /// One [SiteStat] per distinct trimmed non-empty `site_name`, sorted by
  /// `diveCount` descending then `name` ascending. `firstDiveTime`/
  /// `lastDiveTime` = min/max `dives.start_time` over the live dives carrying
  /// that name. `lat`/`lon` = the most-recent non-null coords recorded for
  /// that name (by `updated_at` desc), null if none. Only counts non-deleted
  /// dives and non-deleted annotations; a site whose only dive is soft-deleted
  /// does not appear. Decode happens in Dart to mirror [buddyStats].
  Future<List<SiteStat>> siteStats() async {
    final annRows = await _db.getAll(
      'SELECT dive_id, site_name, site_latitude_e5, site_longitude_e5, '
      'updated_at FROM dive_annotations '
      'WHERE deleted_at IS NULL AND site_name IS NOT NULL',
    );
    final diveRows = await _db.getAll(
      'SELECT id, start_time FROM dives WHERE deleted_at IS NULL',
    );
    final startByDive = <String, int>{
      for (final r in diveRows) r['id'] as String: r['start_time'] as int,
    };

    // Accumulate per trimmed name across all live dives carrying it. Track
    // the most-recently-updated annotation that has coords so the list/map
    // can show a marker for the name.
    final agg = <String,
        ({
          int first,
          int last,
          int count,
          int? coordUpdatedAt,
          double? lat,
          double? lon,
        })>{};
    for (final r in annRows) {
      final diveId = r['dive_id'] as String;
      final start = startByDive[diveId];
      if (start == null) continue; // dive missing or soft-deleted → skip
      final name = (r['site_name'] as String).trim();
      if (name.isEmpty) continue;

      final latE5 = r['site_latitude_e5'] as int?;
      final lonE5 = r['site_longitude_e5'] as int?;
      final hasCoords = latE5 != null || lonE5 != null;
      final updatedAt = r['updated_at'] as int? ?? 0;

      final prev = agg[name];
      if (prev == null) {
        agg[name] = (
          first: start,
          last: start,
          count: 1,
          coordUpdatedAt: hasCoords ? updatedAt : null,
          lat: latE5 == null ? null : latE5 / 1e5,
          lon: lonE5 == null ? null : lonE5 / 1e5,
        );
      } else {
        // Keep the coords from the most-recently-updated annotation that has
        // them (mirrors getLatestSiteCoords' "ORDER BY updated_at DESC").
        final takeCoords = hasCoords &&
            (prev.coordUpdatedAt == null || updatedAt >= prev.coordUpdatedAt!);
        agg[name] = (
          first: start < prev.first ? start : prev.first,
          last: start > prev.last ? start : prev.last,
          count: prev.count + 1,
          coordUpdatedAt: takeCoords ? updatedAt : prev.coordUpdatedAt,
          lat: takeCoords ? (latE5 == null ? null : latE5 / 1e5) : prev.lat,
          lon: takeCoords ? (lonE5 == null ? null : lonE5 / 1e5) : prev.lon,
        );
      }
    }

    final out = agg.entries
        .map((e) => (
              name: e.key,
              lat: e.value.lat,
              lon: e.value.lon,
              firstDiveTime: e.value.first,
              lastDiveTime: e.value.last,
              diveCount: e.value.count,
            ))
        .toList();
    out.sort((a, b) {
      final byCount = b.diveCount.compareTo(a.diveCount);
      if (byCount != 0) return byCount;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// Renames site [from] → [to] across every live annotation whose
  /// `site_name` matches [from] (case-sensitive exact match after trim).
  /// Merging is automatic — two dives that now share a name simply both
  /// carry it (there's no per-dive list to dedupe, unlike buddies).
  /// Persists via [upsert] so version / updated_at / owner_id / sync_status
  /// stay correct. Returns the number of annotations changed. No-op when
  /// [from] == [to] (after trim) or [to] is empty.
  Future<int> renameSite(String from, String to) async {
    final fromName = from.trim();
    final toName = to.trim();
    if (fromName.isEmpty || toName.isEmpty || fromName == toName) return 0;

    final rows = await _db.getAll(
      'SELECT dive_id FROM dive_annotations '
      'WHERE deleted_at IS NULL AND site_name IS NOT NULL',
    );
    var changed = 0;
    for (final r in rows) {
      final diveId = r['dive_id'] as String;
      final existing = await get(diveId);
      if (existing == null) continue;
      if (existing.siteName?.trim() != fromName) continue;

      await upsert(existing.copyWith(siteName: Value(toName)));
      changed++;
    }
    return changed;
  }

  /// Clears site [name] from every live annotation whose `site_name` matches
  /// it (case-sensitive exact match after trim) — unsetting the name *and*
  /// the coords so the map marker disappears, without deleting the dives.
  /// Persists via [upsert]. Returns the number of annotations changed.
  Future<int> deleteSite(String name) async {
    final target = name.trim();
    if (target.isEmpty) return 0;

    final rows = await _db.getAll(
      'SELECT dive_id FROM dive_annotations '
      'WHERE deleted_at IS NULL AND site_name IS NOT NULL',
    );
    var changed = 0;
    for (final r in rows) {
      final diveId = r['dive_id'] as String;
      final existing = await get(diveId);
      if (existing == null) continue;
      if (existing.siteName?.trim() != target) continue;

      await upsert(existing.copyWith(
        siteName: const Value(null),
        siteLatitude: const Value(null),
        siteLongitude: const Value(null),
      ));
      changed++;
    }
    return changed;
  }

  Future<List<String>> distinctTags() async {
    final rows = await _db.getAll(
      'SELECT tags_json FROM dive_annotations '
      'WHERE deleted_at IS NULL AND tags_json IS NOT NULL',
    );
    final all = <String>{};
    for (final r in rows) {
      all.addAll(_decodeStringList(r['tags_json'] as String?));
    }
    return all.toList();
  }

  /// Distinct values seen for an equipment text column. Used by the
  /// Equipment-tab autocompletes (suit, undersuit, weight_system, dpv,
  /// camera) — typed `column` so the call site reads as
  /// `distinctEquipmentValues('suit')` and we don't have to write five
  /// near-identical methods. Column name is whitelisted to defend
  /// against accidental SQL injection from a future caller.
  Future<List<String>> distinctEquipmentValues(String column) async {
    const allowed = {'suit', 'undersuit', 'weight_system', 'dpv', 'camera'};
    if (!allowed.contains(column)) {
      throw ArgumentError.value(column, 'column', 'not an equipment column');
    }
    final rows = await _db.getAll(
      'SELECT DISTINCT $column FROM dive_annotations '
      'WHERE $column IS NOT NULL AND deleted_at IS NULL',
    );
    return rows
        .map((r) => r[column] as String?)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  // ── Renumbering ─────────────────────────────────────────────────────────

  /// Bulk-set `user_dive_number` for many dives in one transaction (renumber).
  /// A null value clears the custom number. Creates a minimal annotation row
  /// for dives that don't have one yet. Stamps owner/updated/version/sync like
  /// the single upsert.
  Future<void> setUserDiveNumbers(Map<String, int?> byDiveId) async {
    if (byDiveId.isEmpty) return;
    final ownerId = _session.currentSession?.user.id;
    final now = DateTime.now().millisecondsSinceEpoch;
    final ids = byDiveId.keys.toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    await _db.writeTransaction((tx) async {
      final existing = await tx.getAll(
        'SELECT dive_id, version FROM dive_annotations '
        'WHERE dive_id IN ($placeholders)',
        ids,
      );
      final versions = <String, int>{
        for (final r in existing)
          r['dive_id'] as String: (r['version'] as int? ?? 0),
      };
      for (final entry in byDiveId.entries) {
        final diveId = entry.key;
        final number = entry.value;
        if (versions.containsKey(diveId)) {
          await tx.execute(
            'UPDATE dive_annotations SET user_dive_number = ?, '
            'updated_at = ?, version = ?, sync_status = ? WHERE dive_id = ?',
            [number, now, versions[diveId]! + 1, SyncStatus.pending.index, diveId],
          );
        } else {
          await tx.execute(
            'INSERT INTO dive_annotations '
            '(id, owner_id, dive_id, user_dive_number, '
            'created_at, updated_at, version, sync_status) '
            'VALUES (?, ?, ?, ?, ?, ?, 1, ?)',
            [diveId, ownerId, diveId, number, now, now, SyncStatus.pending.index],
          );
        }
      }
    });
  }

  // ── Mapping helpers ─────────────────────────────────────────────────────

  DiveAnnotation _rowToModel(Map<String, dynamic> row) {
    final latE5 = row['site_latitude_e5'] as int?;
    final lonE5 = row['site_longitude_e5'] as int?;
    final buddiesJson = row['buddies_json'] as String?;
    final tagsJson = row['tags_json'] as String?;
    final weightsJson = row['weights_json'] as String?;
    final deletedAt = row['deleted_at'] as int?;
    final syncStatusIdx = row['sync_status'] as int? ?? 0;
    return DiveAnnotation(
      diveId: row['dive_id'] as String,
      siteName: row['site_name'] as String?,
      siteLatitude: latE5 == null ? null : latE5 / 1e5,
      siteLongitude: lonE5 == null ? null : lonE5 / 1e5,
      notes: row['notes'] as String?,
      buddies: _decodeStringList(buddiesJson),
      tags: _decodeStringList(tagsJson),
      rating: row['rating'] as int?,
      conditions: row['conditions'] as String?,
      divemaster: row['divemaster'] as String?,
      displayDecoAlgorithm: row['display_deco_algorithm'] as String?,
      userDiveNumber: row['user_dive_number'] as int?,
      suit: row['suit'] as String?,
      undersuit: row['undersuit'] as String?,
      weightSystem: row['weight_system'] as String?,
      dpv: row['dpv'] as String?,
      camera: row['camera'] as String?,
      visibility: row['visibility'] as int?,
      wavesize: row['wavesize'] as int?,
      current: row['current'] as int?,
      surge: row['surge'] as int?,
      chill: row['chill'] as int?,
      airTempC: (row['air_temp_c'] as num?)?.toDouble(),
      waterTempC: (row['water_temp_c'] as num?)?.toDouble(),
      weights: _decodeWeights(weightsJson),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      deletedAt: deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deletedAt),
      version: row['version'] as int? ?? 1,
      syncStatus: SyncStatus.values[syncStatusIdx.clamp(0, SyncStatus.values.length - 1)],
    );
  }

  /// Decode `weights_json` into a list of [Weight] entries. Tolerates the
  /// same wrapped-string-scalar legacy form `_decodeStringList` does for
  /// the buddies/tags columns (Round 2.2c PowerSync upload-path bug).
  List<Weight> _decodeWeights(String? raw) {
    if (raw == null) return const [];
    try {
      var v = jsonDecode(raw);
      if (v is String) v = jsonDecode(v); // unwrap one level
      if (v is List) {
        return v
            .whereType<Map>()
            .map((m) => Weight.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
    } catch (_) {
      // fall through to empty
    }
    return const [];
  }

  /// Decodes a JSON-text-encoded string list. Tolerates legacy rows where
  /// the value got stored as a wrapped JSON-string scalar (Postgres jsonb
  /// round-trip without proper decode at upload — see Round 2.2c fix).
  List<String> _decodeStringList(String? raw) {
    if (raw == null) return const [];
    try {
      var v = jsonDecode(raw);
      if (v is String) v = jsonDecode(v); // unwrap one level
      if (v is List) return v.cast<String>();
    } catch (_) {
      // fall through to empty
    }
    return const [];
  }
}
