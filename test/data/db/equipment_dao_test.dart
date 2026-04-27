import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late EquipmentDao dao;

  setUp(() {
    db = _db();
    dao = EquipmentDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DiveComputers', () {
    test('upsertDiveComputer inserts a new row', () async {
      await dao.upsertDiveComputer(
        serial: 0xB89641E4,
        model: 0xB407,
        firmwareVersion: 103,
      );
      final list = await dao.listDiveComputers();
      expect(list, hasLength(1));
      expect(list.single.serial, 0xB89641E4);
      expect(list.single.nickname, isNull);
    });

    test('upsertDiveComputer is idempotent on serial and preserves nickname',
        () async {
      await dao.upsertDiveComputer(
        serial: 1,
        model: 0xB407,
        firmwareVersion: 103,
      );
      final inserted = (await dao.listDiveComputers()).single;
      await dao.setComputerNickname(inserted.id, 'Top deck');

      // Second upsert with same serial should not clobber nickname.
      await dao.upsertDiveComputer(
        serial: 1,
        model: 0xB407,
        firmwareVersion: 104,
      );

      final list = await dao.listDiveComputers();
      expect(list, hasLength(1));
      expect(list.single.nickname, 'Top deck');
      expect(list.single.firmwareVersion, 104); // firmware does update
    });

    test('recentImportsForComputer returns recent dives sorted desc', () async {
      await dao.upsertDiveComputer(serial: 0xAA, model: 0xB407);

      // Note: real Dives schema column names differ from the planned task code.
      // We use the actual schema fields here (startTime, endTime,
      // durationSeconds, diveMode, decoModel, etc.) — see lib/data/db/tables.dart.
      await db.into(db.dives).insert(
            DivesCompanion.insert(
              id: 'd1',
              dcSerial: 0xAA,
              dcDiveNumber: 1,
              startTime: 1000,
              endTime: 2000,
              durationSeconds: 1000,
              maxDepthMm: 0,
              diveMode: 0,
              decoModel: 0,
              atmosphericPressureMbar: 1013,
              waterDensity: 1030,
              logVersion: 1,
              dcModel: 0,
              sampleIntervalMs: 10000,
              gasMixesJson: '[]',
              rawBlob: Uint8List(0),
              parserVersion: 1,
              importedAt: 1000,
            ),
          );
      await db.into(db.dives).insert(
            DivesCompanion.insert(
              id: 'd2',
              dcSerial: 0xAA,
              dcDiveNumber: 2,
              startTime: 5000,
              endTime: 6000,
              durationSeconds: 1000,
              maxDepthMm: 0,
              diveMode: 0,
              decoModel: 0,
              atmosphericPressureMbar: 1013,
              waterDensity: 1030,
              logVersion: 1,
              dcModel: 0,
              sampleIntervalMs: 10000,
              gasMixesJson: '[]',
              rawBlob: Uint8List(0),
              parserVersion: 1,
              importedAt: 5000,
            ),
          );

      final recent = await dao.recentImportsForComputer(0xAA, limit: 10);
      expect(recent.map((d) => d.id).toList(), ['d2', 'd1']);
    });
  });

  group('OxygenCells', () {
    test('addCell + listCells round-trip', () async {
      final id = await dao.addCell(slot: 1, label: 'R-22D #001', installedDate: DateTime(2025, 1, 1));
      final cells = await dao.listCells();
      expect(cells, hasLength(1));
      expect(cells.single.id, id);
      expect(cells.single.slot, 1);
      expect(cells.single.label, 'R-22D #001');
    });

    test('listCells sorts active first then retired by retiredDate desc', () async {
      final a = await dao.addCell(slot: 1, label: 'old', installedDate: DateTime(2024, 1, 1));
      final b = await dao.addCell(slot: 2, label: 'active', installedDate: DateTime(2025, 1, 1));
      await dao.retireCell(a, retiredAt: DateTime(2024, 6, 1));

      final cells = await dao.listCells();
      expect(cells.map((c) => c.id).toList(), [b, a]);
    });

    test('deleteCellIfUnused succeeds when no dives overlap', () async {
      final id = await dao.addCell(slot: 1, label: 'unused', installedDate: DateTime(2030, 1, 1));
      final ok = await dao.deleteCellIfUnused(id);
      expect(ok, isTrue);
      expect(await dao.listCells(), isEmpty);
    });
  });
}
