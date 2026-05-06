import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
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
    final dao = EquipmentDao(db);
    final diveDao = DiveDao(db);
    final psDb = await openPowerSyncForTest();
    final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final id = await dao.addCell(slot: 1, label: 'R-22D');

    await tester.pumpWidget(MaterialApp(
      home: CellDetailScreen(
        dao: dao,
        diveDao: diveDao,
        annotationsDao: annotationsDao,
        id: id,
      ),
    ));
    await tester.pump(); // initial frame
    await tester.pump(); // after _load future resolves

    expect(find.text('Slot'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('No surface-mV data yet'), findsOneWidget);
  });

  testWidgets('installedDate picker is present and persists selection',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    final diveDao = DiveDao(db);
    final psDb = await openPowerSyncForTest();
    final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final installed = DateTime(2025, 3, 12);
    final id = await dao.addCell(
      slot: 1,
      label: 'R-22D',
      installedDate: installed,
    );

    await tester.pumpWidget(MaterialApp(
      home: CellDetailScreen(
        dao: dao,
        diveDao: diveDao,
        annotationsDao: annotationsDao,
        id: id,
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Installed: 2025-03-12'), findsOneWidget);

    // Tap clear → save → reload from DB, expect null.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('Installed: —'), findsOneWidget);

    await tester.tap(find.byTooltip('Save'));
    await tester.pump();
    await tester.pump();

    final reloaded = await dao.getCell(id);
    expect(reloaded?.installedDate, isNull);
  });
}
