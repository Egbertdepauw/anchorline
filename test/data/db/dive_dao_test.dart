import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late AppDatabase db;
  late DiveDao dao;

  setUp(() {
    db = _createInMemoryDb();
    dao = DiveDao(db);
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
}
