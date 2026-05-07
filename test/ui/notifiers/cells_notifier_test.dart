import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  test('load + add round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = (await openEquipmentDaoForTest(db)).dao;

    final n = CellsNotifier(dao);
    await n.load();
    expect(n.cells, isEmpty);

    await n.addCell(slot: 1, label: 'R-22D');
    expect(n.cells, hasLength(1));
    expect(n.cells.single.label, 'R-22D');
  });
}
