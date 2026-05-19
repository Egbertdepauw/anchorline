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

  test('saturationColour hits anchor stops exactly', () {
    // Anchor stops should pass through unchanged.
    expect(tissueSaturationColour(0), const Color(0xFF1E3A8A));
    expect(tissueSaturationColour(40), const Color(0xFF3B82F6));
    expect(tissueSaturationColour(70), const Color(0xFF06B6D4));
    expect(tissueSaturationColour(85), const Color(0xFF22C55E));
    expect(tissueSaturationColour(95), const Color(0xFFFACC15));
    expect(tissueSaturationColour(100), const Color(0xFFF97316));
    expect(tissueSaturationColour(115), const Color(0xFFDC2626));
  });

  test('saturationColour clamps outside the ramp', () {
    expect(tissueSaturationColour(-20), const Color(0xFF1E3A8A));
    expect(tissueSaturationColour(140), const Color(0xFFDC2626));
  });

  test('saturationColour interpolates linearly between stops', () {
    // Midpoint between green (85%) and yellow (95%) should equal
    // Color.lerp of those two at t=0.5.
    final mid = tissueSaturationColour(90);
    final expected = Color.lerp(
      const Color(0xFF22C55E),
      const Color(0xFFFACC15),
      0.5,
    )!;
    expect(mid, expected);
  });
}
