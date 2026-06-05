import 'dart:typed_data';

import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/ui/widgets/crosshair_tooltip.dart';
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _samples() {
  Float32List f(List<double> v) => Float32List.fromList(v);
  return SampleSet(
    diveId: 'test',
    sampleCount: 2,
    sampleIntervalMs: 10000,
    depthMeters: f([21.0, 9.0]),
    temperatureCelsius: f([11.4, 12.0]),
    ppo2Bar: f([1.30, 1.10]),
    cellMv0: f([50, 50]),
    cellMv1: f([50, 50]),
    cellMv2: f([50, 50]),
    setpointBar: f([1.30, 1.10]),
    cns: f([0.1, 0.1]),
    // index 0 = in deco; index 1 = NDL.
    decoStopDepthMeters: f([6.0, 0.0]),
    decoTimeSeconds: Int32List.fromList([720, 1080]), // 12 min stop / 18 min NDL
    ttsSeconds: Int32List.fromList([1380, 120]), // 23 min / 2 min
    gasMixIndex: Uint8List.fromList([0, 0]),
    statusFlags: Uint8List.fromList([0, 0]),
  );
}

DecoReplayResult _replay() => DecoReplayResult(
      gf99Series: Float32List.fromList([84, 40]),
      ceilingMeters: Float32List.fromList([5.4, 0.0]),
      tissueLoadsPct: const <Float32List>[],
      surfaceGfFinal: 40,
      maxGf99: 84,
      algorithm: DecoAlgorithm.zhl16c,
      gfHigh: 85,
    );

Future<void> _pump(WidgetTester tester, int index) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CrosshairTooltip(
        samples: _samples(),
        sampleIndex: index,
        visibleTraces: const <TraceType>{},
        chartX: 10,
        chartWidth: 300,
        decoReplay: _replay(),
      ),
    ),
  ));
}

void main() {
  testWidgets('in deco: shows Stop, Stop time, TTS, Ceiling, GF99',
      (tester) async {
    await _pump(tester, 0);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('6.0m'), findsOneWidget);
    expect(find.text('Stop time'), findsOneWidget);
    expect(find.text('12 min'), findsOneWidget);
    expect(find.text('TTS'), findsOneWidget);
    expect(find.text('23 min'), findsOneWidget);
    expect(find.text('Ceiling'), findsOneWidget);
    expect(find.text('5.4m'), findsOneWidget);
    expect(find.text('GF99'), findsOneWidget);
    expect(find.text('84%'), findsOneWidget);
    expect(find.text('NDL'), findsNothing);
  });

  testWidgets('out of deco: shows NDL, hides Stop and Ceiling',
      (tester) async {
    await _pump(tester, 1);
    expect(find.text('NDL'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('TTS'), findsOneWidget);
    expect(find.text('2 min'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.text('Ceiling'), findsNothing); // ceiling 0 -> hidden
    expect(find.text('GF99'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('without decoReplay: DC deco rows show, GF99/Ceiling do not',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CrosshairTooltip(
          samples: _samples(),
          sampleIndex: 0,
          visibleTraces: const <TraceType>{},
          chartX: 10,
          chartWidth: 300,
          // decoReplay intentionally omitted (null)
        ),
      ),
    ));
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('TTS'), findsOneWidget);
    expect(find.text('GF99'), findsNothing);
    expect(find.text('Ceiling'), findsNothing);
  });

  testWidgets('does not throw on non-finite sample values (merged-dive gaps)',
      (tester) async {
    Float32List f(List<double> v) => Float32List.fromList(v);
    final samples = SampleSet(
      diveId: 'merged',
      sampleCount: 2,
      sampleIntervalMs: 10000,
      depthMeters: f([10.0, double.nan]), // NaN depth -> NaN vertical rate
      temperatureCelsius: f([10.0, double.nan]),
      ppo2Bar: f([1.0, double.nan]),
      cellMv0: f([50, 50]),
      cellMv1: f([50, 50]),
      cellMv2: f([50, 50]),
      setpointBar: f([1.0, double.nan]),
      cns: f([0.1, 0.1]),
      decoStopDepthMeters: f([0.0, 0.0]),
      decoTimeSeconds: Int32List.fromList([0, 0]),
      ttsSeconds: Int32List.fromList([0, 0]),
      gasMixIndex: Uint8List.fromList([0, 0]),
      statusFlags: Uint8List.fromList([0, 0]),
    );
    final replay = DecoReplayResult(
      gf99Series: f([double.nan, double.infinity]), // non-finite GF99
      ceilingMeters: f([0.0, 0.0]),
      tissueLoadsPct: const <Float32List>[],
      surfaceGfFinal: 0,
      maxGf99: 0,
      algorithm: DecoAlgorithm.zhl16c,
      gfHigh: 85,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CrosshairTooltip(
          samples: samples,
          sampleIndex: 1,
          visibleTraces: const <TraceType>{},
          chartX: 10,
          chartWidth: 300,
          decoReplay: replay,
        ),
      ),
    ));
    // Must not throw "Infinity or NaN toInt".
    expect(tester.takeException(), isNull);
    // Rate falls back to em-dash; the non-finite GF99 row is omitted.
    expect(find.text('—'), findsOneWidget);
    expect(find.text('GF99'), findsNothing);
  });

  testWidgets('tooltip sizes to content width, not the full chart width',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: CrosshairTooltip(
            samples: _samples(),
            sampleIndex: 0, // in deco -> includes the divider row
            visibleTraces: const <TraceType>{},
            chartX: 10,
            chartWidth: 800,
            decoReplay: _replay(),
          ),
        ),
      ),
    ));
    final boxWidth = tester
        .getSize(find.byKey(const ValueKey('crosshairTooltipBox')))
        .width;
    // Content-sized, nowhere near the 800px parent: regression guard for the
    // full-width divider stretch.
    expect(boxWidth, lessThan(400));
  });
}
