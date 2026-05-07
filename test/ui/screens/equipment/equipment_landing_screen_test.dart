import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/ui/screens/equipment/equipment_landing_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../_helpers/powersync_test_helper.dart';

// Phase 2.3 follow-up: PowerSync + flutter_test fake-async deadlock when
// widget initState fires PowerSync queries. Re-enable once we wrap pumps
// in tester.runAsync().
const _skipPowerSyncWidget = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders four category cards with counts', skip: _skipPowerSyncWidget, (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final rig = await openEquipmentDaoForTest(db);
    final dao = rig.dao;
    final diveDao = DiveDao(db);
    final annotationsDao = DiveAnnotationsDao(rig.ps, FakeSessionSource());

    await tester.pumpWidget(MaterialApp(
      home: EquipmentLandingScreen(
        dao: dao,
        diveDao: diveDao,
        annotationsDao: annotationsDao,
      ),
    ));
    await tester.pump();

    expect(find.text('Dive Computers'), findsOneWidget);
    expect(find.text('O2 Cells'), findsOneWidget);
    expect(find.text('Scrubbers'), findsOneWidget);
    expect(find.text('Cylinders'), findsOneWidget);
  });
}
