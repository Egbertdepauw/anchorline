import 'dart:typed_data';
import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:ccrlogger/ui/widgets/tissue_saturation_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DecoReplayResult _stubReplay({
  required int samples,
  double saturation = 50, // % across all compartments and samples
}) {
  final pct = List<Float32List>.generate(
    16,
    (_) => Float32List(samples)..fillRange(0, samples, saturation),
  );
  return DecoReplayResult(
    gf99Series: Float32List(samples),
    ceilingMeters: Float32List(samples),
    tissueLoadsPct: pct,
    surfaceGfFinal: 0,
    maxGf99: 0,
    algorithm: DecoAlgorithm.zhl16c,
    gfLow: 30,
    gfHigh: 85,
  );
}

void main() {
  testWidgets('renders without exception for valid replay input',
      (tester) async {
    final replay = _stubReplay(samples: 100, saturation: 50);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TissueSaturationHeatmap(replay: replay),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byType(TissueSaturationHeatmap), findsOneWidget);
  });

  testWidgets('respects custom height', (tester) async {
    final replay = _stubReplay(samples: 50);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TissueSaturationHeatmap(replay: replay, height: 128),
      ),
    ));
    final size = tester.getSize(find.byType(TissueSaturationHeatmap));
    expect(size.height, 128);
  });

  testWidgets('handles empty sample count gracefully', (tester) async {
    final replay = _stubReplay(samples: 0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TissueSaturationHeatmap(replay: replay),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  test('saturationColour band thresholds match spec', () {
    expect(tissueSaturationColour(60), const Color(0xFF3B82F6)); // blue
    expect(tissueSaturationColour(80), const Color(0xFFFACC15)); // yellow
    expect(tissueSaturationColour(97), const Color(0xFFF97316)); // orange
    expect(tissueSaturationColour(120), const Color(0xFFDC2626)); // red
  });
}
