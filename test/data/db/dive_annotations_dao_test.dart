import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

DiveAnnotation _blank(String diveId) {
  final now = DateTime.now();
  return DiveAnnotation(
    diveId: diveId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late AppDatabase db;
  late DiveAnnotationsDao dao;

  setUp(() {
    db = _db();
    dao = DiveAnnotationsDao(db);
  });

  tearDown(() async {
    await db.close();
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

    test('upsert is idempotent on diveId', () async {
      await dao.upsert(_blank('dive_b').copyWith(siteName: 'first'));
      await dao.upsert(_blank('dive_b').copyWith(siteName: 'second'));
      final got = (await dao.get('dive_b'))!;
      expect(got.siteName, 'second');
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

  group('cylinder linkage', () {
    test('listCylindersForDive returns rows for the dive', () async {
      await dao.setDiveCylinder('d1', 0, 'cyl_o2');
      await dao.setDiveCylinder('d1', 1, 'cyl_dil');
      final rows = await dao.listCylindersForDive('d1');
      expect(rows.map((r) => r.gasMixIndex).toList()..sort(), [0, 1]);
    });

    test('setDiveCylinder upserts on (diveId, gasMixIndex)', () async {
      await dao.setDiveCylinder('d1', 0, 'cyl_o2');
      await dao.setDiveCylinder('d1', 0, 'cyl_o2_v2');
      final rows = await dao.listCylindersForDive('d1');
      expect(rows, hasLength(1));
      expect(rows.single.cylinderId, 'cyl_o2_v2');
    });

    test('setDiveCylinder accepts null (unmapped)', () async {
      await dao.setDiveCylinder('d1', 0, 'cyl_o2');
      await dao.setDiveCylinder('d1', 0, null);
      final rows = await dao.listCylindersForDive('d1');
      expect(rows.single.cylinderId, isNull);
    });

    test('saveAll writes annotation + cylinders in one transaction', () async {
      final now = DateTime.now();
      final a = DiveAnnotation(
        diveId: 'dx',
        siteName: 'Test Site',
        createdAt: now,
        updatedAt: now,
      );
      await dao.saveAll(a, [
        (gasMixIndex: 0, cylinderId: 'cyl_o2'),
        (gasMixIndex: 1, cylinderId: 'cyl_dil'),
      ]);

      expect((await dao.get('dx'))!.siteName, 'Test Site');
      final rows = await dao.listCylindersForDive('dx');
      expect(rows, hasLength(2));
    });
  });
}
