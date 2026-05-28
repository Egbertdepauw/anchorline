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
  // for buddy stats; the rest are filled with harmless defaults so the row
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

  Future<DiveAnnotation> putAnnotation(
    String diveId,
    List<String> buddies,
  ) async {
    final now = DateTime.now();
    await dao.upsert(DiveAnnotation(
      diveId: diveId,
      buddies: buddies,
      createdAt: now,
      updatedAt: now,
    ));
    return (await dao.get(diveId))!;
  }

  group('buddyStats', () {
    test('returns correct count + first/last times, sorted by count desc',
        () async {
      // Three dives at distinct times; Alex on all three, Sam on two.
      const t1 = 1000000; // earliest
      const t2 = 2000000;
      const t3 = 3000000; // latest
      await insertDive('d1', t1);
      await insertDive('d2', t2);
      await insertDive('d3', t3);
      await putAnnotation('d1', ['Alex', 'Sam']);
      await putAnnotation('d2', ['Alex']);
      await putAnnotation('d3', ['Alex', 'Sam']);

      final stats = await dao.buddyStats();
      expect(stats.map((s) => s.name), ['Alex', 'Sam']); // count desc

      final alex = stats.firstWhere((s) => s.name == 'Alex');
      expect(alex.diveCount, 3);
      expect(alex.firstDiveTime, t1);
      expect(alex.lastDiveTime, t3);

      final sam = stats.firstWhere((s) => s.name == 'Sam');
      expect(sam.diveCount, 2);
      expect(sam.firstDiveTime, t1);
      expect(sam.lastDiveTime, t3);
    });

    test('excludes buddies whose only dive is soft-deleted', () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000, deletedAtMs: 1234567890);
      await putAnnotation('d1', ['Alex']);
      await putAnnotation('d2', ['Ghost']);

      final stats = await dao.buddyStats();
      expect(stats.map((s) => s.name), ['Alex']);
      expect(stats.any((s) => s.name == 'Ghost'), isFalse);
    });

    test('a buddy on both a live and a deleted dive only counts the live one',
        () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000, deletedAtMs: 1234567890);
      await putAnnotation('d1', ['Alex']);
      await putAnnotation('d2', ['Alex']);

      final stats = await dao.buddyStats();
      final alex = stats.firstWhere((s) => s.name == 'Alex');
      expect(alex.diveCount, 1);
      expect(alex.firstDiveTime, 1000000);
      expect(alex.lastDiveTime, 1000000);
    });
  });

  group('renameBuddy', () {
    test('renames across multiple dives', () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000);
      await putAnnotation('d1', ['Jon', 'Sam']);
      await putAnnotation('d2', ['Jon']);

      final changed = await dao.renameBuddy('Jon', 'John');
      expect(changed, 2);

      expect((await dao.get('d1'))!.buddies, ['John', 'Sam']);
      expect((await dao.get('d2'))!.buddies, ['John']);

      final stats = await dao.buddyStats();
      expect(stats.any((s) => s.name == 'Jon'), isFalse);
      expect(stats.firstWhere((s) => s.name == 'John').diveCount, 2);
    });

    test('merges + dedupes when target already present in a dive', () async {
      await insertDive('d1', 1000000);
      await putAnnotation('d1', ['Jon', 'John', 'Sam']);

      final changed = await dao.renameBuddy('Jon', 'John');
      expect(changed, 1);

      final buddies = (await dao.get('d1'))!.buddies;
      // No duplicate "John" after the merge.
      expect(buddies.where((b) => b == 'John'), hasLength(1));
      expect(buddies, ['John', 'Sam']);
    });

    test('bumps version (mutation goes through upsert)', () async {
      await insertDive('d1', 1000000);
      final before = await putAnnotation('d1', ['Jon']);

      await dao.renameBuddy('Jon', 'John');
      final after = (await dao.get('d1'))!;
      expect(after.version, greaterThan(before.version));
    });

    test('no-op when from == to or to is empty', () async {
      await insertDive('d1', 1000000);
      await putAnnotation('d1', ['Jon']);

      expect(await dao.renameBuddy('Jon', 'Jon'), 0);
      expect(await dao.renameBuddy('Jon', ''), 0);
      expect((await dao.get('d1'))!.buddies, ['Jon']);
    });
  });

  group('deleteBuddy', () {
    test('removes the name from all dives and it disappears from stats',
        () async {
      await insertDive('d1', 1000000);
      await insertDive('d2', 2000000);
      await putAnnotation('d1', ['Alex', 'Sam']);
      await putAnnotation('d2', ['Sam']);

      final changed = await dao.deleteBuddy('Sam');
      expect(changed, 2);

      expect((await dao.get('d1'))!.buddies, ['Alex']);
      expect((await dao.get('d2'))!.buddies, isEmpty);

      final stats = await dao.buddyStats();
      expect(stats.any((s) => s.name == 'Sam'), isFalse);
      expect(stats.map((s) => s.name), ['Alex']);
    });

    test('bumps version (mutation goes through upsert)', () async {
      await insertDive('d1', 1000000);
      final before = await putAnnotation('d1', ['Alex', 'Sam']);

      await dao.deleteBuddy('Sam');
      final after = (await dao.get('d1'))!;
      expect(after.version, greaterThan(before.version));
    });
  });
}
