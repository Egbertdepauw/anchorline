import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/screens/dive_detail_screen.dart';
import 'package:ccrlogger/ui/screens/sites_map_screen.dart';
import 'package:ccrlogger/ui/widgets/site_mini_map.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({AppDatabase db, DiveDao dao, Dive dive})> _seedDive({
  int? configuredStackSeconds,
  int? stackRemainingAtStartSeconds,
  int? stackRemainingAtEndSeconds,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  final dao = DiveDao(db);
  final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  final parsed = parser.parse(data);
  final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: 718,
      dcModel: ShearwaterModel.petrel3);
  await dao.importDive(converted: converted, rawBlob: data, parserVersion: 1);
  // Override the persisted stack values with the test fixture's choice.
  final row = (await dao.getAllDives()).first;
  await (db.update(db.dives)..where((t) => t.id.equals(row.id))).write(
    DivesCompanion(
      configuredStackSeconds: Value(configuredStackSeconds),
      stackRemainingAtStartSeconds: Value(stackRemainingAtStartSeconds),
      stackRemainingAtEndSeconds: Value(stackRemainingAtEndSeconds),
    ),
  );
  final dive = (await dao.getAllDives()).first;
  return (db: db, dao: dao, dive: dive);
}

Future<void> _pumpScreen(WidgetTester tester, AppDatabase db, Dive dive,
    DiveDao dao) async {
  await tester.pumpWidget(MaterialApp(
    home: DiveDetailScreen(
      dive: dive,
      dao: dao,
      annotationsDao: db.diveAnnotationsDao,
      equipmentDao: db.equipmentDao,
    ),
  ));
  // Drain async loaders (samples + annotations).
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows formatted STACK end-of-dive remaining', (tester) async {
    // 23777s start, 20293s end, 25200s configured (real dive_718 numbers).
    final s = await _seedDive(
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 23777,
      stackRemainingAtEndSeconds: 20293,
    );
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.dive, s.dao);

    // Icon-prefix layout: ⏱ remaining, ∑ configured, ▽ used, STACK label.
    expect(find.text('⏱ 5:38'), findsOneWidget);
    expect(find.text('∑ 7:00'), findsOneWidget);
    expect(find.text('▽ 58:04'), findsOneWidget);
    expect(find.text('STACK'), findsOneWidget);
  });

  testWidgets('hides STACK cell when stack values are null', (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.dive, s.dao);

    // No stack data → cell is hidden entirely (no need to display "—").
    expect(find.textContaining('STACK'), findsNothing);
    expect(find.byType(DiveDetailScreen), findsOneWidget);
  });

  testWidgets('PPO2 cell shows three icon-prefixed values with bar label',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.dive, s.dao);

    // Three big-white lines (avg / min / max) followed by a faded label.
    expect(find.textContaining(RegExp(r'^⌀ \d\.\d{2}$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^↓ \d\.\d{2}$')), findsWidgets);
    expect(find.textContaining(RegExp(r'^↑ \d\.\d{2}$')), findsWidgets);
    expect(find.text('PPO2 (bar)'), findsOneWidget);
  });

  testWidgets('TEMP cell shows three icon-prefixed values with °C suffix',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.dive, s.dao);

    // Each value carries the °C suffix; label is just TEMP.
    expect(find.text('TEMP'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^⌀ -?\d+°C$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^↓ -?\d+°C$')), findsWidgets);
    expect(find.textContaining(RegExp(r'^↑ -?\d+°C$')), findsWidgets);
  });

  testWidgets('shows MAX m/min cell with descent + ascent stacked',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.dive, s.dao);

    // One label, two arrow-prefixed values stacked in a single cell.
    expect(find.text('MAX m/min'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^↓ \d+$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^↑ \d+$')), findsOneWidget);
  });

  testWidgets('TANKS cell renders one row per active tank with start→end',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    // Inject a known tanks JSON onto the seeded row so we can assert
    // exact values regardless of fixture parser output.
    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50},'
        '{"slot":1,"usage":2,"name":"O2","serial":0,"beginBar":195.0,'
        '"endBar":145.0,"maxBar":300,"reserveBar":40}]';
    await (s.db.update(s.db.dives)..where((t) => t.id.equals(s.dive.id)))
        .write(const DivesCompanion(tanksJson: Value(tanksJson)));
    final dive = (await s.dao.getAllDives()).first;

    await _pumpScreen(tester, s.db, dive, s.dao);

    expect(find.text('TANKS (bar)'), findsOneWidget);
    expect(find.text('DIL 230→185'), findsOneWidget);
    expect(find.text('O2 195→145'), findsOneWidget);
  });

  testWidgets('TANKS cell prefers PressureMapping cylinder label',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50},'
        '{"slot":1,"usage":2,"name":"O2","serial":0,"beginBar":195.0,'
        '"endBar":145.0,"maxBar":300,"reserveBar":40}]';
    await (s.db.update(s.db.dives)..where((t) => t.id.equals(s.dive.id)))
        .write(const DivesCompanion(tanksJson: Value(tanksJson)));

    // Register the dive computer and a cylinder, then map channel 0.
    final dcId = await s.db.equipmentDao.upsertDiveComputer(
      serial: 0xB89641E4,
      model: 0,
    );
    final cylId = await s.db.equipmentDao.addCylinder(
      label: 'AL40 EAN21',
      role: 'diluent',
      volumeLiters: 5.7,
      workingPressureBar: 232,
    );
    await s.db.equipmentDao.setPressureMapping(
      diveComputerId: dcId,
      channelIndex: 0,
      cylinderId: cylId,
    );

    final dive = (await s.dao.getAllDives()).first;
    await _pumpScreen(tester, s.db, dive, s.dao);

    expect(find.text('AL40 EAN21 230→185'), findsOneWidget);
    // Slot 1 (O2) wasn't mapped → falls back to parser-derived label.
    expect(find.text('O2 195→145'), findsOneWidget);
  });

  testWidgets('TANKS cell falls back to parser labels with no mappings',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50},'
        '{"slot":1,"usage":2,"name":"O2","serial":0,"beginBar":195.0,'
        '"endBar":145.0,"maxBar":300,"reserveBar":40}]';
    await (s.db.update(s.db.dives)..where((t) => t.id.equals(s.dive.id)))
        .write(const DivesCompanion(tanksJson: Value(tanksJson)));
    final dive = (await s.dao.getAllDives()).first;

    await _pumpScreen(tester, s.db, dive, s.dao);

    // No mappings → parser-derived labels survive.
    expect(find.text('DIL 230→185'), findsOneWidget);
    expect(find.text('O2 195→145'), findsOneWidget);
  });

  testWidgets('TANKS cell hides when no tanks logged', (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    await (s.db.update(s.db.dives)..where((t) => t.id.equals(s.dive.id)))
        .write(const DivesCompanion(tanksJson: Value(null)));
    final dive = (await s.dao.getAllDives()).first;

    await _pumpScreen(tester, s.db, dive, s.dao);

    expect(find.textContaining('TANKS'), findsNothing);
  });

  testWidgets('tapping the header mini-map opens SitesMapScreen',
      (tester) async {
    final s = await _seedDive();
    addTearDown(() async => s.db.close());

    // Stamp an annotation with coords so the header mini-map renders.
    final now = DateTime.now();
    await s.db.diveAnnotationsDao.upsert(DiveAnnotation(
      diveId: s.dive.id,
      siteName: 'Lagoon',
      siteLatitude: 51.5,
      siteLongitude: 4.0,
      createdAt: now,
      updatedAt: now,
    ));

    await _pumpScreen(tester, s.db, s.dive, s.dao);
    expect(find.byType(SiteMiniMap), findsOneWidget);
    expect(find.byType(SitesMapScreen), findsNothing);

    await tester.tap(find.byType(SiteMiniMap));
    await tester.pumpAndSettle();

    expect(find.byType(SitesMapScreen), findsOneWidget);
    expect(find.text('Dive sites'), findsOneWidget);
  });

  testWidgets('survives with sentinel raw blob (smoke)', (tester) async {
    // Independent smoke check: even if loadSamples shortcuts, screen builds.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.into(db.dives).insert(DivesCompanion.insert(
          id: 'dummy',
          dcSerial: 1,
          dcDiveNumber: 1,
          startTime: now,
          endTime: now + 60,
          durationSeconds: 60,
          maxDepthMm: 5000,
          diveMode: 0,
          decoModel: 0,
          atmosphericPressureMbar: 1013,
          waterDensity: 1025,
          logVersion: 17,
          dcModel: 0,
          sampleIntervalMs: 10000,
          gasMixesJson: '[]',
          rawBlob: Uint8List(0),
          parserVersion: 1,
          importedAt: now,
        ));
    expect((await db.select(db.dives).get()).single.configuredStackSeconds,
        isNull);
  });
}
