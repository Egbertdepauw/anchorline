import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/equipment/cell_detail_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders header + empty chart for a fresh cell', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    late final EquipmentDao dao;
    late final DiveDao diveDao;
    late final DiveAnnotationsDao annotationsDao;
    late final String id;
    await tester.runAsync(() async {
      final rig = await openEquipmentDaoForTest(db);
      dao = rig.dao;
      diveDao = DiveDao(db, rig.ps, rig.session);
      annotationsDao = DiveAnnotationsDao(rig.ps, FakeSessionSource());
      id = await dao.addCell(slot: 1, label: 'R-22D');
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: CellDetailScreen(
          dao: dao,
          diveDao: diveDao,
          annotationsDao: annotationsDao,
          settingsNotifier: SettingsNotifier(),
          id: id,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Slot'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('No surface-mV data yet'), findsOneWidget);
  });

  testWidgets('installedDate picker is present and persists selection',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    late final EquipmentDao dao;
    late final DiveDao diveDao;
    late final DiveAnnotationsDao annotationsDao;
    late final String id;
    final installed = DateTime(2025, 3, 12);
    await tester.runAsync(() async {
      final rig = await openEquipmentDaoForTest(db);
      dao = rig.dao;
      diveDao = DiveDao(db, rig.ps, rig.session);
      annotationsDao = DiveAnnotationsDao(rig.ps, FakeSessionSource());
      id = await dao.addCell(
        slot: 1,
        label: 'R-22D',
        installedDate: installed,
      );
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: CellDetailScreen(
          dao: dao,
          diveDao: diveDao,
          annotationsDao: annotationsDao,
          settingsNotifier: SettingsNotifier(),
          id: id,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Installed: 2025-03-12'), findsOneWidget);

    // Tap clear → save → reload from DB, expect null.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('Installed: —'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    final reloaded = await tester.runAsync<OxygenCell?>(
      () => dao.getCell(id),
    );
    expect(reloaded?.installedDate, isNull);
  });
}
