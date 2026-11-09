// Checks that planner labels fit at phone widths, measured with the app's
// own fonts (#183): the segment row's gas dropdown showed "Tx1" for
// Tx18/45, and the plan table cut "→ surface" and the VOL header.
import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/data/models/dive.dart';
import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:ccrlogger/ui/widgets/plan_segments_editor.dart';
import 'package:ccrlogger/ui/widgets/stop_ladder_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Card content width on a 390 pt and a 375 pt phone: screen padding 12 +
// card padding 12 on each side, plus the 3 pt accent border.
const _contentWidths = [339.0, 324.0];

const _tx1845 =
    DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true);
const _ean50 =
    DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);

Future<void> _pumpAtWidth(WidgetTester tester, double width, Widget child) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    ));

Iterable<RenderParagraph> _paragraphs(WidgetTester tester, Finder of) =>
    tester
        .renderObjectList<RenderParagraph>(
            find.descendant(of: of, matching: find.byType(RichText)))
        .where((p) => p.text.toPlainText().isNotEmpty);

void main() {
  setUpAll(() async {
    for (final (family, file) in [
      ('Inter', 'fonts/Inter-VariableFont.ttf'),
      ('JetBrainsMono', 'fonts/JetBrainsMono-VariableFont.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(file))).load();
    }
  });

  for (final width in _contentWidths) {
    testWidgets('the plan table fits every cell at $width pt', (tester) async {
      const stops = [
        AscentStop(
            depthStartMeters: 0,
            depthEndMeters: 120,
            duration: Duration(minutes: 7),
            gas: _tx1845,
            volumeLitresConsumed: 90,
            setpointBar: 1.3),
        AscentStop(
            depthStartMeters: 120,
            depthEndMeters: 120,
            duration: Duration(minutes: 30),
            gas: _tx1845,
            volumeLitresConsumed: 1234,
            setpointBar: 1.3),
        AscentStop(
            depthStartMeters: 21,
            depthEndMeters: 21,
            duration: Duration(minutes: 80),
            gas: _ean50,
            volumeLitresConsumed: 400),
        AscentStop(
            depthStartMeters: 6,
            depthEndMeters: 0,
            duration: Duration(minutes: 1),
            gas: _ean50,
            volumeLitresConsumed: 20),
      ];
      await _pumpAtWidth(
        tester,
        width,
        StopLadderTable(stops: stops, scheme: ThemeData.dark().colorScheme),
      );

      expect(find.text('VOL'), findsOneWidget);
      expect(find.text('→ 0 m'), findsOneWidget);
      expect(find.text('→ surface'), findsNothing);
      final clipped = [
        for (final p in _paragraphs(tester, find.byType(StopLadderTable)))
          if (p.debugHasOverflowShader) p.text.toPlainText(),
      ];
      expect(clipped, isEmpty, reason: 'cells faded out: $clipped');
    });

    testWidgets('the segment row shows the whole gas name at $width pt',
        (tester) async {
      await _pumpAtWidth(
        tester,
        width,
        PlanSegmentsEditor(
          gases: const [
            DivePlanGas(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
          ],
          segments: const [
            DivePlanSegment(
                depthMeters: 55,
                durationMinutes: 120,
                gasMixIndex: 0,
                setpoint: 1.3),
          ],
          onAdd: (_) {},
          onRemove: (_) {},
          onReplace: (_, _) {},
          onReorder: (_, _) {},
          mode: DivePlanMode.cc,
        ),
      );

      final gasLabels = _paragraphs(tester, find.byType(DropdownButton<int>))
          .where((p) => p.text.toPlainText() == 'Tx18/45')
          .toList();
      expect(gasLabels, isNotEmpty);
      for (final p in gasLabels) {
        expect(p.didExceedMaxLines, isFalse,
            reason: 'Tx18/45 is cut off at $width pt');
      }
    });
  }
}
