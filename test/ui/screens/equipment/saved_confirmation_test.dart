import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/equipment/cell_detail_screen.dart';
import 'package:ccrlogger/ui/screens/equipment/cylinder_detail_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(AppDatabase, EquipmentDaoTestRig)> openRig(
      WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final EquipmentDaoTestRig rig;
    await tester.runAsync(() async {
      rig = await openEquipmentDaoForTest(db);
    });
    return (db, rig);
  }

  testWidgets('saving an existing cylinder shows Saved', (tester) async {
    final dao = (await openRig(tester)).$2.dao;
    await tester.runAsync(() async {
      final id = await dao.addCylinder(
        label: 'Dil',
        role: CylinderRole.diluent,
        volumeLiters: 3,
        workingPressureBar: 200,
      );
      await tester.pumpWidget(
          MaterialApp(home: CylinderDetailScreen(dao: dao, id: id)));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Saved'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('saving a new cylinder pops and still shows Saved',
      (tester) async {
    final dao = (await openRig(tester)).$2.dao;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CylinderDetailScreen(dao: dao))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('saving an existing cell shows Saved', (tester) async {
    final (db, rig) = await openRig(tester);
    await tester.runAsync(() async {
      final id = await rig.dao.addCell(slot: 1, label: 'R-22D');
      await tester.pumpWidget(MaterialApp(
        home: CellDetailScreen(
          dao: rig.dao,
          diveDao: DiveDao(db, rig.ps, rig.session),
          annotationsDao: DiveAnnotationsDao(rig.ps, FakeSessionSource()),
          settingsNotifier: SettingsNotifier(),
          id: id,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.check));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
  });
}
