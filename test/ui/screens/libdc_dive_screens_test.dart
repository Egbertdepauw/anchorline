import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_derived_stats_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_detail_screen.dart';
import 'package:ccrlogger/ui/screens/statistics_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';

import '../../_helpers/libdc_fixture_dives.dart';
import '../../_helpers/powersync_test_helper.dart';

typedef _Seed = ({
  AppDatabase db,
  DiveAnnotationsDao annotationsDao,
  EquipmentDao equipmentDao,
  DiveDao dao,
  Dive dive,
});

Future<_Seed> _seed(WidgetTester tester, ConvertedDive converted) async {
  final db = AppDatabase(NativeDatabase.memory());
  late final _Seed seed;
  await tester.runAsync(() async {
    final psDb = await openPowerSyncForTest();
    final dao = DiveDao(db, psDb, FakeSessionSource());
    await dao.importDive(
        converted: converted, rawBlob: Uint8List(0), parserVersion: 1);
    seed = (
      db: db,
      annotationsDao: DiveAnnotationsDao(psDb, FakeSessionSource()),
      equipmentDao: EquipmentDao(db, psDb, FakeSessionSource()),
      dao: dao,
      dive: (await dao.getAllDives()).single,
    );
  });
  addTearDown(() async => db.close());
  return seed;
}

Future<void> _pumpDetail(WidgetTester tester, _Seed s) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      home: DiveDetailScreen(
        dive: s.dive,
        dao: s.dao,
        annotationsDao: s.annotationsDao,
        equipmentDao: s.equipmentDao,
        settingsNotifier: SettingsNotifier(),
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openInformationTab(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.thermostat_outlined));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
      'detail, information and statistics screens render a Divesoft dive '
      'with cells and no mV', (tester) async {
    final s = await _seed(tester, divesoftCcrDive());
    await _pumpDetail(tester, s);

    // Details tab: the badge carries brand and product; no mV anywhere.
    expect(find.textContaining('Divesoft Liberty'), findsWidgets);
    expect(find.textContaining('mV'), findsNothing);

    await _openInformationTab(tester);
    expect(find.text('Divesoft Liberty'), findsOneWidget);
    expect(find.text('1234567'), findsOneWidget);
    // A hex reading of the decimal serial must not show.
    expect(find.text('0012d687'), findsNothing);
    // No calibration was stored, so no calibration row with Petrel defaults.
    expect(find.text('Cell calibration'), findsNothing);
    expect(find.text('Scrubber stack'), findsNothing);
    expect(find.textContaining('0.0210'), findsNothing);
    expect(tester.takeException(), isNull);
    await _leave(tester);

    // Statistics over the same log.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: StatisticsScreen(
          diveDao: s.dao,
          annotationsDao: s.annotationsDao,
          derivedStatsDao: DiveDerivedStatsDao(s.db),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  testWidgets('a Ratio setpoint-only CCR dive shows no cell views',
      (tester) async {
    final s = await _seed(tester, ratioCcrDive());
    await _pumpDetail(tester, s);

    expect(find.textContaining('Ratio iX3M 2021 Tech+'), findsWidgets);
    expect(find.textContaining('mV'), findsNothing);
    // Tooltip rows and the cell legend need mV channels; none exist.
    expect(find.textContaining('C1'), findsNothing);

    await _openInformationTab(tester);
    expect(find.text('Ratio iX3M 2021 Tech+'), findsOneWidget);
    expect(find.text('7654321'), findsOneWidget);
    expect(find.text('Cell calibration'), findsNothing);
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });

  testWidgets('an OSTC OC dive renders like a Shearwater OC dive',
      (tester) async {
    final s = await _seed(tester, ostcOcDive());
    await _pumpDetail(tester, s);
    expect(find.textContaining('Heinrichs Weikamp OSTC 4'), findsWidgets);

    await _openInformationTab(tester);
    expect(find.text('Heinrichs Weikamp OSTC 4'), findsOneWidget);
    expect(find.text('23456'), findsOneWidget);
    expect(find.text('Cell calibration'), findsNothing);
    expect(tester.takeException(), isNull);
    await _leave(tester);
  });
}
