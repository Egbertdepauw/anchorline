import 'dart:async';
import 'dart:math';

import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/equipment_dao.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/screens/equipment/cylinder_detail_screen.dart';
import 'package:ccrlogger/ui/screens/gas_analysis_log_screen.dart';
import 'package:ccrlogger/ui/widgets/mix_match_indicator.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_elapsed.dart';
import '../../_helpers/fake_gas_analyses_dao.dart';
import '../../_helpers/fake_label_printer.dart';
import '../../_helpers/powersync_test_helper.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// A [LabelPrintService] that prints on [printer]. [rendered] collects the
/// labels it is asked to draw.
LabelPrintService _service(
  FakeLabelPrinter printer, {
  bool configured = true,
  List<CylinderLabel>? rendered,
}) =>
    LabelPrintService(
      render: (label) async {
        rendered?.add(label);
        return LabelBitmap.blank(384, 240);
      },
      printerFor: (_) => printer,
      scanner: FakeLabelPrinterScanner(),
      printerId: () => configured ? 'dev-1' : null,
      use14ForDeeperMixes: () => false,
    );

/// A [FakeGasAnalysesDao] where an analysis is deleted (on another device,
/// say) as soon as it is edited.
class _DeletedOnEditDao extends FakeGasAnalysesDao {
  _DeletedOnEditDao({super.analyses});

  @override
  Future<void> update(String id, GasAnalysisEdit edit) async {
    await super.update(id, edit);
    await softDelete(id);
  }
}

void main() {
  GasAnalysis entry(String id, DateTime at, double o2, double he,
          {String? cylinderId,
          String? label,
          bool stable = true,
          int? targetO2,
          int? targetHe,
          GasRole gasRole = GasRole.bailout}) =>
      GasAnalysis(
        id: id,
        cylinderId: cylinderId,
        cylinderLabel: label,
        analysedBy: 'Egbert',
        analysedAt: at,
        o2Percent: o2,
        hePercent: he,
        fillPressureBar: 200,
        stable: stable,
        targetO2Percent: targetO2,
        targetHePercent: targetHe,
        gasRole: gasRole,
      );

  FakeGasAnalysesDao seeded() => FakeGasAnalysesDao(analyses: [
        entry('old', DateTime(2026, 9, 1, 10), 32.2, 0,
            cylinderId: 'c1', label: 'S80 left'),
        entry('new', DateTime(2026, 10, 30, 18, 5), 21.4, 34.6,
            cylinderId: 'c2', label: 'AL40 deco', stable: false),
      ]);

  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('lists newest first with whole-number mix names',
      (tester) async {
    await pump(tester, GasAnalysisLogScreen(dao: seeded()));
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['Tx21/35', 'EAN32']);
    expect(find.textContaining('AL40 deco'), findsOneWidget);
    expect(find.textContaining('Egbert'), findsNWidgets(2));
    expect(find.textContaining('200 bar'), findsNWidgets(2));
    // Stable flag: one warning (not stable), one check.
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('per-cylinder view filters and titles by cylinder',
      (tester) async {
    await pump(
        tester,
        GasAnalysisLogScreen(
            dao: seeded(), cylinderId: 'c1', cylinderLabel: 'S80 left'));
    expect(find.text('Analyses · S80 left'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('EAN32'), findsOneWidget);
  });

  testWidgets('swipe soft-deletes through the DAO', (tester) async {
    final dao = seeded();
    await pump(tester, GasAnalysisLogScreen(dao: dao));
    await tester.drag(find.text('Tx21/35'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(dao.deleted, ['new']);
    expect(find.text('Tx21/35'), findsNothing);
    expect(find.text('EAN32'), findsOneWidget);
    expect(find.text('Deleted Tx21/35 analysis.'), findsOneWidget);
  });

  testWidgets('export hands the CSV of the shown entries to the sharer',
      (tester) async {
    String? csv;
    String? name;
    await pump(
        tester,
        GasAnalysisLogScreen(
          dao: seeded(),
          shareCsv: (c, n, _) async {
            csv = c;
            name = n;
          },
        ));
    await tester.tap(find.byKey(const ValueKey('analysis-log-export')));
    await tester.pumpAndSettle();
    expect(name, matches(RegExp(r'^gas-analyses-\d{4}-\d{2}-\d{2}\.csv$')));
    final lines = csv!.trimRight().split('\n');
    expect(lines.first, startsWith('"time","cylinder","diver","mix"'));
    expect(lines, hasLength(3));
    expect(lines[1], contains('"AL40 deco","Egbert","Tx21/35"'));
    expect(lines[1], endsWith('"false","","bailout"'));
  });

  testWidgets('empty log: message and export disabled', (tester) async {
    await pump(tester, GasAnalysisLogScreen(dao: FakeGasAnalysesDao()));
    expect(find.textContaining('No analyses saved yet'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('analysis-log-export')))
            .onPressed,
        isNull);
  });

  testWidgets('a save elsewhere refreshes the list', (tester) async {
    final dao = FakeGasAnalysesDao();
    await pump(tester, GasAnalysisLogScreen(dao: dao));
    await dao.add(NewGasAnalysis(
      analysedAt: DateTime(2026, 10, 31),
      o2Percent: 50.3,
      hePercent: 0,
      stable: true,
    ));
    await tester.pumpAndSettle();
    expect(find.text('EAN50'), findsOneWidget);
  });

  // ── Desired mix, reprint and edit (#114) ─────────────────────────────

  /// Desired 21/35, analysed 22.5/33.8 (orange: O2 1.5 off), diluent.
  GasAnalysis tx() => entry('tx', DateTime(2026, 10, 30, 18, 5), 22.5, 33.8,
      cylinderId: 'c1',
      label: 'S80 left',
      targetO2: 21,
      targetHe: 35,
      gasRole: GasRole.diluent);

  /// Desired 50/0, analysed 32.1/0: a hard mismatch.
  GasAnalysis ean() => entry('ean', DateTime(2026, 10, 29, 9), 32.1, 0,
      targetO2: 50, targetHe: 0);

  /// No desired mix, bailout.
  GasAnalysis plain() => entry('plain', DateTime(2026, 9, 1, 10), 32.2, 0);

  Finder inTile(String id, Finder f) =>
      find.descendant(of: _key('analysis-$id'), matching: f);

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// Taps the print action of [id] and prints [copies] from the dialog.
  Future<void> reprint(WidgetTester tester, String id,
      {int copies = 1}) async {
    await tapAndSettle(tester, _key('analysis-print-$id'));
    for (var i = 1; i < copies; i++) {
      await tapAndSettle(tester, _key('copies-inc'));
    }
    await tapAndSettle(tester, _key('copies-dialog-print'));
  }

  const mismatchTitle = 'Mix does not conform to analysis';

  group('tile', () {
    testWidgets('shows the desired mix and how far the analysis is off it',
        (tester) async {
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [tx()])));
      expect(inTile('tx', find.text('Tx23/34')), findsOneWidget);
      expect(inTile('tx', find.text('Desired Tx21/35')), findsOneWidget);
      expect(inTile('tx', find.byType(MixMatchIndicator)), findsOneWidget);
      expect(inTile('tx', find.text('O2 1.5 off Tx21/35')), findsOneWidget);
    });

    testWidgets('an entry without a desired mix shows neither',
        (tester) async {
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [plain()])));
      expect(inTile('plain', find.text('EAN32')), findsOneWidget);
      expect(inTile('plain', find.textContaining('Desired')), findsNothing);
      expect(inTile('plain', find.byType(MixMatchIndicator)), findsNothing);
    });

    testWidgets('a diluent entry has a DIL marker, a bailout entry none',
        (tester) async {
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx(), plain()])));
      expect(_key('analysis-dil-tx'), findsOneWidget);
      expect(find.descendant(
              of: _key('analysis-dil-tx'), matching: find.text('DIL')),
          findsOneWidget);
      expect(_key('analysis-dil-plain'), findsNothing);
    });

    testWidgets('the busiest tile fits a phone', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final busy = GasAnalysis(
        id: 'busy',
        cylinderId: 'c1',
        cylinderLabel: 'Left-hand S80 sidemount stage',
        analysedBy: 'Egbert de Pauw',
        analysedAt: DateTime(2026, 10, 30, 18, 5),
        o2Percent: 10.4,
        hePercent: 71.6,
        fillPressureBar: 232,
        stable: false,
        notes: 'Topped up after the second fill',
        targetO2Percent: 18,
        targetHePercent: 45,
        gasRole: GasRole.diluent,
      );
      await pump(
          tester,
          GasAnalysisLogScreen(
            dao: FakeGasAnalysesDao(analyses: [busy]),
            labelPrinting: _service(FakeLabelPrinter()),
          ));
      // A layout overflow would have failed the pump.
      expect(_key('analysis-dil-busy'), findsOneWidget);
      expect(inTile('busy', find.text('O2 7.6, He 26.6 off Tx18/45')),
          findsOneWidget);
      expect(_key('analysis-print-busy'), findsOneWidget);
    });
  });

  group('reprint', () {
    testWidgets('the print action shows only with a printer set up',
        (tester) async {
      final printer = FakeLabelPrinter();
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [tx()])));
      expect(_key('analysis-print-tx'), findsNothing);

      await pump(
          tester,
          GasAnalysisLogScreen(
            key: const ValueKey('not-configured'),
            dao: FakeGasAnalysesDao(analyses: [tx()]),
            labelPrinting: _service(printer, configured: false),
          ));
      expect(_key('analysis-print-tx'), findsNothing);

      await pump(
          tester,
          GasAnalysisLogScreen(
            key: const ValueKey('configured'),
            dao: FakeGasAnalysesDao(analyses: [tx(), plain()]),
            labelPrinting: _service(printer),
          ));
      expect(_key('analysis-print-tx'), findsOneWidget);
      expect(_key('analysis-print-plain'), findsOneWidget);
    });

    testWidgets('asks for copies and prints that many of the entry',
        (tester) async {
      final printer = FakeLabelPrinter();
      final rendered = <CylinderLabel>[];
      final dao = FakeGasAnalysesDao(analyses: [tx(), plain()]);
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: dao,
              labelPrinting: _service(printer, rendered: rendered)));
      await reprint(tester, 'tx', copies: 2);

      expect(printer.printed.single.$2, 2);
      // Up to red the label shows the desired name; the role is the stored one.
      expect(rendered.single.mixName, 'Tx21/35');
      expect(rendered.single.kind, CylinderLabelKind.diluent);
      expect(find.text('Printed 2 labels.'), findsOneWidget);
      expect(dao.updated, isEmpty);
    });

    testWidgets('cancelling the copies prompt prints nothing',
        (tester) async {
      final printer = FakeLabelPrinter();
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx()]),
              labelPrinting: _service(printer)));
      await tapAndSettle(tester, _key('analysis-print-tx'));
      await tapAndSettle(tester, find.text('Cancel'));
      expect(printer.printed, isEmpty);
    });

    testWidgets('a match, orange or red entry prints without the warning',
        (tester) async {
      final printer = FakeLabelPrinter();
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx(), plain()]),
              labelPrinting: _service(printer)));
      await reprint(tester, 'tx');
      await reprint(tester, 'plain');
      expect(find.text(mismatchTitle), findsNothing);
      expect(printer.printed, hasLength(2));
    });

    group('hard mismatch', () {
      testWidgets('"Print as EAN32" prints the analysed mix', (tester) async {
        final printer = FakeLabelPrinter();
        final rendered = <CylinderLabel>[];
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: FakeGasAnalysesDao(analyses: [ean()]),
                labelPrinting: _service(printer, rendered: rendered)));
        await reprint(tester, 'ean', copies: 2);
        expect(find.text(mismatchTitle), findsOneWidget);
        expect(printer.printed, isEmpty, reason: 'asks before printing');

        await tapAndSettle(tester, find.text('Print as EAN32'));
        expect(printer.printed.single.$2, 2);
        expect(rendered.single.mixName, 'EAN32');
      });

      testWidgets('"Cancel" prints nothing', (tester) async {
        final printer = FakeLabelPrinter();
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: FakeGasAnalysesDao(analyses: [ean()]),
                labelPrinting: _service(printer)));
        await reprint(tester, 'ean');
        await tapAndSettle(tester, _key('mix-mismatch-cancel'));
        expect(find.text(mismatchTitle), findsNothing);
        expect(printer.printed, isEmpty);
      });

      testWidgets(
          '"Change desired mix" edits the entry, then prints it without a '
          'second warning or copies prompt', (tester) async {
        final printer = FakeLabelPrinter();
        final rendered = <CylinderLabel>[];
        final dao = FakeGasAnalysesDao(analyses: [ean()]);
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: dao,
                labelPrinting: _service(printer, rendered: rendered)));
        await reprint(tester, 'ean', copies: 3);
        await tapAndSettle(tester, find.text('Change desired mix'));
        expect(_key('analysis-edit-sheet'), findsOneWidget);
        expect(printer.printed, isEmpty);

        await tapAndSettle(tester, _key('desired-mix-other'));
        await tester.enterText(_key('desired-mix-other-o2'), '32');
        await tapAndSettle(tester, _key('desired-mix-other-ok'));
        await tapAndSettle(tester, _key('analysis-edit-save'));

        final (id, edit) = dao.updated.single;
        expect(id, 'ean');
        expect(edit.desiredMix, const DesiredMix(32, 0));
        // The stored mix now matches: no second dialog, no second prompt.
        expect(find.text(mismatchTitle), findsNothing);
        expect(_key('copies-dialog-print'), findsNothing);
        expect(printer.printed.single.$2, 3);
        expect(rendered.single.mixName, 'EAN32');
        // The list shows the edit.
        expect(inTile('ean', find.text('Desired EAN32')), findsOneWidget);
      });

      testWidgets('cancelling the edit prints nothing', (tester) async {
        final printer = FakeLabelPrinter();
        final dao = FakeGasAnalysesDao(analyses: [ean()]);
        await pump(
            tester,
            GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
        await reprint(tester, 'ean');
        await tapAndSettle(tester, find.text('Change desired mix'));
        await tapAndSettle(tester, _key('analysis-edit-cancel'));
        expect(_key('analysis-edit-sheet'), findsNothing);
        expect(find.text(mismatchTitle), findsNothing);
        expect(printer.printed, isEmpty);
        expect(dao.updated, isEmpty);
      });

      testWidgets('an entry deleted while it was edited is not printed',
          (tester) async {
        final printer = FakeLabelPrinter();
        final dao = _DeletedOnEditDao(analyses: [ean()]);
        await pump(
            tester,
            GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
        await reprint(tester, 'ean');
        await tapAndSettle(tester, find.text('Change desired mix'));
        await tapAndSettle(tester, _key('desired-mix-other'));
        await tester.enterText(_key('desired-mix-other-o2'), '32');
        await tapAndSettle(tester, _key('desired-mix-other-ok'));
        await tapAndSettle(tester, _key('analysis-edit-save'));

        expect(printer.printed, isEmpty);
        expect(find.text(mismatchTitle), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(_key('analysis-ean'), findsNothing);
      });
    });

    testWidgets('a second tap while a reprint is under way does nothing',
        (tester) async {
      final gate = Completer<void>();
      final printer = FakeLabelPrinter(printGate: gate);
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx()]),
              labelPrinting: _service(printer)));

      // A double tap: the second lands before the copies prompt is up.
      final action =
          tester.widget<IconButton>(_key('analysis-print-tx')).onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(_key('copies-dialog-print'), findsOneWidget);

      // The print is held at the gate; nothing animates meanwhile.
      await tapAndSettle(tester, _key('copies-dialog-print'));
      expect(printer.printed, hasLength(1));
      // Printing: the action is off until the job is done.
      expect(
          tester.widget<IconButton>(_key('analysis-print-tx')).onPressed,
          isNull);
      action();
      await tester.pumpAndSettle();
      expect(_key('copies-dialog-print'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(printer.printed, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
      expect(
          tester.widget<IconButton>(_key('analysis-print-tx')).onPressed,
          isNotNull);
    });
  });

  group('edit', () {
    testWidgets('tapping an entry opens the sheet with its measured values '
        'read-only and the recent mixes to pick from', (tester) async {
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx(), ean(), plain()])));
      await tapAndSettle(tester, find.text('Tx23/34'));

      final sheet = _key('analysis-edit-sheet');
      Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
      expect(sheet, findsOneWidget);
      final measured = _key('analysis-edit-measured');
      expect(find.descendant(of: measured, matching: find.text('Tx23/34')),
          findsOneWidget);
      expect(
          find.descendant(
              of: measured, matching: find.textContaining('22.5')),
          findsOneWidget);
      // The options are recentDesiredMixes of the log: newest first.
      expect(
          tester
              .widgetList<ChoiceChip>(inSheet(find.byType(ChoiceChip)))
              .map((c) => (c.label as Text).data),
          ['Tx21/35', 'EAN50']);
      expect(inSheet(_key('analysis-edit-role')), findsOneWidget);
      expect(inSheet(_key('analysis-edit-diver')), findsOneWidget);
      expect(inSheet(_key('analysis-edit-notes')), findsOneWidget);
      // Only who analysed and the notes are typed: no measured-value input.
      expect(inSheet(find.byType(EditableText)), findsNWidgets(2));
    });

    testWidgets('saving updates the four fields and refreshes the list',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [tx(), ean()]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      expect(_key('analysis-dil-tx'), findsOneWidget);

      await tapAndSettle(tester, find.text('Tx23/34'));
      await tapAndSettle(tester, _key('desired-mix-50-0'));
      await tapAndSettle(tester, find.text('Bailout/deco'));
      await tester.enterText(_key('analysis-edit-diver'), 'EdP');
      await tester.enterText(_key('analysis-edit-notes'), 'Topped up');
      await tapAndSettle(tester, _key('analysis-edit-save'));

      final (id, edit) = dao.updated.single;
      expect(id, 'tx');
      expect(edit.desiredMix, const DesiredMix(50, 0));
      expect(edit.gasRole, GasRole.bailout);
      expect(edit.analysedBy, 'EdP');
      expect(edit.notes, 'Topped up');
      expect(_key('analysis-edit-sheet'), findsNothing);
      expect(_key('analysis-dil-tx'), findsNothing);
      expect(inTile('tx', find.text('Desired EAN50')), findsOneWidget);
      expect(inTile('tx', find.textContaining('EdP')), findsOneWidget);
      // The measured values are as they were.
      expect(inTile('tx', find.text('Tx23/34')), findsOneWidget);
    });
  });

  group('wiring', () {
    testWidgets('the analyzer passes its label printing to the log',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsNotifier();
      await settings.load();
      await tester.pumpWidget(MaterialApp(
        home: AnalyzerScreen(
          settings: settings,
          analysesDao: FakeGasAnalysesDao(analyses: [tx()]),
          labelPrinting: _service(FakeLabelPrinter()),
          controller: fakeClockAnalyzerController(tester),
          transportOptions: [
            AnalyzerTransportOption(
              label: 'Bench',
              create: () => DemoAnalyzerTransport(
                  targetO2: 21, targetHe: 35, random: Random(1)),
            ),
          ],
        ),
      ));
      await tester.pump();
      await tapAndSettle(tester, _key('analyzer-open-log'));
      expect(_key('analysis-print-tx'), findsOneWidget);
    });

    testWidgets('a cylinder in Equipment passes its label printing to the log',
        (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      late final EquipmentDao equipment;
      late final String cylinderId;
      await tester.runAsync(() async {
        final rig = await openEquipmentDaoForTest(db);
        equipment = rig.dao;
        cylinderId = await equipment.addCylinder(
          label: 'S80 left',
          role: CylinderRole.bailout,
          bailoutOrder: 1,
          volumeLiters: 11.1,
          workingPressureBar: 207,
        );
      });
      final analyses = FakeGasAnalysesDao(analyses: [
        entry('a1', DateTime(2026, 10, 30), 32.1, 0,
            cylinderId: cylinderId, label: 'S80 left'),
      ]);

      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          home: CylinderDetailScreen(
            dao: equipment,
            id: cylinderId,
            analysesDao: analyses,
            labelPrinting: _service(FakeLabelPrinter()),
          ),
        ));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      await tapAndSettle(tester, _key('cylinder-analyses'));
      expect(find.text('Analyses · S80 left'), findsOneWidget);
      expect(_key('analysis-print-a1'), findsOneWidget);
    });
  });
}
