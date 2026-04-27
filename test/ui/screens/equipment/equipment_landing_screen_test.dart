import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/screens/equipment/equipment_landing_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders four category cards with counts', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    final diveDao = DiveDao(db);
    final annotationsDao = DiveAnnotationsDao(db);

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
