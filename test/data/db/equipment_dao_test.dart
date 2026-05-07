import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/data/sample_codec/column_packer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

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
        startTime: startTime.millisecondsSinceEpoch ~/ 1000,
        endTime: startTime.millisecondsSinceEpoch ~/ 1000 + 60,
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

  setUp(() async {
    db = _db();
    dao = (await openEquipmentDaoForTest(db)).dao;
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
        startTime: DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000,
        endTime:
            DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000 + 3600,
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

    test('addCell throws SlotInUseException when slot already has active cell',
        () async {
      await dao.addCell(slot: 2, label: 'first');
      expect(
        () => dao.addCell(slot: 2, label: 'second'),
        throwsA(isA<SlotInUseException>()),
      );
    });

    test('updateCell throws SlotInUseException when target slot is occupied',
        () async {
      await dao.addCell(slot: 1, label: 'a');
      final b = await dao.addCell(slot: 2, label: 'b');
      expect(
        () => dao.updateCell(b, slot: 1),
        throwsA(isA<SlotInUseException>()),
      );
    });

    test('updateCell allows moving into a slot held only by a retired cell',
        () async {
      final retired = await dao.addCell(
        slot: 1,
        label: 'retired',
        installedDate: DateTime(2024, 1, 1),
      );
      await dao.retireCell(retired, retiredAt: DateTime(2024, 6, 1));
      final fresh = await dao.addCell(slot: 2, label: 'fresh');
      // Should not throw.
      await dao.updateCell(fresh, slot: 1);
      final updated = await dao.getCell(fresh);
      expect(updated!.slot, 1);
    });

    test('updateCell on same id with same slot does not throw', () async {
      final id = await dao.addCell(slot: 3, label: 'x');
      // Slot is unchanged → guard skipped; no exception.
      await dao.updateCell(id, label: 'renamed');
      final updated = await dao.getCell(id);
      expect(updated!.label, 'renamed');
    });

    test('deleteCellIfUnused allows delete when both dates are null (no window)',
        () async {
      await dao.upsertDiveComputer(serial: 0xAA, model: 0xB407);
      await db.into(db.dives).insert(DivesCompanion.insert(
        id: 'd2',
        dcSerial: 0xAA,
        dcDiveNumber: 2,
        startTime: DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000,
        endTime:
            DateTime(2025, 6, 1).millisecondsSinceEpoch ~/ 1000 + 3600,
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

  group('ScrubberSessions', () {
    test('addScrubberSession + listScrubberSessions round-trip', () async {
      final id = await dao.addScrubberSession(
        startedDate: DateTime(2025, 1, 1),
        mediaType: 'Sofnolime 797',
        notes: 'fresh',
      );
      final list = await dao.listScrubberSessions();
      expect(list.single.id, id);
      expect(list.single.mediaType, 'Sofnolime 797');
    });

    test('listScrubberSessions sorts active first then by date desc', () async {
      final old = await dao.addScrubberSession(startedDate: DateTime(2024, 1, 1));
      final active = await dao.addScrubberSession(startedDate: DateTime(2025, 1, 1));
      await dao.closeScrubberSession(old, endedAt: DateTime(2024, 6, 1));

      final list = await dao.listScrubberSessions();
      expect(list.map((s) => s.id).toList(), [active, old]);
    });

    test('applyScrubberEvents is no-op when scrubberResetAt is null', () async {
      final initial = await dao.listScrubberSessions();
      await dao.applyScrubberEvents(scrubberResetAt: null, dcSerial: 1);
      expect(await dao.listScrubberSessions(), initial);
    });

    test('applyScrubberEvents closes open session and opens a new one', () async {
      final open = await dao.addScrubberSession(startedDate: DateTime(2025, 1, 1));
      await dao.applyScrubberEvents(
        scrubberResetAt: DateTime(2025, 6, 1),
        dcSerial: 1,
      );

      final all = await dao.listScrubberSessions();
      expect(all, hasLength(2));
      final closed = all.firstWhere((s) => s.id == open);
      final fresh = all.firstWhere((s) => s.id != open);

      expect(closed.totalMinutes, isNotNull);
      expect(fresh.startedDate, DateTime(2025, 6, 1).millisecondsSinceEpoch);
    });

    test('applyScrubberEvents-closed session has accumulated minutes from dives in window',
        () async {
      final open = await dao.addScrubberSession(startedDate: DateTime(2025, 1, 1));

      Future<void> insertDive(String id, DateTime start, int durationSec) async {
        await db.into(db.dives).insert(DivesCompanion.insert(
          id: id,
          dcSerial: 1,
          dcDiveNumber: int.parse(id.substring(1)),
          startTime: start.millisecondsSinceEpoch ~/ 1000,
          endTime: start.millisecondsSinceEpoch ~/ 1000 + durationSec,
          durationSeconds: durationSec,
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
      }

      // Two 30-minute dives in the open session's window → 60 total minutes.
      await insertDive('d1', DateTime(2025, 2, 1), 30 * 60);
      await insertDive('d2', DateTime(2025, 3, 1), 30 * 60);

      await dao.applyScrubberEvents(
        scrubberResetAt: DateTime(2025, 6, 1),
        dcSerial: 1,
      );

      final all = await dao.listScrubberSessions();
      final closed = all.firstWhere((s) => s.id == open);
      expect(closed.totalMinutes, 60);
    });
  });

  group('Cylinders', () {
    test('addCylinder + listCylinders round-trip', () async {
      final id = await dao.addCylinder(
        label: 'AL40 stage',
        role: CylinderRole.bailout,
        bailoutOrder: 1,
        volumeLiters: 5.7,
        workingPressureBar: 207,
        gasMix: '21/35',
      );
      final list = await dao.listCylinders();
      expect(list, hasLength(1));
      expect(list.single.id, id);
      expect(list.single.role, 'bailout');
      expect(list.single.bailoutOrder, 1);
    });

    test('updateCylinder clears bailoutOrder when role changes away from bailout',
        () async {
      final id = await dao.addCylinder(
        label: 'BO1',
        role: CylinderRole.bailout,
        bailoutOrder: 1,
        volumeLiters: 5.0,
        workingPressureBar: 200,
      );
      await dao.updateCylinder(id, role: CylinderRole.diluent);
      final updated = (await dao.listCylinders()).single;
      expect(updated.role, 'diluent');
      expect(updated.bailoutOrder, isNull);
    });

    test('seedStandardCcrCylinders inserts O2, Diluent, Bailout #1', () async {
      await dao.seedStandardCcrCylinders();
      final list = await dao.listCylinders();
      expect(list.map((c) => c.role).toSet(),
          {'oxygen', 'diluent', 'bailout'});
      final bailout = list.firstWhere((c) => c.role == 'bailout');
      expect(bailout.bailoutOrder, 1);
    });

    test('addCylinder rejects unknown role', () async {
      expect(
        () => dao.addCylinder(
          label: 'x',
          role: 'rocket-fuel',
          volumeLiters: 1,
          workingPressureBar: 200,
        ),
        throwsArgumentError,
      );
    });
  });

  group('PressureMappings', () {
    test('setPressureMapping inserts and round-trips', () async {
      await dao.setPressureMapping(
        diveComputerId: 'dc1',
        channelIndex: 0,
        cylinderId: 'cyl_a',
      );
      final list = await dao.listPressureMappings('dc1');
      expect(list, hasLength(1));
      expect(list.single.cylinderId, 'cyl_a');
    });

    test('setPressureMapping updates existing row', () async {
      await dao.setPressureMapping(
        diveComputerId: 'dc1',
        channelIndex: 0,
        cylinderId: 'cyl_a',
      );
      await dao.setPressureMapping(
        diveComputerId: 'dc1',
        channelIndex: 0,
        cylinderId: 'cyl_b',
      );
      final list = await dao.listPressureMappings('dc1');
      expect(list, hasLength(1));
      expect(list.single.cylinderId, 'cyl_b');
    });

    test('setPressureMapping accepts null (unmapped)', () async {
      await dao.setPressureMapping(
        diveComputerId: 'dc1',
        channelIndex: 0,
        cylinderId: 'cyl_a',
      );
      await dao.setPressureMapping(
        diveComputerId: 'dc1',
        channelIndex: 0,
        cylinderId: null,
      );
      final list = await dao.listPressureMappings('dc1');
      expect(list.single.cylinderId, isNull);
    });
  });
}
