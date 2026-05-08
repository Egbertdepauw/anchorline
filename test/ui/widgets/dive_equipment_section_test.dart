import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart';
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_equipment_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Boots a Drift + PowerSync rig and returns the wired notifier.
  /// Optionally seeds a pre-existing annotation row plus a set of
  /// historical equipment values used to populate the autocomplete
  /// suggestion lists.
  Future<({
    DiveAnnotationsDao annotationsDao,
    EquipmentDao equipmentDao,
    DiveAnnotationsNotifier notifier,
  })> bootRig(
    WidgetTester tester, {
    required String diveId,
    DiveAnnotation? preset,
    List<DiveAnnotation> historical = const [],
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsDao annotationsDao;
    late final EquipmentDao equipmentDao;
    late final DiveAnnotationsNotifier notifier;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      for (final h in historical) {
        await annotationsDao.upsert(h);
      }
      if (preset != null) {
        await annotationsDao.upsert(preset);
      }
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load(diveId);
    });
    addTearDown(notifier.dispose);
    return (
      annotationsDao: annotationsDao,
      equipmentDao: equipmentDao,
      notifier: notifier,
    );
  }

  /// Pumps the section + lets initState's bootstrap futures resolve.
  Future<void> pumpSection(
    WidgetTester tester, {
    required DiveAnnotationsNotifier notifier,
    required DiveAnnotationsDao annotationsDao,
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiveEquipmentSection(
              notifier: notifier,
              annotationsDao: annotationsDao,
            ),
          ),
        ),
      ));
      // Give bootstrap's distinctEquipmentValues() futures a beat.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('renders all four labeled equipment fields + Weights editor',
      (tester) async {
    final rig = await bootRig(tester, diveId: 'dive_a');
    await pumpSection(
      tester,
      notifier: rig.notifier,
      annotationsDao: rig.annotationsDao,
    );

    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('Suit'), findsOneWidget);
    expect(find.text('Undersuit'), findsOneWidget);
    expect(find.text('DPV'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    // Weight system moved out of the freeform autocomplete list and into
    // the structured WeightsEditor (kg + description rows).
    expect(find.text('Weights'), findsOneWidget);
  });

  testWidgets('hydrates field text from a preset annotation', (tester) async {
    final now = DateTime.now();
    final preset = DiveAnnotation(
      diveId: 'dive_b',
      suit: 'Santi BZ400',
      undersuit: 'Halo 250',
      weightSystem: '4kg backplate',
      dpv: 'Suex XK1',
      camera: 'GoPro Hero 12',
      createdAt: now,
      updatedAt: now,
    );
    final rig = await bootRig(tester, diveId: 'dive_b', preset: preset);
    await pumpSection(
      tester,
      notifier: rig.notifier,
      annotationsDao: rig.annotationsDao,
    );

    // Each field is a TextField; the text should be the preset value.
    expect(find.widgetWithText(TextField, 'Santi BZ400'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Halo 250'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Suex XK1'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'GoPro Hero 12'), findsOneWidget);
  });

  testWidgets('typing in the Suit field calls notifier.setSuit', (tester) async {
    final rig = await bootRig(tester, diveId: 'dive_c');
    await pumpSection(
      tester,
      notifier: rig.notifier,
      annotationsDao: rig.annotationsDao,
    );

    expect(rig.notifier.suit, isNull);
    expect(rig.notifier.dirty, isFalse);

    // The Suit field is the first TextField in the section. Locating by
    // hint keeps the test robust against widget reordering.
    final suitField = find.widgetWithText(TextField, 'e.g. Santi BZ400, Mares Rover 7mm');
    expect(suitField, findsOneWidget);
    await tester.enterText(suitField, 'Santi BZ400');
    await tester.pump();

    expect(rig.notifier.suit, 'Santi BZ400');
    expect(rig.notifier.dirty, isTrue);
  });

  testWidgets('clearing the Suit field calls setSuit(null)', (tester) async {
    final now = DateTime.now();
    final preset = DiveAnnotation(
      diveId: 'dive_d',
      suit: 'Santi BZ400',
      createdAt: now,
      updatedAt: now,
    );
    final rig = await bootRig(tester, diveId: 'dive_d', preset: preset);
    await pumpSection(
      tester,
      notifier: rig.notifier,
      annotationsDao: rig.annotationsDao,
    );

    expect(rig.notifier.suit, 'Santi BZ400');

    final suitField =
        find.widgetWithText(TextField, 'Santi BZ400');
    expect(suitField, findsOneWidget);
    await tester.enterText(suitField, '');
    await tester.pump();

    expect(rig.notifier.suit, isNull);
  });

  // The autocomplete-overlay-open path is hard to assert reliably in
  // widget tests — RawAutocomplete schedules indefinite frames via the
  // focused TextField's cursor blink, and PowerSync teardown after a
  // multi-row seed in this rig hangs the test framework even when the
  // widget side is bypassed. Coverage of the DAO end of the
  // autocomplete pipeline (distinctEquipmentValues) lives in
  // dive_annotations_dao_test.dart instead.
}
