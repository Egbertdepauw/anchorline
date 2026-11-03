import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  // Regression: the dive-computer detail screen's "recent imports" list was
  // always empty in production because EquipmentDao.recentImportsForComputer
  // read from the Drift `dives` table, but dives moved to PowerSync in
  // Phase 2.5 (DiveDao reads/writes via `_ps`). An imported dive must now
  // surface in the per-computer recent-imports query.
  const serial = 0xB89641E4;

  test('recentImportsForComputer reads imported dives from PowerSync',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u');
    final diveDao = DiveDao(db, ps, session);
    final equipDao = EquipmentDao(db, ps, session);

    final data = File('test/fixtures/dives/dive_716.bin').readAsBytesSync();
    final parsed =
        ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: serial,
      dcDiveNumber: 716,
      dcModel: ShearwaterModel.petrel3,
    );
    await diveDao.importDive(
        converted: converted, rawBlob: data, parserVersion: 1);

    final dive = (await diveDao.getAllDives()).single;

    // Before the fix this returned [] (Drift `dives` table is empty).
    final recent = await equipDao.recentImportsForComputer(serial);
    expect(recent, isNotEmpty);
    expect(recent.first.id, dive.id);
    expect(recent.first.dcSerial, serial);

    // A different computer's serial sees nothing.
    final other = await equipDao.recentImportsForComputer(0xDEADBEEF);
    expect(other, isEmpty);
  });
}
