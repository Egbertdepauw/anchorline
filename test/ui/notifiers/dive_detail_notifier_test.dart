import 'dart:io';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDao dao;
  late Dive diveRow;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDao(db);
    final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final parsed = parser.parse(data);
    final converted = DiveConverter.convert(
        parsed: parsed,
        dcSerial: 0xB89641E4,
        dcDiveNumber: 718,
        dcModel: ShearwaterModel.petrel3);
    await dao.importDive(converted: converted, rawBlob: data, parserVersion: 1);
    final dives = await dao.getAllDives();
    diveRow = dives.first;
  });

  tearDown(() async {
    await db.close();
  });

  test('loadSamples populates samples', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    await notifier.loadSamples();
    expect(notifier.samples, isNotNull);
    expect(notifier.samples!.sampleCount, greaterThan(0));
    notifier.dispose();
  });

  test('CCR dive defaults to ppo2 + setpoint + deco visible', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    expect(notifier.visibleTraces.contains(TraceType.ppo2), isTrue);
    expect(notifier.visibleTraces.contains(TraceType.setpoint), isTrue);
    expect(notifier.visibleTraces.contains(TraceType.deco), isTrue);
    expect(notifier.visibleTraces.contains(TraceType.cells), isFalse);
    expect(notifier.visibleTraces.contains(TraceType.tanks), isFalse);
    notifier.dispose();
  });

  test('toggleTrace flips visibility and notifies', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    var notified = false;
    notifier.addListener(() => notified = true);
    expect(notifier.visibleTraces.contains(TraceType.cells), isFalse);
    notifier.toggleTrace(TraceType.cells);
    expect(notifier.visibleTraces.contains(TraceType.cells), isTrue);
    expect(notified, isTrue);
    notified = false;
    notifier.toggleTrace(TraceType.cells);
    expect(notifier.visibleTraces.contains(TraceType.cells), isFalse);
    expect(notified, isTrue);
    notifier.dispose();
  });

  test('setCrosshairIndex and clearCrosshair notify', () async {
    final notifier = DiveDetailNotifier(dive: diveRow, dao: dao);
    await notifier.loadSamples();
    var notified = false;
    notifier.addListener(() => notified = true);
    notifier.setCrosshairIndex(42);
    expect(notifier.crosshairIndex, equals(42));
    expect(notified, isTrue);
    notified = false;
    notifier.clearCrosshair();
    expect(notifier.crosshairIndex, isNull);
    expect(notified, isTrue);
    notifier.dispose();
  });
}
