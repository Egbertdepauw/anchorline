import 'dart:io';
import 'dart:typed_data';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveGasMix, DiveTank;
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:ccrlogger/ui/util/tank_labels.dart';
import 'package:ccrlogger/ui/widgets/profile_chart.dart';
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

void main() {
  testWidgets('ProfileChart renders with real dive data', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {
                      TraceType.ppo2,
                      TraceType.setpoint,
                      TraceType.deco
                    },
                    crosshairIndex: null)))));
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with crosshair', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {TraceType.ppo2},
                    crosshairIndex: 50)))));
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with cells', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {TraceType.ppo2, TraceType.cells},
                    crosshairIndex: null)))));
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with empty traces', (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {},
                    crosshairIndex: null)))));
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with speed-coloured graph on',
      (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: const {},
                    crosshairIndex: null,
                    useSpeedColoredGraph: true)))));
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart renders with speed-coloured graph off',
      (tester) async {
    final samples = _loadSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: const {},
                    crosshairIndex: null,
                    useSpeedColoredGraph: false)))));
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('shows cell label when cellsBySlot is provided', (tester) async {
    final samples = _loadSamples();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cell1 = OxygenCell(
      id: 'c1',
      slot: 1,
      label: 'Top R-22D',
      installedDate: null,
      retiredDate: null,
      notes: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      syncStatus: 0,
    );
    final cell2 = OxygenCell(
      id: 'c2',
      slot: 2,
      label: '',
      installedDate: null,
      retiredDate: null,
      notes: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
      syncStatus: 0,
    );
    final cellsBySlot = {1: cell1, 2: cell2};

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: const {TraceType.cells},
                    crosshairIndex: null,
                    cellsBySlot: cellsBySlot)))));

    expect(find.text('Top R-22D'), findsOneWidget);
    // Empty label falls back to "Slot N".
    expect(find.text('Slot 2'), findsOneWidget);
    // No cell at slot 3 → "—".
    expect(find.text('—'), findsOneWidget);
  });

  test('cellTraceLabelForSlot fallbacks', () {
    expect(cellTraceLabelForSlot(null, 1), '—');
    expect(cellTraceLabelForSlot(const {}, 2), '—');
  });

  testWidgets('renders tank traces and labels them DIL/O2', (tester) async {
    const n = 60;
    final ch0 = Float32List(n);
    final ch1 = Float32List(n);
    for (var i = 0; i < n; i++) {
      ch0[i] = 230.0 - 0.5 * i;
      ch1[i] = 200.0 - 0.7 * i;
    }
    final samples = SampleSet(
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
      tankPressuresBar: [ch0, ch1],
    );
    final tanks = [
      DiveTank(
        slot: 0,
        usage: TankUsage.diluent,
        name: '',
        serial: 0,
        beginPressureBar: 230,
        endPressureBar: 200,
        pressureMaxBar: 300,
        pressureReserveBar: 50,
      ),
      DiveTank(
        slot: 1,
        usage: TankUsage.oxygen,
        name: '',
        serial: 0,
        beginPressureBar: 200,
        endPressureBar: 160,
        pressureMaxBar: 300,
        pressureReserveBar: 40,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: const {TraceType.tanks},
                    crosshairIndex: null,
                    tanks: tanks)))));
    expect(find.byType(ProfileChart), findsOneWidget);
    expect(find.text('DIL'), findsOneWidget);
    expect(find.text('O2'), findsOneWidget);
  });

  test('tankTraceLabelFor maps usage to compact labels', () {
    DiveTank mk(TankUsage u, {int slot = 0}) => DiveTank(
          slot: slot,
          usage: u,
          name: '',
          serial: 0,
          beginPressureBar: 0,
          endPressureBar: 0,
          pressureMaxBar: 0,
          pressureReserveBar: 0,
        );
    expect(tankTraceLabelFor(mk(TankUsage.diluent)), 'DIL');
    expect(tankTraceLabelFor(mk(TankUsage.oxygen)), 'O2');
    expect(tankTraceLabelFor(mk(TankUsage.sidemount)), 'BO');
    expect(tankTraceLabelFor(mk(TankUsage.none, slot: 4)), 'T4');
  });

  testWidgets(
      'ProfileChart with TraceType.density visible builds without error',
      (tester) async {
    const n = 60;
    final depth = Float32List(n);
    final gasMixIdx = Uint8List(n); // all zeros → mix index 0
    for (var i = 0; i < n; i++) {
      depth[i] = i < 10 ? i * 3.0 : (i < 50 ? 30.0 : (60 - i) * 3.0);
    }
    final samples = SampleSet(
      diveId: 'density-test',
      sampleCount: n,
      sampleIntervalMs: 10000,
      depthMeters: depth,
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
      gasMixIndex: gasMixIdx,
      statusFlags: Uint8List(n),
      tankPressuresBar: [],
    );
    final gasMixes = [
      DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
    ];

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {TraceType.density},
                    crosshairIndex: null,
                    gasMixes: gasMixes)))));

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  testWidgets('ProfileChart with TraceType.end visible builds without error',
      (tester) async {
    const n = 60;
    final depth = Float32List(n);
    final gasMixIdx = Uint8List(n);
    for (var i = 0; i < n; i++) {
      depth[i] = i < 10 ? i * 3.0 : (i < 50 ? 30.0 : (60 - i) * 3.0);
    }
    final samples = SampleSet(
      diveId: 'end-test',
      sampleCount: n,
      sampleIntervalMs: 10000,
      depthMeters: depth,
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
      gasMixIndex: gasMixIdx,
      statusFlags: Uint8List(n),
      tankPressuresBar: [],
    );
    final gasMixes = [
      DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
    ];

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: ProfileChart(
                    samples: samples,
                    visibleTraces: {TraceType.end},
                    crosshairIndex: null,
                    gasMixes: gasMixes,
                    endCountsOxygen: false)))));

    expect(tester.takeException(), isNull);
    expect(find.byType(ProfileChart), findsOneWidget);
  });

  test('shouldRepaint detects changes', () {
    final samples = _loadSamples();
    final p1 = ProfileChartPainter(
        samples: samples,
        visibleTraces: {TraceType.ppo2},
        crosshairIndex: null);
    final p2 = ProfileChartPainter(
        samples: samples,
        visibleTraces: {TraceType.ppo2, TraceType.cells},
        crosshairIndex: null);
    final p3 = ProfileChartPainter(
        samples: samples,
        visibleTraces: {TraceType.ppo2},
        crosshairIndex: 10);
    final p4 = ProfileChartPainter(
        samples: samples,
        visibleTraces: {TraceType.ppo2},
        crosshairIndex: null,
        useSpeedColoredGraph: false);
    expect(p1.shouldRepaint(p2), isTrue);
    expect(p1.shouldRepaint(p3), isTrue);
    expect(p1.shouldRepaint(p4), isTrue);
    expect(p1.shouldRepaint(p1), isFalse);
  });
}
