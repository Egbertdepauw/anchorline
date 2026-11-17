import 'dart:io';
import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:subsurface_core/data/models/dive.dart' as model;
import 'package:subsurface_core/subsurface_core.dart' show ConvertedDive;

/// A real, anonymised Garmin Descent Mk1 CCR dive from the fit_reader
/// fixtures.
const kFitFixture = 'garmin_mk1_ccr_2023-08-17.fit';

Uint8List fitFixtureBytes([String name = kFitFixture]) =>
    File('packages/fit_reader/test/fixtures/$name').readAsBytesSync();

/// The raw blob an import stores for [fit].
Uint8List fitBlob([Uint8List? fit, String name = 'dive.fit']) =>
    FitEnvelope(
      source: FitSource.file,
      fileName: name,
      fit: fit ?? fitFixtureBytes(),
    ).encode();

ConvertedDive fitDive([String name = kFitFixture]) =>
    mapFitFile(fitFixtureBytes(name)).single;

/// [c] with some fields substituted; samples and events are kept.
/// [asSubsurfaceCopy] drops what only a download has (family, fingerprint,
/// model code), as a Subsurface Cloud copy of the dive carries it.
ConvertedDive rebuildFit(
  ConvertedDive c, {
  String? id,
  int shiftSeconds = 0,
  int? number,
  double? maxDepth,
  String? fingerprint,
  int? family,
  bool asSubsurfaceCopy = false,
}) {
  final d = c.dive;
  final shift = Duration(seconds: shiftSeconds);
  return ConvertedDive(
    dive: model.Dive(
      id: id ?? d.id,
      dcSerial: d.dcSerial,
      dcDiveNumber: number ?? d.dcDiveNumber,
      startTime: d.startTime.add(shift),
      endTime: d.endTime.add(shift),
      utcOffsetMinutes: d.utcOffsetMinutes,
      duration: d.duration,
      maxDepthMeters: maxDepth ?? d.maxDepthMeters,
      diveMode: d.diveMode,
      decoModel: d.decoModel,
      gfLow: d.gfLow,
      gfHigh: d.gfHigh,
      atmosphericPressureMbar: d.atmosphericPressureMbar,
      waterDensityKgM3: d.waterDensityKgM3,
      logVersion: d.logVersion,
      dcModel: d.dcModel,
      gasMixes: d.gasMixes,
      tanks: d.tanks,
      sampleIntervalMs: d.sampleIntervalMs,
      sensorCalibration: d.sensorCalibration,
      dcVendor: d.dcVendor,
      dcProduct: d.dcProduct,
      dcFamily: asSubsurfaceCopy ? null : (family ?? d.dcFamily),
      dcModelCode: asSubsurfaceCopy ? null : d.dcModelCode,
      dcFingerprint: asSubsurfaceCopy ? null : (fingerprint ?? d.dcFingerprint),
    ),
    samples: c.samples,
    events: c.events,
  );
}
