import 'dart:async';

import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/ui/theme/tokens.dart';
import 'package:ccrlogger/ui/widgets/analysis_edit_sheet.dart';
import 'package:ccrlogger/ui/widgets/desired_mix_picker.dart';
import 'package:ccrlogger/ui/widgets/analysis_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/fake_gas_analyses_dao.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

final Finder _sheet = _key('analysis-edit-sheet');
final Finder _measured = _key('analysis-edit-measured');

Finder _inSheet(Finder f) => find.descendant(of: _sheet, matching: f);

/// A diluent Tx analysed at 22.5/33.8, with the desired mix 21/35, on
/// cylinder c1, for Jan.
GasAnalysis _tx({
  int? targetO2 = 21,
  int? targetHe = 35,
  String? analysedBy = 'Egbert',
  bool needsSignoff = false,
}) =>
    GasAnalysis(
      id: 'tx',
      cylinderId: 'c1',
      cylinderLabel: 'S80 left',
      analysedBy: analysedBy,
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
      needsSignoff: needsSignoff,
      analysedFor: 'Jan',
    );

const _options = [DesiredMix(21, 35), DesiredMix(50, 0)];

/// A [FakeGasAnalysesDao] whose [update] and [softDelete] throw while
/// [fail] is set.
class _FlakyDao extends FakeGasAnalysesDao {
  _FlakyDao({super.analyses});

  bool fail = false;

  @override
  Future<void> update(String id, GasAnalysisEdit edit) async {
    if (fail) throw Exception('disk full');
    return super.update(id, edit);
  }

  @override
  Future<void> softDelete(String id) async {
    if (fail) throw Exception('disk full');
    return super.softDelete(id);
  }
}

/// A [FakeGasAnalysesDao] whose [update] waits for [gate], so a test can
/// look at the sheet while the update is under way.
class _GatedDao extends FakeGasAnalysesDao {
  _GatedDao(this.gate, {super.analyses});

  final Completer<void> gate;

  @override
  Future<void> update(String id, GasAnalysisEdit edit) async {
    await gate.future;
    return super.update(id, edit);
  }
}

/// A [FakeGasAnalysesDao] whose [list] for cylinder [slowCylinder] waits for
/// [gate], so a test can act while the sheet looks up a cylinder's mix.
class _SlowListDao extends FakeGasAnalysesDao {
  _SlowListDao(this.gate, {required this.slowCylinder, super.analyses})
      : super(cylinders: const [_c1, _c2]);

  final Completer<void> gate;
  final String slowCylinder;

  @override
  Future<List<GasAnalysis>> list({String? cylinderId}) async {
    if (cylinderId == slowCylinder) await gate.future;
    return super.list(cylinderId: cylinderId);
  }
}

/// Opens the sheet for [analysis] from a button at phone size. What
/// [showAnalysisEditSheet] returns lands in the returned list.
Future<List<AnalysisEditOutcome>> _open(
  WidgetTester tester, {
  required FakeGasAnalysesDao dao,
  GasAnalysis? analysis,
  List<DesiredMix> mixOptions = _options,
  String? suggestedAnalysedBy,
  bool canPrint = false,
  double width = 400,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <AnalysisEditOutcome>[];
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
            suggestedAnalysedBy: suggestedAnalysedBy,
            canPrint: canPrint,
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

/// The button [key] can be pressed.
bool _enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(_key(key)).onPressed != null;

/// Opens the cylinder dropdown and picks the item labelled [label].
Future<void> _pickCylinder(WidgetTester tester, String label) async {
  await _tapAndSettle(tester, _key('analysis-edit-cylinder'));
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// What the cylinder dropdown shows as picked: the one item it paints.
String _cylinderShown(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
      of: find.descendant(
          of: _key('analysis-edit-cylinder'),
          matching: find.byType(IndexedStack)),
      matching: find.byType(Text),
    ))
    .data!;

/// The delete dialog's own Cancel button (the sheet has one too).
Finder get _dialogCancel => find.descendant(
    of: find.byType(AlertDialog), matching: find.text('Cancel'));

const _c1 = CylinderChoice(
    id: 'c1', label: 'S80 left', role: CylinderRole.diluent);
const _c2 = CylinderChoice(
    id: 'c2', label: 'AL40 deco', role: CylinderRole.bailout);

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
    expect(measured(find.textContaining('21.4 °C')), findsOneWidget);
    // The cylinder and the fill pressure are inputs below, not repeated here.
    expect(measured(find.textContaining('S80 left')), findsNothing);
    expect(measured(find.textContaining('bar')), findsNothing);
    expect(measured(find.text('Stable')), findsOneWidget);
    expect(measured(find.byType(EditableText)), findsNothing);
    // A band in surfaceRaised, not an outlined box.
    final band = tester.widget<Container>(_measured);
    expect((band.decoration as BoxDecoration).color,
        tester.element(_measured).palette.surfaceRaised);

    // Editable: the picker on the stored mix, graded; role; diver; notes.
    expect(_inSheet(find.byType(DesiredMixPicker)), findsOneWidget);
    expect(_chipSelected(tester, 'desired-mix-21-35'), isTrue);
    expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
    expect(_inSheet(find.byType(AnalysisVerdict)), findsOneWidget);
    expect(_inSheet(find.text('O2 1.5 off Tx21/35')), findsOneWidget);
    expect(_role(tester), {GasRole.diluent});
    expect(_field(tester, 'analysis-edit-diver'), 'Egbert');
    expect(_field(tester, 'analysis-edit-notes'), 'Blended Friday');

    // The stated fields are inputs: who analysed, fill pressure, for, notes.
    expect(_cylinderShown(tester), 'S80 left');
    expect(_field(tester, 'analysis-edit-pressure'), '200');
    expect(_field(tester, 'analysis-edit-for'), 'Jan');
    expect(_inSheet(find.byType(EditableText)), findsNWidgets(4));
  });

  testWidgets('without a desired mix: no chip picked and no grade',
      (tester) async {
    await _open(tester,
        dao: FakeGasAnalysesDao(
            analyses: [_tx(targetO2: null, targetHe: null)]));
    expect(_chipSelected(tester, 'desired-mix-21-35'), isFalse);
    expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
    expect(_inSheet(find.byType(AnalysisVerdict)), findsNothing);
  });

  testWidgets('Save sends the four fields, trimmed, and returns saved',
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
    expect(results, [AnalysisEditOutcome.saved]);
    expect(_sheet, findsNothing);
  });

  testWidgets('tapping the picked mix clears it, and Save clears it too',
      (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    await _open(tester, dao: dao);
    await _tapAndSettle(tester, _key('desired-mix-21-35'));
    expect(_inSheet(find.byType(AnalysisVerdict)), findsNothing);
    await _tapAndSettle(tester, _key('analysis-edit-save'));

    final (_, edit) = dao.updated.single;
    expect(edit.desiredMix, isNull);
    // Untouched fields go back as they were.
    expect(edit.gasRole, GasRole.diluent);
    expect(edit.analysedBy, 'Egbert');
    expect(edit.notes, 'Blended Friday');
    expect(edit.cylinderId, 'c1');
    expect(edit.fillPressureBar, 200);
    expect(edit.analysedFor, 'Jan');
    expect(edit.signOff, isFalse);
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

  testWidgets('Cancel saves nothing and returns cancelled', (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);
    await _tapAndSettle(tester, _key('desired-mix-50-0'));
    await _tapAndSettle(tester, _key('analysis-edit-cancel'));
    expect(dao.updated, isEmpty);
    expect(results, [AnalysisEditOutcome.cancelled]);
    expect(_sheet, findsNothing);
  });

  testWidgets('dismissing the sheet saves nothing and returns cancelled',
      (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);
    expect(_sheet, findsOneWidget);
    // Tap the barrier above the sheet.
    await tester.tapAt(const Offset(200, 10));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(dao.updated, isEmpty);
    expect(results, [AnalysisEditOutcome.cancelled]);
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
    expect(results, [AnalysisEditOutcome.saved]);
  });

  testWidgets('a double tap on Save updates once', (tester) async {
    final dao = FakeGasAnalysesDao(analyses: [_tx()]);
    final results = await _open(tester, dao: dao);
    final save = tester.widget<ButtonStyleButton>(_key('analysis-edit-save'));
    save.onPressed!();
    save.onPressed!();
    await tester.pumpAndSettle();
    expect(dao.updated, hasLength(1));
    expect(results, [AnalysisEditOutcome.saved]);
  });

  group('cylinder, fill pressure and for', () {
    testWidgets('cylinder, fill pressure and for are saved', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()], cylinders: [_c1, _c2]);
      await _open(tester, dao: dao);
      expect(_cylinderShown(tester), 'S80 left');

      await _pickCylinder(tester, 'AL40 deco');
      expect(_cylinderShown(tester), 'AL40 deco');
      await tester.enterText(_key('analysis-edit-pressure'), '210');
      await tester.enterText(_key('analysis-edit-for'), '  Wendy ');
      await _tapAndSettle(tester, _key('analysis-edit-save'));

      final (id, edit) = dao.updated.single;
      expect(id, 'tx');
      expect(edit.cylinderId, 'c2');
      expect(edit.fillPressureBar, 210.0);
      expect(edit.analysedFor, 'Wendy');
      // The measured values and the entry stay as they were.
      expect(dao.analyses.single.o2Percent, 22.5);
    });

    testWidgets('a comma works as the decimal separator', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      await _open(tester, dao: dao);
      await tester.enterText(_key('analysis-edit-pressure'), ' 207,5 ');
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      expect(dao.updated.single.$2.fillPressureBar, 207.5);
    });

    testWidgets('a blank fill pressure and a blank for are cleared',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      await _open(tester, dao: dao);
      await tester.enterText(_key('analysis-edit-pressure'), '  ');
      await tester.enterText(_key('analysis-edit-for'), ' ');
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      final (_, edit) = dao.updated.single;
      expect(edit.fillPressureBar, isNull);
      expect(edit.analysedFor, isNull);
    });

    testWidgets('the cylinder dropdown lists No cylinder first',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()], cylinders: [_c1, _c2]);
      await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('analysis-edit-cylinder'));
      double top(String label) => tester.getTopLeft(find.text(label).last).dy;
      expect(top('No cylinder'), lessThan(top('S80 left')));
      expect(top('S80 left'), lessThan(top('AL40 deco')));
    });

    testWidgets('No cylinder clears the cylinder', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()], cylinders: [_c1]);
      await _open(tester, dao: dao);
      await _pickCylinder(tester, 'No cylinder');
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      final (_, edit) = dao.updated.single;
      expect(edit.cylinderId, isNull);
      // No cylinder says nothing about the role.
      expect(edit.gasRole, GasRole.diluent);
    });

    testWidgets('picking a cylinder sets the role from the cylinder',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()], cylinders: [_c1, _c2]);
      await _open(tester, dao: dao);
      expect(_role(tester), {GasRole.diluent});
      await _pickCylinder(tester, 'AL40 deco');
      expect(_role(tester), {GasRole.bailout});
      // The picked desired mix stays.
      expect(_chipSelected(tester, 'desired-mix-21-35'), isTrue);
      await _pickCylinder(tester, 'S80 left');
      expect(_role(tester), {GasRole.diluent});
    });

    testWidgets(
        'picking a cylinder takes the desired mix and role from its latest '
        'analysis', (tester) async {
      GasAnalysis other(String id, DateTime at,
              {int? o2, GasRole role = GasRole.bailout}) =>
          GasAnalysis(
            id: id,
            cylinderId: 'c2',
            analysedAt: at,
            o2Percent: 32,
            hePercent: 0,
            stable: true,
            targetO2Percent: o2,
            targetHePercent: o2 == null ? null : 0,
            gasRole: role,
          );
      final dao = FakeGasAnalysesDao(
        // c2 is a diluent cylinder, so the role must come from the entry.
        cylinders: [
          _c1,
          const CylinderChoice(
              id: 'c2', label: 'AL40 deco', role: CylinderRole.diluent),
        ],
        analyses: [
          _tx(targetO2: null, targetHe: null),
          // Newest with a desired mix: this one is used.
          other('mid', DateTime(2026, 10, 1), o2: 32),
          // Newer, but with no desired mix: skipped.
          other('newest', DateTime(2026, 10, 20)),
          // Older, with another mix: not used.
          other('old', DateTime(2026, 9, 1), o2: 50, role: GasRole.diluent),
        ],
      );
      await _open(tester,
          dao: dao,
          analysis: dao.analyses.first,
          mixOptions: const [DesiredMix(32, 0), DesiredMix(50, 0)]);
      expect(_chipSelected(tester, 'desired-mix-32-0'), isFalse);
      expect(_role(tester), {GasRole.diluent});

      await _pickCylinder(tester, 'AL40 deco');

      expect(_chipSelected(tester, 'desired-mix-32-0'), isTrue);
      expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
      expect(_role(tester), {GasRole.bailout});
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      final (_, edit) = dao.updated.single;
      expect(edit.desiredMix, const DesiredMix(32, 0));
      expect(edit.gasRole, GasRole.bailout);
      expect(edit.cylinderId, 'c2');
    });

    testWidgets('a cylinder with no earlier mix leaves the desired mix empty',
        (tester) async {
      final dao = FakeGasAnalysesDao(
        cylinders: [_c1, _c2],
        analyses: [_tx(targetO2: null, targetHe: null)],
      );
      await _open(tester, dao: dao);
      await _pickCylinder(tester, 'AL40 deco');
      expect(_chipSelected(tester, 'desired-mix-21-35'), isFalse);
      expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
      expect(_role(tester), {GasRole.bailout}, reason: 'from the cylinder');
    });

    testWidgets('a desired mix already picked is not replaced',
        (tester) async {
      final dao = FakeGasAnalysesDao(
        cylinders: [_c1, _c2],
        analyses: [
          _tx(targetO2: null, targetHe: null),
          GasAnalysis(
            id: 'earlier',
            cylinderId: 'c2',
            analysedAt: DateTime(2026, 10, 1),
            o2Percent: 50,
            hePercent: 0,
            stable: true,
            targetO2Percent: 50,
            targetHePercent: 0,
          ),
        ],
      );
      await _open(tester, dao: dao, analysis: dao.analyses.first);
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      await _pickCylinder(tester, 'AL40 deco');
      expect(_chipSelected(tester, 'desired-mix-21-35'), isTrue);
      expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
    });

    testWidgets('the entry itself is not the source of its own desired mix',
        (tester) async {
      // On c2 with 21/35. The diver clears the mix, goes to c1 and back.
      final entry = GasAnalysis(
        id: 'self',
        cylinderId: 'c2',
        cylinderLabel: 'AL40 deco',
        analysedAt: DateTime(2026, 10, 1),
        o2Percent: 21,
        hePercent: 35,
        stable: true,
        targetO2Percent: 21,
        targetHePercent: 35,
      );
      final dao = FakeGasAnalysesDao(cylinders: [_c1, _c2], analyses: [entry]);
      await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      expect(_chipSelected(tester, 'desired-mix-21-35'), isFalse);
      await _pickCylinder(tester, 'S80 left');
      await _pickCylinder(tester, 'AL40 deco');
      expect(_chipSelected(tester, 'desired-mix-21-35'), isFalse);
    });

    GasAnalysis earlierOnC2() => GasAnalysis(
          id: 'earlier',
          cylinderId: 'c2',
          analysedAt: DateTime(2026, 10, 1),
          o2Percent: 50,
          hePercent: 0,
          stable: true,
          targetO2Percent: 50,
          targetHePercent: 0,
        );

    testWidgets('a mix picked while the cylinder\'s analyses load is kept',
        (tester) async {
      final gate = Completer<void>();
      final dao = _SlowListDao(gate,
          slowCylinder: 'c2',
          analyses: [_tx(targetO2: null, targetHe: null), earlierOnC2()]);
      await _open(tester, dao: dao, analysis: dao.analyses.first);
      await _pickCylinder(tester, 'AL40 deco');
      await _tapAndSettle(tester, _key('desired-mix-21-35'));
      gate.complete();
      await tester.pumpAndSettle();
      expect(_chipSelected(tester, 'desired-mix-21-35'), isTrue);
      expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
    });

    testWidgets('the analyses of a cylinder no longer picked are ignored',
        (tester) async {
      final gate = Completer<void>();
      final dao = _SlowListDao(gate,
          slowCylinder: 'c2',
          analyses: [_tx(targetO2: null, targetHe: null), earlierOnC2()]);
      await _open(tester, dao: dao, analysis: dao.analyses.first);
      await _pickCylinder(tester, 'AL40 deco');
      await _pickCylinder(tester, 'S80 left');
      gate.complete();
      await tester.pumpAndSettle();
      expect(_chipSelected(tester, 'desired-mix-21-35'), isFalse);
      expect(_chipSelected(tester, 'desired-mix-50-0'), isFalse);
      expect(_role(tester), {GasRole.diluent}, reason: 'S80 left is diluent');
    });

    testWidgets('an unknown cylinder survives an unrelated edit',
        (tester) async {
      final entry = GasAnalysis(
        id: 'gone-entry',
        cylinderId: 'gone',
        analysedAt: DateTime(2026, 10, 1),
        o2Percent: 32,
        hePercent: 0,
        fillPressureBar: 190,
        stable: true,
        gasRole: GasRole.diluent,
      );
      final dao = FakeGasAnalysesDao(cylinders: [_c1, _c2], analyses: [entry]);
      await _open(tester, dao: dao);
      // Shown as the entry says, and still picked.
      expect(_cylinderShown(tester), 'Unknown cylinder');

      await tester.enterText(_key('analysis-edit-notes'), 'Checked');
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      final (_, edit) = dao.updated.single;
      expect(edit.cylinderId, 'gone');
      expect(edit.notes, 'Checked');
      expect(edit.gasRole, GasRole.diluent);
    });

    testWidgets('an unknown cylinder can be picked again after another',
        (tester) async {
      final entry = GasAnalysis(
        id: 'gone-entry',
        cylinderId: 'gone',
        analysedAt: DateTime(2026, 10, 1),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
        gasRole: GasRole.diluent,
      );
      final dao = FakeGasAnalysesDao(cylinders: [_c2], analyses: [entry]);
      await _open(tester, dao: dao);
      await _pickCylinder(tester, 'AL40 deco');
      await _pickCylinder(tester, 'Unknown cylinder');
      // It is not one of the diver's cylinders: the role is left alone.
      expect(_role(tester), {GasRole.bailout});
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      expect(dao.updated.single.$2.cylinderId, 'gone');
    });

    testWidgets('a cylinder deleted from Equipment is labelled as such',
        (tester) async {
      final entry = GasAnalysis(
        id: 'del',
        cylinderId: 'c9',
        cylinderLabel: 'Old S80',
        cylinderDeleted: true,
        analysedAt: DateTime(2026, 10, 1),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
      );
      await _open(tester, dao: FakeGasAnalysesDao(analyses: [entry]));
      expect(_cylinderShown(tester), 'Old S80 (deleted)');
    });

    for (final bad in ['21o', 'abc', '-5', 'NaN', 'Infinity', '1,2,3']) {
      testWidgets('a bad fill pressure ($bad) blocks saving', (tester) async {
        final dao = FakeGasAnalysesDao(analyses: [_tx()]);
        await _open(tester, dao: dao);
        expect(find.text('Enter a pressure in bar'), findsNothing);
        await tester.enterText(_key('analysis-edit-pressure'), bad);
        await tester.pumpAndSettle();
        expect(find.text('Enter a pressure in bar'), findsOneWidget);
        expect(_enabled(tester, 'analysis-edit-save'), isFalse);

        // Mending it brings Save back.
        await tester.enterText(_key('analysis-edit-pressure'), '210');
        await tester.pumpAndSettle();
        expect(find.text('Enter a pressure in bar'), findsNothing);
        expect(_enabled(tester, 'analysis-edit-save'), isTrue);
      });
    }

    testWidgets('a bad fill pressure disables Sign off and Sign off and print',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]);
      await _open(tester, dao: dao, canPrint: true);
      expect(_enabled(tester, 'analysis-edit-signoff'), isTrue);
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isTrue);
      await tester.enterText(_key('analysis-edit-pressure'), '21o');
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'analysis-edit-save'), isFalse);
      expect(_enabled(tester, 'analysis-edit-signoff'), isFalse);
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isFalse);
    });
  });

  group('analysed by', () {
    testWidgets('a flagged entry with no name starts from the suggestion',
        (tester) async {
      final dao = FakeGasAnalysesDao(
          analyses: [_tx(analysedBy: null, needsSignoff: true)]);
      await _open(tester, dao: dao, suggestedAnalysedBy: 'Wendy');
      expect(_field(tester, 'analysis-edit-diver'), 'Wendy');
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      expect(dao.updated.single.$2.analysedBy, 'Wendy');
    });

    testWidgets('an old unflagged entry with no name stays without one',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx(analysedBy: null)]);
      await _open(tester, dao: dao, suggestedAnalysedBy: 'Wendy');
      expect(_field(tester, 'analysis-edit-diver'), '');
      await tester.enterText(_key('analysis-edit-notes'), 'Checked');
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      expect(dao.updated.single.$2.analysedBy, isNull,
          reason: 'Save must not put today\'s name on an old entry');
    });

    testWidgets('keeps the entry\'s own name over the suggestion',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      await _open(tester, dao: dao, suggestedAnalysedBy: 'Wendy');
      expect(_field(tester, 'analysis-edit-diver'), 'Egbert');
    });

    testWidgets('is empty without a name and without a suggestion',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx(analysedBy: null)]);
      await _open(tester, dao: dao);
      expect(_field(tester, 'analysis-edit-diver'), '');
    });
  });

  group('delete', () {
    testWidgets('Delete asks first, then soft-deletes and returns deleted',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      final results = await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('analysis-edit-delete'));

      expect(find.text('Delete this analysis?'), findsOneWidget);
      expect(dao.deleted, isEmpty, reason: 'asks before deleting');
      expect(results, isEmpty);

      await tester.tap(_key('analysis-delete-confirm'));
      await tester.pumpAndSettle();
      expect(dao.deleted, ['tx']);
      expect(dao.updated, isEmpty);
      expect(results, [AnalysisEditOutcome.deleted]);
      expect(_sheet, findsNothing);
      expect(find.text('Delete this analysis?'), findsNothing);
    });

    testWidgets('Cancel in the delete dialog deletes nothing',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      final results = await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('analysis-edit-delete'));
      await tester.tap(_dialogCancel);
      await tester.pumpAndSettle();

      expect(find.text('Delete this analysis?'), findsNothing);
      expect(dao.deleted, isEmpty);
      expect(results, isEmpty);
      // The sheet is still there, and still works.
      expect(_sheet, findsOneWidget);
      expect(_enabled(tester, 'analysis-edit-save'), isTrue);
      expect(_enabled(tester, 'analysis-edit-delete'), isTrue);
    });

    testWidgets('a failed delete keeps the sheet open and says why',
        (tester) async {
      final dao = _FlakyDao(analyses: [_tx()])..fail = true;
      final results = await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('analysis-edit-delete'));
      await tester.tap(_key('analysis-delete-confirm'));
      await tester.pumpAndSettle();

      expect(_sheet, findsOneWidget);
      expect(_inSheet(find.textContaining('Delete failed')), findsOneWidget);
      expect(results, isEmpty);
      expect(dao.deleted, isEmpty);

      dao.fail = false;
      await _tapAndSettle(tester, _key('analysis-edit-delete'));
      await tester.tap(_key('analysis-delete-confirm'));
      await tester.pumpAndSettle();
      expect(dao.deleted, ['tx']);
      expect(results, [AnalysisEditOutcome.deleted]);
    });

    testWidgets('a double tap on Delete opens one dialog', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      await _open(tester, dao: dao);
      final delete =
          tester.widget<ButtonStyleButton>(_key('analysis-edit-delete'));
      delete.onPressed!();
      delete.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(_key('analysis-delete-confirm'));
      await tester.pumpAndSettle();
      expect(dao.deleted, ['tx']);
    });

    testWidgets('a double tap on the confirm deletes once', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx()]);
      await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('analysis-edit-delete'));
      final confirm =
          tester.widget<ButtonStyleButton>(_key('analysis-delete-confirm'));
      confirm.onPressed!();
      confirm.onPressed!();
      await tester.pumpAndSettle();
      expect(dao.deleted, ['tx']);
    });
  });

  group('sign-off', () {
    testWidgets('an unflagged entry has Save and Cancel and no Sign off',
        (tester) async {
      await _open(tester,
          dao: FakeGasAnalysesDao(analyses: [_tx()]), canPrint: true);
      expect(_key('analysis-edit-save'), findsOneWidget);
      expect(_key('analysis-edit-cancel'), findsOneWidget);
      expect(_key('analysis-edit-signoff'), findsNothing);
      expect(_key('analysis-edit-signoff-print'), findsNothing);
    });

    testWidgets('a flagged entry signs off only with a name', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _tx(
            analysedBy: null,
            targetO2: null,
            targetHe: null,
            needsSignoff: true),
      ]);
      final results = await _open(tester,
          dao: dao, mixOptions: const [DesiredMix(32, 0)]);
      // No name: disabled, and the sheet says what is missing.
      expect(_enabled(tester, 'analysis-edit-signoff'), isFalse);
      expect(_key('analysis-edit-signoff-hint'), findsOneWidget);
      expect(find.text('To sign off, add who analysed it.'), findsOneWidget);

      // A mix but no name (blanks are no name).
      await _tapAndSettle(tester, _key('desired-mix-32-0'));
      await tester.enterText(_key('analysis-edit-diver'), '   ');
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'analysis-edit-signoff'), isFalse);
      expect(_key('analysis-edit-signoff-hint'), findsOneWidget);

      // A name and a mix.
      await tester.enterText(_key('analysis-edit-diver'), 'Wendy');
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'analysis-edit-signoff'), isTrue);
      expect(_key('analysis-edit-signoff-hint'), findsNothing);
      await _tapAndSettle(tester, _key('analysis-edit-signoff'));

      final (id, edit) = dao.updated.single;
      expect(id, 'tx');
      expect(edit.signOff, isTrue);
      expect(edit.analysedBy, 'Wendy');
      expect(edit.desiredMix, const DesiredMix(32, 0));
      expect(results, [AnalysisEditOutcome.signedOff]);
      expect(_sheet, findsNothing);
      expect(dao.analyses.single.needsSignoff, isFalse);
    });

    testWidgets('a flagged entry signs off with a name and no desired mix',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _tx(
            analysedBy: null,
            targetO2: null,
            targetHe: null,
            needsSignoff: true),
      ]);
      final results = await _open(tester,
          dao: dao, mixOptions: const [DesiredMix(32, 0)], canPrint: true);
      expect(_enabled(tester, 'analysis-edit-signoff'), isFalse);
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isFalse);

      // A name alone is enough, for both buttons.
      await tester.enterText(_key('analysis-edit-diver'), 'Wendy');
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'analysis-edit-signoff'), isTrue);
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isTrue);
      expect(_key('analysis-edit-signoff-hint'), findsNothing);
      await _tapAndSettle(tester, _key('analysis-edit-signoff'));

      final (_, edit) = dao.updated.single;
      expect(edit.signOff, isTrue);
      expect(edit.analysedBy, 'Wendy');
      expect(edit.desiredMix, isNull);
      expect(results, [AnalysisEditOutcome.signedOff]);
      expect(dao.analyses.single.needsSignoff, isFalse);
    });

    testWidgets('Sign off and print signs off with a name and no desired mix',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _tx(
            analysedBy: 'Wendy',
            targetO2: null,
            targetHe: null,
            needsSignoff: true),
      ]);
      final results = await _open(tester, dao: dao, canPrint: true);
      await _tapAndSettle(tester, _key('analysis-edit-signoff-print'));

      final (_, edit) = dao.updated.single;
      expect(edit.signOff, isTrue);
      expect(edit.desiredMix, isNull);
      expect(results, [AnalysisEditOutcome.signOffAndPrint]);
    });

    testWidgets('Save on a flagged entry keeps the flag', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [
        _tx(
            analysedBy: null,
            targetO2: null,
            targetHe: null,
            needsSignoff: true),
      ]);
      final results = await _open(tester, dao: dao);
      // Save needs neither a name nor a mix.
      await tester.enterText(_key('analysis-edit-notes'), 'Later');
      await _tapAndSettle(tester, _key('analysis-edit-save'));

      final (_, edit) = dao.updated.single;
      expect(edit.signOff, isFalse);
      expect(edit.notes, 'Later');
      expect(results, [AnalysisEditOutcome.saved]);
      expect(dao.analyses.single.needsSignoff, isTrue);
    });

    testWidgets('Sign off and print is offered only with canPrint',
        (tester) async {
      await _open(tester,
          dao: FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]));
      expect(_key('analysis-edit-signoff'), findsOneWidget);
      expect(_key('analysis-edit-signoff-print'), findsNothing);
    });

    testWidgets('only the two sign-off buttons set the sign-off flag',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]);
      await _open(tester, dao: dao, canPrint: true);
      await _tapAndSettle(tester, _key('analysis-edit-save'));
      expect(dao.updated.single.$2.signOff, isFalse);

      final dao2 = FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]);
      await _open(tester, dao: dao2, canPrint: true);
      await _tapAndSettle(tester, _key('analysis-edit-signoff'));
      expect(dao2.updated.single.$2.signOff, isTrue);

      final dao3 = FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]);
      await _open(tester, dao: dao3, canPrint: true);
      await _tapAndSettle(tester, _key('analysis-edit-signoff-print'));
      expect(dao3.updated.single.$2.signOff, isTrue);
    });

    testWidgets('Sign off and print signs off and returns signOffAndPrint',
        (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]);
      final results = await _open(tester, dao: dao, canPrint: true);
      expect(_key('analysis-edit-signoff-print'), findsOneWidget);
      await _tapAndSettle(tester, _key('analysis-edit-signoff-print'));

      expect(dao.updated.single.$2.signOff, isTrue);
      expect(results, [AnalysisEditOutcome.signOffAndPrint]);
      expect(_sheet, findsNothing);
    });

    testWidgets('Sign off and print needs a name too', (tester) async {
      final dao = FakeGasAnalysesDao(
          analyses: [_tx(analysedBy: null, needsSignoff: true)]);
      await _open(tester, dao: dao, canPrint: true);
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isFalse);
      await tester.enterText(_key('analysis-edit-diver'), 'Wendy');
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isTrue);
    });

    testWidgets('a failed sign-off keeps the sheet open and the flag',
        (tester) async {
      final dao = _FlakyDao(analyses: [_tx(needsSignoff: true)])..fail = true;
      final results = await _open(tester, dao: dao);
      await _tapAndSettle(tester, _key('analysis-edit-signoff'));
      expect(_sheet, findsOneWidget);
      expect(_inSheet(find.textContaining('Save failed')), findsOneWidget);
      expect(results, isEmpty);
      expect(dao.analyses.single.needsSignoff, isTrue);

      dao.fail = false;
      await _tapAndSettle(tester, _key('analysis-edit-signoff'));
      expect(results, [AnalysisEditOutcome.signedOff]);
    });

    testWidgets('the busiest sheet fits a 320 px phone', (tester) async {
      // Flagged, with Sign off and print, a bad pressure and a long
      // cylinder name: every row has to wrap or ellipsize, not overflow.
      final entry = GasAnalysis(
        id: 'long',
        cylinderId: 'c9',
        cylinderLabel: 'A rather long cylinder name for the stage bottle',
        analysedAt: DateTime(2026, 10, 1),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
        needsSignoff: true,
      );
      await _open(tester,
          dao: FakeGasAnalysesDao(analyses: [entry]),
          canPrint: true,
          width: 320);
      await tester.enterText(_key('analysis-edit-pressure'), '21o');
      await tester.pumpAndSettle();
      expect(find.text('Enter a pressure in bar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a double tap on Sign off updates once', (tester) async {
      final dao = FakeGasAnalysesDao(analyses: [_tx(needsSignoff: true)]);
      final results = await _open(tester, dao: dao, canPrint: true);
      final signOff =
          tester.widget<ButtonStyleButton>(_key('analysis-edit-signoff'));
      signOff.onPressed!();
      signOff.onPressed!();
      await tester.pumpAndSettle();
      expect(dao.updated, hasLength(1));
      expect(results, [AnalysisEditOutcome.signedOff]);
    });

    testWidgets('a sheet dismissed mid-write does not pop the page beneath',
        (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Completer<void>();
      final dao = _GatedDao(gate, analyses: [_tx(needsSignoff: true)]);
      final results = <AnalysisEditOutcome>[];
      // A page that opens the sheet, on top of a home page (the analyzer
      // screen over the rest of the app).
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (home) => TextButton(
              onPressed: () => Navigator.of(home).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Builder(
                    builder: (page) => TextButton(
                      onPressed: () async =>
                          results.add(await showAnalysisEditSheet(
                        page,
                        dao: dao,
                        analysis: dao.analyses.first,
                        mixOptions: _options,
                      )),
                      child: const Text('Edit'),
                    ),
                  ),
                ),
              )),
              child: const Text('Home'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Sign off starts the write; it waits on the gate. Then the diver
      // taps outside the sheet.
      tester
          .widget<ButtonStyleButton>(_key('analysis-edit-signoff'))
          .onPressed!();
      await tester.pump();
      await tester.tapAt(const Offset(200, 10));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_sheet, findsOneWidget, reason: 'still sliding out');

      // The write ends while the sheet is still on its way out.
      gate.complete();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_sheet, findsNothing);
      expect(find.text('Edit'), findsOneWidget,
          reason: 'the page beneath is still there');
      expect(find.text('Home'), findsNothing);
      expect(dao.updated, hasLength(1));
      expect(results, [AnalysisEditOutcome.cancelled]);
    });

    testWidgets('while an update is under way no button writes again',
        (tester) async {
      final gate = Completer<void>();
      final dao = _GatedDao(gate, analyses: [_tx(needsSignoff: true)]);
      await _open(tester, dao: dao, canPrint: true);
      final signOff =
          tester.widget<ButtonStyleButton>(_key('analysis-edit-signoff'));
      signOff.onPressed!();
      await tester.pump();
      expect(_enabled(tester, 'analysis-edit-save'), isFalse);
      expect(_enabled(tester, 'analysis-edit-signoff'), isFalse);
      expect(_enabled(tester, 'analysis-edit-signoff-print'), isFalse);
      expect(_enabled(tester, 'analysis-edit-delete'), isFalse);
      expect(_enabled(tester, 'analysis-edit-cancel'), isFalse);
      gate.complete();
      await tester.pumpAndSettle();
      expect(dao.updated, hasLength(1));
    });
  });
}
