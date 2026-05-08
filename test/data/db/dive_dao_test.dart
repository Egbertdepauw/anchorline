import 'dart:convert';
import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/models/dive.dart' as model;
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

AppDatabase _createInMemoryDb() {
  return AppDatabase(NativeDatabase.memory());
}

ConvertedDive _convertFixture(int diveNumber) {
  final data =
      File('test/fixtures/dives/dive_$diveNumber.bin').readAsBytesSync();
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  final parsed = parser.parse(data);
  return DiveConverter.convert(
    parsed: parsed,
    dcSerial: 0xB89641E4,
    dcDiveNumber: diveNumber,
    dcModel: ShearwaterModel.petrel3,
  );
}

/// Returns a copy of [dive] with [sensorCalibration] substituted in.
/// Lets us assert deterministic round-trip semantics without depending
/// on whatever the parser happens to read out of a fixture binary.
model.Dive _diveWithCalibration(
    model.Dive dive, List<double> sensorCalibration) {
  return model.Dive(
    id: dive.id,
    dcSerial: dive.dcSerial,
    dcDiveNumber: dive.dcDiveNumber,
    startTime: dive.startTime,
    endTime: dive.endTime,
    utcOffsetMinutes: dive.utcOffsetMinutes,
    duration: dive.duration,
    maxDepthMeters: dive.maxDepthMeters,
    diveMode: dive.diveMode,
    decoModel: dive.decoModel,
    gfLow: dive.gfLow,
    gfHigh: dive.gfHigh,
    atmosphericPressureMbar: dive.atmosphericPressureMbar,
    waterDensityKgM3: dive.waterDensityKgM3,
    logVersion: dive.logVersion,
    dcModel: dive.dcModel,
    gasMixes: dive.gasMixes,
    tanks: dive.tanks,
    sampleIntervalMs: dive.sampleIntervalMs,
    sensorCalibration: sensorCalibration,
    configuredStackSeconds: dive.configuredStackSeconds,
    stackRemainingAtStartSeconds: dive.stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: dive.stackRemainingAtEndSeconds,
  );
}

void main() {
  late AppDatabase db;
  late DiveDao dao;

  setUp(() async {
    db = _createInMemoryDb();
    dao = (await openDiveDaoForTest(db)).dao;
  });

  tearDown(() async {
    await db.close();
  });

  group('importDive', () {
    test('imports a dive and its samples atomically', () async {
      final converted = _convertFixture(718);
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      final result = await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );

      expect(result, isTrue); // new dive
    });

    test('dedup: importing same dive twice returns false', () async {
      final converted = _convertFixture(718);
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      final first = await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );
      expect(first, isTrue);

      final second = await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );
      expect(second, isFalse); // duplicate
    });

    test('imports multiple different dives', () async {
      for (final num in [711, 712, 718]) {
        final converted = _convertFixture(num);
        final rawBlob =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        final result = await dao.importDive(
          converted: converted,
          rawBlob: rawBlob,
          parserVersion: 1,
        );
        expect(result, isTrue, reason: 'Dive $num should import successfully');
      }
    });

    test('persists per-cell sensor calibration through the DAO', () async {
      // Substitute a known-good calibration on top of fixture 718 so the
      // round-trip assertion is deterministic regardless of what value
      // the parser pulled from the binary.
      final original = _convertFixture(718);
      final calibration = [0.021, 0.022, 0.020];
      final converted = ConvertedDive(
        dive: _diveWithCalibration(original.dive, calibration),
        samples: original.samples,
      );
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );

      final stored = await dao.getDive(converted.dive.id);
      expect(stored, isNotNull);
      expect(stored!.sensorCalibrationJson, isNotNull);
      final decoded = (jsonDecode(stored.sensorCalibrationJson!) as List)
          .map((v) => (v as num).toDouble())
          .toList();
      expect(decoded, equals(calibration));
    });

    test('OC-style empty calibration is persisted as null', () async {
      // Empty list (OC dives) is stored as NULL so the mapper / chart
      // fallback path is consistent with legacy rows.
      final original = _convertFixture(718);
      final converted = ConvertedDive(
        dive: _diveWithCalibration(original.dive, const <double>[]),
        samples: original.samples,
      );
      final rawBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();

      await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );

      final stored = await dao.getDive(converted.dive.id);
      expect(stored, isNotNull);
      expect(stored!.sensorCalibrationJson, isNull);
    });
  });

  group('queries', () {
    setUp(() async {
      // Import 3 dives for query tests
      for (final num in [711, 712, 718]) {
        final converted = _convertFixture(num);
        final rawBlob =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        await dao.importDive(
          converted: converted,
          rawBlob: rawBlob,
          parserVersion: 1,
        );
      }
    });

    test('diveExists returns true for imported dives', () async {
      final converted = _convertFixture(718);
      expect(await dao.diveExists(converted.dive.id), isTrue);
    });

    test('diveExists returns false for unknown dives', () async {
      expect(await dao.diveExists('nonexistent'), isFalse);
    });

    test('getAllDives returns all imported dives ordered by start time desc',
        () async {
      final dives = await dao.getAllDives();
      expect(dives, hasLength(3));
      // Most recent first
      for (var i = 1; i < dives.length; i++) {
        expect(dives[i].startTime, lessThanOrEqualTo(dives[i - 1].startTime));
      }
    });

    test('getSamples returns correct sample data', () async {
      final converted = _convertFixture(718);
      final samples = await dao.getSamples(converted.dive.id);

      expect(samples, isNotNull);
      expect(samples!.sampleCount, equals(converted.samples.sampleCount));
      expect(samples.depthMeters, equals(converted.samples.depthMeters));
      expect(samples.ppo2Bar, equals(converted.samples.ppo2Bar));
    });

    test('getSamples returns null for unknown dive', () async {
      final samples = await dao.getSamples('nonexistent');
      expect(samples, isNull);
    });

    test('getRawBlob returns the original binary', () async {
      final converted = _convertFixture(718);
      final originalBlob =
          File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
      final stored = await dao.getRawBlob(converted.dive.id);

      expect(stored, isNotNull);
      expect(stored, equals(originalBlob));
    });
  });

  group('subsurface upload tracking', () {
    setUp(() async {
      for (final num in [711, 712, 718]) {
        final converted = _convertFixture(num);
        final rawBlob =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        await dao.importDive(
          converted: converted,
          rawBlob: rawBlob,
          parserVersion: 1,
        );
      }
    });

    test('all imports start as pending uploads', () async {
      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(3));
      // Ascending by start time.
      for (var i = 1; i < pending.length; i++) {
        expect(pending[i].startTime,
            greaterThanOrEqualTo(pending[i - 1].startTime));
      }
    });

    test('markSubsurfaceUploaded removes them from pending', () async {
      final marked = _convertFixture(718).dive.id;
      await dao.markSubsurfaceUploaded([marked], 1700000000);

      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(2));
      expect(pending.every((d) => d.id != marked), isTrue);
      // Ordering preserved.
      for (var i = 1; i < pending.length; i++) {
        expect(pending[i].startTime,
            greaterThanOrEqualTo(pending[i - 1].startTime));
      }
    });

    test('markSubsurfaceUploaded with empty list is a no-op', () async {
      await dao.markSubsurfaceUploaded(const [], 1700000000);
      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(3));
    });
  });

  group('soft-delete', () {
    setUp(() async {
      // The 'subsurface uploaded' group's setUp imports 711/712/718 in
      // its own scope; this group needs its own seed.
      for (final n in [711, 712, 718]) {
        final converted = _convertFixture(n);
        final raw = File('test/fixtures/dives/dive_$n.bin').readAsBytesSync();
        await dao.importDive(
          converted: converted,
          rawBlob: raw,
          parserVersion: 1,
        );
      }
    });

    test('softDeleteDive hides the dive from getAllDives', () async {
      final id = (await dao.getAllDives()).first.id;
      await dao.softDeleteDive(id);
      final visible = await dao.getAllDives();
      expect(visible.any((d) => d.id == id), isFalse);
      expect(visible, hasLength(2));
    });

    test('softDeleteDive also excludes from pending Subsurface uploads',
        () async {
      final id = (await dao.getAllDives()).first.id;
      final beforeCount = (await dao.getPendingSubsurfaceUploads()).length;
      await dao.softDeleteDive(id);
      final pending = await dao.getPendingSubsurfaceUploads();
      expect(pending, hasLength(beforeCount - 1));
      expect(pending.any((d) => d.id == id), isFalse);
    });

    test('getDive still returns soft-deleted rows (for the undo path)',
        () async {
      final id = (await dao.getAllDives()).first.id;
      await dao.softDeleteDive(id);
      final row = await dao.getDive(id);
      expect(row, isNotNull);
      expect(row!.deletedAt, isNotNull);
    });

    test('restoreDive clears deletedAt and re-includes the dive', () async {
      final id = (await dao.getAllDives()).first.id;
      await dao.softDeleteDive(id);
      expect((await dao.getAllDives()).any((d) => d.id == id), isFalse);
      await dao.restoreDive(id);
      final visible = await dao.getAllDives();
      expect(visible.any((d) => d.id == id), isTrue);
      expect(visible, hasLength(3));
    });
  });
}
