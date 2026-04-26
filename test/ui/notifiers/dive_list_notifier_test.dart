import 'dart:io';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late DiveListNotifier notifier;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDao(db);
    notifier = DiveListNotifier(dao);

    for (final num in [711, 712, 718]) {
      final data = File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      final parsed = parser.parse(data);
      final converted = DiveConverter.convert(
        parsed: parsed, dcSerial: 0xB89641E4, dcDiveNumber: num,
        dcModel: ShearwaterModel.petrel3,
      );
      await dao.importDive(converted: converted, rawBlob: data, parserVersion: 1);
    }
  });

  tearDown(() async {
    notifier.dispose();
    await db.close();
  });

  test('loadDives populates dives list', () async {
    await notifier.loadDives();
    expect(notifier.dives, hasLength(3));
  });

  test('dives are ordered by start time descending', () async {
    await notifier.loadDives();
    for (var i = 1; i < notifier.dives.length; i++) {
      expect(notifier.dives[i].startTime, lessThanOrEqualTo(notifier.dives[i - 1].startTime));
    }
  });

  test('groupedByMonth groups dives correctly', () async {
    await notifier.loadDives();
    final groups = notifier.groupedByMonth;
    expect(groups, isNotEmpty);
    for (final key in groups.keys) {
      expect(key, matches(RegExp(r'^[A-Z][a-z]+ \d{4}$')));
    }
  });

  test('getSparklineData returns depth data for a dive', () async {
    await notifier.loadDives();
    final diveId = notifier.dives.first.id;
    final depths = await notifier.getSparklineData(diveId);
    expect(depths, isNotNull);
    expect(depths!.length, greaterThan(0));
  });

  test('getSparklineData caches results', () async {
    await notifier.loadDives();
    final diveId = notifier.dives.first.id;
    final depths1 = await notifier.getSparklineData(diveId);
    final depths2 = await notifier.getSparklineData(diveId);
    expect(identical(depths1, depths2), isTrue);
  });
}
