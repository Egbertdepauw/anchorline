/// Data Access Object for dive annotations and per-dive cylinder linkage.
///
/// Owns the `DiveAnnotations` and `DiveCylinders` tables. This file lands
/// the annotation CRUD half (read, upsert, distinct lookups). The cylinder
/// linkage methods land in a follow-up task.
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
