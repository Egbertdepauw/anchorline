import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/sample_codec/column_packer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

AppDatabase _db() => AppDatabase(NativeDatabase.memory());

/// Inserts a Dives row + a DiveSamples row whose per-channel blobs hold
/// the supplied Float32 series. All other channels are filled with
/// zero-blobs of the same length. Returns the dive id.
Future<String> _insertDiveWithSamples(
  AppDatabase db, {
  required String id,
  required int dcSerial,
  required DateTime startTime,
  required List<double> depthM,
  required List<double> cellMv0,
  required List<double> cellMv1,
  required List<double> cellMv2,
}) async {
  final n = depthM.length;
  assert(cellMv0.length == n && cellMv1.length == n && cellMv2.length == n);

  Uint8List packF(List<double> xs) =>
      ColumnPacker.packFloat32(Float32List.fromList(xs));
  final zerosF = packF(List.filled(n, 0.0));

  await db.into(db.dives).insert(DivesCompanion.insert(
        id: id,
        dcSerial: dcSerial,
        dcDiveNumber: 1,
        startTime: startTime.millisecondsSinceEpoch,
        endTime: startTime.millisecondsSinceEpoch + 60 * 1000,
        durationSeconds: 60,
        maxDepthMm: 0,
        diveMode: 0,
        decoModel: 0,
        atmosphericPressureMbar: 1013,
        waterDensity: 1030,
        logVersion: 1,
        dcModel: 0xB407,
        sampleIntervalMs: 10000,
        gasMixesJson: '[]',
        rawBlob: Uint8List(0),
        parserVersion: 1,
        importedAt: 0,
      ));

  await db.into(db.diveSamples).insert(DiveSamplesCompanion.insert(
        diveId: id,
        sampleCount: n,
        depthBlob: packF(depthM),
        temperatureBlob: zerosF,
        ppo2Blob: zerosF,
        cellMv0Blob: packF(cellMv0),
        cellMv1Blob: packF(cellMv1),
        cellMv2Blob: packF(cellMv2),
        setpointBlob: zerosF,
        cnsBlob: zerosF,
        decoDepthBlob: zerosF,
        decoTimeBlob:
            ColumnPacker.packInt32(Int32List.fromList(List.filled(n, 0))),
        ttsBlob:
            ColumnPacker.packInt32(Int32List.fromList(List.filled(n, 0))),
        gasMixIdxBlob:
            ColumnPacker.packUint8(Uint8List.fromList(List.filled(n, 0))),
        statusBlob:
            ColumnPacker.packUint8(Uint8List.fromList(List.filled(n, 0))),
      ));

  return id;
}

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

    test('deleteCellIfUnused refuses when a dive falls in the cell window',
        () async {
      await dao.upsertDiveComputer(serial: 0xAA, model: 0xB407);
      await db.into(db.dives).insert(DivesCompanion.insert(
        id: 'd1',
        dcSerial: 0xAA,
        dcDiveNumber: 1,
        startTime: DateTime(2025, 6, 1).millisecondsSinceEpoch,
        endTime: DateTime(2025, 6, 1).millisecondsSinceEpoch + 3600 * 1000,
        durationSeconds: 3600,
        maxDepthMm: 0,
        diveMode: 0,
        decoModel: 0,
        atmosphericPressureMbar: 1013,
        waterDensity: 1030,
        logVersion: 1,
        dcModel: 0xB407,
        sampleIntervalMs: 10000,
        gasMixesJson: '[]',
        rawBlob: Uint8List(0),
        parserVersion: 1,
        importedAt: 0,
      ));
      final id = await dao.addCell(slot: 1, installedDate: DateTime(2025, 1, 1));
      final ok = await dao.deleteCellIfUnused(id);
      expect(ok, isFalse);
      expect(await dao.listCells(), hasLength(1));
    });

    test('deleteCellIfUnused allows delete when both dates are null (no window)',
        () async {
      await dao.upsertDiveComputer(serial: 0xAA, model: 0xB407);
      await db.into(db.dives).insert(DivesCompanion.insert(
        id: 'd2',
        dcSerial: 0xAA,
        dcDiveNumber: 2,
        startTime: DateTime(2025, 6, 1).millisecondsSinceEpoch,
        endTime: DateTime(2025, 6, 1).millisecondsSinceEpoch + 3600 * 1000,
        durationSeconds: 3600,
        maxDepthMm: 0,
        diveMode: 0,
        decoModel: 0,
        atmosphericPressureMbar: 1013,
        waterDensity: 1030,
        logVersion: 1,
        dcModel: 0xB407,
        sampleIntervalMs: 10000,
        gasMixesJson: '[]',
        rawBlob: Uint8List(0),
        parserVersion: 1,
        importedAt: 0,
      ));
      final id = await dao.addCell(slot: 1); // no installedDate
      final ok = await dao.deleteCellIfUnused(id);
      expect(ok, isTrue);
    });
  });

  group('surfaceMvSeriesForCell', () {
    test('returns mean of cellMv samples below 1.0m, voted-out filtered',
        () async {
      final cellId = await dao.addCell(
        slot: 1,
        label: 'test',
        installedDate: DateTime(2025, 1, 1),
      );
      // Slot 1 → cellMv0 column.
      await _insertDiveWithSamples(
        db,
        id: 'dive_a',
        dcSerial: 1,
        startTime: DateTime(2025, 6, 1),
        depthM: [0.0, 0.5, 5.0, 0.5, 0.0],
        cellMv0: [10.0, 11.0, 50.0, 12.0, 9.0], // surface samples avg = 10.5
        cellMv1: [0, 0, 0, 0, 0],
        cellMv2: [0, 0, 0, 0, 0],
      );

      final series = await dao.surfaceMvSeriesForCell(cellId);
      expect(series, hasLength(1));
      expect(series.single.mv, closeTo(10.5, 0.01));
      expect(series.single.diveId, 'dive_a');
    });

    test('omits dives outside the cell window', () async {
      final cellId = await dao.addCell(
        slot: 1,
        label: 't',
        installedDate: DateTime(2025, 1, 1),
      );
      await dao.retireCell(cellId, retiredAt: DateTime(2025, 3, 1));

      await _insertDiveWithSamples(
        db,
        id: 'dive_outside',
        dcSerial: 1,
        startTime: DateTime(2025, 6, 1),
        depthM: [0.0],
        cellMv0: [10.0],
        cellMv1: [0],
        cellMv2: [0],
      );

      expect(await dao.surfaceMvSeriesForCell(cellId), isEmpty);
    });

    test('omits dives whose surface samples are all voted-out', () async {
      final cellId = await dao.addCell(
        slot: 1,
        label: 't',
        installedDate: DateTime(2025, 1, 1),
      );
      await _insertDiveWithSamples(
        db,
        id: 'dive_vo',
        dcSerial: 1,
        startTime: DateTime(2025, 6, 1),
        depthM: [0.0, 0.5, 0.0],
        cellMv0: [2.0, 3.0, 1.0], // all below 5 mV → treated as voted-out
        cellMv1: [0, 0, 0],
        cellMv2: [0, 0, 0],
      );

      expect(await dao.surfaceMvSeriesForCell(cellId), isEmpty);
    });
  });
}
