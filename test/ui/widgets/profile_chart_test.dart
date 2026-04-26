import 'dart:io';
import 'package:ccrlogger/data/models/sample_set.dart';
import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/ui/notifiers/dive_detail_notifier.dart';
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
    expect(p1.shouldRepaint(p2), isTrue);
    expect(p1.shouldRepaint(p3), isTrue);
    expect(p1.shouldRepaint(p1), isFalse);
  });
}
