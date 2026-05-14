import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late EquipmentDao dao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = (await openEquipmentDaoForTest(db)).dao;
    await dao.addCylinder(
      label: 'AL40',
      role: CylinderRole.bailout,
      bailoutOrder: 1,
      volumeLiters: 5.7,
      workingPressureBar: 207,
    );
  });

  tearDown(() async => db.close());

  Future<String> cylinderId() async {
    final cyls = await dao.listCylinders();
    return cyls.single.id;
  }

  test('addBailoutCarry + listBailoutCarry round-trip', () async {
    final cylId = await cylinderId();
    await dao.addBailoutCarry(
      diveId: 'dive-1',
      cylinderId: cylId,
      gasMix: '21/35',
      fillPressureBar: 200,
      bailoutOrder: 1,
    );
    final rows = await dao.listBailoutCarry('dive-1');
    expect(rows, hasLength(1));
    expect(rows.single.gasMix, '21/35');
    expect(rows.single.fillPressureBar, 200);
    expect(rows.single.bailoutOrder, 1);
  });

  test('updateBailoutCarry mutates only specified fields', () async {
    final cylId = await cylinderId();
    await dao.addBailoutCarry(
      diveId: 'dive-1',
      cylinderId: cylId,
      gasMix: '21/35',
      bailoutOrder: 1,
    );
    final rowId = (await dao.listBailoutCarry('dive-1')).single.id;
    await dao.updateBailoutCarry(rowId, gasMix: '18/45');
    final updated = (await dao.listBailoutCarry('dive-1')).single;
    expect(updated.gasMix, '18/45');
    expect(updated.bailoutOrder, 1);
  });

  test('deleteBailoutCarry soft-deletes the row', () async {
    final cylId = await cylinderId();
    await dao.addBailoutCarry(
      diveId: 'dive-1',
      cylinderId: cylId,
      gasMix: '50',
      bailoutOrder: 1,
    );
    final id = (await dao.listBailoutCarry('dive-1')).single.id;
    await dao.deleteBailoutCarry(id);
    expect(await dao.listBailoutCarry('dive-1'), isEmpty);
  });

  test('listBailoutCarryWithCylinders joins physical cylinder', () async {
    final cylId = await cylinderId();
    await dao.addBailoutCarry(
      diveId: 'dive-1',
      cylinderId: cylId,
      gasMix: '50',
      bailoutOrder: 2,
    );
    final joined = await dao.listBailoutCarryWithCylinders('dive-1');
    expect(joined, hasLength(1));
    expect(joined.single.cylinder.label, 'AL40');
    expect(joined.single.carry.gasMix, '50');
  });

  test('list orders by bailoutOrder ascending', () async {
    final cyl1 = await cylinderId();
    await dao.addCylinder(
      label: 'AL40 #2',
      role: CylinderRole.bailout,
      bailoutOrder: 2,
      volumeLiters: 5.7,
      workingPressureBar: 207,
    );
    final cyls = await dao.listCylinders();
    final cyl2 = cyls.firstWhere((c) => c.label == 'AL40 #2').id;

    await dao.addBailoutCarry(
      diveId: 'd',
      cylinderId: cyl1,
      gasMix: '100',
      bailoutOrder: 3,
    );
    await dao.addBailoutCarry(
      diveId: 'd',
      cylinderId: cyl2,
      gasMix: '50',
      bailoutOrder: 1,
    );
    final ordered = await dao.listBailoutCarry('d');
    expect(ordered.map((r) => r.bailoutOrder).toList(), [1, 3]);
  });
}
