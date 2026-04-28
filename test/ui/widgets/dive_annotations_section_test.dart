import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_annotations_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all field labels for a fresh (no-row-yet) dive',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final annotationsDao = DiveAnnotationsDao(db);
    final equipmentDao = EquipmentDao(db);
    final notifier = DiveAnnotationsNotifier(annotationsDao);
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
    expect(find.widgetWithText(ElevatedButton, 'Save'), findsOneWidget);
  });
}
