import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/sync/subsurface_export.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;
import 'package:xml/xml.dart';

import '../_helpers/powersync_test_helper.dart';

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

Future<void> _importFixture(DiveDao dao, int diveNumber) async {
  final converted = _convertFixture(diveNumber);
  final raw = File('test/fixtures/dives/dive_$diveNumber.bin').readAsBytesSync();
  await dao.importDive(converted: converted, rawBlob: raw, parserVersion: 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PowerSyncDatabase psDb;
  late DiveDao diveDao;
  late DiveAnnotationsDao annotationsDao;
  late Directory tmpDir;
  late SubsurfaceExporter exporter;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    psDb = await openPowerSyncForTest();
    diveDao = DiveDao(db);
    annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    tmpDir = await Directory.systemTemp.createTemp('ccrlogger_export_');
    exporter = SubsurfaceExporter(
      diveDao: diveDao,
      annotationsDao: annotationsDao,
      resolveBaseDir: () async => tmpDir,
      now: () => DateTime.utc(2026, 5, 6, 12, 34, 56),
    );
  });

  tearDown(() async {
    await db.close();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  test('exportPending returns null when nothing pending', () async {
    final result = await exporter.exportPending();
    expect(result, isNull);
  });

  test('exportPending writes a parseable .ssrf with one <dive> per pending row',
      () async {
    for (final n in [711, 712, 718]) {
      await _importFixture(diveDao, n);
    }

    final result = await exporter.exportPending();
    expect(result, isNotNull);
    expect(result!.diveCount, 3);

    final file = File(result.filePath);
    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('.ssrf'));
    expect(file.path, contains('exports/'));

    final xml = await file.readAsString();
    final doc = XmlDocument.parse(xml);
    expect(doc.rootElement.name.local, 'divelog');
    expect(doc.rootElement.findAllElements('dive').length, 3);
  });

  test('exportPending excludes dives already marked uploaded', () async {
    for (final n in [711, 712, 718]) {
      await _importFixture(diveDao, n);
    }
    final converted = _convertFixture(718);
    await diveDao.markSubsurfaceUploaded([converted.dive.id], 1234567890);

    final result = await exporter.exportPending();
    expect(result, isNotNull);
    expect(result!.diveCount, 2);
    expect(result.diveIds, isNot(contains(converted.dive.id)));
  });

  test('markExported stamps every dive id with the same timestamp', () async {
    for (final n in [711, 712, 718]) {
      await _importFixture(diveDao, n);
    }

    final result = await exporter.exportPending();
    expect(result, isNotNull);
    await exporter.markExported(result!.diveIds);

    final pending = await diveDao.getPendingSubsurfaceUploads();
    expect(pending, isEmpty);
    final post = await exporter.exportPending();
    expect(post, isNull);
  });
}
