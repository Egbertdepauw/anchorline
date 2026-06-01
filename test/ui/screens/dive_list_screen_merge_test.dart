import 'dart:io';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/dive_merge_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
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

typedef _Rig = ({
  AppDatabase db,
  PowerSyncDatabase psDb,
  DiveDao diveDao,
  DiveAnnotationsDao annotationsDao,
  DiveMergeDao mergeDao,
  DiveListNotifier notifier,
});

Future<_Rig> _seed(WidgetTester tester) async {
  final db = AppDatabase(NativeDatabase.memory());
  late final _Rig rig;
  await tester.runAsync(() async {
    final psDb = await openPowerSyncForTest();
    final session = FakeSessionSource();
    final diveDao = DiveDao(db, psDb, session);
    final annotationsDao = DiveAnnotationsDao(psDb, session);
    final mergeDao = DiveMergeDao(db, psDb, session);
    for (final num in [711, 712]) {
      final data = File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
      final parsed =
          ShearwaterDiveParser(model: ShearwaterModel.petrel3).parse(data);
      final converted = DiveConverter.convert(
        parsed: parsed,
        dcSerial: 0xB89641E4,
        dcDiveNumber: num,
        dcModel: ShearwaterModel.petrel3,
      );
      await diveDao.importDive(
          converted: converted, rawBlob: data, parserVersion: 1);
    }
    final notifier = DiveListNotifier(diveDao, annotationsDao, mergeDao);
    await notifier.loadDives();
    rig = (
      db: db,
      psDb: psDb,
      diveDao: diveDao,
      annotationsDao: annotationsDao,
      mergeDao: mergeDao,
      notifier: notifier,
    );
  });
  return rig;
}

Future<void> _pump(WidgetTester tester, _Rig rig) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveListScreen(
          notifier: rig.notifier,
          diveDao: rig.diveDao,
          annotationsDao: rig.annotationsDao,
          equipmentDao: EquipmentDao(rig.db, rig.psDb, FakeSessionSource()),
          settingsNotifier: SettingsNotifier(),
        ),
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('merged dives collapse into one group tile', (tester) async {
    final rig = await _seed(tester);
    addTearDown(() async => rig.db.close());

    // Link both seeded dives into one group, then refresh.
    final ids = rig.notifier.dives.map((d) => d.id).toList();
    expect(ids, hasLength(2));
    await tester.runAsync(() async {
      await rig.mergeDao.mergeDives(ids);
      await rig.notifier.loadDives();
    });

    await _pump(tester, rig);

    // The two dives collapse into ONE merged entry: a summary DiveTile
    // (reusing the normal list format) plus a chain line with count + SI.
    expect(find.byType(DiveTile), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.textContaining('2 dives'), findsOneWidget);
  });

  testWidgets('long-press a dive enters selection mode with checkboxes',
      (tester) async {
    final rig = await _seed(tester);
    addTearDown(() async => rig.db.close());

    await _pump(tester, rig);

    expect(rig.notifier.selectionMode, isFalse);
    expect(find.byType(DiveTile), findsNWidgets(2));

    await tester.longPress(find.byType(DiveTile).first);
    await tester.pump();

    expect(rig.notifier.selectionMode, isTrue);
    // Both rows switch to the checkbox layout in selection mode.
    expect(find.byType(Checkbox), findsNWidgets(2));
  });
}
