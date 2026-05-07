import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_annotations_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

// Phase 2.3 follow-up: these widget tests pump screens whose initState
// fires PowerSync queries. PowerSync's isolate scheduler doesn't advance
// under flutter_test's fake-async clock, so pumpWidget deadlocks.
// Re-enable once we wire `tester.runAsync()` around the pump calls.
const _skipPowerSyncWidget = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders all field labels for a fresh (no-row-yet) dive',
      skip: _skipPowerSyncWidget, (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final psDb = await openPowerSyncForTest();
    final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
    final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
    final notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
    addTearDown(notifier.dispose);
    await notifier.load('dive_x');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DiveAnnotationsSection(
            notifier: notifier,
            gasMixes: const [],
            activeSecondsByMix: const {},
            annotationsDao: annotationsDao,
            equipmentDao: equipmentDao,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Site'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Buddies'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Conditions'), findsOneWidget);
    // Save lives in the parent screen's AppBar now (see DiveDetailScreen);
    // the section itself should not render its own Save button.
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsNothing);
  });
}
