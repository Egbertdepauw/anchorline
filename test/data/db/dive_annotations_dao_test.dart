import 'dart:io';

import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

DiveAnnotation _blank(String diveId) {
  final now = DateTime.now();
  return DiveAnnotation(
    diveId: diveId,
    createdAt: now,
    updatedAt: now,
  );
}

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

  group('annotation CRUD', () {
    test('get returns null for an unannotated dive', () async {
      expect(await dao.get('dive_x'), isNull);
    });

    test('upsert + get round-trips all fields', () async {
      final now = DateTime.now();
      final a = DiveAnnotation(
        diveId: 'dive_a',
        siteName: 'Black Lagoon',
        siteLatitude: 51.92345,
        siteLongitude: 4.47812,
        notes: 'good viz',
        buddies: ['Alex', 'Sam'],
        tags: ['drysuit', 'training'],
        rating: 4,
        conditions: '8m viz, no current',
        createdAt: now,
        updatedAt: now,
      );
      await dao.upsert(a);
      final got = (await dao.get('dive_a'))!;
      expect(got.siteName, 'Black Lagoon');
      expect(got.siteLatitude, closeTo(51.92345, 1e-5));
      expect(got.siteLongitude, closeTo(4.47812, 1e-5));
      expect(got.notes, 'good viz');
      expect(got.buddies, ['Alex', 'Sam']);
      expect(got.tags, ['drysuit', 'training']);
      expect(got.rating, 4);
      expect(got.conditions, '8m viz, no current');
    });

    test('upsert sets created_at/updated_at to sane millis-since-epoch',
        () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await dao.upsert(_blank('dive_t'));
      final got = (await dao.get('dive_t'))!;
      final after = DateTime.now().millisecondsSinceEpoch;
      expect(got.createdAt.millisecondsSinceEpoch,
          greaterThanOrEqualTo(before - 1));
      expect(got.updatedAt.millisecondsSinceEpoch,
          inInclusiveRange(before - 1, after + 1));
    });

    test('upsert is idempotent on diveId and bumps version', () async {
      await dao
          .upsert(_blank('dive_b').copyWith(siteName: const Value('first')));
      final v1 = (await dao.get('dive_b'))!.version;

      await dao
          .upsert(_blank('dive_b').copyWith(siteName: const Value('second')));
      final got = (await dao.get('dive_b'))!;

      expect(got.siteName, 'second');
      expect(got.version, greaterThan(v1));
    });

    test('upsert without session leaves owner_id null in local DB', () async {
      await dao.upsert(_blank('dive_no_owner'));
      final row = await db.get(
          'SELECT owner_id FROM dive_annotations WHERE dive_id = ?',
          ['dive_no_owner']);
      expect(row['owner_id'], isNull);
    });
  });

  group('batch lookups', () {
    test('getAnnotationsForDives returns a map keyed by diveId', () async {
      final now = DateTime.now();
      await dao.upsert(DiveAnnotation(
          diveId: 'd1', siteName: 'A', createdAt: now, updatedAt: now));
      await dao.upsert(DiveAnnotation(
          diveId: 'd2', siteName: 'B', createdAt: now, updatedAt: now));

      final map = await dao.getAnnotationsForDives(['d1', 'd2', 'unknown']);
      expect(map.keys.toSet(), {'d1', 'd2'});
      expect(map['d1']!.siteName, 'A');
      expect(map['d2']!.siteName, 'B');
    });

    test('getAnnotationsForDives is empty for empty input', () async {
      expect(await dao.getAnnotationsForDives(const []), isEmpty);
    });
  });

  group('distinct lookups', () {
    test('distinctSiteNames / distinctBuddies / distinctTags', () async {
      final now = DateTime.now();
      await dao.upsert(DiveAnnotation(
        diveId: 'd1',
        siteName: 'Site A',
        buddies: ['Alex'],
        tags: ['drysuit'],
        createdAt: now,
        updatedAt: now,
      ));
      await dao.upsert(DiveAnnotation(
        diveId: 'd2',
        siteName: 'Site B',
        buddies: ['Alex', 'Sam'],
        tags: ['training', 'drysuit'],
        createdAt: now,
        updatedAt: now,
      ));

      expect((await dao.distinctSiteNames())..sort(), ['Site A', 'Site B']);
      expect((await dao.distinctBuddies())..sort(), ['Alex', 'Sam']);
      expect((await dao.distinctTags())..sort(), ['drysuit', 'training']);
    });
  });

  group('site coords lookup', () {
    test('getLatestSiteCoords returns most-recent stored coords', () async {
      final now = DateTime.now();
      await dao.upsert(DiveAnnotation(
        diveId: 'd1',
        siteName: 'Lagoon',
        siteLatitude: 51.0,
        siteLongitude: 4.0,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ));
      // Sleep briefly so the second upsert's updated_at is strictly later.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await dao.upsert(DiveAnnotation(
        diveId: 'd2',
        siteName: 'Lagoon',
        siteLatitude: 52.5,
        siteLongitude: 5.5,
        createdAt: now,
        updatedAt: now,
      ));
      final got = await dao.getLatestSiteCoords('Lagoon');
      expect(got?.lat, closeTo(52.5, 1e-5));
      expect(got?.lon, closeTo(5.5, 1e-5));
    });

    test('getLatestSiteCoords returns null for unknown site', () async {
      expect(await dao.getLatestSiteCoords('Nowhere'), isNull);
    });

    test('distinctSiteCoords dedups by 5dp and keeps named/unnamed entries',
        () async {
      final now = DateTime.now();
      await dao.upsert(DiveAnnotation(
        diveId: 'd1',
        siteName: 'Lagoon',
        siteLatitude: 51.92345,
        siteLongitude: 4.47812,
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await dao.upsert(DiveAnnotation(
        diveId: 'd2',
        siteName: 'Lagoon',
        siteLatitude: 51.923451, // collapses to 51.92345 at 5dp
        siteLongitude: 4.478124,
        createdAt: now,
        updatedAt: now,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await dao.upsert(DiveAnnotation(
        diveId: 'd3',
        siteName: null,
        siteLatitude: 52.5,
        siteLongitude: 5.5,
        createdAt: now,
        updatedAt: now,
      ));

      final got = await dao.distinctSiteCoords();
      expect(got, hasLength(2));
      // Named entry sorts first; null-named entry last.
      expect(got[0].siteName, 'Lagoon');
      expect(got[0].lat, closeTo(51.92345, 1e-5));
      expect(got[0].lon, closeTo(4.47812, 1e-5));
      expect(got[1].siteName, isNull);
      expect(got[1].lat, closeTo(52.5, 1e-5));
      expect(got[1].lon, closeTo(5.5, 1e-5));
    });

    test('distinctSiteCoords skips coordless rows', () async {
      final now = DateTime.now();
      await dao.upsert(DiveAnnotation(
        diveId: 'd1',
        siteName: 'No coords',
        createdAt: now,
        updatedAt: now,
      ));
      expect(await dao.distinctSiteCoords(), isEmpty);
    });
  });
}
