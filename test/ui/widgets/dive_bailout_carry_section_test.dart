import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/widgets/dive_bailout_carry_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  late AppDatabase db;
  late EquipmentDao dao;
  const diveId = 'd-1';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = (await openEquipmentDaoForTest(db)).dao;
  });

  tearDown(() async => db.close());

  // Single widget-level smoke test: the empty-state path. The render-with-rows
  // and delete paths are covered at the DAO layer in
  // test/data/db/dive_bailout_carry_dao_test.dart — running them as
  // widget tests fights with PowerSync's never-settling watch stream
  // (pumpAndSettle hangs, runAsync starves Future.delayed) and isn't
  // worth the timer-engineering complexity for the marginal coverage.
  testWidgets('empty state when no carry rows exist', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DiveBailoutCarrySection(diveId: diveId, dao: dao),
      ),
    ));
    await tester.pump();
    expect(find.text('No bailout cylinders configured'), findsOneWidget);
    expect(find.text('Add cylinder'), findsOneWidget);
  });
}
