import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart' hide DiveAnnotation;
import 'package:ccrlogger/sync/subsurface_git/drift_sync_inputs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diveInputFromRow copies every field the mapper reads', () {
    final row = Dive(
      id: 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      dcSerial: 0xb89641e4,
      dcDiveNumber: 705,
      startTime: 1776591525,
      endTime: 1776591525 + 3450,
      durationSeconds: 3450,
      maxDepthMm: 18000,
      diveMode: 0,
      decoModel: 0,
      gfLow: 50,
      gfHigh: 95,
      atmosphericPressureMbar: 1013,
      waterDensity: 1025,
      logVersion: 17,
      dcModel: 3,
      dcFirmware: 0xa3,
      sampleIntervalMs: 10000,
      gasMixesJson: '',
      sensorCalibrationJson: '[0.021,0.022,0.023]',
      configuredStackSeconds: 25200,
      stackRemainingAtStartSeconds: 10847,
      stackRemainingAtEndSeconds: 7347,
      rawBlob: Uint8List(0),
      parserVersion: 1,
      importedAt: 1776591525,
    );
    final i = diveInputFromRow(row);
    expect(i.id, row.id);
    expect(i.dcSerial, 0xb89641e4);
    expect(i.dcDiveNumber, 705);
    expect(i.startTime, 1776591525);
    expect(i.durationSeconds, 3450);
    expect(i.maxDepthMm, 18000);
    expect(i.diveMode, 0);
    expect(i.dcModel, 3);
    expect(i.dcFirmware, 0xa3);
    expect(i.logVersion, 17);
    expect(i.atmosphericPressureMbar, 1013);
    expect(i.waterDensity, 1025);
    expect(i.gfLow, 50);
    expect(i.gfHigh, 95);
    expect(i.sensorCalibrationJson, '[0.021,0.022,0.023]');
    expect(i.configuredStackSeconds, 25200);
    expect(i.stackRemainingAtStartSeconds, 10847);
    expect(i.stackRemainingAtEndSeconds, 7347);
  });

  test('nullable row fields stay null (VPM-B dive, OC dive, old import)', () {
    final row = Dive(
      id: 'x', dcSerial: 1, dcDiveNumber: 2, startTime: 3, endTime: 4,
      durationSeconds: 1, maxDepthMm: 1, diveMode: 8, decoModel: 1,
      atmosphericPressureMbar: 1013, waterDensity: 1000, logVersion: 17,
      dcModel: 3, sampleIntervalMs: 10000, gasMixesJson: '',
      rawBlob: Uint8List(0), parserVersion: 1, importedAt: 0,
    );
    final i = diveInputFromRow(row);
    expect(i.gfLow, isNull);
    expect(i.gfHigh, isNull);
    expect(i.dcFirmware, isNull);
    expect(i.sensorCalibrationJson, isNull);
    expect(i.configuredStackSeconds, isNull);
    expect(i.stackRemainingAtStartSeconds, isNull);
    expect(i.stackRemainingAtEndSeconds, isNull);
  });

  test('cylinderInputFromRow and diveComputerInputFromRow copy their fields', () {
    final cyl = Cylinder(
      id: 'c', label: 'AL40 stage', role: 'bailout', volumeLiters: 5.7,
      workingPressureBar: 207, createdAt: 0, updatedAt: 0, version: 1, syncStatus: 0,
    );
    final c = cylinderInputFromRow(cyl);
    expect(c.label, 'AL40 stage');
    expect(c.volumeLiters, 5.7);
    expect(c.workingPressureBar, 207);

    final dc = DiveComputer(
      id: 'dc', serial: 0xb89641e4, model: 3, nickname: 'Petrel 3',
      createdAt: 0, updatedAt: 0, version: 1, syncStatus: 0,
    );
    final d = diveComputerInputFromRow(dc);
    expect(d.serial, 0xb89641e4);
    expect(d.model, 3);
    expect(d.nickname, 'Petrel 3');
    expect(diveComputerInputFromRow(DiveComputer(
      id: 'dc2', serial: 7, model: 3, createdAt: 0, updatedAt: 0, version: 1, syncStatus: 0,
    )).nickname, isNull);
  });
}
