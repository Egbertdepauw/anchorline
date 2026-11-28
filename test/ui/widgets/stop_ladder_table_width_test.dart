// The plan table at 402 pt (iPhone 17): four-digit VOL values and the final
// ascent row must not be cut off (columns were resized in #185). Also checks
// the profile chart's "min" unit stays clear of the time tick labels (#275).
import 'package:ccrlogger/analysis/bailout/ascent_simulator.dart';
import 'package:ccrlogger/ui/widgets/dive_profile_chart.dart';
import 'package:ccrlogger/ui/widgets/stop_ladder_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/data/models/dive.dart';

const _tx1845 =
    DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true);
const _ean50 =
    DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false);

void main() {
  setUpAll(() async {
    for (final (family, file) in [
      ('Inter', 'fonts/Inter-VariableFont.ttf'),
      ('JetBrainsMono', 'fonts/JetBrainsMono-VariableFont.ttf'),
    ]) {
      await (FontLoader(family)..addFont(rootBundle.load(file))).load();
    }
  });

  testWidgets('four-digit volumes and the final ascent fit at 402 pt',
      (tester) async {
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
          volumeLitresConsumed: 1605,
          setpointBar: 1.3),
      AscentStop(
          depthStartMeters: 21,
          depthEndMeters: 21,
          duration: Duration(minutes: 80),
          gas: _ean50,
          volumeLitresConsumed: 1234),
      AscentStop(
          depthStartMeters: 6,
          depthEndMeters: 0,
          duration: Duration(minutes: 1),
          gas: _ean50,
          volumeLitresConsumed: 20),
    ];
    // Card content width on 402 pt: 12 + 12 padding on each side, 3 border.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: 402 - 27,
              child: StopLadderTable(
                  stops: stops, scheme: ThemeData.dark().colorScheme),
            ),
          ),
        ),
      ),
    ));

    expect(find.text('VOL'), findsOneWidget);
    expect(find.text('→ 0 m'), findsOneWidget);
    for (final v in ['1605', '1234']) {
      expect(find.textContaining(v), findsWidgets, reason: '$v missing');
    }
    final paragraphs = tester
        .renderObjectList<RenderParagraph>(find.descendant(
            of: find.byType(StopLadderTable), matching: find.byType(RichText)))
        .where((p) => p.text.toPlainText().isNotEmpty);
    final clipped = [
      for (final p in paragraphs)
        if (p.debugHasOverflowShader || p.didExceedMaxLines)
          p.text.toPlainText(),
    ];
    expect(clipped, isEmpty, reason: 'cells cut off: $clipped');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the chart "min" unit sits left of the first tick label',
      (tester) async {
    final unit = TextPainter(
      text: const TextSpan(
          text: 'min', style: TextStyle(fontFamily: 'Inter', fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    final tick = TextPainter(
      text: const TextSpan(
          text: '0',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    const left = 36.0;
    final o = timeUnitOffset(left, 100, unit.width);
    final unitRect = o & unit.size;
    final firstTick =
        Offset(left - tick.width / 2, 104) & tick.size;
    expect(unitRect.overlaps(firstTick), isFalse);
    expect(unitRect.left, greaterThanOrEqualTo(0));
    // The chart itself still renders.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DiveProfileChart(legs: [
          AscentStop(
              depthStartMeters: 0,
              depthEndMeters: 40,
              duration: Duration(minutes: 50),
              gas: _ean50,
              volumeLitresConsumed: 100),
        ]),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
