import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/widgets/cell_data_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _loadSamples() {
  final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  final parsed = parser.parse(data);
  return DiveConverter.convert(
          parsed: parsed,
          dcSerial: 0xB89641E4,
          dcDiveNumber: 718,
          dcModel: ShearwaterModel.petrel3)
      .samples;
}

SampleSet _emptySamples({int n = 30}) => SampleSet(
      diveId: 't',
      sampleCount: n,
      sampleIntervalMs: 10000,
      depthMeters: Float32List(n),
      temperatureCelsius: Float32List(n),
      ppo2Bar: Float32List(n),
      cellMv0: Float32List(n),
      cellMv1: Float32List(n),
      cellMv2: Float32List(n),
      setpointBar: Float32List(n),
      cns: Float32List(n),
      decoStopDepthMeters: Float32List(n),
      decoTimeSeconds: Int32List(n),
      ttsSeconds: Int32List(n),
      gasMixIndex: Uint8List(n),
      statusFlags: Uint8List(n),
      tankPressuresBar: const [],
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 360, height: 240, child: child),
      ),
    );

void main() {
  testWidgets('CellDataChart renders with real CCR dive data',
      (tester) async {
    await tester.pumpWidget(_wrap(CellDataChart(samples: _loadSamples())));
    expect(find.byType(CellDataChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CellDataChart shows an empty-state message when no cell/PPO2 data',
      (tester) async {
    await tester.pumpWidget(_wrap(CellDataChart(samples: _emptySamples())));
    expect(find.textContaining('No cell'), findsOneWidget);
  });

  testWidgets('CellDataChart legend uses physical cell labels when provided',
      (tester) async {
    final n = 30;
    final cellMv = Float32List(n)..fillRange(0, n, 50.0); // ~1.05 bar @ 0.021
    final samples = SampleSet(
      diveId: 't',
      sampleCount: n,
      sampleIntervalMs: 10000,
      depthMeters: Float32List(n),
      temperatureCelsius: Float32List(n),
      ppo2Bar: Float32List(n)..fillRange(0, n, 1.3),
      cellMv0: cellMv,
      cellMv1: Float32List(n)..fillRange(0, n, 48.0),
      cellMv2: Float32List(n)..fillRange(0, n, 52.0),
      setpointBar: Float32List(n)..fillRange(0, n, 1.3),
      cns: Float32List(n),
      decoStopDepthMeters: Float32List(n),
      decoTimeSeconds: Int32List(n),
      ttsSeconds: Int32List(n),
      gasMixIndex: Uint8List(n),
      statusFlags: Uint8List(n),
      tankPressuresBar: const [],
    );
    await tester.pumpWidget(_wrap(CellDataChart(
      samples: samples,
      cellLabels: const {1: 'Top R-22D'},
    )));
    expect(find.text('Top R-22D'), findsOneWidget);
    // Slots without a physical label fall back to "Cell N".
    expect(find.text('Cell 2'), findsOneWidget);
    expect(find.text('PPO2'), findsOneWidget);
    expect(find.text('Setpoint'), findsOneWidget);
  });
}
