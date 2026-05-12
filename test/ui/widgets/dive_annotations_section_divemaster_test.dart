import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_annotations_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Divemaster field renders + writes back to notifier',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    late final DiveAnnotationsDao annotationsDao;
    late final EquipmentDao equipmentDao;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load('dive_x');
    });
    addTearDown(notifier.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiveAnnotationsSection(
              notifier: notifier,
              gasMixes: const [],
              activeSecondsByMix: const {},
              annotationsDao: annotationsDao,
              equipmentDao: equipmentDao,
              settingsNotifier: SettingsNotifier(),
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Divemaster'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Divemaster name'),
      'Wendy De Joode',
    );
    await tester.pump();

    expect(notifier.divemaster, 'Wendy De Joode');
  });
}
