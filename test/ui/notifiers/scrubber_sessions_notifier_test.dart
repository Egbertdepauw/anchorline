import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/ui/notifiers/equipment_notifiers.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  test('addPack + load surfaces an active session', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = (await openEquipmentDaoForTest(db)).dao;

    final n = ScrubberSessionsNotifier(dao);
    await n.addPack(startedDate: DateTime(2025, 1, 1));
    expect(n.sessions, hasLength(1));
    expect(n.sessions.single.totalMinutes, isNull);
  });

  test('closePack closes the session and computes minutes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = (await openEquipmentDaoForTest(db)).dao;

    final n = ScrubberSessionsNotifier(dao);
    final id = await n.addPack(startedDate: DateTime(2025, 1, 1));
    await n.closePack(id, endedAt: DateTime(2025, 6, 1));
    expect(n.sessions.single.totalMinutes, 0); // no dives recorded
  });
}
