import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/site_form_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SiteFormView renders Site / Lat / Lon and writes to notifier',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    late final DiveAnnotationsDao annotationsDao;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load('dive_y');
    });
    addTearDown(notifier.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SiteFormView(
              notifier: notifier,
              annotationsDao: annotationsDao,
              onPickOnMap: () async {},
            ),
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Site'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Site name'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Latitude'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Longitude'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'), '52.2366');
    await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'), '4.9570');
    await tester.pump();

    expect(notifier.siteLatitude, closeTo(52.2366, 0.0001));
    expect(notifier.siteLongitude, closeTo(4.9570, 0.0001));
  });
}
