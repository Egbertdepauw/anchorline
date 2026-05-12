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

  Future<DiveAnnotationsNotifier> loadedNotifier(
    WidgetTester tester,
    String diveId, {
    double? lat,
    double? lon,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load(diveId);
      if (lat != null && lon != null) notifier.setLatLon(lat, lon);
    });
    addTearDown(notifier.dispose);
    return notifier;
  }

  Future<void> pumpSection(
    WidgetTester tester,
    DiveAnnotationsNotifier notifier,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsDao annotationsDao;
    late final EquipmentDao equipmentDao;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
    });
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
  }

  testWidgets('no coords → no tab strip, form alone', (tester) async {
    final n = await loadedNotifier(tester, 'd_no_coords');
    await pumpSection(tester, n);

    expect(find.text('Site'), findsOneWidget);
    expect(find.text('Form'), findsNothing);
    expect(find.text('Map'), findsNothing);
  });

  testWidgets('coords present → tab strip visible, Map default',
      (tester) async {
    final n = await loadedNotifier(tester, 'd_with_coords',
        lat: 52.2366, lon: 4.9570);
    await pumpSection(tester, n);

    expect(find.text('Form'), findsOneWidget);
    expect(find.text('Map'), findsOneWidget);
    // Map tab is initial: SiteMapView should be visible (its coords text)
    expect(find.textContaining('52.2366'), findsOneWidget);
  });
}
