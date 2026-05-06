import 'dart:typed_data';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/annotation.dart' as dom;
import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/ui/widgets/dive_tile.dart';
import 'package:ccrlogger/ui/widgets/site_mini_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Dive _makeDive({
  int diveMode = 0,
  int diveNumber = 718,
  int maxDepthMm = 28400,
  int durationSeconds = 3428,
  int? gfLow = 35,
  int? gfHigh = 75,
  int startTime = 1776591525,
}) {
  return Dive(
    id: 'test-dive-id', dcSerial: 123, dcDiveNumber: diveNumber,
    startTime: startTime, endTime: startTime + durationSeconds,
    utcOffsetMinutes: null, durationSeconds: durationSeconds,
    maxDepthMm: maxDepthMm, diveMode: diveMode, decoModel: 0,
    gfLow: gfLow, gfHigh: gfHigh,
    atmosphericPressureMbar: 1013, waterDensity: 1025,
    logVersion: 14, dcModel: 3, dcFirmware: null,
    sampleIntervalMs: 10000,
    gasMixesJson: '[{"o2":21,"he":35,"dil":true}]',
    rawBlob: Uint8List(0), parserVersion: 1, importedAt: 1776591525,
  );
}

void main() {
  testWidgets('DiveTile shows dive number', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiveTile(
        dive: _makeDive(), sparklineData: Float32List.fromList([0, 10, 20, 30, 20, 10, 0]),
        onTap: () {},
      )),
    ));
    expect(find.text('#718'), findsOneWidget);
  });

  testWidgets('DiveTile shows depth', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiveTile(
        dive: _makeDive(), sparklineData: Float32List.fromList([0, 10, 20, 30, 20, 10, 0]),
        onTap: () {},
      )),
    ));
    expect(find.textContaining('28.4m'), findsOneWidget);
  });

  testWidgets('DiveTile shows mode label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiveTile(
        dive: _makeDive(diveMode: DiveMode.ocTec.value),
        sparklineData: Float32List.fromList([0, 10, 20, 10, 0]),
        onTap: () {},
      )),
    ));
    expect(find.text('OC'), findsOneWidget);
  });

  testWidgets('DiveTile renders without sparkline data', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiveTile(
        dive: _makeDive(), sparklineData: null, onTap: () {},
      )),
    ));
    expect(find.byType(DiveTile), findsOneWidget);
  });

  testWidgets('DiveTile shows mini map when annotation has coords',
      (tester) async {
    final now = DateTime.now();
    final ann = dom.DiveAnnotation(
      diveId: 'test-dive-id',
      siteLatitude: 51.5,
      siteLongitude: 3.7,
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiveTile(
        dive: _makeDive(),
        sparklineData: Float32List.fromList([0, 10, 0]),
        annotation: ann,
        onTap: () {},
      )),
    ));
    expect(find.byType(SiteMiniMap), findsOneWidget);
  });

  testWidgets('DiveTile omits mini map when annotation lacks coords',
      (tester) async {
    final now = DateTime.now();
    final ann = dom.DiveAnnotation(
      diveId: 'test-dive-id',
      siteName: 'Some Site',
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DiveTile(
        dive: _makeDive(),
        sparklineData: Float32List.fromList([0, 10, 0]),
        annotation: ann,
        onTap: () {},
      )),
    ));
    expect(find.byType(SiteMiniMap), findsNothing);
  });
}
