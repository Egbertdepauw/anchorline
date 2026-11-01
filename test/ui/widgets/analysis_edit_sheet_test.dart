import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/ui/widgets/analysis_edit_sheet.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:ccrlogger/ui/widgets/mix_match_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

final Finder _sheet = _key('analysis-edit-sheet');
final Finder _measured = _key('analysis-edit-measured');

Finder _inSheet(Finder f) => find.descendant(of: _sheet, matching: f);

/// A diluent Tx analysed at 22.5/33.8, with the desired mix 21/35.
GasAnalysis _tx({int? targetO2 = 21, int? targetHe = 35}) => GasAnalysis(
      id: 'tx',
      cylinderId: 'c1',
      cylinderLabel: 'S80 left',
      analysedBy: 'Egbert',
      analysedAt: DateTime(2026, 10, 30, 18, 5),
      o2Percent: 22.5,
      hePercent: 33.8,
      fillPressureBar: 200,
      tempC: 21.4,
      stable: true,
      notes: 'Blended Friday',
      targetO2Percent: targetO2,
      targetHePercent: targetHe,
      gasRole: GasRole.diluent,
    );

const _options = [DesiredMix(21, 35), DesiredMix(50, 0)];

/// A [FakeGasAnalysesDao] whose [update] throws while [fail] is set.
class _FlakyDao extends FakeGasAnalysesDao {
  _FlakyDao({super.analyses});

  bool fail = false;

  @override
  Future<void> update(String id, GasAnalysisEdit edit) async {
    if (fail) throw Exception('disk full');
    return super.update(id, edit);
  }
}

/// Opens the sheet for [analysis] from a button at phone size. What
/// [showAnalysisEditSheet] returns lands in the returned list.
Future<List<bool>> _open(
  WidgetTester tester, {
  required FakeGasAnalysesDao dao,
  GasAnalysis? analysis,
  List<DesiredMix> mixOptions = _options,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <bool>[];
  final a = analysis ?? dao.analyses.first;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(await showAnalysisEditSheet(
            context,
            dao: dao,
            analysis: a,
            mixOptions: mixOptions,
          )),
          child: const Text('Edit'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

bool _chipSelected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(_key(key)).selected;

Set<GasRole> _role(WidgetTester tester) => tester
    .widget<SegmentedButton<GasRole>>(_key('analysis-edit-role'))
    .selected;

String _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

void main() {
  testWidgets('shows the measured values read-only and the editable fields',
      (tester) async {
    await _open(tester, dao: FakeGasAnalysesDao(analyses: [_tx()]));
    expect(_sheet, findsOneWidget);

    // Measured: shown, never in an input.
    Finder measured(Finder f) => find.descendant(of: _measured, matching: f);
    expect(measured(find.text('Tx23/34')), findsOneWidget);
    expect(measured(find.textContaining('22.5')), findsOneWidget);
    expect(measured(find.textContaining('33.8')), findsOneWidget);
    expect(measured(find.textContaining('30 Oct 2026, 18:05')), findsOneWidget);
    expect(measured(find.textContaining('S80 left')), findsOneWidget);
    expect(measured(find.textContaining('200 bar')), findsOneWidget);
    expect(measured(find.textContaining('21.4 °C')), findsOneWidget);
    expect(measured(find.text('Stable')), findsOneWidget);
    expect(measured(find.byType(EditableText)), findsNothing);

    // Editable: the picker on the stored mix, graded; role; diver; notes.
    expect(_inSheet(find.byType(DesiredMixPicker)), findsOneWidget);
    expect(_chipSelected(tester, 'desired-mix-21-35'), isTrue);
    expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
    expect(_inSheet(find.byType(MixMatchIndicator)), findsOneWidget);
    expect(_inSheet(find.text('O2 1.5 off Tx21/35')), findsOneWidget);
    expect(_role(tester), {GasRole.diluent});
    expect(_field(tester, 'analysis-edit-diver'), 'Egbert');
    expect(_field(tester, 'analysis-edit-notes'), 'Blended Friday');

    // The only inputs are who analysed and the notes.
    expect(_inSheet(find.byType(EditableText)), findsNWidgets(2));
  });

  testWidgets('without a desired mix: no chip picked and no grade',
      (tester) async {
    await _open(tester,
        dao: FakeGasAnalysesDao(
            analyses: [_tx(targetO2: null, targetHe: null)]));
    expect(_chipSelected(tester, 'desired-mix-21-35'), isFalse);
    expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
    expect(_inSheet(find.byType(MixMatchIndicator)), findsNothing);
  });

  testWidgets('Save sends the four fields, trimmed, and returns true',
      (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);

    await _tapAndSettle(tester, _key('desired-mix-50-0'));
    expect(_inSheet(find.text('O2 27.5, He 33.8 off EAN50')), findsOneWidget,
        reason: 'the grade follows the picked mix');
    await _tapAndSettle(tester, find.text('Bailout/deco'));
    await tester.enterText(_key('analysis-edit-diver'), '  EdP ');
    await tester.enterText(_key('analysis-edit-notes'), '   ');
    await _tapAndSettle(tester, _key('analysis-edit-save'));

    final (id, edit) = dao.updated.single;
    expect(id, 'tx');
    expect(edit.desiredMix, const DesiredMix(50, 0));
    expect(edit.gasRole, GasRole.bailout);
    expect(edit.analysedBy, 'EdP');
    expect(edit.notes, isNull);
    expect(results, [true]);
    expect(_sheet, findsNothing);
  });

  testWidgets('tapping the picked mix clears it, and Save clears it too',
      (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    await _open(tester, dao: dao);
    await _tapAndSettle(tester, _key('desired-mix-21-35'));
    expect(_inSheet(find.byType(MixMatchIndicator)), findsNothing);
    await _tapAndSettle(tester, _key('analysis-edit-save'));

    final (_, edit) = dao.updated.single;
    expect(edit.desiredMix, isNull);
    // Untouched fields go back as they were.
    expect(edit.gasRole, GasRole.diluent);
    expect(edit.analysedBy, 'Egbert');
    expect(edit.notes, 'Blended Friday');
  });

  testWidgets('a mix typed in through Other… is saved', (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    await _open(tester, dao: dao);
    await _tapAndSettle(tester, _key('desired-mix-other'));
    await tester.enterText(_key('desired-mix-other-o2'), '23');
    await tester.enterText(_key('desired-mix-other-he'), '34');
    await _tapAndSettle(tester, _key('desired-mix-other-ok'));
    expect(_inSheet(find.text('Matches Tx23/34')), findsOneWidget);
    await _tapAndSettle(tester, _key('analysis-edit-save'));
    expect(dao.updated.single.$2.desiredMix, const DesiredMix(23, 34));
  });

  testWidgets('Cancel saves nothing and returns false', (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);
    await _tapAndSettle(tester, _key('desired-mix-50-0'));
    await _tapAndSettle(tester, _key('analysis-edit-cancel'));
    expect(dao.updated, isEmpty);
    expect(results, [false]);
    expect(_sheet, findsNothing);
  });

  testWidgets('dismissing the sheet saves nothing and returns false',
      (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);
    expect(_sheet, findsOneWidget);
    // Tap the barrier above the sheet.
    await tester.tapAt(const Offset(200, 10));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(dao.updated, isEmpty);
    expect(results, [false]);
  });

  testWidgets('a failed save keeps the sheet open and says why',
      (tester) async {
    final dao = _FlakyDao(analyses: [_tx()])..fail = true;
    final results = await _open(tester, dao: dao);
    await tester.enterText(_key('analysis-edit-diver'), 'EdP');
    await _tapAndSettle(tester, _key('analysis-edit-save'));
    expect(_sheet, findsOneWidget);
    expect(_inSheet(find.textContaining('Save failed')), findsOneWidget);
    expect(_field(tester, 'analysis-edit-diver'), 'EdP');
    expect(results, isEmpty);

    dao.fail = false;
    await _tapAndSettle(tester, _key('analysis-edit-save'));
    expect(dao.updated.single.$2.analysedBy, 'EdP');
    expect(results, [true]);
  });

  testWidgets('a double tap on Save updates once', (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);
    final save = tester.widget<ButtonStyleButton>(_key('analysis-edit-save'));
    save.onPressed!();
    save.onPressed!();
    await tester.pumpAndSettle();
    expect(dao.updated, hasLength(1));
    expect(results, [true]);
  });
}
