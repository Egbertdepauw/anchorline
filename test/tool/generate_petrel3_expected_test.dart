// Generator, not a test: writes packages/libdivecomputer/test/fixtures/
// petrel3_expected.json from the app's Dart Shearwater reader over the eight
// dive files of the Petrel 3 download (test/fixtures/dives, byte-identical to
// what libdivecomputer decodes from test/fixtures/raw/subsurface2.combined.txt).
//
// Skipped unless GENERATE_PETREL3_EXPECTED is set:
//   GENERATE_PETREL3_EXPECTED=1 flutter test test/tool/generate_petrel3_expected_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';

void main() {
  test(
    'generate petrel3_expected.json',
    () {
      final dives = <Map<String, Object?>>[];
      for (var num = 711; num <= 718; num++) {
        final data = File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        final parsed = ShearwaterDiveParser(
          model: ShearwaterModel.petrel3,
        ).parse(data);
        final c = DiveConverter.convert(
          parsed: parsed,
          dcSerial: 0xB89641E4,
          dcDiveNumber: num,
          dcModel: ShearwaterModel.petrel3,
        );
        final d = c.dive;
        final s = c.samples;
        dives.add({
          'diveNumber': num,
          'startTimeEpochSeconds': d.startTime.millisecondsSinceEpoch ~/ 1000,
          'durationSeconds': d.duration.inSeconds,
          'maxDepthM': d.maxDepthMeters,
          'gasMixes': [
            for (final g in d.gasMixes)
              {
                'oxygenPercent': g.oxygenPercent,
                'heliumPercent': g.heliumPercent,
                'isDiluent': g.isDiluent,
              },
          ],
          'sampleCount': s.sampleCount,
          'sampleIntervalMs': s.sampleIntervalMs,
          'depthM': s.depthMeters.toList(),
          'temperatureC': s.temperatureCelsius.toList(),
          'ppo2Bar': s.ppo2Bar.toList(),
          'setpointBar': s.setpointBar.toList(),
        });
      }
      File('packages/libdivecomputer/test/fixtures/petrel3_expected.json')
          .writeAsStringSync(
            const JsonEncoder.withIndent(null).convert({'dives': dives}),
          );
    },
    skip: Platform.environment['GENERATE_PETREL3_EXPECTED'] == null
        ? 'generator: set GENERATE_PETREL3_EXPECTED=1'
        : false,
  );
}
