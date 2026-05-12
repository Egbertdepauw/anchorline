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

import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/annotation.dart';

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
          'suit, undersuit, weight_system, dpv, camera, '
          'visibility, wavesize, current, surge, chill, '
          'air_temp_c, water_temp_c, weights_json, '
          'created_at, updated_at, deleted_at, version, sync_status) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
          '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
