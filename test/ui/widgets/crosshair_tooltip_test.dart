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
}
