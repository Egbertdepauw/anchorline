import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/screens/dive_detail_screen.dart';
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
