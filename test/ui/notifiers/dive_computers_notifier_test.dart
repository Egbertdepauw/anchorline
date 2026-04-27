import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load() populates list and notifies', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    await dao.upsertDiveComputer(serial: 1, model: 0xB407);

    final n = DiveComputersNotifier(dao);
    var notified = 0;
    n.addListener(() => notified++);

    await n.load();
    expect(n.computers, hasLength(1));
    expect(notified, greaterThan(0));
  });

  test('setMapping persists and reloads mappings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    await dao.upsertDiveComputer(serial: 1, model: 0xB407);
    final dcs = await dao.listDiveComputers();
    final dcId = dcs.single.id;

    final n = DiveComputersNotifier(dao);
    await n.setMapping(dcId, 0, 'cyl_a');
    expect(n.mappings, hasLength(1));
    expect(n.mappings.single.cylinderId, 'cyl_a');
  });
}
