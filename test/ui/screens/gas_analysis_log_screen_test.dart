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
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/screens/equipment/cylinder_detail_screen.dart';
import 'package:ccrlogger/ui/screens/gas_analysis_log_screen.dart';
import 'package:ccrlogger/ui/screens/gas_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
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

/// A [LabelPrintService] whose jobs take the next printer in [printers]
/// each, so a test can make the first print fail and its Retry work.
LabelPrintService _serviceOn(
  List<FakeLabelPrinter> printers, {
  List<CylinderLabel>? rendered,
}) {
  var next = 0;
  return LabelPrintService(
    render: (label) async {
      rendered?.add(label);
      return LabelBitmap.blank(384, 240);
    },
    printerFor: (_) => printers[next++],
    scanner: FakeLabelPrinterScanner(),
    printerId: () => 'dev-1',
    use14ForDeeperMixes: () => false,
  );
}

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

/// A [FakeGasAnalysesDao] where an analysis is flagged as needing sign-off
/// (through sync, say) as soon as it is edited.
class _FlaggedOnEditDao extends FakeGasAnalysesDao {
  _FlaggedOnEditDao({super.analyses});

  @override
  Future<void> update(String id, GasAnalysisEdit edit) async {
    await super.update(id, edit);
    await setNeedsSignoff(id, true);
  }
}

void main() {
  GasAnalysis entry(String id, DateTime at, double o2, double he,
          {String? cylinderId,
          String? label,
          bool stable = true,
          bool needsSignoff = false,
          String? analysedBy = 'Egbert',
          int? targetO2,
          int? targetHe,
          GasRole gasRole = GasRole.bailout}) =>
      GasAnalysis(
        id: id,
        cylinderId: cylinderId,
        cylinderLabel: label,
        analysedBy: analysedBy,
        analysedAt: at,
        o2Percent: o2,
        hePercent: he,
        fillPressureBar: 200,
        stable: stable,
        needsSignoff: needsSignoff,
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
    expect(find.byType(Dismissible), findsNWidgets(2));
    expect(tester.getTopLeft(find.text('Tx21/35')).dy,
        lessThan(tester.getTopLeft(find.text('EAN32')).dy));
    expect(find.textContaining('AL40 deco'), findsOneWidget);
    expect(find.textContaining('Egbert'), findsNWidgets(2));
    expect(find.textContaining('200 bar'), findsNWidgets(2));
    // Stable flag: only the unstable entry says so.
    expect(find.text('Saved before stable'), findsOneWidget);
  });

  testWidgets('per-cylinder view filters and titles by cylinder',
      (tester) async {
    await pump(
        tester,
        GasAnalysisLogScreen(
            dao: seeded(), cylinderId: 'c1', cylinderLabel: 'S80 left'));
    expect(find.text('Analyses · S80 left'), findsOneWidget);
    expect(find.byType(Dismissible), findsOneWidget);
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
    expect(lines[1], endsWith('"false","","bailout","","false"'));
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

  testWidgets('the embedded log with entries has one tool row',
      (tester) async {
    await pump(
        tester,
        Scaffold(
          body: GasAnalysisLogScreen(
            dao: FakeGasAnalysesDao(analyses: [
              entry('a1', DateTime(2026, 10, 30, 18), 32.1, 0),
            ]),
            embedded: true,
          ),
        ));
    expect(_key('analysis-log-filter-all'), findsOneWidget);
    expect(_key('analysis-log-export'), findsOneWidget);
    expect(find.text('All 1'), findsOneWidget);
  });

  testWidgets('the pushed log has its chips in the body and Export in the '
      'app bar', (tester) async {
    await pump(tester, GasAnalysisLogScreen(dao: seeded()));
    expect(_key('analysis-log-filter-all'), findsOneWidget);
    expect(_key('analysis-log-export'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AppBar), matching: _key('analysis-log-export')),
        findsOneWidget);
  });

  testWidgets('the pushed log with no entries has no tool row',
      (tester) async {
    await pump(tester, GasAnalysisLogScreen(dao: FakeGasAnalysesDao()));
    expect(_key('analysis-log-filter-all'), findsNothing);
    expect(_key('analysis-log-export'), findsOneWidget);
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

  /// Taps [f], scrolling it into view first: the edit sheet is taller than
  /// the test's 800x600 screen.
  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
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
    testWidgets('rows lead with the analysed name and say the desired mix '
        'in line 3', (tester) async {
      final e = entry('m', DateTime(2026, 10, 30, 18, 5), 20.6, 33.8,
          targetO2: 21, targetHe: 35, gasRole: GasRole.diluent);
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [e])));
      expect(inTile('m', find.text('Tx21/34')), findsOneWidget);
      expect(inTile('m', find.text('Matches Tx21/35')), findsOneWidget);
      // Line 2: the measured numbers to one decimal, pressure and name.
      expect(inTile('m', find.text('20.6 / 33.8 · 200 bar · Egbert')),
          findsOneWidget);
      expect(inTile('m', find.text('18:05')), findsOneWidget);
      expect(inTile('m', find.textContaining('Desired')), findsNothing);
    });

    testWidgets('an orange entry says how far it is off', (tester) async {
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [tx()])));
      expect(inTile('tx', find.text('Tx23/34')), findsOneWidget);
      expect(inTile('tx', find.text('O2 1.5 off Tx21/35')), findsOneWidget);
    });

    testWidgets('an entry without a desired mix has no line 3',
        (tester) async {
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [plain()])));
      expect(inTile('plain', find.text('EAN32')), findsOneWidget);
      expect(inTile('plain', find.textContaining('Matches')), findsNothing);
      expect(inTile('plain', find.textContaining(' off ')), findsNothing);
      expect(inTile('plain', find.text('Saved before stable')), findsNothing);
    });

    testWidgets('an unstable entry says Saved before stable', (tester) async {
      final e = entry('u', DateTime(2026, 10, 30, 18, 5), 21, 35,
          stable: false, targetO2: 21, targetHe: 35);
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [e])));
      final text = find.text('Saved before stable');
      expect(inTile('u', text), findsOneWidget);
      expect(tester.widget<Text>(text).style?.color, SafetyColors.warning);
      expect(inTile('u', find.text('Matches Tx21/35')), findsOneWidget);
    });

    testWidgets('the role tag says DIL or BO and an entry with no name says '
        'so', (tester) async {
      final noName = entry('nn', DateTime(2026, 10, 28, 9), 32, 0,
          analysedBy: null);
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx(), plain(), noName])));
      expect(
          find.descendant(
              of: _key('analysis-role-tx'), matching: find.text('DIL')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _key('analysis-role-plain'), matching: find.text('BO')),
          findsOneWidget);
      expect(inTile('nn', find.textContaining('no name')), findsOneWidget);
    });

    testWidgets('a note shows as an icon on line 1', (tester) async {
      final e = GasAnalysis(
        id: 'n',
        analysedAt: DateTime(2026, 10, 30, 18, 5),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
        notes: 'Topped up',
      );
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: [e])));
      expect(_key('analysis-notes-n'), findsOneWidget);
      // A tap shows the note (a touch screen has no hover).
      expect(find.text('Topped up'), findsNothing);
      await tester.tap(_key('analysis-notes-n'));
      await tester.pump();
      expect(find.text('Topped up'), findsOneWidget);
      expect(_key('analysis-notes-tx'), findsNothing);
    });

    testWidgets('day separators group entries', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final yesterday = today.subtract(const Duration(days: 1));
      final es = [
        entry('t1', today.add(const Duration(hours: 2)), 32, 0),
        entry('t2', today, 36, 0),
        entry('y1', yesterday, 50, 0),
        entry('o1', DateTime(2026, 9, 1, 10), 21, 35),
      ];
      await pump(tester,
          GasAnalysisLogScreen(dao: FakeGasAnalysesDao(analyses: es)));
      String key(DateTime d) =>
          'analysis-day-${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      expect(find.descendant(of: _key(key(today)), matching: find.text('TODAY')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _key(key(yesterday)), matching: find.text('YESTERDAY')),
          findsOneWidget);
      expect(
          find.descendant(
              of: _key('analysis-day-2026-09-01'),
              matching: find.text('1 SEP 2026')),
          findsOneWidget);
      // One header per day, not per entry.
      expect(find.byWidgetPredicate((w) =>
              w.key is ValueKey &&
              (w.key as ValueKey).value.toString().startsWith('analysis-day-')),
          findsNWidgets(3));
      // t1 and t2 sit under the same header, above yesterday's.
      expect(tester.getTopLeft(_key(key(today))).dy,
          lessThan(tester.getTopLeft(find.text('EAN36')).dy));
      expect(tester.getTopLeft(find.text('EAN36')).dy,
          lessThan(tester.getTopLeft(_key(key(yesterday))).dy));
    });

    testWidgets('the bailout edge uses a palette colour in every theme',
        (tester) async {
      for (final theme in AppThemes.all) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(theme.id),
          theme: theme.themeData,
          home: GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [tx(), plain()])),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: theme.id);
        Color edge(String id) {
          final box = tester.widget<Container>(find
              .descendant(
                  of: _key('analysis-$id'), matching: find.byType(Container))
              .first);
          return ((box.decoration as BoxDecoration).border as Border)
              .left
              .color;
        }

        expect(edge('tx'), theme.palette.accentPrimary, reason: theme.id);
        expect(edge('plain'), theme.palette.textMuted, reason: theme.id);
      }
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
      expect(_key('analysis-role-busy'), findsOneWidget);
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
        expect(inTile('ean', find.text('Matches EAN32')), findsOneWidget);
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

      testWidgets('an entry deleted while the mismatch dialog is open prints '
          'nothing', (tester) async {
        final printer = FakeLabelPrinter();
        final dao = FakeGasAnalysesDao(analyses: [ean()]);
        await pump(tester,
            GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
        await reprint(tester, 'ean');
        expect(find.text(mismatchTitle), findsOneWidget);

        await dao.softDelete('ean');
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Print as EAN32'));

        expect(printer.connects, 0);
        expect(printer.printed, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
      });

      /// [ean] with its desired mix replaced, as an edit stores it.
      GasAnalysisEdit eanEdit(DesiredMix mix) => GasAnalysisEdit(
          desiredMix: mix,
          gasRole: GasRole.bailout,
          analysedBy: 'Egbert',
          notes: null,
          cylinderId: ean().cylinderId,
          fillPressureBar: ean().fillPressureBar,
          analysedFor: ean().analysedFor);

      testWidgets('a desired mix changed while the mismatch dialog is open '
          'is graded and asked about again', (tester) async {
        final printer = FakeLabelPrinter();
        final rendered = <CylinderLabel>[];
        final dao = FakeGasAnalysesDao(analyses: [ean()]);
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: dao,
                labelPrinting: _service(printer, rendered: rendered)));
        await reprint(tester, 'ean');

        // Changed through sync meanwhile: another hard mismatch.
        await dao.update('ean', eanEdit(const DesiredMix(60, 0)));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Print as EAN32'));
        expect(printer.printed, isEmpty, reason: 'asks about the new mix');
        expect(find.text(mismatchTitle), findsOneWidget);

        await tapAndSettle(tester, find.text('Print as EAN32'));
        expect(printer.printed, hasLength(1));
        expect(rendered.single.mixName, 'EAN32');
      });

      testWidgets('a desired mix changed to a milder mismatch while the '
          'dialog is open prints that entry without asking again',
          (tester) async {
        final printer = FakeLabelPrinter();
        final rendered = <CylinderLabel>[];
        final dao = FakeGasAnalysesDao(analyses: [ean()]);
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: dao,
                labelPrinting: _service(printer, rendered: rendered)));
        await reprint(tester, 'ean', copies: 2);

        // 2.9 off EAN35: red, no longer a hard mismatch. Up to red the
        // label shows the desired name, so it is of the entry as stored now.
        await dao.update('ean', eanEdit(const DesiredMix(35, 0)));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, find.text('Print as EAN32'));

        expect(find.text(mismatchTitle), findsNothing);
        expect(printer.printed.single.$2, 2);
        expect(rendered.single.mixName, 'EAN35');
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

    // The entry can change (here, or through sync) while a reprint waits on
    // the diver: during the copies prompt, or between a failed print and
    // its Retry. A label must never show what the entry no longer says.
    group('an entry that changes', () {
      const deleted = 'This analysis was deleted.';
      const changed = 'This analysis changed. Print it again from the log.';

      /// [tx] with the stated fields replaced, as an edit stores them. The
      /// cylinder, fill pressure and analysed for stay as [tx] has them.
      GasAnalysisEdit txEdit({
        DesiredMix? mix = const DesiredMix(21, 35),
        GasRole role = GasRole.diluent,
        String? by = 'Egbert',
      }) =>
          GasAnalysisEdit(
              desiredMix: mix,
              gasRole: role,
              analysedBy: by,
              notes: null,
              cylinderId: tx().cylinderId,
              fillPressureBar: tx().fillPressureBar,
              analysedFor: tx().analysedFor);

      /// Reprints 2 copies of `tx` on a printer that fails. Its Retry
      /// prints on [on].
      Future<FakeGasAnalysesDao> failReprint(
          WidgetTester tester, FakeLabelPrinter on,
          {List<CylinderLabel>? rendered}) async {
        final dao = FakeGasAnalysesDao(analyses: [tx(), plain()]);
        final off = FakeLabelPrinter(failOnConnect: Exception('no link'));
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: dao,
                labelPrinting: _serviceOn([off, on], rendered: rendered)));
        await reprint(tester, 'tx', copies: 2);
        expect(find.text('Printer not found'), findsOneWidget);
        return dao;
      }

      testWidgets('Retry prints the entry as stored now', (tester) async {
        final on = FakeLabelPrinter();
        final rendered = <CylinderLabel>[];
        final dao = await failReprint(tester, on, rendered: rendered);
        // Edited elsewhere, but not the mix or the role.
        await dao.update('tx', txEdit(by: 'EdP'));
        await tester.pumpAndSettle();

        await tapAndSettle(tester, find.text('Retry'));
        expect(on.printed.single.$2, 2);
        expect(rendered.last.analysedBy, 'EdP');
        expect(rendered.last.mixName, 'Tx21/35');
        expect(find.text('Printed 2 labels.'), findsOneWidget);
      });

      testWidgets('Retry does not print an entry whose mix changed since',
          (tester) async {
        final on = FakeLabelPrinter();
        final dao = await failReprint(tester, on);
        await dao.update('tx', txEdit(mix: const DesiredMix(23, 34)));
        await tester.pumpAndSettle();

        await tapAndSettle(tester, find.text('Retry'));
        expect(on.connects, 0);
        expect(find.text(changed), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('Retry does not print an entry whose role changed since',
          (tester) async {
        final on = FakeLabelPrinter();
        final dao = await failReprint(tester, on);
        await dao.update('tx', txEdit(role: GasRole.bailout));
        await tester.pumpAndSettle();

        await tapAndSettle(tester, find.text('Retry'));
        expect(on.connects, 0);
        expect(find.text(changed), findsOneWidget);
      });

      testWidgets('Retry does not print an entry deleted since',
          (tester) async {
        final on = FakeLabelPrinter();
        final dao = await failReprint(tester, on);
        // Deleted on another device: the list drops it, the bar stays.
        await dao.softDelete('tx');
        await tester.pumpAndSettle();
        expect(_key('analysis-tx'), findsNothing);

        await tapAndSettle(tester, find.text('Retry'));
        expect(on.connects, 0);
        expect(find.text(deleted), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('saving an edit hides an old print failure',
          (tester) async {
        final on = FakeLabelPrinter();
        await failReprint(tester, on);
        await tapAndSettle(tester, find.text('Tx23/34'));
        await tester.enterText(_key('analysis-edit-notes'), 'Topped up');
        await tapAndSettle(tester, _key('analysis-edit-save'));

        expect(find.text('Printer not found'), findsNothing);
        expect(find.text('Retry'), findsNothing);
        expect(on.connects, 0);
      });

      testWidgets('a cancelled edit leaves the print failure up',
          (tester) async {
        final on = FakeLabelPrinter();
        await failReprint(tester, on);
        await tapAndSettle(tester, find.text('Tx23/34'));
        await tapAndSettle(tester, _key('analysis-edit-cancel'));

        expect(find.text('Printer not found'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
      });

      testWidgets('swiping an entry away hides an old print failure',
          (tester) async {
        final on = FakeLabelPrinter();
        await failReprint(tester, on);
        await tester.drag(find.text('Tx23/34'), const Offset(-600, 0));
        await tester.pumpAndSettle();

        expect(find.text('Deleted Tx23/34 analysis.'), findsOneWidget);
        expect(find.text('Printer not found'), findsNothing);
        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('an edit made while the copies prompt is up is printed '
          'as stored, mismatch check included', (tester) async {
        final printer = FakeLabelPrinter();
        final rendered = <CylinderLabel>[];
        final dao = FakeGasAnalysesDao(analyses: [tx()]);
        await pump(
            tester,
            GasAnalysisLogScreen(
                dao: dao,
                labelPrinting: _service(printer, rendered: rendered)));
        await tapAndSettle(tester, _key('analysis-print-tx'));
        expect(_key('copies-dialog-print'), findsOneWidget);

        // Changed through sync meanwhile: desired EAN50 (a hard mismatch
        // with the analysed Tx23/34) and bailout.
        await dao.update(
            'tx', txEdit(mix: const DesiredMix(50, 0), role: GasRole.bailout));
        await tester.pumpAndSettle();
        await tapAndSettle(tester, _key('copies-dialog-print'));

        expect(find.text(mismatchTitle), findsOneWidget);
        expect(printer.printed, isEmpty);
        await tapAndSettle(tester, find.text('Print as Tx23/34'));
        expect(printer.printed, hasLength(1));
        expect(rendered.single.mixName, 'Tx23/34');
        expect(rendered.single.kind, CylinderLabelKind.bailout);
      });

      testWidgets('an entry deleted while the copies prompt is up is not '
          'printed', (tester) async {
        final printer = FakeLabelPrinter();
        final dao = FakeGasAnalysesDao(analyses: [tx()]);
        await pump(tester,
            GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
        await tapAndSettle(tester, _key('analysis-print-tx'));
        await dao.softDelete('tx');
        await tester.pumpAndSettle();
        await tapAndSettle(tester, _key('copies-dialog-print'));

        expect(printer.printed, isEmpty);
        expect(find.text(mismatchTitle), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      });
    });
  });

  group('needs sign-off', () {
    const filterKey = 'analysis-log-signoff-filter';

    /// Two flagged entries (newest) and one that is not.
    FakeGasAnalysesDao twoFlagged() => FakeGasAnalysesDao(analyses: [
          entry('f1', DateTime(2026, 10, 30, 18), 32.2, 0,
              needsSignoff: true),
          entry('f2', DateTime(2026, 10, 29, 18), 36, 0, needsSignoff: true),
          entry('ok', DateTime(2026, 10, 28, 18), 50.3, 0),
        ]);

    int tiles(WidgetTester tester) =>
        tester.widgetList(find.byType(Dismissible)).length;

    testWidgets('a flagged entry shows the badge and a faded print action',
        (tester) async {
      await pump(
          tester,
          GasAnalysisLogScreen(
            dao: FakeGasAnalysesDao(analyses: [
              entry('a1', DateTime(2026, 10, 30, 18), 32.2, 0,
                  needsSignoff: true),
              entry('a2', DateTime(2026, 10, 29, 18), 50.3, 0),
            ]),
            labelPrinting: _service(FakeLabelPrinter()),
          ));
      expect(_key('analysis-needs-signoff-a1'), findsOneWidget);
      expect(find.descendant(
              of: _key('analysis-needs-signoff-a1'),
              matching: find.text('Needs sign-off')),
          findsOneWidget);
      // The warning colour, not a theme one.
      final label = tester.widget<Text>(find.descendant(
          of: _key('analysis-needs-signoff-a1'),
          matching: find.text('Needs sign-off')));
      expect(label.style?.color, SafetyColors.warning);
      expect(_key('analysis-print-a1'), findsOneWidget);

      // An entry that is signed off keeps its print action, and no badge.
      expect(_key('analysis-needs-signoff-a2'), findsNothing);
      expect(_key('analysis-print-a2'), findsOneWidget);
    });

    testWidgets('a flagged entry with a note, a desired mix and a DIL marker '
        'still fits a phone', (tester) async {
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
        needsSignoff: true,
      );
      await pump(
          tester,
          GasAnalysisLogScreen(
            dao: FakeGasAnalysesDao(analyses: [busy]),
            labelPrinting: _service(FakeLabelPrinter()),
          ));
      // A layout overflow would have failed the pump.
      expect(_key('analysis-needs-signoff-busy'), findsOneWidget);
      expect(_key('analysis-role-busy'), findsOneWidget);
      expect(_key(filterKey), findsOneWidget);
      expect(_key('analysis-print-busy'), findsOneWidget);
    });

    testWidgets("a flagged entry's print button is faded and explains on tap",
        (tester) async {
      final printer = FakeLabelPrinter();
      await pump(
          tester,
          GasAnalysisLogScreen(
            dao: FakeGasAnalysesDao(analyses: [
              entry('a1', DateTime(2026, 10, 30, 18), 32.2, 0,
                  needsSignoff: true),
              entry('a2', DateTime(2026, 10, 29, 18), 50.3, 0),
            ]),
            labelPrinting: _service(printer),
          ));
      Opacity fade(String id) => tester.widget<Opacity>(find.ancestor(
          of: _key('analysis-print-$id'), matching: find.byType(Opacity)));
      expect(fade('a1').opacity, 0.35);
      expect(fade('a2').opacity, 1);

      await tapAndSettle(tester, _key('analysis-print-a1'));
      expect(find.text(kSignOffBeforePrintMessage), findsOneWidget);
      // No copies prompt, nothing printed.
      expect(_key('copies-dialog-print'), findsNothing);
      expect(printer.printed, isEmpty);
    });

    testWidgets('the sign-off chip filters, and All restores', (tester) async {
      await pump(tester, GasAnalysisLogScreen(dao: twoFlagged()));
      expect(find.text('All 3'), findsOneWidget);
      expect(find.descendant(
              of: _key(filterKey), matching: find.text('Needs sign-off 2')),
          findsOneWidget);
      expect(tester.widget<FilterChip>(_key('analysis-log-filter-all')).selected,
          isTrue);
      expect(tiles(tester), 3);

      await tapAndSettle(tester, _key(filterKey));
      expect(tiles(tester), 2);
      expect(_key('analysis-ok'), findsNothing);
      expect(tester.widget<FilterChip>(_key(filterKey)).selected, isTrue);
      // The count stays what it is: the filter doesn't hide the chip.
      expect(find.text('Needs sign-off 2'), findsOneWidget);

      await tapAndSettle(tester, _key('analysis-log-filter-all'));
      expect(tiles(tester), 3);
      expect(tester.widget<FilterChip>(_key(filterKey)).selected, isFalse);
    });

    testWidgets('the chip counts one flagged entry', (tester) async {
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: FakeGasAnalysesDao(analyses: [
            entry('f1', DateTime(2026, 10, 30, 18), 32.2, 0,
                needsSignoff: true),
            entry('ok', DateTime(2026, 10, 28, 18), 50.3, 0),
          ])));
      expect(find.text('Needs sign-off 1'), findsOneWidget);
    });

    testWidgets('no flagged entries: All 2 shown, no sign-off chip',
        (tester) async {
      await pump(tester, GasAnalysisLogScreen(dao: seeded()));
      expect(_key(filterKey), findsNothing);
      expect(find.descendant(
              of: _key('analysis-log-filter-all'), matching: find.text('All 2')),
          findsOneWidget);
      expect(find.textContaining('sign-off'), findsNothing);
      expect(tiles(tester), 2);
    });

    testWidgets('the filter follows the entries: it goes when the last '
        'flagged one is signed off', (tester) async {
      final dao = twoFlagged();
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, _key(filterKey));
      expect(tiles(tester), 2);

      // Signed off elsewhere, one at a time.
      await dao.setNeedsSignoff('f1', false);
      await tester.pumpAndSettle();
      expect(find.text('Needs sign-off 1'), findsOneWidget);
      expect(tiles(tester), 1);

      await dao.setNeedsSignoff('f2', false);
      await tester.pumpAndSettle();
      expect(_key(filterKey), findsNothing);
      expect(tiles(tester), 3, reason: 'nothing left to filter to');

      // Flagged again later: the old filter does not come back by itself.
      await dao.setNeedsSignoff('ok', true);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(_key(filterKey)).selected, isFalse);
      expect(tiles(tester), 3);
    });

    testWidgets('export hands over what is shown', (tester) async {
      String? csv;
      await pump(
          tester,
          GasAnalysisLogScreen(
            dao: twoFlagged(),
            shareCsv: (c, _, _) async => csv = c,
          ));
      await tapAndSettle(tester, _key(filterKey));
      await tapAndSettle(tester, _key('analysis-log-export'));
      // The header and the two flagged entries.
      expect(csv!.trimRight().split('\n'), hasLength(3));
    });

    testWidgets('an entry flagged while its print prompt is open prints '
        'nothing', (tester) async {
      final printer = FakeLabelPrinter();
      final dao = FakeGasAnalysesDao(analyses: [tx()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await tapAndSettle(tester, _key('analysis-print-tx'));
      expect(_key('copies-dialog-print'), findsOneWidget);

      // Flagged through sync meanwhile.
      await dao.setNeedsSignoff('tx', true);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, _key('copies-dialog-print'));

      expect(find.text(kSignOffBeforePrintMessage), findsOneWidget);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
      expect(find.text('Retry'), findsNothing);
      expect(_key('analysis-needs-signoff-tx'), findsOneWidget);
    });

    testWidgets('an entry flagged while it was edited after a mismatch '
        'warning prints nothing', (tester) async {
      final printer = FakeLabelPrinter();
      final dao = _FlaggedOnEditDao(analyses: [ean()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await reprint(tester, 'ean');
      await tapAndSettle(tester, find.text('Change desired mix'));
      await tapAndSettle(tester, _key('desired-mix-other'));
      await tester.enterText(_key('desired-mix-other-o2'), '32');
      await tapAndSettle(tester, _key('desired-mix-other-ok'));
      await tapAndSettle(tester, _key('analysis-edit-save'));

      expect(find.text(kSignOffBeforePrintMessage), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
    });

    testWidgets('an entry flagged while the mismatch dialog is open prints '
        'nothing', (tester) async {
      final printer = FakeLabelPrinter();
      final dao = FakeGasAnalysesDao(analyses: [ean()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await reprint(tester, 'ean');
      expect(find.text(mismatchTitle), findsOneWidget);

      // Flagged through sync meanwhile.
      await dao.setNeedsSignoff('ean', true);
      await tester.pumpAndSettle();
      expect(find.text(mismatchTitle), findsOneWidget);
      await tapAndSettle(tester, find.text('Print as EAN32'));

      expect(find.text(kSignOffBeforePrintMessage), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
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
      // Only what the diver states is typed (who analysed, fill pressure,
      // for, notes): no measured-value input.
      expect(inSheet(find.byType(EditableText)), findsNWidgets(4));
    });

    testWidgets('saving updates the four fields and refreshes the list',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [tx(), ean()]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      expect(_key('analysis-role-tx'), findsOneWidget);

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
      expect(
          find.descendant(
              of: _key('analysis-role-tx'), matching: find.text('BO')),
          findsOneWidget);
      expect(inTile('tx', find.textContaining('off EAN50')), findsOneWidget);
      expect(inTile('tx', find.textContaining('EdP')), findsOneWidget);
      // The measured values are as they were.
      expect(inTile('tx', find.text('Tx23/34')), findsOneWidget);
    });

    testWidgets('the sheet of an entry waiting for sign-off starts "analysed '
        'by" from the latest name in the log', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        entry('newest', DateTime(2026, 10, 30), 32.1, 0,
            analysedBy: null, needsSignoff: true),
        entry('mid', DateTime(2026, 10, 29), 32.1, 0, analysedBy: '  '),
        entry('older', DateTime(2026, 10, 28), 32.1, 0, analysedBy: 'Wendy'),
        entry('oldest', DateTime(2026, 10, 27), 32.1, 0, analysedBy: 'Jan'),
      ]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, _key('analysis-newest'));
      final diver = tester
          .widget<TextField>(_key('analysis-edit-diver'))
          .controller!
          .text;
      expect(diver, 'Wendy');
    });

    testWidgets('the sheet of an old entry with no name does not suggest one',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        entry('newest', DateTime(2026, 10, 30), 32.1, 0, analysedBy: null),
        entry('older', DateTime(2026, 10, 28), 32.1, 0, analysedBy: 'Wendy'),
      ]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, _key('analysis-newest'));
      final diver = tester
          .widget<TextField>(_key('analysis-edit-diver'))
          .controller!
          .text;
      expect(diver, '');
    });

    testWidgets('deleting from the sheet shows the deleted SnackBar',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [tx(), ean()]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, find.text('Tx23/34'));
      await tapAndSettle(tester, _key('analysis-edit-delete'));
      expect(find.text('Delete this analysis?'), findsOneWidget);
      await tapAndSettle(tester, _key('analysis-delete-confirm'));

      expect(dao.deleted, ['tx']);
      expect(_key('analysis-edit-sheet'), findsNothing);
      expect(find.text('Deleted Tx23/34 analysis.'), findsOneWidget);
      expect(_key('analysis-tx'), findsNothing);
      expect(_key('analysis-ean'), findsOneWidget);
    });

    testWidgets('cancelling the delete leaves the list and the SnackBar alone',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [tx()]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, find.text('Tx23/34'));
      await tapAndSettle(tester, _key('analysis-edit-delete'));
      await tapAndSettle(
          tester,
          find.descendant(
              of: find.byType(AlertDialog), matching: find.text('Cancel')));
      await tapAndSettle(tester, _key('analysis-edit-cancel'));

      expect(dao.deleted, isEmpty);
      expect(_key('analysis-tx'), findsOneWidget);
      expect(find.textContaining('Deleted'), findsNothing);
    });

    testWidgets('a delete from the sheet replaces an old print failure',
        (tester) async {
      final printer = FakeLabelPrinter(failOnConnect: Exception('off'));
      final dao = FakeGasAnalysesDao(analyses: [tx(), plain()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await reprint(tester, 'plain');
      expect(find.text('Retry'), findsOneWidget);

      await tapAndSettle(tester, find.text('Tx23/34'));
      await tapAndSettle(tester, _key('analysis-edit-delete'));
      await tapAndSettle(tester, _key('analysis-delete-confirm'));
      expect(find.text('Deleted Tx23/34 analysis.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('sign off in the edit sheet', () {
    /// Flagged, with a name and a desired mix the analysis matches: ready
    /// to sign off.
    GasAnalysis flagged({String id = 'f'}) => entry(
        id, DateTime(2026, 10, 30, 18), 32.1, 0,
        needsSignoff: true, targetO2: 32, targetHe: 0);

    Finder sheetButton(String key) => _key(key);

    testWidgets('Sign off clears the flag and prints nothing', (tester) async {
      final printer = FakeLabelPrinter();
      final dao = FakeGasAnalysesDao(analyses: [flagged()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      expect(_key('analysis-needs-signoff-f'), findsOneWidget);

      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff'));

      expect(dao.updated.single.$2.signOff, isTrue);
      expect(_key('analysis-needs-signoff-f'), findsNothing);
      expect(_key('analysis-log-signoff-count'), findsNothing);
      // The print action is there now, and nothing was printed.
      expect(_key('analysis-print-f'), findsOneWidget);
      expect(_key('copies-dialog-print'), findsNothing);
      expect(printer.printed, isEmpty);
    });

    testWidgets('signing off from the log prints when asked', (tester) async {
      final printer = FakeLabelPrinter();
      final rendered = <CylinderLabel>[];
      final dao = FakeGasAnalysesDao(analyses: [flagged()]);
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: dao,
              labelPrinting: _service(printer, rendered: rendered)));

      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff-print'));
      expect(dao.updated.single.$2.signOff, isTrue);
      // The usual copies prompt, then one print.
      expect(_key('copies-dialog-print'), findsOneWidget);
      expect(printer.printed, isEmpty);
      await tapAndSettle(tester, _key('copies-inc'));
      await tapAndSettle(tester, _key('copies-dialog-print'));

      expect(printer.printed, hasLength(1));
      expect(printer.printed.single.$2, 2);
      expect(rendered.single.mixName, 'EAN32');
      expect(find.text('Printed 2 labels.'), findsOneWidget);
      expect(_key('analysis-needs-signoff-f'), findsNothing);
    });

    testWidgets('an entry with no desired mix signs off with its name and '
        'prints the analysed mix', (tester) async {
      final printer = FakeLabelPrinter();
      final rendered = <CylinderLabel>[];
      // Named, but no desired mix: nothing to check it against.
      final dao = FakeGasAnalysesDao(analyses: [
        entry('f', DateTime(2026, 10, 30, 18), 32.1, 0, needsSignoff: true),
      ]);
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: dao,
              labelPrinting: _service(printer, rendered: rendered)));
      await tapAndSettle(tester, find.text('EAN32'));
      expect(_key('analysis-edit-signoff-hint'), findsNothing);
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff-print'));
      await tapAndSettle(tester, _key('copies-dialog-print'));

      expect(dao.updated.single.$2.signOff, isTrue);
      expect(dao.updated.single.$2.desiredMix, isNull);
      expect(find.text(mismatchTitle), findsNothing);
      expect(printer.printed, hasLength(1));
      expect(rendered.single.mixName, 'EAN32');
      expect(_key('analysis-needs-signoff-f'), findsNothing);
    });

    testWidgets('Sign off and print goes through the mismatch dialog',
        (tester) async {
      final printer = FakeLabelPrinter();
      final rendered = <CylinderLabel>[];
      // Desired 50/0 against 32.1/0: a hard mismatch.
      final dao = FakeGasAnalysesDao(analyses: [
        entry('f', DateTime(2026, 10, 30, 18), 32.1, 0,
            needsSignoff: true, targetO2: 50, targetHe: 0),
      ]);
      await pump(
          tester,
          GasAnalysisLogScreen(
              dao: dao,
              labelPrinting: _service(printer, rendered: rendered)));
      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff-print'));
      await tapAndSettle(tester, _key('copies-dialog-print'));

      expect(find.text(mismatchTitle), findsOneWidget);
      expect(printer.printed, isEmpty, reason: 'asks before printing');
      await tapAndSettle(tester, find.text('Print as EAN32'));
      expect(printer.printed, hasLength(1));
      expect(rendered.single.mixName, 'EAN32');
    });

    testWidgets('cancelling the copies prompt after Sign off and print keeps '
        'the sign-off and prints nothing', (tester) async {
      final printer = FakeLabelPrinter();
      final dao = FakeGasAnalysesDao(analyses: [flagged()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff-print'));
      await tapAndSettle(tester, find.text('Cancel'));

      expect(printer.printed, isEmpty);
      expect(dao.analyses.single.needsSignoff, isFalse);
      expect(_key('analysis-print-f'), findsOneWidget);
    });

    testWidgets('an entry flagged again after Sign off and print is not '
        'printed', (tester) async {
      final printer = FakeLabelPrinter();
      final dao = _FlaggedOnEditDao(analyses: [flagged()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff-print'));

      // Read back as flagged: refused, with no prompt for copies.
      expect(find.text(kSignOffBeforePrintMessage), findsOneWidget);
      expect(_key('copies-dialog-print'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
    });

    testWidgets('an entry deleted after Sign off and print is not printed',
        (tester) async {
      final printer = FakeLabelPrinter();
      final dao = _DeletedOnEditDao(analyses: [flagged()]);
      await pump(tester,
          GasAnalysisLogScreen(dao: dao, labelPrinting: _service(printer)));
      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, sheetButton('analysis-edit-signoff-print'));

      expect(_key('copies-dialog-print'), findsNothing);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
    });

    testWidgets('Sign off and print is offered only with a printer set up',
        (tester) async {
      final printer = FakeLabelPrinter();
      for (final (name, service) in <(String, LabelPrintService?)>[
        ('none', null),
        ('not-configured', _service(printer, configured: false)),
      ]) {
        await pump(
            tester,
            GasAnalysisLogScreen(
                key: ValueKey(name),
                dao: FakeGasAnalysesDao(analyses: [flagged()]),
                labelPrinting: service));
        await tapAndSettle(tester, find.text('EAN32'));
        expect(_key('analysis-edit-signoff'), findsOneWidget, reason: name);
        expect(_key('analysis-edit-signoff-print'), findsNothing,
            reason: name);
        await tapAndSettle(tester, _key('analysis-edit-cancel'));
      }

      await pump(
          tester,
          GasAnalysisLogScreen(
              key: const ValueKey('configured'),
              dao: FakeGasAnalysesDao(analyses: [flagged()]),
              labelPrinting: _service(printer)));
      await tapAndSettle(tester, find.text('EAN32'));
      expect(_key('analysis-edit-signoff-print'), findsOneWidget);
    });

    testWidgets('Save on a flagged entry keeps the badge', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [flagged()]);
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, find.text('EAN32'));
      await tester.enterText(_key('analysis-edit-notes'), 'Later');
      await tapAndSettle(tester, _key('analysis-edit-save'));
      expect(dao.updated.single.$2.signOff, isFalse);
      expect(_key('analysis-needs-signoff-f'), findsOneWidget);
    });

    testWidgets('a cylinder picked in the sheet shows in the log',
        (tester) async {
      final dao = FakeGasAnalysesDao(
        cylinders: const [
          CylinderChoice(
              id: 'c9', label: 'AL80 stage', role: CylinderRole.bailout),
        ],
        analyses: [flagged()],
      );
      await pump(tester, GasAnalysisLogScreen(dao: dao));
      await tapAndSettle(tester, find.text('EAN32'));
      await tapAndSettle(tester, _key('analysis-edit-cylinder'));
      await tapAndSettle(tester, find.text('AL80 stage').last);
      await tester.enterText(_key('analysis-edit-pressure'), '207,5');
      await tapAndSettle(tester, _key('analysis-edit-save'));
      expect(inTile('f', find.textContaining('AL80 stage')), findsOneWidget);
      expect(inTile('f', find.textContaining('208 bar')), findsOneWidget);
    });
  });

  group('wiring', () {
    testWidgets('the Gas destination passes its label printing to the log',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsNotifier();
      await settings.load();
      final dao = FakeGasAnalysesDao(analyses: [tx()]);
      final printing = _service(FakeLabelPrinter());
      final session = AnalyzerSession(
        settings: settings,
        analysesDao: dao,
        labelPrinting: printing,
        controller: fakeClockAnalyzerController(tester),
        transportOptions: [
          AnalyzerTransportOption(
            label: 'Bench',
            create: () => DemoAnalyzerTransport(
                targetO2: 21, targetHe: 35, random: Random(1)),
          ),
        ],
      );
      addTearDown(session.dispose);
      await tester.pumpWidget(MaterialApp(
        home: GasScreen(
          blend: BlendNotifier(settings: settings),
          settings: settings,
          session: session,
          analysesDao: dao,
          labelPrinting: printing,
          onHome: () {},
        ),
      ));
      await tester.pump();
      await tapAndSettle(tester, _key('gas-tab-log'));
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
