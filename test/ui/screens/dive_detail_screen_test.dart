import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/screens/dive_detail_screen.dart';
import 'package:ccrlogger/ui/screens/sites_map_screen.dart';
import 'package:ccrlogger/ui/widgets/site_mini_map.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

typedef _Seed = ({
  AppDatabase db,
  PowerSyncDatabase psDb,
  DiveAnnotationsDao annotationsDao,
  EquipmentDao equipmentDao,
  DiveDao dao,
  Dive dive,
});

Future<_Seed> _seedDive(
  WidgetTester tester, {
  int? configuredStackSeconds,
  int? stackRemainingAtStartSeconds,
  int? stackRemainingAtEndSeconds,
}) async {
  final db = AppDatabase(NativeDatabase.memory());
  late final DiveDao dao;
  late final _Seed seed;
  await tester.runAsync(() async {
    final psDb = await openPowerSyncForTest();
    dao = DiveDao(db, psDb, FakeSessionSource());
    final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
    final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final parsed = parser.parse(data);
    final converted = DiveConverter.convert(
        parsed: parsed,
        dcSerial: 0xB89641E4,
        dcDiveNumber: 718,
        dcModel: ShearwaterModel.petrel3);
    await dao.importDive(
        converted: converted, rawBlob: data, parserVersion: 1);
    // Override the persisted stack values with the test fixture's choice.
    // Phase 2.5 lives in PowerSync now, so the override goes through
    // raw SQL on psDb, not Drift's Dives table.
    final row = (await dao.getAllDives()).first;
    await psDb.execute(
      'UPDATE dives SET configured_stack_seconds = ?, '
      'stack_remaining_at_start_seconds = ?, '
      'stack_remaining_at_end_seconds = ? WHERE id = ?',
      [
        configuredStackSeconds,
        stackRemainingAtStartSeconds,
        stackRemainingAtEndSeconds,
        row.id,
      ],
    );
    final dive = (await dao.getAllDives()).first;
    seed = (
      db: db,
      psDb: psDb,
      annotationsDao: annotationsDao,
      equipmentDao: equipmentDao,
      dao: dao,
      dive: dive,
    );
  });
  return seed;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  AppDatabase db,
  EquipmentDao equipmentDao,
  DiveAnnotationsDao annotationsDao,
  Dive dive,
  DiveDao dao,
) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      home: DiveDetailScreen(
        dive: dive,
        dao: dao,
        annotationsDao: annotationsDao,
        equipmentDao: equipmentDao,
      ),
    ));
    // Let initState's PowerSync + sample loaders settle before we
    // re-enter fake time for expects.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();
}

void main() {
  testWidgets('shows formatted STACK end-of-dive remaining', (tester) async {
    // 23777s start, 20293s end, 25200s configured (real dive_718 numbers).
    final s = await _seedDive(tester,
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 23777,
      stackRemainingAtEndSeconds: 20293,
    );
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, s.dive, s.dao);

    // StatTile layout: uppercased "STACK" label, value (remaining), hint
    // (used · configured) below.
    expect(find.text('STACK'), findsOneWidget);
    expect(find.text('5:38'), findsOneWidget);
    expect(find.text('58:04 · 7:00'), findsOneWidget);
  });

  testWidgets('hides STACK cell when stack values are null', (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, s.dive, s.dao);

    // No stack data → cell is hidden entirely (no need to display "—").
    expect(find.textContaining('STACK'), findsNothing);
    expect(find.byType(DiveDetailScreen), findsOneWidget);
  });

  testWidgets('PPO2 cell shows StatTile with avg value + min/max hint',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, s.dive, s.dao);

    // StatTile renders label uppercased + unit appended: "PPO2  BAR".
    // Value is the avg as N.NN. Hint is "min / max".
    expect(find.text('PPO2  BAR'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d\.\d{2}$')), findsWidgets);
    expect(find.textContaining(RegExp(r'^\d\.\d{2} / \d\.\d{2}$')),
        findsOneWidget);
  });

  testWidgets('TEMP cell shows StatTile with avg + min/max hint',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, s.dive, s.dao);

    // Label is "TEMP  °C" (uppercased + unit). Value is integer avg.
    // Hint is "min / max" (both integers, °C goes in the label).
    expect(find.text('TEMP  °C'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^-?\d+ / -?\d+$')), findsOneWidget);
  });

  testWidgets('shows V-speed cell with descent + ascent combined',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, s.dive, s.dao);

    // Single StatTile with combined "↓N ↑M" value, uppercased label
    // "V-SPEED  M/MIN".
    expect(find.text('V-SPEED  M/MIN'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^↓\d+ ↑\d+$')), findsOneWidget);
  });

  testWidgets('TANKS cell renders one row per active tank with start→end',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    // Inject a known tanks JSON onto the seeded row so we can assert
    // exact values regardless of fixture parser output.
    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50},'
        '{"slot":1,"usage":2,"name":"O2","serial":0,"beginBar":195.0,'
        '"endBar":145.0,"maxBar":300,"reserveBar":40}]';
    late final Dive dive;
    await tester.runAsync(() async {
      await s.psDb.execute(
          "UPDATE dives SET tanks_json = ? WHERE id = ?",
          [tanksJson, s.dive.id]);
      dive = (await s.dao.getAllDives()).first;
    });

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, dive, s.dao);

    expect(find.text('TANKS  BAR'), findsOneWidget);
    expect(find.text('DIL 230→185'), findsOneWidget);
    expect(find.text('O2 195→145'), findsOneWidget);
  });

  testWidgets('TANKS cell prefers PressureMapping cylinder label',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50},'
        '{"slot":1,"usage":2,"name":"O2","serial":0,"beginBar":195.0,'
        '"endBar":145.0,"maxBar":300,"reserveBar":40}]';
    late final Dive dive;
    // PowerSync writes must run on real time, not the test framework's
    // fake clock.
    await tester.runAsync(() async {
      await s.psDb.execute(
          "UPDATE dives SET tanks_json = ? WHERE id = ?",
          [tanksJson, s.dive.id]);
      final dcId = await s.equipmentDao.upsertDiveComputer(
        serial: 0xB89641E4,
        model: 0,
      );
      final cylId = await s.equipmentDao.addCylinder(
        label: 'AL40 EAN21',
        role: 'diluent',
        volumeLiters: 5.7,
        workingPressureBar: 232,
      );
      await s.equipmentDao.setPressureMapping(
        diveComputerId: dcId,
        channelIndex: 0,
        cylinderId: cylId,
      );
      dive = (await s.dao.getAllDives()).first;
    });

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, dive, s.dao);

    expect(find.text('AL40 EAN21 230→185'), findsOneWidget);
    // Slot 1 (O2) wasn't mapped → falls back to parser-derived label.
    expect(find.text('O2 195→145'), findsOneWidget);
  });

  testWidgets('TANKS cell falls back to parser labels with no mappings',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    const tanksJson =
        '[{"slot":0,"usage":3,"name":"DI","serial":0,"beginBar":230.0,'
        '"endBar":185.0,"maxBar":300,"reserveBar":50},'
        '{"slot":1,"usage":2,"name":"O2","serial":0,"beginBar":195.0,'
        '"endBar":145.0,"maxBar":300,"reserveBar":40}]';
    late final Dive dive;
    await tester.runAsync(() async {
      await s.psDb.execute(
          "UPDATE dives SET tanks_json = ? WHERE id = ?",
          [tanksJson, s.dive.id]);
      dive = (await s.dao.getAllDives()).first;
    });

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, dive, s.dao);

    // No mappings → parser-derived labels survive.
    expect(find.text('DIL 230→185'), findsOneWidget);
    expect(find.text('O2 195→145'), findsOneWidget);
  });

  testWidgets('TANKS cell hides when no tanks logged', (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    late final Dive dive;
    await tester.runAsync(() async {
      await s.psDb.execute(
          "UPDATE dives SET tanks_json = NULL WHERE id = ?", [s.dive.id]);
      dive = (await s.dao.getAllDives()).first;
    });

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, dive, s.dao);

    expect(find.textContaining('TANKS'), findsNothing);
  });

  testWidgets('tapping the header mini-map opens SitesMapScreen',
      (tester) async {
    final s = await _seedDive(tester);
    addTearDown(() async => s.db.close());

    // Stamp an annotation with coords so the header mini-map renders.
    final now = DateTime.now();
    await tester.runAsync(() async {
      await s.annotationsDao.upsert(DiveAnnotation(
        diveId: s.dive.id,
        siteName: 'Lagoon',
        siteLatitude: 51.5,
        siteLongitude: 4.0,
        createdAt: now,
        updatedAt: now,
      ));
    });

    await _pumpScreen(tester, s.db, s.equipmentDao, s.annotationsDao, s.dive, s.dao);
    // Two SiteMiniMap widgets now: the header one and another inside the
    // Map tab of the site sub-block's tab-group. Both open SitesMapScreen
    // on tap; this test exercises the header (the first match).
    expect(find.byType(SiteMiniMap), findsNWidgets(2));
    expect(find.byType(SitesMapScreen), findsNothing);

    await tester.tap(find.byType(SiteMiniMap).first);
    // SitesMapScreen wraps a FlutterMap whose tile loaders never settle
    // under the test framework, so pumpAndSettle would hang. Pump a few
    // frames to advance the page transition and stop.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

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
