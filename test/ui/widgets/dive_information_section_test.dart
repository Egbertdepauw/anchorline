import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/data/db/dive_annotations_dao.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/models/annotation.dart' show DiveAnnotation;
import 'package:ccrlogger/ui/notifiers/dive_annotations_notifier.dart';
import 'package:ccrlogger/ui/widgets/dive_information_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({AppDatabase db, DiveAnnotationsNotifier notifier})> setup(
      WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      await notifier.load('dive_x');
    });
    addTearDown(notifier.dispose);
    return (db: db, notifier: notifier);
  }

  Future<void> pumpSection(
    WidgetTester tester, {
    required DiveAnnotationsNotifier notifier,
    required Dive dive,
  }) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiveInformationSection(
            notifier: notifier,
            dive: dive,
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('star rows show polarity caption pairs', (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(),
    );

    expect(find.text('Large'), findsOneWidget);
    expect(find.text('Small'), findsOneWidget);
    expect(find.text('Bad'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(find.text('Strong'), findsNWidgets(2)); // current + surge
    expect(find.text('Weak'), findsNWidgets(2));
    expect(find.text('Freezing'), findsOneWidget);
    expect(find.text('Comfy'), findsOneWidget);
  });

  testWidgets('water type row renders Fresh for density 1000', (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(waterDensity: 1000, atmosphericPressureMbar: 1003),
    );

    expect(find.text('Water type'), findsOneWidget);
    expect(find.text('Fresh — 1.000 g/L'), findsOneWidget);
  });

  testWidgets('water type row renders Salt for density 1025', (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(waterDensity: 1025),
    );

    expect(find.text('Salt — 1.025 g/L'), findsOneWidget);
  });

  testWidgets('water type row renders Brackish for density 1015',
      (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(waterDensity: 1015),
    );

    expect(find.text('Brackish — 1.015 g/L'), findsOneWidget);
  });

  testWidgets('atm pressure row renders mbar value', (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(atmosphericPressureMbar: 1003),
    );

    expect(find.text('Atm. pressure'), findsOneWidget);
    expect(find.text('1003 mbar'), findsOneWidget);
  });

  testWidgets('DC section renders Model + Serial + Firmware + Deco + log',
      (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      dive: _testDive(),
    );

    expect(find.text('DIVE COMPUTER'), findsOneWidget);
    expect(find.text('Shearwater Petrel 3'), findsOneWidget);
    expect(find.text('b89641e4'), findsOneWidget);
    expect(find.text('Bühlmann ZHL-16 · GF 50 / 95'), findsOneWidget);
    expect(find.text('10 s'), findsOneWidget);
    expect(find.textContaining('17'), findsOneWidget); // log version
  });

  testWidgets('DC section renders Scrubber sub-block when configured stack present',
      (tester) async {
    final harness = await setup(tester);
    await pumpSection(
      tester,
      notifier: harness.notifier,
      // configuredStackSeconds = 25200 = 7h, start=10847, end=7347 from _testDive.
      dive: _testDive(),
    );

    expect(find.text('SCRUBBER'), findsOneWidget);
    expect(find.text('7:00'), findsOneWidget); // configured
  });

  // Explicitly-recorded temps must render once the annotation loads,
  // regardless of whether the load resolves before or after first build.

  Future<({DiveAnnotationsNotifier notifier})> setupWithTemps(
    WidgetTester tester, {
    required bool loadBeforePump,
    required DiveInformationSectionPump pump,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    late final DiveAnnotationsNotifier notifier;
    await tester.runAsync(() async {
      final psDb = await openPowerSyncForTest();
      final annotationsDao = DiveAnnotationsDao(psDb, FakeSessionSource());
      final equipmentDao = EquipmentDao(db, psDb, FakeSessionSource());
      final now = DateTime.now();
      await annotationsDao.upsert(DiveAnnotation(
        diveId: 'dive_x',
        airTempC: 21.0,
        waterTempC: 14.0,
        createdAt: now,
        updatedAt: now,
      ));
      notifier = DiveAnnotationsNotifier(annotationsDao, equipmentDao);
      if (loadBeforePump) await notifier.load('dive_x');
    });
    addTearDown(notifier.dispose);
    await pump(notifier);
    return (notifier: notifier);
  }

  testWidgets('temps hydrate when notifier is loaded BEFORE first build',
      (tester) async {
    await setupWithTemps(
      tester,
      loadBeforePump: true,
      pump: (notifier) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: DiveInformationSection(
                  notifier: notifier, dive: _testDive()),
            ),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      },
    );

    expect(find.text('21'), findsOneWidget); // air temp
    expect(find.text('14'), findsOneWidget); // water temp
  });

  testWidgets('temps hydrate when load completes AFTER first build '
      '(no interaction)', (tester) async {
    await setupWithTemps(
      tester,
      loadBeforePump: false,
      pump: (notifier) async {
        await tester.runAsync(() async {
          // Pump with an UNLOADED notifier first (spinner state)...
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: DiveInformationSection(
                  notifier: notifier, dive: _testDive()),
            ),
          ));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          // ...then the async load resolves and notifies.
          await notifier.load('dive_x');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
      },
    );

    expect(find.text('21'), findsOneWidget); // air temp
    expect(find.text('14'), findsOneWidget); // water temp
  });

  // #32: with no explicitly-recorded water temp, the sample-derived
  // average is shown as the field's hint. Material hides the hint behind
  // the label when the field is empty + unfocused, which made the average
  // look blank until tapped. The fix floats the label always, so assert
  // the field is configured to surface the hint without an interaction.
  testWidgets('avg water temp hint is visible without focusing the field',
      (tester) async {
    final harness = await setup(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiveInformationSection(
            notifier: harness.notifier,
            dive: _testDive(),
            defaultWaterTempC: 28.0,
          ),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final waterField = tester
        .widgetList<TextField>(find.byType(TextField))
        .firstWhere((tf) => tf.decoration?.hintText == '28 (avg)');
    expect(waterField.decoration?.floatingLabelBehavior,
        FloatingLabelBehavior.always);
  });
}

typedef DiveInformationSectionPump = Future<void> Function(
    DiveAnnotationsNotifier notifier);

Dive _testDive({
  int waterDensity = 1025,
  int atmosphericPressureMbar = 1013,
}) {
  const start = 1776611925;
  return Dive(
    id: 'dive_x',
    dcSerial: 0xb89641e4,
    dcDiveNumber: 705,
    startTime: start,
    endTime: start + 3450,
    utcOffsetMinutes: null,
    durationSeconds: 3450,
    maxDepthMm: 18000,
    diveMode: 0,
    decoModel: 0,
    gfLow: 50,
    gfHigh: 95,
    atmosphericPressureMbar: atmosphericPressureMbar,
    waterDensity: waterDensity,
    logVersion: 17,
    dcModel: 3,
    dcFirmware: 0xa3,
    sampleIntervalMs: 10000,
    gasMixesJson: '',
    tanksJson: null,
    configuredStackSeconds: 25200,
    stackRemainingAtStartSeconds: 10847,
    stackRemainingAtEndSeconds: 7347,
    rawBlob: Uint8List(0),
    parserVersion: 1,
    importedAt: 1776591525,
  );
}
