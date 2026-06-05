import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/dive.dart' show DiveTank;
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/parsed_dive.dart' show TankUsage;
import 'package:ccrlogger/ui/widgets/trace_segmented_bar.dart' show TraceType;
import 'package:ccrlogger/ui/widgets/crosshair_overlay.dart';
import 'package:ccrlogger/ui/widgets/crosshair_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _stubSamples({
  Float32List? depth,
  List<Float32List> tankPressuresBar = const [],
}) {
  Float32List f(double v) => Float32List.fromList(List.filled(3, v));
  return SampleSet(
    diveId: 'd1',
    sampleCount: 3,
    sampleIntervalMs: 10000,
    depthMeters: depth ?? f(5.0),
    temperatureCelsius: f(20.0),
    ppo2Bar: f(1.0),
    cellMv0: f(50.0),
    cellMv1: f(48.0),
    cellMv2: f(47.0),
    setpointBar: f(1.3),
    cns: f(0.0),
    decoStopDepthMeters: f(0.0),
    decoTimeSeconds: Int32List.fromList([0, 0, 0]),
    ttsSeconds: Int32List.fromList([0, 0, 0]),
    gasMixIndex: Uint8List.fromList([0, 0, 0]),
    statusFlags: Uint8List.fromList([0, 0, 0]),
    tankPressuresBar: tankPressuresBar,
  );
}

DiveTank _tank(int slot, TankUsage usage) => DiveTank(
      slot: slot,
      usage: usage,
      name: '',
      serial: 0,
      beginPressureBar: 0,
      endPressureBar: 0,
      pressureMaxBar: 300,
      pressureReserveBar: 50,
    );

OxygenCell _cell(int slot, String? label) => OxygenCell(
      id: 'c$slot',
      slot: slot,
      label: label,
      createdAt: 0,
      updatedAt: 0,
      version: 1,
      syncStatus: 0,
    );

void main() {
  testWidgets('renders child widget', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CrosshairOverlay(
                sampleCount: 100,
                chartLeftPad: 40,
                chartRightPad: 44,
                onIndexChanged: (_) {},
                onRelease: () {},
                child: const SizedBox(width: 360, height: 250)))));
    expect(find.byType(CrosshairOverlay), findsOneWidget);
  });

  testWidgets('CrosshairTooltip shows cell label when cellsBySlot is provided',
      (tester) async {
    final samples = _stubSamples();
    final cellsBySlot = {
      1: _cell(1, 'Top R-22D'),
      2: _cell(2, ''),
      // slot 3 absent → "—"
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 800,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {TraceType.cells},
                    chartX: 50,
                    chartWidth: 800,
                    cellsBySlot: cellsBySlot)))));
    expect(find.text('Top R-22D'), findsOneWidget);
    expect(find.text('Slot 2'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('CrosshairTooltip shows instantaneous descent rate',
      (tester) async {
    // 10s interval, depth 0 → 3 → 6 m/sample → 18 m/min descent.
    final samples = _stubSamples(
        depth: Float32List.fromList([0.0, 3.0, 6.0]));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 800,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {},
                    chartX: 50,
                    chartWidth: 800)))));
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('↓ 18 m/min'), findsOneWidget);
  });

  testWidgets('CrosshairTooltip falls back to C1/C2/C3 when no cellsBySlot',
      (tester) async {
    final samples = _stubSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 800,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {TraceType.cells},
                    chartX: 50,
                    chartWidth: 800)))));
    expect(find.text('C1'), findsOneWidget);
    expect(find.text('C2'), findsOneWidget);
    expect(find.text('C3'), findsOneWidget);
  });

  testWidgets('CrosshairTooltip shows per-tank pressures at hovered sample',
      (tester) async {
    final samples = _stubSamples(tankPressuresBar: [
      Float32List.fromList([0.0, 165.0, 160.0]),
      Float32List.fromList([0.0, 140.0, 138.0]),
    ]);
    final tanks = [_tank(0, TankUsage.diluent), _tank(1, TankUsage.oxygen)];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 800,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {},
                    chartX: 50,
                    chartWidth: 800,
                    tanks: tanks)))));
    expect(find.text('DIL'), findsOneWidget);
    expect(find.text('165 bar'), findsOneWidget);
    expect(find.text('O2'), findsOneWidget);
    expect(find.text('140 bar'), findsOneWidget);
  });

  testWidgets('CrosshairTooltip hides tanks section when all tanks read zero',
      (tester) async {
    final samples = _stubSamples(tankPressuresBar: [
      Float32List.fromList([0.0, 0.0, 0.0]),
    ]);
    final tanks = [_tank(0, TankUsage.diluent)];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 800,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {},
                    chartX: 50,
                    chartWidth: 800,
                    tanks: tanks)))));
    expect(find.text('DIL'), findsNothing);
  });

  testWidgets('long press triggers callback', (tester) async {
    int? reportedIndex;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 360,
                height: 250,
                child: CrosshairOverlay(
                    sampleCount: 100,
                    chartLeftPad: 40,
                    chartRightPad: 44,
                    onIndexChanged: (i) => reportedIndex = i,
                    onRelease: () {},
                    child: Container(color: Colors.black))))));
    final center = tester.getCenter(find.byType(CrosshairOverlay));
    await tester.longPressAt(center);
    await tester.pump();
    expect(reportedIndex, isNotNull);
    expect(reportedIndex, greaterThanOrEqualTo(0));
    expect(reportedIndex, lessThan(100));
  });
}
