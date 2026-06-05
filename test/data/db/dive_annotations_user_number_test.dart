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
  return DiveAnnotation(diveId: diveId, createdAt: now, updatedAt: now);
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

  group('setUserDiveNumbers', () {
    test('creates minimal annotation rows and round-trips userDiveNumber',
        () async {
      await dao.setUserDiveNumbers({'a': 482, 'b': 483});
      final map = await dao.getAnnotationsForDives(['a', 'b']);
      expect(map['a']!.userDiveNumber, 482);
      expect(map['b']!.userDiveNumber, 483);
    });

    test('clears userDiveNumber when set to null', () async {
      await dao.setUserDiveNumbers({'a': 482});
      expect(
          (await dao.getAnnotationsForDives(['a']))['a']!.userDiveNumber, 482);

      await dao.setUserDiveNumbers({'a': null});
      expect((await dao.getAnnotationsForDives(['a']))['a']!.userDiveNumber,
          isNull);
    });

    test('updates existing annotation row without clobbering other fields',
        () async {
      // Upsert a full annotation for dive 'c' with a site name.
      await dao.upsert(
          _blank('c').copyWith(siteName: const Value('Test Site')));
      final before = (await dao.getAnnotationsForDives(['c']))['c']!;
      expect(before.siteName, 'Test Site');
      expect(before.userDiveNumber, isNull);

      await dao.setUserDiveNumbers({'c': 99});
      final after = (await dao.getAnnotationsForDives(['c']))['c']!;
      expect(after.userDiveNumber, 99);
      // Site name must survive — UPDATE touches only user_dive_number +
      // version/updated_at/sync_status, not the rest of the row.
      expect(after.siteName, 'Test Site');
      expect(after.version, greaterThan(before.version));
    });

    test('is a no-op for empty map', () async {
      await dao.setUserDiveNumbers({});
      expect(await dao.getAnnotationsForDives(['x']), isEmpty);
    });
  });
}
