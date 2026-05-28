import 'dart:io';

import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late PowerSyncDatabase db;
  late DiveAnnotationsDao dao;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ccrlogger_psync_');
    db = PowerSyncDatabase(
      schema: appSchema,
      path: p.join(tmpDir.path, 'powersync.db'),
    );
    await db.initialize();
    dao = DiveAnnotationsDao(db, FakeSessionSource());
  });

  tearDown(() async {
    await db.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  // Insert a minimal `dives` row. We only need id + start_time + deleted_at
  // for site stats; the rest are filled with harmless defaults so the row
  // satisfies the schema. start_time is Unix seconds.
  Future<void> insertDive(
    String id,
    int startTimeSeconds, {
    int? deletedAtMs,
  }) async {
    await db.execute(
      'INSERT INTO dives '
      '(id, dc_serial, dc_dive_number, start_time, end_time, '
      'duration_seconds, max_depth_mm, dive_mode, deco_model, '
      'atmospheric_pressure_mbar, water_density, log_version, dc_model, '
      'sample_interval_ms, gas_mixes_json, parser_version, imported_at, '
      'deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id, 1, 1, startTimeSeconds, startTimeSeconds + 3600,
        3600, 30000, 0, 0, 1013, 1030, 1, 0, 10000, '[]', 1,
        startTimeSeconds, deletedAtMs, 1, 0,
      ],
    );
  }

  Future<DiveAnnotation> putSite(
    String diveId,
    String? siteName, {
    double? lat,
    double? lon,
  }) async {
    final now = DateTime.now();
    await dao.upsert(DiveAnnotation(
      diveId: diveId,
      siteName: siteName,
      siteLatitude: lat,
      siteLongitude: lon,
      createdAt: now,
      updatedAt: now,
    ));
    return (await dao.get(diveId))!;
  }

  group('siteStats', () {
    test(
        'returns correct count + first/last + latest coords, sorted by count desc',
        () async {
      // Three dives at distinct times; Lagoon on all three, Reef on one.
      const t1 = 1000000; // earliest
      const t2 = 2000000;
      const t3 = 3000000; // latest
      await insertDive('d1', t1);
      await insertDive('d2', t2);
      await insertDive('d3', t3);
      // Lagoon recorded with coords on d1, then again (newer coords) on d3.
      await putSite('d1', 'Lagoon', lat: 51.5, lon: 4.0);
      await putSite('d2', 'Reef', lat: 52.0, lon: 5.0);
      await putSite('d3', 'Lagoon', lat: 51.6, lon: 4.1);

      final stats = await dao.siteStats();
      expect(stats.map((s) => s.name), ['Lagoon', 'Reef']); // count desc

      final lagoon = stats.firstWhere((s) => s.name == 'Lagoon');
      expect(lagoon.diveCount, 2);
      expect(lagoon.firstDiveTime, t1);
      expect(lagoon.lastDiveTime, t3);
      // Latest coords = the most-recently-updated annotation's coords.
      expect(lagoon.lat, closeTo(51.6, 0.001));
      expect(lagoon.lon, closeTo(4.1, 0.001));

      final reef = stats.firstWhere((s) => s.name == 'Reef');
      expect(reef.diveCount, 1);
      expect(reef.lat, closeTo(52.0, 0.001));
      expect(reef.lon, closeTo(5.0, 0.001));
    });

    test('a site with no coords reports null lat/lon', () async {
      await insertDive('d1', 1000000);
      await putSite('d1', 'Quarry');

      final stats = await dao.siteStats();
      final quarry = stats.firstWhere((s) => s.name == 'Quarry');
      expect(quarry.lat, isNull);
      expect(quarry.lon, isNull);
      expect(quarry.diveCount, 1);
    });

    test('excludes a site whose only dive is soft-deleted', () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000, deletedAtMs: 1234567890);
      await putSite('d1', 'Lagoon');
      await putSite('d2', 'Ghost Reef');

      final stats = await dao.siteStats();
      expect(stats.map((s) => s.name), ['Lagoon']);
      expect(stats.any((s) => s.name == 'Ghost Reef'), isFalse);
    });

    test('a site on both a live and a deleted dive only counts the live one',
        () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000, deletedAtMs: 1234567890);
      await putSite('d1', 'Lagoon');
      await putSite('d2', 'Lagoon');

      final stats = await dao.siteStats();
      final lagoon = stats.firstWhere((s) => s.name == 'Lagoon');
      expect(lagoon.diveCount, 1);
      expect(lagoon.firstDiveTime, 1000000);
      expect(lagoon.lastDiveTime, 1000000);
    });
  });

  group('renameSite', () {
    test('renames across multiple dives', () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000);
      await putSite('d1', 'Old Pier');
      await putSite('d2', 'Old Pier');

      final changed = await dao.renameSite('Old Pier', 'New Pier');
      expect(changed, 2);

      expect((await dao.get('d1'))!.siteName, 'New Pier');
      expect((await dao.get('d2'))!.siteName, 'New Pier');

      final stats = await dao.siteStats();
      expect(stats.any((s) => s.name == 'Old Pier'), isFalse);
      expect(stats.firstWhere((s) => s.name == 'New Pier').diveCount, 2);
    });

    test('merges: two dives sharing the new name both report under it',
        () async {
      // d1 = "Jetty", d2 already "Pier". Rename Jetty → Pier merges.
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000);
      await putSite('d1', 'Jetty');
      await putSite('d2', 'Pier');

      final changed = await dao.renameSite('Jetty', 'Pier');
      expect(changed, 1); // only d1 carried "Jetty"

      expect((await dao.get('d1'))!.siteName, 'Pier');
      expect((await dao.get('d2'))!.siteName, 'Pier');

      final stats = await dao.siteStats();
      expect(stats.any((s) => s.name == 'Jetty'), isFalse);
      // Both dives now report under the merged name.
      expect(stats.firstWhere((s) => s.name == 'Pier').diveCount, 2);
    });

    test('bumps version (mutation goes through upsert)', () async {
      await insertDive('d1', 1000000);
      final before = await putSite('d1', 'Old Pier');

      await dao.renameSite('Old Pier', 'New Pier');
      final after = (await dao.get('d1'))!;
      expect(after.version, greaterThan(before.version));
    });

    test('no-op when from == to or to is empty', () async {
      await insertDive('d1', 1000000);
      await putSite('d1', 'Pier');

      expect(await dao.renameSite('Pier', 'Pier'), 0);
      expect(await dao.renameSite('Pier', ''), 0);
      expect((await dao.get('d1'))!.siteName, 'Pier');
    });
  });

  group('deleteSite', () {
    test('clears name + coords and the site disappears from stats', () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000);
      await putSite('d1', 'Lagoon', lat: 51.5, lon: 4.0);
      await putSite('d2', 'Lagoon', lat: 51.5, lon: 4.0);

      final changed = await dao.deleteSite('Lagoon');
      expect(changed, 2);

      for (final id in ['d1', 'd2']) {
        final ann = (await dao.get(id))!;
        expect(ann.siteName, isNull);
        expect(ann.siteLatitude, isNull);
        expect(ann.siteLongitude, isNull);
      }

      final stats = await dao.siteStats();
      expect(stats.any((s) => s.name == 'Lagoon'), isFalse);
    });

    test('bumps version (mutation goes through upsert)', () async {
      await insertDive('d1', 1000000);
      final before = await putSite('d1', 'Lagoon', lat: 51.5, lon: 4.0);

      await dao.deleteSite('Lagoon');
      final after = (await dao.get('d1'))!;
      expect(after.version, greaterThan(before.version));
    });
  });
}
