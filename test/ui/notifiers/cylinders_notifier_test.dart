import 'package:ccrlogger/data/db/database.dart';
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
    await n.seedStandard();
    expect(n.cylinders, hasLength(3));
    expect(n.cylinders.map((c) => c.role).toSet(),
        {CylinderRole.oxygen, CylinderRole.diluent, CylinderRole.bailout});
  });
}
