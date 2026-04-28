import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
import 'package:ccrlogger/ui/widgets/crosshair_overlay.dart';
import 'package:ccrlogger/ui/widgets/crosshair_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SampleSet _stubSamples() {
  Float32List f(double v) => Float32List.fromList(List.filled(3, v));
  return SampleSet(
    diveId: 'd1',
    sampleCount: 3,
    sampleIntervalMs: 10000,
    depthMeters: f(5.0),
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
  );
}

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
                width: 300,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {TraceType.cells},
                    chartX: 50,
                    chartWidth: 300,
                    cellsBySlot: cellsBySlot)))));
    expect(find.text('Top R-22D'), findsOneWidget);
    expect(find.text('Slot 2'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('CrosshairTooltip falls back to C1/C2/C3 when no cellsBySlot',
      (tester) async {
    final samples = _stubSamples();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 300,
                height: 200,
                child: CrosshairTooltip(
                    samples: samples,
                    sampleIndex: 1,
                    visibleTraces: const {TraceType.cells},
                    chartX: 50,
                    chartWidth: 300)))));
    expect(find.text('C1'), findsOneWidget);
    expect(find.text('C2'), findsOneWidget);
    expect(find.text('C3'), findsOneWidget);
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
