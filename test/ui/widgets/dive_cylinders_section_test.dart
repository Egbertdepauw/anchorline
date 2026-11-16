import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_cylinders_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/data/models/dive.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mix = DiveGasMix(oxygenPercent: 21, heliumPercent: 0, isDiluent: true);

  testWidgets('an unassigned cylinder is listed and can be removed',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late EquipmentDao equipment;
    late DiveAnnotationsNotifier notifier;
    late final Future<List<dynamic>> Function() rows;
    await tester.runAsync(() async {
      final ps = await openPowerSyncForTest();
      equipment = EquipmentDao(db, ps, FakeSessionSource());
      final annotations = DiveAnnotationsDao(ps, FakeSessionSource());
      final cyl = await equipment.addCylinder(
        label: 'AL80 Air',
        role: 'diluent',
        volumeLiters: 11.1,
        workingPressureBar: 207,
      );
      await equipment.setDiveCylinder('dive1', 0, cyl);
      await equipment.setDiveCylinder('dive1', -1, cyl);
      notifier = DiveAnnotationsNotifier(annotations, equipment);
      await notifier.load('dive1');
      rows = () => ps.getAll(
          'SELECT gas_mix_index FROM dive_cylinders '
          'WHERE dive_id = ? AND deleted_at IS NULL ORDER BY gas_mix_index',
          ['dive1']);
    });
    addTearDown(notifier.dispose);
    expect(notifier.unassignedCylinders.keys, [-1]);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiveCylindersSection(
              notifier: notifier,
              gasMixes: const [mix],
              activeSecondsByMix: const {0: 600},
              equipmentDao: equipment,
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('No longer matches a gas on this dive'), findsOneWidget);
    expect(find.text('AL80 Air (diluent)'), findsWidgets);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Remove cylinder'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text('No longer matches a gas on this dive'), findsNothing);
    expect(notifier.unassignedCylinders, isEmpty);
    final left = await tester.runAsync(rows);
    expect([for (final r in left!) (r as Map)['gas_mix_index']], [0]);
  });
}
