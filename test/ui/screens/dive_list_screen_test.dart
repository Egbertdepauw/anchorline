import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart' as dom;
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_list_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/dive_list_screen.dart';
import 'package:ccrlogger/ui/widgets/dive_tile.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

Future<({AppDatabase db, PowerSyncDatabase psDb, DiveListNotifier notifier, DiveAnnotationsDao annotationsDao})> _seed() async {
  final db = AppDatabase(NativeDatabase.memory());
  final psDb = await openPowerSyncForTest();
  final dao = DiveDao(db);
  final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
  for (final num in [711, 712, 718]) {
    final data = File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final parsed = parser.parse(data);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: num,
      dcModel: ShearwaterModel.petrel3,
    );
    await dao.importDive(
        converted: converted, rawBlob: data, parserVersion: 1);
  }
  final notifier = DiveListNotifier(dao, annotationsDao);
  await notifier.loadDives();
  return (db: db, psDb: psDb, notifier: notifier, annotationsDao: annotationsDao);
}

Future<void> _pump(
  WidgetTester tester,
  AppDatabase db,
  PowerSyncDatabase psDb,
  DiveAnnotationsDao annotationsDao,
  DiveListNotifier notifier,
) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DiveListScreen(
        notifier: notifier,
        diveDao: DiveDao(db),
        annotationsDao: annotationsDao,
        equipmentDao: EquipmentDao(db, psDb, FakeSessionSource()),
        settingsNotifier: SettingsNotifier(),
      ),
    ),
  ));
  await tester.pump();
}

// Phase 2.3 follow-up: PowerSync + flutter_test fake-async deadlock when
// widget initState fires PowerSync queries. Re-enable once we wrap pumps
// in tester.runAsync().
const _skipPowerSyncWidget = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders search field', skip: _skipPowerSyncWidget, (tester) async {
    final s = await _seed();
    addTearDown(() async {
      s.notifier.dispose();
      await s.db.close();
    });
    await _pump(tester, s.db, s.psDb, s.annotationsDao, s.notifier);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search dives'), findsOneWidget);
  });

  testWidgets('typing a dive number filters the list', skip: _skipPowerSyncWidget, (tester) async {
    final s = await _seed();
    addTearDown(() async {
      s.notifier.dispose();
      await s.db.close();
    });
    await _pump(tester, s.db, s.psDb, s.annotationsDao, s.notifier);
    expect(find.byType(DiveTile), findsNWidgets(3));

    await tester.enterText(find.byType(TextField), '#718');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.byType(DiveTile), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(DiveTile), matching: find.text('#718')),
        findsOneWidget);
  });

  testWidgets('non-matching query shows empty placeholder', skip: _skipPowerSyncWidget, (tester) async {
    final s = await _seed();
    addTearDown(() async {
      s.notifier.dispose();
      await s.db.close();
    });
    await _pump(tester, s.db, s.psDb, s.annotationsDao, s.notifier);

    await tester.enterText(find.byType(TextField), 'nonexistent-zzz');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.byType(DiveTile), findsNothing);
    expect(find.text('No dives match.'), findsOneWidget);
  });

  testWidgets('clear button resets the query', skip: _skipPowerSyncWidget, (tester) async {
    final s = await _seed();
    addTearDown(() async {
      s.notifier.dispose();
      await s.db.close();
    });
    await _pump(tester, s.db, s.psDb, s.annotationsDao, s.notifier);

    await tester.enterText(find.byType(TextField), '#718');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byType(DiveTile), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byType(DiveTile), findsNWidgets(3));
  });

  testWidgets('site filter narrows list and shows active chip', skip: _skipPowerSyncWidget,
      (tester) async {
    final s = await _seed();
    addTearDown(() async {
      s.notifier.dispose();
      await s.db.close();
    });
    // Tag exactly one dive with a site name.
    final firstId = s.notifier.dives.first.id;
    final now = DateTime.now();
    await s.annotationsDao.upsert(dom.DiveAnnotation(
      diveId: firstId,
      siteName: 'Zelandia',
      createdAt: now,
      updatedAt: now,
    ));
    await s.notifier.loadDives();
    await _pump(tester, s.db, s.psDb, s.annotationsDao, s.notifier);
    expect(find.byType(DiveTile), findsNWidgets(3));

    // Open the filter sheet.
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Site'), findsOneWidget);

    // Select the site chip and apply.
    await tester.tap(find.widgetWithText(FilterChip, 'Zelandia'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.byType(DiveTile), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Site: Zelandia'), findsOneWidget);

    // Tap the X on the active filter chip to clear it.
    await tester.tap(find.byTooltip('Delete'));
    await tester.pump();

    expect(find.byType(DiveTile), findsNWidgets(3));
    expect(find.widgetWithText(InputChip, 'Site: Zelandia'), findsNothing);
  });
}
