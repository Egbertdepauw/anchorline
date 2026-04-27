import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load + add round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);

    final n = CellsNotifier(dao);
    await n.load();
    expect(n.cells, isEmpty);

    await n.addCell(slot: 1, label: 'R-22D');
    expect(n.cells, hasLength(1));
    expect(n.cells.single.label, 'R-22D');
  });
}
