import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  test('seedStandard inserts O2 + Diluent + Bailout', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = (await openEquipmentDaoForTest(db)).dao;

    final n = CylindersNotifier(dao);
    addTearDown(n.dispose);
    await n.seedStandard();
    expect(n.cylinders, hasLength(3));
    expect(n.cylinders.map((c) => c.role).toSet(),
        {CylinderRole.oxygen, CylinderRole.diluent, CylinderRole.bailout});
  });

  test('auto-refreshes when another DAO instance writes (watch round-trip)',
      () async {
    // Two DAO instances against the same PowerSync DB simulates two devices
    // writing into a shared local store. The cloud-side cross-device flow
    // is the same: PowerSync mutates the local table, the watch fires, the
    // notifier reloads.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final rig = await openEquipmentDaoForTest(db);
    final daoA = rig.dao;
    final daoB = EquipmentDao(db, rig.ps, rig.session);

    final n = CylindersNotifier(daoA);
    addTearDown(n.dispose);
    // Wait for the watch's initial emit + ensuing load() to settle.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(n.cylinders, isEmpty);

    // Write via DAO B (simulating a remote-origin write that PowerSync
    // pulled into the local SQLite from the cloud).
    await daoB.addCylinder(
      label: 'Stage AL40',
      role: CylinderRole.bailout,
      bailoutOrder: 1,
      volumeLiters: 5.7,
      workingPressureBar: 232,
    );

    // Watch fires after PowerSync's 30ms throttle; allow a generous window.
    for (var i = 0; i < 20 && n.cylinders.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(n.cylinders, hasLength(1));
    expect(n.cylinders.single.label, 'Stage AL40');
  });
}
