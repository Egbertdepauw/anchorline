/// Hand-built dives shaped the way the libdivecomputer mapping will shape
/// them (phase 2), so screens and analysis can be tested without the native
/// library: vendor and product set, a libdivecomputer family, the model
/// stored as `ShearwaterModel.unknown`, log version 0, no calibration and no
/// stack times.
library;

import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart' show dc_family_t;
import 'package:subsurface_core/data/models/dive.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

const int kFixtureFamilyDivesoft = dc_family_t.DC_FAMILY_DIVESOFT_FREEDOM;
const int kFixtureFamilyRatio = dc_family_t.DC_FAMILY_DIVESYSTEM_IDIVE;
const int kFixtureFamilyOstc = dc_family_t.DC_FAMILY_HW_OSTC3;

/// 10 minutes at 10 s per sample.
const int _n = 60;

Float32List _f(double Function(int i) v) =>
    Float32List.fromList([for (var i = 0; i < _n; i++) v(i)]);

double _depth(int i) => i < 5 ? i * 4.0 : (i > 54 ? (59 - i) * 4.0 : 20.0);

SampleSet _samples(
  String id, {
  double ppo2 = 0,
  double setpoint = 0,
  List<Float32List> cellPpo2 = const [],
}) =>
    SampleSet(
      diveId: id,
      sampleCount: _n,
      sampleIntervalMs: 10000,
      depthMeters: _f(_depth),
      temperatureCelsius: _f((_) => 18.0),
      ppo2Bar: _f((_) => ppo2),
      cellMv0: Float32List(_n),
      cellMv1: Float32List(_n),
      cellMv2: Float32List(_n),
      setpointBar: _f((_) => setpoint),
      cns: Float32List(_n),
      decoStopDepthMeters: Float32List(_n),
      decoTimeSeconds: Int32List(_n),
      ttsSeconds: Int32List(_n),
      gasMixIndex: Uint8List(_n),
      statusFlags: Uint8List(_n),
      cellPpo2Bar: cellPpo2,
    );

ConvertedDive _convert({
  required String id,
  required int serial,
  required String vendor,
  required String product,
  required int family,
  required DiveMode mode,
  required int startTime,
  required SampleSet samples,
  required List<DiveGasMix> gases,
}) {
  final start = DateTime.fromMillisecondsSinceEpoch(startTime * 1000,
      isUtc: true);
  return ConvertedDive(
    dive: Dive(
      id: id,
      dcSerial: serial,
      dcDiveNumber: 0,
      startTime: start,
      endTime: start.add(const Duration(minutes: 10)),
      duration: const Duration(minutes: 10),
      maxDepthMeters: 20,
      diveMode: mode,
      decoModel: DecoModel.gf,
      gfLow: 50,
      gfHigh: 80,
      atmosphericPressureMbar: 1013,
      waterDensityKgM3: 1020,
      logVersion: 0,
      dcModel: ShearwaterModel.unknown,
      gasMixes: gases,
      sampleIntervalMs: 10000,
      dcVendor: vendor,
      dcProduct: product,
      dcFamily: family,
    ),
    samples: samples,
  );
}

/// Divesoft Liberty CCR: four per-cell ppO2 channels, mV zero-filled.
ConvertedDive divesoftCcrDive() {
  const id = 'divesoft-ccr-dive-0000000000000001';
  return _convert(
    id: id,
    serial: 1234567,
    vendor: 'Divesoft',
    product: 'Liberty',
    family: kFixtureFamilyDivesoft,
    mode: DiveMode.cc,
    startTime: 1700000000,
    samples: _samples(id, ppo2: 1.3, setpoint: 1.3, cellPpo2: [
      _f((_) => 1.29),
      _f((_) => 1.30),
      _f((_) => 1.31),
      _f((_) => 1.30),
    ]),
    gases: const [
      DiveGasMix(oxygenPercent: 18, heliumPercent: 45, isDiluent: true),
    ],
  );
}

/// Ratio iDive CCR: a setpoint trace and no cells.
ConvertedDive ratioCcrDive() {
  const id = 'ratio-ccr-dive-000000000000000002';
  return _convert(
    id: id,
    serial: 7654321,
    vendor: 'Ratio',
    product: 'iX3M 2021 Tech+',
    family: kFixtureFamilyRatio,
    mode: DiveMode.cc,
    startTime: 1700100000,
    samples: _samples(id, setpoint: 1.2),
    gases: const [
      DiveGasMix(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
    ],
  );
}

/// OSTC open-circuit dive.
ConvertedDive ostcOcDive() {
  const id = 'ostc-oc-dive-00000000000000000003';
  return _convert(
    id: id,
    serial: 23456,
    vendor: 'Heinrichs Weikamp',
    product: 'OSTC 4',
    family: kFixtureFamilyOstc,
    mode: DiveMode.ocTec,
    startTime: 1700200000,
    samples: _samples(id),
    gases: const [
      DiveGasMix(oxygenPercent: 32, heliumPercent: 0, isDiluent: false),
    ],
  );
}
