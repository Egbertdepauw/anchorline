import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/dive_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/screens/equipment/cell_detail_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders header + empty chart for a fresh cell', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = EquipmentDao(db);
    final diveDao = DiveDao(db);
    final annotationsDao = DiveAnnotationsDao(db);
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

    expect(find.text('Slot 1'), findsOneWidget);
    expect(find.text('No surface-mV data yet'), findsOneWidget);
  });
}
