import 'dart:async';

import 'package:ccrlogger/analysis/open_blend_match.dart';
import 'package:ccrlogger/analysis/standard_mix_pick.dart' show gasRoleForMix;
import 'package:ccrlogger/analyzer/protocol/analyzer_reading.dart';
import 'package:ccrlogger/analyzer/stability.dart';
import 'package:ccrlogger/analyzer/transport/demo_transport.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/db/open_blends_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/analyzer_session.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/analyzer_screen.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/analysis_action_bar.dart';
import 'package:ccrlogger/ui/widgets/analysis_save_card.dart';
import 'package:ccrlogger/ui/widgets/analysis_save_controller.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:ccrlogger/ui/widgets/label_printer_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';
import '../../_helpers/fake_label_printer.dart';
import '../../_helpers/fake_open_blends_dao.dart';

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

/// An open-blends log whose closes fail.
class _ThrowingOpenBlends extends FakeOpenBlendsDao {
  _ThrowingOpenBlends({super.blends});

  @override
  Future<bool> closeBlend(OpenBlend b, String analysisId) =>
      throw Exception('offline');
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

/// The controller of the test's card: made by the first [_pump] of a test,
/// and given the reading of each.
AnalysisSaveController? _controller;

/// The open blends of the test's controller; see [_pump].
FakeOpenBlendsDao? _openDao;

/// The test clock of the card's controller.
final _clock = DateTime(2026, 10, 31, 9);

/// An open blend of [target], blended [ago] before [_clock].
OpenBlend _openBlend(
  String id,
  DesiredMix target, {
  GasRole? role,
  Duration ago = const Duration(hours: 1),
}) =>
    OpenBlend(
      id: id,
      target: target,
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 3,
      // As the Blend tab guesses: lean is diluent, rich bailout.
      role: role ?? gasRoleForMix(target.o2Percent.toDouble()),
      blendedBy: null,
      blendedAt: _clock.subtract(ago),
    );

/// The save section at phone width, in a scroll view like the analyzer
/// screen's, with the action bar pinned under it. [above] is empty space
/// above the section, to push it below the fold.
Future<void> _pump(
  WidgetTester tester, {
  required FakeGasAnalysesDao dao,
  AnalyzerReading? reading,
  ReadingStability stability = ReadingStability.stable,
  DesiredMix? openBlend,
  List<OpenBlend> openBlends = const [],
  FakeOpenBlendsDao? openDao,
  void Function(double, double, double?)? onResidualSaved,
  LabelPrintService? labelPrinting,
  VoidCallback? onSetUpPrinter,
  double above = 0,
  Size size = const Size(400, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  var controller = _controller;
  if (controller == null) {
    final settings = SettingsNotifier();
    await settings.setAnalyzerModPpo2s(const [1.4, 1.6]);
    // [openBlend] is a single open blend of that mix (blended an hour ago).
    final open = _openDao = openDao ??
        FakeOpenBlendsDao(blends: [
          if (openBlend != null) _openBlend('open-1', openBlend),
          ...openBlends,
        ]);
    controller = _controller = AnalysisSaveController(
      dao: dao,
      settings: settings,
      labelPrinting: labelPrinting,
      openBlends: open,
      onResidualSaved: onResidualSaved,
      now: () => _clock,
    );
    addTearDown(() {
      controller!.dispose();
      _controller = null;
      _openDao = null;
    });
  }
  controller.update(
    reading: reading ?? _tx2135,
    stability: stability,
    connected: true,
  );
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: above),
                  AnalysisSaveCard(
                    controller: controller,
                    onSetUpPrinter: onSetUpPrinter,
                  ),
                ],
              ),
            ),
          ),
          AnalysisActionBar(controller: controller),
        ],
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

/// The key of the one selected mix chip, or null.
String? _picked(WidgetTester tester) {
  final picked = _pickedChips(tester);
  return picked.isEmpty
      ? null
      : (picked.single.key! as ValueKey<String>).value;
}

/// The diver picks [mix] through "Other…".
Future<void> _pickOther(WidgetTester tester, DesiredMix mix) async {
  await _tapAndSettle(tester, _key('desired-mix-other'));
  await tester.enterText(_key('desired-mix-other-o2'), '${mix.o2Percent}');
  await tester.enterText(_key('desired-mix-other-he'), '${mix.hePercent}');
  await tester.tap(_key('desired-mix-other-ok'));
  await tester.pumpAndSettle();
}

Finder _verdict() => _key('analysis-verdict');

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
    testWidgets('with no pick: the open blend first, then the log, no duplicate',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _logged('l1', DateTime(2026, 10, 30), 32, 0),
        _logged('l2', DateTime(2026, 10, 29), 21, 35),
      ]);
      // 23/30 is within orange of no standard mix.
      await _pump(tester,
          dao: dao,
          reading: _reading(23.0, 30.0),
          openBlend: const DesiredMix(21, 35));

      expect(_chipLabels(tester), ['Tx21/35', 'EAN32', 'Other…']);
      expect(_pickedChips(tester), isEmpty);
      expect(_verdict(), findsNothing);
    });

    testWidgets('the automatic pick comes first', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _logged('l1', DateTime(2026, 10, 30), 32, 0),
      ]);
      await _pump(tester,
          dao: dao,
          reading: _reading(49.2, 0),
          openBlend: const DesiredMix(21, 35));

      expect(_chipLabels(tester), ['EAN50', 'Tx21/35', 'EAN32', 'Other…']);
      expect(_picked(tester), 'desired-mix-50-0');
    });
  });

  group('gas role', () {
    testWidgets('follows the cylinder, and the saved role follows the control',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil, _o2]);
      // EAN50 by itself would be Bailout.
      await _pump(tester, dao: dao, reading: _reading(49.2, 0));
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

  group('verdict', () {
    testWidgets('says how the reading matches, in the match colour',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao);
      expect(tester.widget<Text>(_verdict()).data,
          'Matches Tx21/35, the nearest standard mix');
      expect(tester.widget<Text>(_verdict()).style!.color,
          SafetyColors.success);

      await _pump(tester, dao: dao, reading: _reading(22.5, 33.8));
      expect(tester.widget<Text>(_verdict()).data,
          'O2 1.5 off Tx21/35, the nearest standard mix');
      expect(tester.widget<Text>(_verdict()).style!.color,
          SafetyColors.warning);
      // The two numbers are in the summary band, not repeated here.
      expect(find.text('O2 22.5  He 33.8'), findsNothing);
    });

    testWidgets('a diver\'s pick has no suffix and may be red',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao, reading: _reading(32.1, 0));
      await _pickOther(tester, const DesiredMix(36, 0));
      expect(tester.widget<Text>(_verdict()).data, 'O2 3.9 off EAN36');
      expect(tester.widget<Text>(_verdict()).style!.color,
          SafetyColors.danger);
    });

    testWidgets('is not built for a reading that is not a number',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao, openBlend: const DesiredMix(21, 35));
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      expect(_verdict(), findsOneWidget);

      await _pump(
        tester,
        dao: dao,
        openBlend: const DesiredMix(21, 35),
        reading: _reading(double.nan, 33.8),
      );
      expect(tester.takeException(), isNull);
      expect(_verdict(), findsNothing);
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
        openBlend: const DesiredMix(21, 35),
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

      // Tx21/35 is picked automatically.
      expect(_picked(tester), 'desired-mix-21-35');
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
        openBlend: const DesiredMix(50, 0),
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
          openBlend: mix,
          labelPrinting: _service([off, on], rendered: rendered),
        );
        // The diver's pick, unless it is the automatic one already.
        final chip = 'desired-mix-${mix.o2Percent}-${mix.hePercent}';
        if (_picked(tester) != chip) await _tapAndSettle(tester, _key(chip));
        expect(_picked(tester), chip);
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
        final saved = dao.analyses.single;
        await dao.update(
          saved.id,
          GasAnalysisEdit(
            desiredMix: const DesiredMix(21, 33),
            gasRole: GasRole.bailout,
            analysedBy: null,
            notes: null,
            cylinderId: saved.cylinderId,
            fillPressureBar: saved.fillPressureBar,
            analysedFor: saved.analysedFor,
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
          openBlend: const DesiredMix(50, 0),
          labelPrinting: _service([printer], rendered: rendered),
          // A phone screen with the section below the fold, as on a small
          // phone.
          size: const Size(400, 500),
          above: 1200,
        );
        await _tapAndSettle(tester, _key('desired-mix-50-0'));
        // Back to the top: the chips go out of view, the pinned bar stays.
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, 2000));
        await tester.pumpAndSettle();
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
        // The button is pinned; the chips are below the fold.
        expect(tester.getRect(find.byType(DesiredMixPicker)).top,
            greaterThan(500));

        await tester.tap(_key('mix-mismatch-change'));
        await tester.pumpAndSettle();
        expect(dao.added, isEmpty);
        expect(printer.printed, isEmpty);
        final picker = tester.getRect(find.byType(DesiredMixPicker));
        final bar = tester.getRect(_key('analysis-action-bar'));
        expect(picker.top, greaterThanOrEqualTo(0));
        expect(picker.bottom, lessThanOrEqualTo(bar.top));
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
        openBlend: const DesiredMix(50, 0),
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
        openBlend: const DesiredMix(21, 35),
        labelPrinting: _service([printer]),
      );
      expect(_picked(tester), 'desired-mix-21-35');
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, _key('analysis-save'));

      expect(dao.added.single.desiredMix, const DesiredMix(21, 35));
      expect(dao.added.single.gasRole, GasRole.diluent);
      expect(printer.connects, 0);
      expect(printer.printed, isEmpty);
      // The SnackBar names the analysed mix, not the desired one.
      expect(find.text('Saved Tx21/34 to the analysis log · closes Tx21/35.'),
          findsOneWidget);
    });

    testWidgets('does not ask about a hard mismatch, since nothing prints',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final printer = FakeLabelPrinter();
      await _pump(
        tester,
        dao: dao,
        reading: _reading(32.1, 0),
        openBlend: const DesiredMix(50, 0),
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
      await _pump(tester, dao: dao, openBlend: const DesiredMix(21, 35));
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, find.text('Bailout'));
      await _pickOther(tester, const DesiredMix(21, 33));
      expect(_picked(tester), 'desired-mix-21-33');

      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added.single.desiredMix, const DesiredMix(21, 33));
      expect(dao.added.single.gasRole, GasRole.bailout);
      // A mix left picked would print its name on the next cylinder: the
      // pick is automatic again.
      expect(_picked(tester), 'desired-mix-21-35');
      // The Tx21/35 blend is still open (the save was of another mix).
      expect(tester.widget<Text>(_verdict()).data,
          'Matches Tx21/35, an open blend');
      expect(_role(tester), {GasRole.diluent},
          reason: 'back to the Dil cylinder\'s role');
    });

    testWidgets('Save & print prints the choices it saved, then starts fresh',
        (tester) async {
      final dao = FakeGasAnalysesDao(cylinders: const [_dil]);
      final rendered = <CylinderLabel>[];
      await _pump(
        tester,
        dao: dao,
        openBlend: const DesiredMix(21, 35),
        labelPrinting: _service([FakeLabelPrinter()], rendered: rendered),
      );
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, find.text('Bailout'));
      await _pickOther(tester, const DesiredMix(21, 33));

      await _tapAndSettle(tester, _key('analysis-save-print'));
      // The desired name (the analysed gas is Tx21/34) and the flipped role.
      expect(rendered.single.mixName, 'Tx21/33');
      expect(rendered.single.kind, CylinderLabelKind.bailout);
      expect(_picked(tester), 'desired-mix-21-35');
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
        openBlend: const DesiredMix(21, 35),
        labelPrinting: _service([off, on]),
      );
      await _tapAndSettle(tester, _key('analysis-save-print'));
      expect(find.text('Printer not found'), findsOneWidget);

      // The next cylinder, whose save fails.
      dao.fail = true;
      await _pickCylinder(tester, 'Dil 3L');
      await _tapAndSettle(tester, find.text('Bailout'));
      await _pickOther(tester, const DesiredMix(21, 33));
      await _tapAndSettle(tester, _key('analysis-save-print'));

      expect(find.text('Save failed: Exception: disk full'), findsOneWidget);
      expect(find.text('Printer not found'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(dao.added, hasLength(1));
      expect(on.connects, 0);
      expect(_picked(tester), 'desired-mix-21-33');
      expect(_verdict(), findsOneWidget);
      expect(_role(tester), {GasRole.bailout});
    });

    testWidgets('the mix just saved stays a chip for the next cylinder',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester, dao: dao, openBlend: const DesiredMix(21, 35));
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
      // The automatic pick (also the Blend target), then the log's newest,
      // not picked.
      expect(_chipLabels(tester), ['Tx21/35', 'Tx25/25', 'Other…']);
      expect(_picked(tester), 'desired-mix-21-35');

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
        openBlend: const DesiredMix(21, 35),
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
      // The automatic EAN32 and the Blend target; the log could not be read.
      expect(_chipLabels(tester), ['EAN32', 'Tx21/35', 'Other…']);
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

  group('the section and its bar on a small phone', () {
    // The test font is far wider than Inter, so this is harder than a phone.
    for (final printer in [true, false]) {
      testWidgets(
          'no overflow at 320×568 and text scale 1.3 '
          '(${printer ? 'printer' : 'no printer'})', (tester) async {
        await _pump(
          tester,
          dao: FakeGasAnalysesDao(cylinders: const [_dil, _o2]),
          reading: _reading(19.1, 43.0),
          stability: ReadingStability.settling,
          openBlend: const DesiredMix(21, 35),
          labelPrinting: _service([], configured: printer),
          onSetUpPrinter: () {},
          size: const Size(320, 568),
          textScale: 1.3,
        );
        await _tapAndSettle(tester, _key('analysis-add-note'));
        await _pickCylinder(tester, 'Dil 3L');
        expect(tester.takeException(), isNull);
        expect(_key('analysis-unstable-hint'), findsOneWidget);
        expect(_key('analysis-save-print'),
            printer ? findsOneWidget : findsNothing);
        expect(_key('analysis-setup-printer'),
            printer ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('the "Saved" SnackBar floats clear of the action bar',
        (tester) async {
      await _pump(tester, dao: FakeGasAnalysesDao(), size: const Size(400, 800));
      await _tapAndSettle(tester, _key('analysis-save'));
      expect(find.text('Saved Tx21/34 to the analysis log.'), findsOneWidget);
      // The bar's own surface, inside the SnackBar's margin.
      final snack = tester.getRect(find
          .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
          .first);
      final bar = tester.getRect(_key('analysis-action-bar'));
      expect(snack.bottom, lessThanOrEqualTo(bar.top));
    });
  });

  group('screens hand the card its open blends and printer', () {
    Future<SettingsNotifier> loadSettings() async {
      final s = SettingsNotifier();
      await s.load();
      return s;
    }

    Future<void> pumpAnalyzer(
      WidgetTester tester, {
      required LabelPrintService labelPrinting,
      DesiredMix? openBlend,
    }) async {
      tester.view.physicalSize = const Size(400, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = await loadSettings();
      final dao = FakeGasAnalysesDao();
      final session = AnalyzerSession(
        settings: settings,
        analysesDao: dao,
        labelPrinting: labelPrinting,
        transportOptions: [
          AnalyzerTransportOption(
            label: 'Bench',
            create: () => DemoAnalyzerTransport(),
          ),
        ],
      );
      addTearDown(session.dispose);
      final blend = BlendNotifier(settings: settings);
      final open = FakeOpenBlendsDao(blends: [
        if (openBlend != null) _openBlend('open-1', openBlend),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AnalyzerScreen(
              settings: settings,
              session: session,
              blend: blend,
              openBlends: open),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the analyzer passes its open blends and printer to the card',
        (tester) async {
      await pumpAnalyzer(
        tester,
        labelPrinting: _service([FakeLabelPrinter()]),
        openBlend: const DesiredMix(21, 35),
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
  });

  group('open blends', () {
    const tx1845 = DesiredMix(18, 45);

    /// The text of the SnackBar that is up.
    String snack(WidgetTester tester) => tester
        .widget<Text>(find.descendant(
            of: find.byType(SnackBar), matching: find.byType(Text)).first)
        .data!;

    testWidgets('save closes the oldest matching open blend and takes its '
        'target and role', (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          openBlends: [
            _openBlend('new', tx1845,
                role: GasRole.diluent, ago: const Duration(minutes: 5)),
            _openBlend('old', tx1845,
                role: GasRole.diluent, ago: const Duration(hours: 2)),
          ]);
      expect(
          tester.widget<Text>(_key('blend-close-text')).data,
          'Closes Tx18/45 · blended 2 h 00 min ago');

      await _tapAndSettle(tester, _key('analysis-save'));
      final a = dao.added.single;
      expect(a.desiredMix, tx1845);
      expect(a.gasRole, GasRole.diluent);
      expect(a.isResidual, isFalse);
      expect(_openDao!.closedBy.keys, ['old']);
      expect(snack(tester), contains('closes Tx18/45'));
    });

    testWidgets('a tapped role still wins over the blend\'s role',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          openBlends: [_openBlend('a', tx1845, role: GasRole.diluent)]);
      await _tapAndSettle(tester, find.text('Bailout'));
      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added.single.gasRole, GasRole.bailout);
      expect(dao.added.single.desiredMix, tx1845);
      expect(_openDao!.closedBy.keys, ['a']);
    });

    testWidgets('a manual mix chip closes the oldest blend of that mix',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          openBlends: [
            _openBlend('a', tx1845, ago: const Duration(minutes: 5)),
            _openBlend('b', const DesiredMix(21, 35),
                ago: const Duration(minutes: 30)),
            _openBlend('c', const DesiredMix(21, 35),
                ago: const Duration(hours: 3)),
          ]);
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      expect(
          tester.widget<Text>(_key('blend-close-text')).data,
          startsWith('Closes Tx21/35'));
      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added.single.desiredMix, const DesiredMix(21, 35));
      expect(_openDao!.closedBy.keys, ['c']);
    });

    testWidgets('choosing None closes nothing', (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          openBlends: [_openBlend('a', tx1845)]);
      await _tapAndSettle(tester, _key('blend-close-change'));
      await tester.tap(_key('blend-choice-none'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(_key('blend-close-text')).data,
          'No open blend');

      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added, hasLength(1));
      expect(_openDao!.closeBlendCalls, isEmpty);
      expect(snack(tester), isNot(contains('closes')));
    });

    testWidgets('the Change sheet lists every blend, best match first, '
        'and a blend picked there is what the row says', (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          openBlends: [
            _openBlend('far', const DesiredMix(50, 0),
                ago: const Duration(hours: 5)),
            _openBlend('near', tx1845, role: GasRole.diluent),
          ]);
      await _tapAndSettle(tester, _key('blend-close-change'));
      final near = tester.getTopLeft(_key('blend-choice-near')).dy;
      final far = tester.getTopLeft(_key('blend-choice-far')).dy;
      expect(near, lessThan(far));
      expect(_key('blend-choice-none'), findsOneWidget);
      expect(find.textContaining('Diluent'), findsWidgets);

      await tester.tap(_key('blend-choice-far'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(_key('blend-close-text')).data,
          startsWith('Closes EAN50 · blended 5 h 00 min ago'));
    });

    testWidgets('picking a hard-mismatched blend closes it and shows the '
        'loud warning', (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(55.0, 0),
          openBlends: [_openBlend('deco', const DesiredMix(50, 0))]);
      // Nothing matches by itself: the nearest is named, nothing is closed.
      expect(tester.widget<Text>(_key('blend-close-text')).data,
          startsWith('No open blend matches. Nearest: EAN50 ('));
      expect(_key('blend-close-warning'), findsNothing);

      await _tapAndSettle(tester, _key('blend-close-change'));
      await tester.tap(_key('blend-choice-deco'));
      await tester.pumpAndSettle();
      expect(_controller!.warning?.level, WarningLevel.loud);
      final warning = tester.widget<Text>(_key('blend-close-warning'));
      expect(warning.data, contains('MOD at'));
      expect(warning.style!.color, SafetyColors.danger);

      await _tapAndSettle(tester, _key('analysis-save'));
      expect(dao.added.single.desiredMix, const DesiredMix(50, 0));
      expect(_openDao!.closedBy.keys, ['deco']);
    });

    testWidgets('an unmatched reading names the nearest blend in the '
        'SnackBar', (tester) async {
      final dao = FakeGasAnalysesDao();
      await _pump(tester,
          dao: dao,
          reading: _reading(55.0, 0),
          openBlends: [_openBlend('deco', const DesiredMix(50, 0))]);
      await _tapAndSettle(tester, _key('analysis-save'));
      expect(snack(tester),
          contains('No open blend matches. Nearest: EAN50 ('));
      expect(_openDao!.closeBlendCalls, isEmpty);
    });

    testWidgets('residual: saved as residual, no desired mix, no print, '
        'closes nothing, fills the Blend tab', (tester) async {
      final dao = FakeGasAnalysesDao();
      final printer = FakeLabelPrinter();
      final told = <(double, double, double?)>[];
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          openBlends: [_openBlend('a', tx1845)],
          labelPrinting: _service([printer]),
          onResidualSaved: (o2, he, bar) => told.add((o2, he, bar)));
      await _tapAndSettle(tester, _key('analysis-residual-toggle'));
      // No label for a residual.
      expect(
          tester
              .widget<ButtonStyleButton>(_key('analysis-save-print'))
              .onPressed,
          isNull);
      expect(_key('blend-close-change'), findsNothing);

      await _tapAndSettle(tester, _key('analysis-save'));
      final a = dao.added.single;
      expect(a.isResidual, isTrue);
      expect(a.desiredMix, isNull);
      expect(printer.printed, isEmpty);
      expect(_openDao!.closeBlendCalls, isEmpty);
      expect(told, [(18.5, 44.0, 230.0)]);
      // It stays on until turned off.
      expect(_controller!.residual, isTrue);
      await _tapAndSettle(tester, _key('analysis-residual-toggle'));
      expect(_controller!.residual, isFalse);
      expect(
          tester
              .widget<ButtonStyleButton>(_key('analysis-save-print'))
              .onPressed,
          isNotNull);
    });

    testWidgets('without open blends there is no row, only the switch',
        (tester) async {
      await _pump(tester, dao: FakeGasAnalysesDao());
      expect(_key('blend-close-row'), findsNothing);
      expect(_key('analysis-residual-toggle'), findsOneWidget);
    });

    testWidgets('the row is at most two lines and 32 pt high, switch aside',
        (tester) async {
      await _pump(tester,
          dao: FakeGasAnalysesDao(),
          reading: _reading(18.5, 44.0),
          size: const Size(320, 900),
          openBlends: [_openBlend('a', tx1845)]);
      expect(tester.getSize(_key('blend-close-row')).height, 32);
      expect(_key('analysis-residual-toggle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the chosen blend closed elsewhere while the unstable dialog '
        'is up still saves', (tester) async {
      final dao = FakeGasAnalysesDao();
      final blend = _openBlend('a', tx1845);
      await _pump(tester,
          dao: dao,
          reading: _reading(18.5, 44.0),
          stability: ReadingStability.settling,
          openBlends: [blend]);
      await _tapAndSettle(tester, _key('analysis-save'));
      expect(find.text('Reading not stable'), findsOneWidget);

      await _openDao!.closeBlend(blend, 'elsewhere');
      await tester.pumpAndSettle();
      await tester.tap(_key('analysis-save-anyway'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(dao.added, hasLength(1));
      expect(dao.added.single.desiredMix, tx1845);
      expect(_openDao!.closedBy['a'], 'elsewhere');
      expect(snack(tester), isNot(contains('closes')));
    });

    testWidgets('a close that fails leaves the analysis saved',
        (tester) async {
      final dao = FakeGasAnalysesDao();
      final open = _ThrowingOpenBlends(blends: [_openBlend('a', tx1845)]);
      await _pump(tester,
          dao: dao, reading: _reading(18.5, 44.0), openDao: open);
      await _tapAndSettle(tester, _key('analysis-save'));
      expect(tester.takeException(), isNull);
      expect(dao.added, hasLength(1));
      expect(snack(tester), isNot(contains('closes')));
      expect(find.textContaining('Save failed'), findsNothing);
    });
  });
}
