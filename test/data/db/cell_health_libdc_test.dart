import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/libdc_fixture_dives.dart';
import '../../_helpers/powersync_test_helper.dart';

void main() {
  test('cell health never counts a dive without mV as cells at 0 mV',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u');
    final diveDao = DiveDao(db, ps, session);
    final equipDao = EquipmentDao(db, ps, session);

    // A Divesoft CCR dive: four per-cell ppO2 channels, mV zero-filled.
    await diveDao.importDive(
        converted: divesoftCcrDive(),
        rawBlob: Uint8List(0),
        parserVersion: 1);
    final dive = (await diveDao.getAllDives()).single;
    final installed = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000)
        .subtract(const Duration(days: 1));
    final cellId = await equipDao.addCell(slot: 1, installedDate: installed);

    final series = await equipDao.mvSeriesForCell(cellId);
    expect(series.surface, isEmpty);
    expect(series.peak, isEmpty);
    final health = await equipDao.evaluateHealthForCell(cellId);
    expect(health.diveCount, 0, reason: 'a dive without mV is not a cell dive');
  });
}
