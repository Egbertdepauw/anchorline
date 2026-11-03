import 'dart:async';

import 'package:ccrlogger/analyzer/protocol/analyzer_reading.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/screens/blend_screen.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/analysis_save_card.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:ccrlogger/ui/widgets/label_printer_settings_section.dart';
import 'package:ccrlogger/ui/widgets/mix_match_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';
import '../../_helpers/fake_label_printer.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

AnalyzerReading _reading(double o2, double he) =>
    AnalyzerReading(o2: o2, he: he, tempC: 21.4, baroHpa: 1013, raw: 'test');

final _tx2135 = _reading(20.6, 33.8);

const _dil =
    CylinderChoice(id: 'c-dil', label: 'Dil 3L', role: CylinderRole.diluent);
const _o2 =
    CylinderChoice(id: 'c-o2', label: 'O2 3L', role: CylinderRole.oxygen);

/// A [LabelPrintService] on fakes. Each print job takes the next printer in
/// [printers], so a test can make the first attempt fail and the next work.
/// [rendered] collects the labels it is asked to draw.
LabelPrintService _service(
  List<FakeLabelPrinter> printers, {
  bool configured = true,
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
    printerId: () => configured ? 'dev-1' : null,
    use14ForDeeperMixes: () => false,
  );
}

/// A [FakeGasAnalysesDao] whose [add] throws while [fail] is set, and whose
/// [list] throws while [failList] is set.
class _FlakyDao extends FakeGasAnalysesDao {
  _FlakyDao({super.cylinders});

  bool fail = false;
  bool failList = false;

  @override
  Future<String> add(NewGasAnalysis a) async {
    if (fail) throw Exception('disk full');
    return super.add(a);
  }

  @override
  Future<List<GasAnalysis>> list({String? cylinderId}) async {
    if (failList) throw Exception('log unreadable');
    return super.list(cylinderId: cylinderId);
  }
}

/// An analysis already in the log, with the desired mix [o2]/[he].
GasAnalysis _logged(String id, DateTime at, int o2, int he) => GasAnalysis(
      id: id,
      analysedAt: at,
      o2Percent: o2.toDouble(),
      hePercent: he.toDouble(),
      stable: true,
      targetO2Percent: o2,
      targetHePercent: he,
    );

/// The card at phone width, in a scroll view like the analyzer screen's.
/// [above] is empty space above the card, to push it below the fold.
Future<void> _pump(
  WidgetTester tester, {
  required FakeGasAnalysesDao dao,
  AnalyzerReading? reading,
  ReadingStability stability = ReadingStability.stable,
  DesiredMix? blendTarget,
  LabelPrintService? labelPrinting,
  VoidCallback? onSetUpPrinter,
  double above = 0,
  Size size = const Size(400, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: above),
            AnalysisSaveCard(
              dao: dao,
              reading: reading ?? _tx2135,
              stability: stability,
              modPpo2s: const [1.4, 1.6],
              blendTarget: blendTarget,
              labelPrinting: labelPrinting,
              onSetUpPrinter: onSetUpPrinter,
              now: () => DateTime(2026, 10, 31, 9),
            ),
          ],
        ),
      ),
    ),
  ));
  // The card loads its cylinders and the log's mixes.
  await tester.pumpAndSettle();
}

Future<void> _pickCylinder(WidgetTester tester, String label) async {
  await tester.tap(_key('analysis-cylinder'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Set<GasRole> _role(WidgetTester tester) => tester
    .widget<SegmentedButton<GasRole>>(_key('analysis-gas-role'))
    .selected;

Iterable<ChoiceChip> _pickedChips(WidgetTester tester) => tester
    .widgetList<ChoiceChip>(find.byType(ChoiceChip))
    .where((c) => c.selected);

/// The labels of the mix chips, "Other…" included, in order.
List<String?> _chipLabels(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(DesiredMixPicker),
      matching: find.byType(Text),
    ))
    .map((t) => t.data)
    .toList();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('mix chips', () {
    testWidgets('Blend target first, then the log, no duplicate, none picked',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _logged('l1', DateTime(2026, 10, 30), 32, 0),
        _logged('l2', DateTime(2026, 10, 29), 21, 35),
      ]);
      await _pump(tester, dao: dao, blendTarget: const DesiredMix(21, 35));

      expect(_chipLabels(tester), ['Tx21/35', 'EAN32', 'Other…']);
      expect(_pickedChips(tester), isEmpty);
      expect(find.text('Mix (optional)'), findsOneWidget);
    });
  });

  group('gas role', () {
    testWidgets('follows the cylinder, and the saved role follows the control',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil, _o2]);
      await _pump(tester, dao: dao);
      expect(_role(tester), {GasRole.bailout});

      await _pickCylinder(tester, 'Dil 3L');
      expect(_role(tester), {GasRole.diluent});
      await _pickCylinder(tester, 'O2 3L');
      expect(_role(tester), {GasRole.bailout});

      // The diver overrides the oxygen cylinder's default.
      await _tapAndSettle(tester, find.text('Diluent'));
      expect(_role(tester), {GasRole.diluent});
      await _tapAndSettle(tester, _key('analysis-save'));

      expect(dao.added.single.cylinderId, 'c-o2');
      expect(dao.added.single.gasRole, GasRole.diluent);
    });
  });

  group('match indicator', () {
    testWidgets('appears once a mix is picked and follows the reading',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao, blendTarget: const DesiredMix(21, 35));
      expect(find.byType(MixMatchIndicator), findsNothing);

      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      expect(find.byType(MixMatchIndicator), findsOneWidget);
      expect(find.text('Matches Tx21/35'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Matches Tx21/35')).style!.color,
        SafetyColors.success,
      );

      await _pump(
        tester,
        dao: dao,
        blendTarget: const DesiredMix(21, 35),
        reading: _reading(22.5, 33.8),
      );
      expect(find.text('O2 1.5 off Tx21/35'), findsOneWidget);
    });

    testWidgets('is not built for a reading that is not a number',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao, blendTarget: const DesiredMix(21, 35));
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      expect(find.byType(MixMatchIndicator), findsOneWidget);

      await _pump(
        tester,
        dao: dao,
        blendTarget: const DesiredMix(21, 35),
        reading: _reading(double.nan, 33.8),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(MixMatchIndicator), findsNothing);
    });
  });

  group('Save & print', () {
    testWidgets('saves the mix and role, then prints the stepper\'s copies',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil]);
      final printer = FakeLabelPrinter();
      final rendered = <CylinderLabel>[];
      var savedBeforePrint = false;
      await _pump(
        tester,
        dao: dao,
        blendTarget: const DesiredMix(21, 35),
        labelPrinting: LabelPrintService(
          render: (label) async {
            savedBeforePrint = dao.added.length == 1;
            rendered.add(label);
            return LabelBitmap.blank(384, 240);
          },
          printerFor: (_) => printer,
          scanner: FakeLabelPrinterScanner(),
          printerId: () => 'dev-1',
          use14ForDeeperMixes: () => false,
        ),
      );

      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, _key('copies-inc'));
      expect(tester.widget<Text>(_key('copies-value')).data, '2');
      await _tapAndSettle(tester, _key('analysis-save-print'));

      final a = dao.added.single;
      expect(a.desiredMix, const DesiredMix(21, 35));
      expect(a.gasRole, GasRole.diluent);
      expect(a.o2Percent, 20.6);
      expect(savedBeforePrint, isTrue);
      expect(printer.printed.single.$2, 2);
      expect(rendered.single.mixName, 'Tx21/35');
      expect(find.text('Printed 2 labels.'), findsOneWidget);
    });

    testWidgets('Review Focus 2: a double tap saves once and prints once',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final gate = Completer<void>();
      final printer = FakeLabelPrinter(printGate: gate);
      await _pump(tester, dao: dao, labelPrinting: _service([printer]));

      await tester.ensureVisible(_key('analysis-save-print'));
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-save-print'));
      await tester.pump();
      // The first print is held by the printer.
      expect(printer.printed, hasLength(1));

      await tester.tap(_key('analysis-save-print'));
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();

      expect(dao.added, hasLength(1));
      expect(printer.printed, hasLength(1));
      expect(printer.connects, 1);
    });

    testWidgets('a second press before the card rebuilds is ignored',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final printer = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        reading: _reading(32.1, 0),
        stability: ReadingStability.settling,
        blendTarget: const DesiredMix(50, 0),
        labelPrinting: _service([printer, FakeLabelPrinter()]),
      );
      await _tapAndSettle(tester, _key('desired-mix-50-0'));

      // Both presses arrive before the card can rebuild with its buttons
      // disabled, so only a guard raised before the first dialog's await
      // stops the second. (A real second tap is also absorbed by the
      // Navigator until the dialog's first frame; this doesn't rely on it.)
      final press = tester
          .widget<ButtonStyleButton>(_key('analysis-save-print'))
          .onPressed!;
      press();
      press();
      await tester.pumpAndSettle();
      expect(find.text('Reading not stable'), findsOneWidget);
      await tester.tap(_key('analysis-save-anyway'));
      await tester.pumpAndSettle();
      expect(find.text('Reading not stable'), findsNothing);
      expect(find.text('Mix does not conform to analysis'), findsOneWidget);

      await tester.tap(_key('mix-mismatch-print'));
      await tester.pumpAndSettle();
      expect(find.text('Mix does not conform to analysis'), findsNothing);
      expect(dao.added, hasLength(1));
      expect(printer.printed, hasLength(1));
    });

    testWidgets(
        'Review Focus 1: a print failure keeps the analysis; Retry only prints',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final off = FakeLabelPrinter(failOnConnect: Exception('Bluetooth off'));
      final on = FakeLabelPrinter();
      await _pump(tester, dao: dao, labelPrinting: _service([off, on]));

      await _tapAndSettle(tester, _key('analysis-save-print'));
      expect(dao.added, hasLength(1));
      expect(off.printed, isEmpty);
      expect(find.text('Printer not found'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(on.printed, hasLength(1));
      expect(dao.added, hasLength(1));
      expect(find.text('Label printed.'), findsOneWidget);
    });

    // The failure bar stays up across screens, so the diver can correct or
    // delete the analysis in the log before tapping Retry.
    group('Retry re-reads the saved analysis', () {
      late FakeGasAnalysesDao dao;
      late FakeLabelPrinter on;
      late List<CylinderLabel> rendered;

      /// "Save & print" of desired Tx21/35 on a printer that is off.
      Future<void> saveAndFail(WidgetTester tester,
          {AnalyzerReading? reading, DesiredMix mix = const DesiredMix(21, 35)})
          async {
        dao = FakeGasAnalysesDao();
        on = FakeLabelPrinter();
        rendered = [];
        final off = FakeLabelPrinter(failOnConnect: Exception('Bluetooth off'));
        await _pump(
          tester,
          dao: dao,
          reading: reading,
          blendTarget: mix,
          labelPrinting: _service([off, on], rendered: rendered),
        );
        await _tapAndSettle(
            tester, _key('desired-mix-${mix.o2Percent}-${mix.hePercent}'));
        await _tapAndSettle(tester, _key('analysis-save-print'));
      }

      Future<void> retry(WidgetTester tester) async {
        expect(find.text('Printer not found'), findsOneWidget);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
      }

      testWidgets('an analysis deleted since is not printed', (tester) async {
        await saveAndFail(tester);
        await dao.softDelete(dao.analyses.single.id);
        await retry(tester);

        expect(on.connects, 0);
        expect(find.text('This analysis was deleted.'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('an analysis whose mix changed since is not printed',
          (tester) async {
        await saveAndFail(tester);
        await dao.update(
          dao.analyses.single.id,
          const GasAnalysisEdit(
            desiredMix: DesiredMix(21, 33),
            gasRole: GasRole.bailout,
            analysedBy: null,
            notes: null,
          ),
        );
        await retry(tester);

        expect(on.connects, 0);
        expect(
          find.text('This analysis changed. Print it again from the log.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsNothing);
      });

      testWidgets('a confirmed "Print as EAN32" still prints on Retry',
          (tester) async {
        await saveAndFail(tester,
            reading: _reading(32.1, 0), mix: const DesiredMix(50, 0));
        await tester.tap(_key('mix-mismatch-print'));
        await tester.pumpAndSettle();
        await retry(tester);

        expect(find.text('Mix does not conform to analysis'), findsNothing);
        expect(on.printed, hasLength(1));
        expect(rendered.last.mixName, 'EAN32');
        expect(find.text('Label printed.'), findsOneWidget);
      });
    });

    group('hard mismatch', () {
      late FakeGasAnalysesDao dao;
      late FakeLabelPrinter printer;
      late List<CylinderLabel> rendered;

      Future<void> tapSavePrint(WidgetTester tester) async {
        dao = FakeGasAnalysesDao();
        printer = FakeLabelPrinter();
        rendered = [];
        await _pump(
          tester,
          dao: dao,
          reading: _reading(32.1, 0),
          blendTarget: const DesiredMix(50, 0),
          labelPrinting: _service([printer], rendered: rendered),
          // A phone screen with the card below the fold, as on the
          // analyzer screen.
          size: const Size(400, 500),
          above: 1200,
        );
        await _tapAndSettle(tester, _key('desired-mix-50-0'));
        await _tapAndSettle(tester, _key('analysis-save-print'));
        expect(find.text('Mix does not conform to analysis'), findsOneWidget);
        expect(dao.added, isEmpty, reason: 'the dialog comes before saving');
      }

      testWidgets('Cancel saves and prints nothing', (tester) async {
        await tapSavePrint(tester);
        await tester.tap(_key('mix-mismatch-cancel'));
        await tester.pumpAndSettle();
        expect(dao.added, isEmpty);
        expect(printer.printed, isEmpty);
      });

      testWidgets('Change desired mix saves nothing and shows the mix chips',
          (tester) async {
        await tapSavePrint(tester);
        expect(tester.getRect(find.byType(DesiredMixPicker)).top, isNegative,
            reason: 'scrolled out of view to reach the button');

        await tester.tap(_key('mix-mismatch-change'));
        await tester.pumpAndSettle();
        expect(dao.added, isEmpty);
        expect(printer.printed, isEmpty);
        final picker = tester.getRect(find.byType(DesiredMixPicker));
        expect(picker.top, greaterThanOrEqualTo(0));
        expect(picker.bottom, lessThanOrEqualTo(500));
        // The desired mix stays picked, for the diver to change.
        expect(
          tester.widget<ChoiceChip>(_key('desired-mix-50-0')).selected,
          isTrue,
        );
      });

      testWidgets('"Print as EAN32" saves, then prints the analysed mix',
          (tester) async {
        await tapSavePrint(tester);
        expect(find.text('Print as EAN32'), findsOneWidget);
        await tester.tap(_key('mix-mismatch-print'));
        await tester.pumpAndSettle();
        expect(dao.added.single.desiredMix, const DesiredMix(50, 0));
        expect(printer.printed, hasLength(1));
        expect(rendered.single.mixName, 'EAN32');
      });
    });

    testWidgets('an unstable reading is confirmed before the mismatch',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final printer = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        reading: _reading(32.1, 0),
        stability: ReadingStability.settling,
        blendTarget: const DesiredMix(50, 0),
        labelPrinting: _service([printer]),
      );
      await _tapAndSettle(tester, _key('desired-mix-50-0'));

      await _tapAndSettle(tester, _key('analysis-save-print'));
      expect(find.text('Reading not stable'), findsOneWidget);
      expect(find.text('Mix does not conform to analysis'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Mix does not conform to analysis'), findsNothing);
      expect(dao.added, isEmpty);
      expect(printer.printed, isEmpty);

      await _tapAndSettle(tester, _key('analysis-save-print'));
      await tester.tap(_key('analysis-save-anyway'));
      await tester.pumpAndSettle();
      expect(dao.added, isEmpty);
      expect(find.text('Mix does not conform to analysis'), findsOneWidget);
      await tester.tap(_key('mix-mismatch-print'));
      await tester.pumpAndSettle();
      expect(dao.added.single.stable, isFalse);
      expect(printer.printed, hasLength(1));
    });
  });

  group('without a printer', () {
    testWidgets('not set up: a set-up link instead of Save & print',
        (tester) async {
      var setUps = 0;
      await _pump(
        tester,
        dao: FakeGasAnalysesDao(),
        labelPrinting: _service([], configured: false),
        onSetUpPrinter: () => setUps++,
      );
      expect(_key('analysis-save-print'), findsNothing);
      expect(_key('copies-inc'), findsNothing);
      expect(find.text('Set up label printer'), findsOneWidget);

      await _tapAndSettle(tester, _key('analysis-setup-printer'));
      expect(setUps, 1);
    });

    testWidgets('no label printing at all: no button and no link',
        (tester) async {
      await _pump(tester, dao: FakeGasAnalysesDao());
      expect(_key('analysis-save-print'), findsNothing);
      expect(_key('analysis-setup-printer'), findsNothing);
      expect(_key('analysis-save'), findsOneWidget);
    });
  });

  group('Save analysis', () {
    testWidgets('saves the mix and role too, and never prints',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil]);
      final printer = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        blendTarget: const DesiredMix(21, 35),
        labelPrinting: _service([printer]),
      );
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, _key('analysis-save'));

      expect(dao.added.single.desiredMix, const DesiredMix(21, 35));
      expect(dao.added.single.gasRole, GasRole.diluent);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
      // The SnackBar names the analysed mix, not the desired one.
      expect(find.text('Saved Tx21/34 to the analysis log.'), findsOneWidget);
    });

    testWidgets('does not ask about a hard mismatch, since nothing prints',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final printer = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        reading: _reading(32.1, 0),
        blendTarget: const DesiredMix(50, 0),
        labelPrinting: _service([printer]),
      );
      await _tapAndSettle(tester, _key('desired-mix-50-0'));
      await _tapAndSettle(tester, _key('analysis-save'));

      expect(find.text('Mix does not conform to analysis'), findsNothing);
      expect(dao.added.single.desiredMix, const DesiredMix(50, 0));
      expect(printer.printed, isEmpty);
    });
  });

  group('after a save', () {
    testWidgets('a successful save starts the next analysis fresh',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil]);
      await _pump(tester, dao: dao, blendTarget: const DesiredMix(21, 35));
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, find.text('Bailout/deco'));
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      expect(find.byType(MixMatchIndicator), findsOneWidget);

      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added.single.desiredMix, const DesiredMix(21, 35));
      expect(dao.added.single.gasRole, GasRole.bailout);
      // A mix left picked would print its name on the next cylinder.
      expect(_pickedChips(tester), isEmpty);
      expect(find.byType(MixMatchIndicator), findsNothing);
      expect(_role(tester), {GasRole.diluent},
          reason: 'back to the Dil cylinder\'s default');
    });

    testWidgets('Save & print prints the choices it saved, then starts fresh',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil]);
      final rendered = <CylinderLabel>[];
      await _pump(
        tester,
        dao: dao,
        blendTarget: const DesiredMix(21, 35),
        labelPrinting: _service([FakeLabelPrinter()], rendered: rendered),
      );
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, find.text('Bailout/deco'));
      await _tapAndSettle(tester, _key('desired-mix-21-35'));

      await _tapAndSettle(tester, _key('analysis-save-print'));
      // The desired name (the analysed gas is Tx21/34) and the flipped role.
      expect(rendered.single.mixName, 'Tx21/35');
      expect(rendered.single.kind, CylinderLabelKind.bailout);
      expect(_pickedChips(tester), isEmpty);
      expect(_role(tester), {GasRole.diluent});
    });

    testWidgets('Save & print prints the copies chosen, then goes back to 1',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final printer = FakeLabelPrinter();
      await _pump(tester, dao: dao, labelPrinting: _service([printer]));
      await _tapAndSettle(tester, _key('copies-inc'));
      await _tapAndSettle(tester, _key('copies-inc'));
      expect(tester.widget<Text>(_key('copies-value')).data, '3');

      await _tapAndSettle(tester, _key('analysis-save-print'));
      expect(printer.printed.single.$2, 3);
      expect(find.text('Printed 3 labels.'), findsOneWidget);
      // Three labels for this cylinder doesn't mean three for the next.
      expect(tester.widget<Text>(_key('copies-value')).data, '1');
    });

    testWidgets(
        'a failed save keeps the choices, prints nothing, and is not hidden '
        'by an old print failure', (tester) async {
      final dao = _FlakyDao(cylinders: const [_dil]);
      final off = FakeLabelPrinter(failOnConnect: Exception('Bluetooth off'));
      final on = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        blendTarget: const DesiredMix(21, 35),
        labelPrinting: _service([off, on]),
      );
      await _tapAndSettle(tester, _key('analysis-save-print'));
      expect(find.text('Printer not found'), findsOneWidget);

      // The next cylinder, whose save fails.
      dao.fail = true;
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, find.text('Bailout/deco'));
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      await _tapAndSettle(tester, _key('analysis-save-print'));

      expect(find.text('Save failed: Exception: disk full'), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(dao.added, hasLength(1));
      expect(on.connects, 0);
      expect(
        tester.widget<ChoiceChip>(_key('desired-mix-21-35')).selected,
        isTrue,
      );
      expect(find.byType(MixMatchIndicator), findsOneWidget);
      expect(_role(tester), {GasRole.bailout});
    });

    testWidgets('the mix just saved stays a chip for the next cylinder',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao, blendTarget: const DesiredMix(21, 35));
      expect(_key('desired-mix-25-25'), findsNothing);

      await _tapAndSettle(tester, _key('desired-mix-other'));
      await tester.enterText(_key('desired-mix-other-o2'), '25');
      await tester.enterText(_key('desired-mix-other-he'), '25');
      await tester.tap(_key('desired-mix-other-ok'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChoiceChip>(_key('desired-mix-25-25')).selected,
        isTrue,
      );

      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added.single.desiredMix, const DesiredMix(25, 25));
      // Newest first, right after the Blend target, and not picked.
      expect(_chipLabels(tester), ['Tx21/35', 'Tx25/25', 'Other…']);
      expect(_pickedChips(tester), isEmpty);

      await _tapAndSettle(tester, _key('desired-mix-25-25'));
      expect(
        tester.widget<ChoiceChip>(_key('desired-mix-25-25')).selected,
        isTrue,
      );
    });

    testWidgets('a failing reload of the mixes keeps the old ones',
        (tester) async {
      final dao = _FlakyDao();
      final printer = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        reading: _reading(32.1, 0),
        blendTarget: const DesiredMix(21, 35),
        labelPrinting: _service([printer]),
      );
      dao.failList = true;

      final logged = <String?>[];
      final old = debugPrint;
      debugPrint = (message, {wrapWidth}) => logged.add(message);
      try {
        await _tapAndSettle(tester, _key('analysis-save-print'));
      } finally {
        debugPrint = old;
      }

      expect(tester.takeException(), isNull);
      expect(dao.added, hasLength(1));
      expect(printer.printed, hasLength(1));
      expect(_chipLabels(tester), ['Tx21/35', 'Other…']);
      // Not swallowed silently.
      expect(logged.join(), contains('log unreadable'));
    });

    testWidgets('after a failed print, a plain save shows "Saved …" and '
        'the old Retry is gone', (tester) async {
      final dao = FakeGasAnalysesDao();
      final off = FakeLabelPrinter(failOnConnect: Exception('Bluetooth off'));
      await _pump(tester, dao: dao, labelPrinting: _service([off]));
      await _tapAndSettle(tester, _key('analysis-save-print'));
      expect(find.text('Printer not found'), findsOneWidget);

      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added, hasLength(2));
      expect(find.text('Saved Tx21/34 to the analysis log.'), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
    });
  });

  group('screens hand the card its Blend target and printer', () {
    Future<SettingsNotifier> loadSettings() async {
      final s = SettingsNotifier();
      await s.load();
      return s;
    }

    Future<void> pumpAnalyzer(
      WidgetTester tester, {
      required LabelPrintService labelPrinting,
      DesiredMix? blendTarget,
    }) async {
      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = await loadSettings();
      await tester.pumpWidget(MaterialApp(
        home: AnalyzerScreen(
          settings: settings,
          analysesDao: FakeGasAnalysesDao(),
          blendTarget: blendTarget,
          labelPrinting: labelPrinting,
          transportOptions: [
            AnalyzerTransportOption(
              label: 'Bench',
              create: () => DemoAnalyzerTransport(),
            ),
          ],
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the analyzer passes its target and printer to the card',
        (tester) async {
      await pumpAnalyzer(
        tester,
        labelPrinting: _service([FakeLabelPrinter()]),
        blendTarget: const DesiredMix(21, 35),
      );
      expect(_key('desired-mix-21-35'), findsOneWidget);
      expect(_key('analysis-save-print'), findsOneWidget);
    });

    testWidgets('"Set up label printer" opens the label printer settings',
        (tester) async {
      await pumpAnalyzer(
        tester,
        labelPrinting: _service([], configured: false),
      );
      await _tapAndSettle(tester, _key('analysis-setup-printer'));
      expect(find.byType(LabelPrinterSettingsScreen), findsOneWidget);
    });

    testWidgets('Blend passes its recent target and the printer on',
        (tester) async {
      final settings = await loadSettings();
      final notifier = BlendNotifier(settings: settings);
      notifier.setTargetMix(21, 35);
      final printing = _service([FakeLabelPrinter()]);
      await tester.pumpWidget(MaterialApp(
        home: BlendScreen(
          notifier: notifier,
          settings: settings,
          analysesDao: FakeGasAnalysesDao(),
          labelPrinting: printing,
        ),
      ));
      await tester.tap(find.byKey(const Key('blend-open-analyzer')));
      await tester.pumpAndSettle();

      final analyzer =
          tester.widget<AnalyzerScreen>(find.byType(AnalyzerScreen));
      expect(analyzer.blendTarget, const DesiredMix(21, 35));
      expect(analyzer.labelPrinting, same(printing));
    });
  });
}
