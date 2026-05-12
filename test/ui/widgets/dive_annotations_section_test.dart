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

  testWidgets('renders all field labels for a fresh (no-row-yet) dive',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Everything that touches PowerSync must run in real time —
    // PowerSync's isolate scheduler waits on wall-clock futures that
    // the test binding's fake clock will never advance.
    late final DiveAnnotationsDao annotationsDao;
    late final EquipmentDao equipmentDao;
    late final DiveAnnotationsNotifier notifier;
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
      // Give the section's initState futures (annotations + cylinders
      // queries) a beat to land before we re-enter fake time.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Site'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Buddies'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    // Save lives in the parent screen's AppBar now (see DiveDetailScreen);
    // the section itself should not render its own Save button.
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsNothing);
  });
}
