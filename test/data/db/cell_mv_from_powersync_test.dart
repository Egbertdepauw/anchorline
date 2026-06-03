import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  // Regression: the per-cell mV view showed "Dives with mV data: 0" because
  // EquipmentDao's cell aggregation queried the Drift `dives`/`dive_samples`
  // tables, but those moved to PowerSync (Phase 2.5). Importing a real CCR
  // dive (which goes to PowerSync) must now surface in the cell-health view.
  test('cell mV aggregation reads dives + samples from PowerSync', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u');
    final diveDao = DiveDao(db, ps, session);
    final equipDao = EquipmentDao(db, ps, session);

    // dive_716 is a CCR Petrel-3 dive — it carries per-cell mV.
    final data = File('test/fixtures/dives/dive_716.bin').readAsBytesSync();
    final parsed =
        ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: 716,
      dcModel: ShearwaterModel.petrel3,
    );
    await diveDao.importDive(
        converted: converted, rawBlob: data, parserVersion: 1);

    final dive = (await diveDao.getAllDives()).single;
    final installed = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000)
        .subtract(const Duration(days: 1));
    final cellId = await equipDao.addCell(slot: 1, installedDate: installed);

    // Before the fix both came back empty (Drift tables are empty).
    final health = await equipDao.evaluateHealthForCell(cellId);
    expect(health.diveCount, greaterThan(0),
        reason: 'cell should see the imported CCR dive in PowerSync');

    final series = await equipDao.surfaceMvSeriesForCell(cellId);
    expect(series, isNotEmpty);
    expect(series.first.diveId, dive.id);
  });

  test('mvSeriesForCell returns surface + peak series in one pass', () async {
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
      dcSerial: 0xB89641E4,
      dcDiveNumber: 716,
      dcModel: ShearwaterModel.petrel3,
    );
    await diveDao.importDive(
        converted: converted, rawBlob: data, parserVersion: 1);

    final dive = (await diveDao.getAllDives()).single;
    final installed = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000)
        .subtract(const Duration(days: 1));
    final cellId = await equipDao.addCell(slot: 1, installedDate: installed);

    final result = await equipDao.mvSeriesForCell(cellId);
    expect(result.surface, isNotEmpty);
    expect(result.peak, isNotEmpty);
    expect(result.peak.first.diveId, dive.id);
    // peak = global max of mv>=5; surface = mean of a subset of those samples,
    // so peak.mv must be >= surface.mv for the same dive.
    expect(result.peak.first.mv,
        greaterThanOrEqualTo(result.surface.first.mv));

    // surfaceMvSeriesForCell now delegates to mvSeriesForCell(...).surface
    final legacy = await equipDao.surfaceMvSeriesForCell(cellId);
    expect(legacy, equals(result.surface));
  });
}
