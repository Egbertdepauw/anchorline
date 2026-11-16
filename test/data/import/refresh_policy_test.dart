import 'dart:typed_data';

import 'package:ccrlogger/data/import/refresh_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/data/models/dive.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

ConvertedDive _converted({required int samples, required Duration duration}) {
  final start = DateTime.utc(2026, 1, 1);
  return ConvertedDive(
    dive: Dive(
      id: 'd',
      dcSerial: 1,
      dcDiveNumber: 1,
      startTime: start,
      endTime: start.add(duration),
      duration: duration,
      maxDepthMeters: 10,
      diveMode: DiveMode.cc,
      decoModel: DecoModel.gf,
      gfLow: 30,
      gfHigh: 70,
      atmosphericPressureMbar: 1013,
      waterDensityKgM3: 1025,
      logVersion: 1,
      dcModel: ShearwaterModel.petrel3,
      gasMixes: const [],
      sampleIntervalMs: 10000,
    ),
    samples: SampleSet(
      diveId: 'd',
      sampleCount: samples,
      sampleIntervalMs: 10000,
      depthMeters: Float32List(samples),
      temperatureCelsius: Float32List(samples),
      ppo2Bar: Float32List(samples),
      cellMv0: Float32List(samples),
      cellMv1: Float32List(samples),
      cellMv2: Float32List(samples),
      setpointBar: Float32List(samples),
      cns: Float32List(samples),
      decoStopDepthMeters: Float32List(samples),
      decoTimeSeconds: Int32List(samples),
      ttsSeconds: Int32List(samples),
      gasMixIndex: Uint8List(samples),
      statusFlags: Uint8List(samples),
    ),
  );
}

void main() {
  group('refreshMayWrite', () {
    test('a Subsurface copy is always refreshed', () {
      expect(
        refreshMayWrite(
          storedVersion: -1,
          storedIsLibdc: false,
          incomingVersion: 1,
          incomingIsLibdc: true,
        ),
        isTrue,
      );
    });

    test('a higher version of the same engine refreshes', () {
      expect(
        refreshMayWrite(
          storedVersion: 1,
          storedIsLibdc: false,
          incomingVersion: 2,
          incomingIsLibdc: false,
        ),
        isTrue,
      );
    });

    test('the same or a lower version never refreshes', () {
      expect(
        refreshMayWrite(
          storedVersion: 2,
          storedIsLibdc: true,
          incomingVersion: 2,
          incomingIsLibdc: true,
        ),
        isFalse,
      );
      expect(
        refreshMayWrite(
          storedVersion: 3,
          storedIsLibdc: true,
          incomingVersion: 2,
          incomingIsLibdc: true,
        ),
        isFalse,
      );
    });

    test('another engine never refreshes a download', () {
      expect(
        refreshMayWrite(
          storedVersion: 1,
          storedIsLibdc: false,
          incomingVersion: 5,
          incomingIsLibdc: true,
        ),
        isFalse,
      );
    });
  });

  group('isUsableParse', () {
    test('a parse with samples and a duration is usable', () {
      expect(
        isUsableParse(
            _converted(samples: 3, duration: const Duration(minutes: 5))),
        isTrue,
      );
    });

    test('an empty parse is not usable', () {
      expect(
        isUsableParse(
            _converted(samples: 0, duration: const Duration(minutes: 5))),
        isFalse,
      );
      expect(
        isUsableParse(_converted(samples: 3, duration: Duration.zero)),
        isFalse,
      );
    });
  });
}
