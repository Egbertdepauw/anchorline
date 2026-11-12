import 'dart:typed_data';

import 'package:ccrlogger/analysis/deco/replay_result.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:ccrlogger/ui/widgets/crosshair_tooltip.dart';
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _f(List<double> v) => Float32List.fromList(v);

/// index 0 = in deco (6 m stop, 12 min, TTS 23 min, ceiling 5.4, GF99 84);
/// index 1 = NDL (18 min, TTS 2 min, GF99 40).
SampleSet _samples() => SampleSet(
      diveId: 'test',
      sampleCount: 2,
      sampleIntervalMs: 10000,
      depthMeters: _f([21.0, 9.0]),
      temperatureCelsius: _f([11.4, 12.0]),
      ppo2Bar: _f([1.30, 1.10]),
      cellMv0: _f([50, 50]),
      cellMv1: _f([50, 50]),
      cellMv2: _f([50, 50]),
      setpointBar: _f([1.30, 1.10]),
      cns: _f([0.1, 0.1]),
      decoStopDepthMeters: _f([6.0, 0.0]),
      decoTimeSeconds: Int32List.fromList([720, 1080]),
      ttsSeconds: Int32List.fromList([1380, 120]),
      gasMixIndex: Uint8List.fromList([0, 0]),
      statusFlags: Uint8List.fromList([0, 0]),
    );

DecoReplayResult _replay() => DecoReplayResult(
      gf99Series: _f([84, 40]),
      ceilingMeters: _f([5.4, 0.0]),
      tissueLoadsPct: const <Float32List>[],
      surfaceGfFinal: 40,
      maxGf99: 84,
      algorithm: DecoAlgorithm.zhl16c,
      gfHigh: 85,
    );

/// Merged-dive style: NaN at index 1 (surface gap) + non-finite GF99.
SampleSet _nanSamples() => SampleSet(
      diveId: 'merged',
      sampleCount: 2,
      sampleIntervalMs: 10000,
      depthMeters: _f([10.0, double.nan]),
      temperatureCelsius: _f([10.0, double.nan]),
      ppo2Bar: _f([1.0, double.nan]),
      cellMv0: _f([50, 50]),
      cellMv1: _f([50, 50]),
      cellMv2: _f([50, 50]),
      setpointBar: _f([1.0, double.nan]),
      cns: _f([0.1, 0.1]),
      decoStopDepthMeters: _f([0.0, 0.0]),
      decoTimeSeconds: Int32List.fromList([0, 0]),
      ttsSeconds: Int32List.fromList([0, 0]),
      gasMixIndex: Uint8List.fromList([0, 0]),
      statusFlags: Uint8List.fromList([0, 0]),
    );

DecoReplayResult _nanReplay() => DecoReplayResult(
      gf99Series: _f([double.nan, double.infinity]),
      ceilingMeters: _f([0.0, 0.0]),
      tissueLoadsPct: const <Float32List>[],
      surfaceGfFinal: 0,
      maxGf99: 0,
      algorithm: DecoAlgorithm.zhl16c,
      gfHigh: 85,
    );

/// Wide chart (>= 520) -> vertical list layout.
Future<void> _pumpList(WidgetTester tester, int index) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CrosshairTooltip(
        samples: _samples(),
        sampleIndex: index,
        visibleTraces: const <TraceType>{},
        chartX: 10,
        chartWidth: 800,
        decoReplay: _replay(),
      ),
    ),
  ));
}

/// Narrow chart (< 520) -> compact two-tier layout.
Future<void> _pumpCompact(
    WidgetTester tester, int index, Set<TraceType> traces) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 600,
        child: CrosshairTooltip(
          samples: _samples(),
          sampleIndex: index,
          visibleTraces: traces,
          chartX: 10,
          chartWidth: 360,
          decoReplay: _replay(),
        ),
      ),
    ),
  ));
}

void main() {
  group('wide (vertical list)', () {
    testWidgets('in deco: shows Stop, Stop time, TTS, Ceiling, GF99',
        (tester) async {
      await _pumpList(tester, 0);
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
      await _pumpList(tester, 1);
      expect(find.text('NDL'), findsOneWidget);
      expect(find.text('18 min'), findsOneWidget);
      expect(find.text('TTS'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Ceiling'), findsNothing);
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
            chartWidth: 800,
            // decoReplay intentionally omitted (null)
          ),
        ),
      ));
      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('TTS'), findsOneWidget);
      expect(find.text('GF99'), findsNothing);
      expect(find.text('Ceiling'), findsNothing);
    });

    testWidgets('sizes to content width, not the full chart width',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: CrosshairTooltip(
              samples: _samples(),
              sampleIndex: 0,
              visibleTraces: const <TraceType>{},
              chartX: 10,
              chartWidth: 800,
              decoReplay: _replay(),
            ),
          ),
        ),
      ));
      final w = tester
          .getSize(find.byKey(const ValueKey('crosshairTooltipBox')))
          .width;
      expect(w, lessThan(400));
    });

    testWidgets('does not throw on non-finite sample values', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CrosshairTooltip(
            samples: _nanSamples(),
            sampleIndex: 1,
            visibleTraces: const <TraceType>{},
            chartX: 10,
            chartWidth: 800,
            decoReplay: _nanReplay(),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('compact (two-tier readout)', () {
    testWidgets('header shows depth + time; no chips when no traces on',
        (tester) async {
      await _pumpCompact(tester, 0, const <TraceType>{});
      expect(find.byKey(const ValueKey('crosshairTooltipBoxCompact')),
          findsOneWidget);
      expect(find.textContaining('21.0'), findsOneWidget); // depth header
      expect(find.text('0:10'), findsOneWidget); // time at index 0
      expect(find.textContaining('PPO2'), findsNothing);
      expect(find.textContaining('Stop'), findsNothing);
      expect(find.textContaining('GF99'), findsNothing);
    });

    testWidgets('chips appear for visible traces (in deco)', (tester) async {
      await _pumpCompact(tester, 0, const {
        TraceType.ppo2,
        TraceType.deco,
        TraceType.ceiling,
        TraceType.gf99,
      });
      expect(find.textContaining('PPO2'), findsOneWidget);
      expect(find.textContaining('Stop'), findsOneWidget); // "Stop 6.0 m · 12 min"
      expect(find.textContaining('12 min'), findsOneWidget);
      expect(find.textContaining('TTS'), findsOneWidget); // "TTS 23 min"
      expect(find.textContaining('Ceil'), findsOneWidget); // "Ceil 5.4 m"
      expect(find.textContaining('GF99'), findsOneWidget); // "GF99 84%"
      expect(find.textContaining('SP '), findsNothing); // setpoint not on
    });

    testWidgets('box stays short and narrow on a phone-width chart',
        (tester) async {
      await _pumpCompact(tester, 0, const {
        TraceType.ppo2,
        TraceType.setpoint,
        TraceType.deco,
        TraceType.ceiling,
        TraceType.gf99,
      });
      final size = tester
          .getSize(find.byKey(const ValueKey('crosshairTooltipBoxCompact')));
      expect(size.width, lessThanOrEqualTo(240)); // bounded (~maxW)
      expect(size.height, lessThan(180)); // the point: not full chart height
    });

    testWidgets('does not throw on non-finite sample values', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 600,
            child: CrosshairTooltip(
              samples: _nanSamples(),
              sampleIndex: 1,
              visibleTraces: const {TraceType.deco, TraceType.gf99},
              chartX: 10,
              chartWidth: 360,
              decoReplay: _nanReplay(),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
