import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart'
    show SessionSource;
import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync/powersync.dart' hide SyncStatus;
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

class _FakeSessionSource implements SessionSource {
  @override
  Session? get currentSession => null;
  @override
  Future<void> refreshSession() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmpDir;
  late PowerSyncDatabase psDb;
  late DiveAnnotationsDao annotationsDao;
  late EquipmentDao equipmentDao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    equipmentDao = EquipmentDao(db);
    tmpDir = await Directory.systemTemp.createTemp('ccrlogger_psync_');
    psDb = PowerSyncDatabase(
      schema: appSchema,
      path: p.join(tmpDir.path, 'powersync.db'),
    );
    await psDb.initialize();
    annotationsDao = DiveAnnotationsDao(psDb, _FakeSessionSource());
  });

  tearDown(() async {
    await psDb.close();
    await db.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('load → set fields → dirty == true → save → dirty == false', () async {
    final n = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
    await n.load('dive_x');
    expect(n.dirty, isFalse);

    n.setSiteName('Test Site');
    expect(n.dirty, isTrue);

    await n.save();
    expect(n.dirty, isFalse);

    final got = await annotationsDao.get('dive_x');
    expect(got?.siteName, 'Test Site');
  });

  test('save persists cylinder mappings', () async {
    final n = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
    await n.load('dive_y');
    n.setCylinderForMix(0, 'cyl_o2');
    n.setCylinderForMix(1, null);
    await n.save();

    final rows = await equipmentDao.listCylindersForDive('dive_y');
    expect(rows, hasLength(2));
    expect(rows.firstWhere((r) => r.gasMixIndex == 0).cylinderId, 'cyl_o2');
    expect(rows.firstWhere((r) => r.gasMixIndex == 1).cylinderId, isNull);
  });

  test('clearing a previously-set siteName persists null to the DB', () async {
    final n = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
    await n.load('dive_clear');
    n.setSiteName('Black Lagoon');
    await n.save();
    expect((await annotationsDao.get('dive_clear'))!.siteName, 'Black Lagoon');

    await n.load('dive_clear');
    n.setSiteName(null);
    await n.save();
    expect((await annotationsDao.get('dive_clear'))?.siteName, isNull);
  });
}
