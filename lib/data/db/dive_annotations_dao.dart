/// Data Access Object for dive annotations and per-dive cylinder linkage.
///
/// Owns the `DiveAnnotations` and `DiveCylinders` tables: annotation CRUD
/// (read, upsert, distinct lookups for autocomplete pools) plus per-dive
/// gas-mix-to-cylinder mapping with a transactional `saveAll` that the
/// notifier uses to persist both halves atomically.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/annotation.dart' as dom;
import 'database.dart';
import 'tables.dart';

part 'dive_annotations_dao.g.dart';

@DriftAccessor(tables: [DiveAnnotations, DiveCylinders])
class DiveAnnotationsDao extends DatabaseAccessor<AppDatabase>
    with _$DiveAnnotationsDaoMixin {
  DiveAnnotationsDao(super.db);

  // ── DiveAnnotations ─────────────────────────────────────────────────────

  Future<dom.DiveAnnotation?> get(String diveId) async {
    final row = await (select(diveAnnotations)
          ..where((t) => t.diveId.equals(diveId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (row == null) return null;
    return _toModel(row);
  }

  Future<void> upsert(dom.DiveAnnotation a) async {
    await into(diveAnnotations).insertOnConflictUpdate(_toCompanion(a));
  }

  /// Returns the most recent (by updatedAt desc) lat/lon recorded for any
  /// annotation with this site name. Returns null if no match or both
  /// coords are null.
  Future<({double? lat, double? lon})?> getLatestSiteCoords(
      String siteName) async {
    if (siteName.trim().isEmpty) return null;
    final row = await (select(diveAnnotations)
          ..where((t) =>
              t.siteName.equals(siteName) &
              t.deletedAt.isNull() &
              (t.siteLatitudeE5.isNotNull() | t.siteLongitudeE5.isNotNull()))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    return (
      lat: row.siteLatitudeE5 == null ? null : row.siteLatitudeE5! / 1e5,
      lon: row.siteLongitudeE5 == null ? null : row.siteLongitudeE5! / 1e5,
    );
  }

  /// Batch-loads annotations for a list of dive ids. Returns a map keyed
  /// by diveId; dives without an annotation row are absent from the map.
  Future<Map<String, dom.DiveAnnotation>> getAnnotationsForDives(
      Iterable<String> diveIds) async {
    if (diveIds.isEmpty) return const {};
    final rows = await (select(diveAnnotations)
          ..where((t) => t.diveId.isIn(diveIds) & t.deletedAt.isNull()))
        .get();
    return {for (final r in rows) r.diveId: _toModel(r)};
  }

  /// Returns one entry per distinct (lat, lon) pair across all non-deleted
  /// annotations where both coords are non-null. Coords are rounded to 5dp
  /// before deduping (matches the storage precision). Site name is taken
  /// from the most-recent annotation at those coords (may be null).
  /// Sorted alphabetically by site name with null-named entries last.
  Future<List<({String? siteName, double lat, double lon})>>
      distinctSiteCoords() async {
    final rows = await (select(diveAnnotations)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.siteLatitudeE5.isNotNull() &
              t.siteLongitudeE5.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    final byKey = <String, ({String? siteName, double lat, double lon})>{};
    for (final r in rows) {
      final lat = r.siteLatitudeE5! / 1e5;
      final lon = r.siteLongitudeE5! / 1e5;
      final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
      byKey.putIfAbsent(
          key, () => (siteName: r.siteName, lat: lat, lon: lon));
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
    final rows = await (selectOnly(diveAnnotations, distinct: true)
          ..addColumns([diveAnnotations.siteName])
          ..where(diveAnnotations.siteName.isNotNull() &
              diveAnnotations.deletedAt.isNull()))
        .get();
    return rows
        .map((r) => r.read(diveAnnotations.siteName))
        .whereType<String>()
        .toList();
  }

  Future<List<String>> distinctBuddies() async {
    final rows = await (select(diveAnnotations)
          ..where((t) => t.deletedAt.isNull() & t.buddiesJson.isNotNull()))
        .get();
    final all = <String>{};
    for (final r in rows) {
      if (r.buddiesJson == null) continue;
      final list = (jsonDecode(r.buddiesJson!) as List).cast<String>();
      all.addAll(list);
    }
    return all.toList();
  }

  Future<List<String>> distinctTags() async {
    final rows = await (select(diveAnnotations)
          ..where((t) => t.deletedAt.isNull() & t.tagsJson.isNotNull()))
        .get();
    final all = <String>{};
    for (final r in rows) {
      if (r.tagsJson == null) continue;
      final list = (jsonDecode(r.tagsJson!) as List).cast<String>();
      all.addAll(list);
    }
    return all.toList();
  }

  // ── DiveCylinders ───────────────────────────────────────────────────────

  Future<List<DiveCylinder>> listCylindersForDive(String diveId) {
    return (select(diveCylinders)
          ..where((t) => t.diveId.equals(diveId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.gasMixIndex)]))
        .get();
  }

  Future<void> setDiveCylinder(
      String diveId, int gasMixIndex, String? cylinderId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await into(diveCylinders).insertOnConflictUpdate(
      DiveCylindersCompanion.insert(
        diveId: diveId,
        gasMixIndex: gasMixIndex,
        cylinderId: Value(cylinderId),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Writes the annotation row and all dive-cylinder rows atomically.
  Future<void> saveAll(
    dom.DiveAnnotation annotation,
    List<({int gasMixIndex, String? cylinderId})> mappings,
  ) async {
    await db.transaction(() async {
      await upsert(annotation);
      for (final m in mappings) {
        await setDiveCylinder(annotation.diveId, m.gasMixIndex, m.cylinderId);
      }
    });
  }

  // ── Mapping helpers ─────────────────────────────────────────────────────

  /// Maps the Drift-generated row class (named `DiveAnnotation` —
  /// the auto-singular of the table — and importantly NOT prefixed)
  /// to our domain class (prefixed with `dom.`).
  dom.DiveAnnotation _toModel(DiveAnnotation row) {
    return dom.DiveAnnotation(
      diveId: row.diveId,
      siteName: row.siteName,
      siteLatitude:
          row.siteLatitudeE5 == null ? null : row.siteLatitudeE5! / 1e5,
      siteLongitude:
          row.siteLongitudeE5 == null ? null : row.siteLongitudeE5! / 1e5,
      notes: row.notes,
      buddies: row.buddiesJson == null
          ? const []
          : (jsonDecode(row.buddiesJson!) as List).cast<String>(),
      tags: row.tagsJson == null
          ? const []
          : (jsonDecode(row.tagsJson!) as List).cast<String>(),
      rating: row.rating,
      conditions: row.conditions,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      deletedAt: row.deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.deletedAt!),
      version: row.version,
      syncStatus: dom.SyncStatus.values[row.syncStatus],
    );
  }

  DiveAnnotationsCompanion _toCompanion(dom.DiveAnnotation a) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return DiveAnnotationsCompanion.insert(
      diveId: a.diveId,
      siteName: Value(a.siteName),
      siteLatitudeE5: Value(
          a.siteLatitude == null ? null : (a.siteLatitude! * 1e5).round()),
      siteLongitudeE5: Value(
          a.siteLongitude == null ? null : (a.siteLongitude! * 1e5).round()),
      notes: Value(a.notes),
      buddiesJson:
          Value(a.buddies.isEmpty ? null : jsonEncode(a.buddies)),
      tagsJson: Value(a.tags.isEmpty ? null : jsonEncode(a.tags)),
      rating: Value(a.rating),
      conditions: Value(a.conditions),
      createdAt: a.createdAt.millisecondsSinceEpoch,
      updatedAt: now,
    );
  }
}
