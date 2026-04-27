import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveAnnotationsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveAnnotationsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('load → set fields → dirty == true → save → dirty == false', () async {
    final n = DiveAnnotationsNotifier(dao);
    await n.load('dive_x');
    expect(n.dirty, isFalse);

    n.setSiteName('Test Site');
    expect(n.dirty, isTrue);

    await n.save();
    expect(n.dirty, isFalse);

    final got = await dao.get('dive_x');
    expect(got?.siteName, 'Test Site');
  });

  test('save persists cylinder mappings', () async {
    final n = DiveAnnotationsNotifier(dao);
    await n.load('dive_y');
    n.setCylinderForMix(0, 'cyl_o2');
    n.setCylinderForMix(1, null);
    await n.save();

    final rows = await dao.listCylindersForDive('dive_y');
    expect(rows, hasLength(2));
    expect(rows.firstWhere((r) => r.gasMixIndex == 0).cylinderId, 'cyl_o2');
    expect(rows.firstWhere((r) => r.gasMixIndex == 1).cylinderId, isNull);
  });
}
