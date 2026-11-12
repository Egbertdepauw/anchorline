import 'dart:io';
import 'dart:typed_data';

import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

/// Load a fixture file from test/fixtures/dives/.
Uint8List loadFixture(String name) {
  // Try relative to cwd (normal flutter test) or project root
  for (final base in ['.', 'test/fixtures/dives']) {
    final file = File('$base/$name');
    if (file.existsSync()) return file.readAsBytesSync();
  }
  final file = File('test/fixtures/dives/$name');
  return file.readAsBytesSync();
}

void main() {
  // Dive 718 from a Petrel 3 (PNF format, log version >= 9).
  // Manifest says: start 2026-04-19 10:38:45 UTC = 0x69E4A356
  late Uint8List dive718Data;
  late ParsedDive dive718;

  setUpAll(() {
    dive718Data = loadFixture('dive_718.bin');
    final parser = ShearwaterDiveParser(
      model: ShearwaterModel.petrel3,
    );
    dive718 = parser.parse(dive718Data);
  });

  group('PNF format detection', () {
    test('detects PNF format (first uint16 != 0xFFFF)', () {
      // Dive 718 first bytes are 0x10 0xFF (record type OPENING_0)
      // 0x10FF != 0xFFFF → PNF
      expect(dive718.header.isPnf, isTrue);
    });
  });

  group('header parsing', () {
    test('extracts start timestamp', () {
      // 0x69E4A356 = 1776673622 → 2026-04-19 10:38:45 UTC (from manifest)
      // But the parser reads from opening[0] + 12 which may differ slightly.
      // The timestamp in the dive blob is at bytes [12..15] of opening[0].
      expect(dive718.header.startTimestamp, equals(0x69E4A356));
    });

    test('extracts log version', () {
      // Petrel 3 with firmware V103 should have a recent log version
      expect(dive718.header.logVersion, greaterThanOrEqualTo(9));
    });

    test('extracts units', () {
      // Units from opening[0] + 8
      expect(
        dive718.header.units,
        anyOf(equals(unitsMetric), equals(unitsImperial)),
      );
    });

    test('extracts dive mode', () {
      // Should be a valid dive mode
      expect(DiveMode.values, contains(dive718.header.diveMode));
    });

    test('extracts sensor calibration (3 values)', () {
      expect(dive718.header.sensorCalibration, hasLength(3));
      for (final cal in dive718.header.sensorCalibration) {
        // Calibration should be a small positive number (typically ~0.02)
        // or 0 if sensor not present
        expect(cal, greaterThanOrEqualTo(0.0));
        expect(cal, lessThan(1.0));
      }
    });

    test('extracts atmospheric pressure', () {
      // Should be roughly sea level (900-1100 mbar)
      expect(dive718.header.atmosphericPressureMbar, greaterThan(800));
      expect(dive718.header.atmosphericPressureMbar, lessThan(1200));
    });

    test('extracts water density', () {
      // Should be fresh (1000) or salt (1020-1030)
      expect(dive718.header.waterDensity, greaterThanOrEqualTo(990));
      expect(dive718.header.waterDensity, lessThanOrEqualTo(1040));
    });
  });

  group('footer parsing', () {
    test('extracts max depth (non-zero)', () {
      expect(dive718.footer.maxDepthRaw, greaterThan(0));
    });

    test('extracts dive time (reasonable range)', () {
      // A real dive should be between 1 minute and 10 hours
      expect(dive718.footer.diveTimeSeconds, greaterThan(60));
      expect(dive718.footer.diveTimeSeconds, lessThan(36000));
    });
  });

  group('gas mixes', () {
    test('has at least one gas mix', () {
      expect(dive718.gasMixes, isNotEmpty);
    });

    test('gas mixes have valid O2 percentages', () {
      for (final mix in dive718.gasMixes) {
        expect(mix.oxygenPercent, greaterThan(0));
        expect(mix.oxygenPercent, lessThanOrEqualTo(100));
        expect(mix.oxygenPercent + mix.heliumPercent, lessThanOrEqualTo(100));
      }
    });
  });

  group('sample parsing', () {
    test('has samples', () {
      expect(dive718.samples, isNotEmpty);
    });

    test('sample times are monotonically increasing', () {
      for (var i = 1; i < dive718.samples.length; i++) {
        expect(
          dive718.samples[i].timeMs,
          greaterThan(dive718.samples[i - 1].timeMs),
          reason: 'Sample $i time should be > sample ${i - 1} time',
        );
      }
    });

    test('sample count is consistent with dive duration and interval', () {
      final expectedSamples = dive718.footer.diveTimeSeconds * 1000 ~/
          dive718.header.sampleIntervalMs;
      // Allow some tolerance (empty samples skipped, rounding)
      expect(dive718.samples.length, greaterThan(expectedSamples ~/ 2));
      expect(dive718.samples.length, lessThan(expectedSamples * 2));
    });

    test('depth values are non-negative', () {
      for (final s in dive718.samples) {
        expect(s.depthRaw, greaterThanOrEqualTo(0));
      }
    });

    test('first and last samples have shallow depth', () {
      // Dive should start and end near the surface
      // Raw depth is in 1/10 m (or ft), so < 50 = < 5m
      expect(dive718.samples.first.depthRaw, lessThan(100));
      expect(dive718.samples.last.depthRaw, lessThan(100));
    });

    test('O2 and He percentages are populated', () {
      // At least the first sample should have gas info
      final first = dive718.samples.first;
      expect(first.o2Percent, greaterThan(0));
    });
  });

  group('final record', () {
    test('final record is present in PNF format', () {
      expect(dive718.finalRecord, isNotNull);
    });

    test('final record contains device serial', () {
      // Serial B89641E4 = 0xB89641E4 = 3097600484
      expect(dive718.finalRecord!.serial, greaterThan(0));
    });
  });

  group('multiple fixture dives', () {
    test('all 8 fixture dives parse without error', () {
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      for (final num in [711, 712, 713, 714, 715, 716, 717, 718]) {
        final data = loadFixture('dive_$num.bin');
        final dive = parser.parse(data);
        expect(dive.samples, isNotEmpty, reason: 'Dive $num should have samples');
        expect(dive.header.startTimestamp, greaterThan(0),
            reason: 'Dive $num should have a start timestamp');
        expect(dive.footer.diveTimeSeconds, greaterThan(0),
            reason: 'Dive $num should have a dive time');
      }
    });
  });

  group('parseOne (multi-dive demux)', () {
    test('returns bytesConsumed == data.length for a single-dive buffer', () {
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      final data = loadFixture('dive_715.bin');
      final r = parser.parseOne(data);
      expect(r.bytesConsumed, equals(data.length));
      expect(r.dive.samples, isNotEmpty);
    });

    test('parseOne advances offset correctly for a multi-dive blob', () {
      // Concatenate two fixture dives end-to-end. Each fixture already
      // ends with a 0xFF final record followed by zero padding to the
      // next 128-byte boundary — exactly what the Petrel emits between
      // dives in a single-session download of the entire on-flash log.
      final dive1 = loadFixture('dive_715.bin');
      final dive2 = loadFixture('dive_716.bin');

      final blob = Uint8List(dive1.length + dive2.length)
        ..setRange(0, dive1.length, dive1)
        ..setRange(dive1.length, dive1.length + dive2.length, dive2);

      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);

      final r1 = parser.parseOne(blob, offset: 0);
      expect(r1.bytesConsumed, equals(dive1.length),
          reason: 'First dive should consume exactly dive1.length bytes');

      final r2 = parser.parseOne(blob, offset: r1.bytesConsumed);
      expect(r2.bytesConsumed, equals(dive2.length),
          reason: 'Second dive should consume exactly dive2.length bytes');

      // Each demuxed dive should parse to the same header values as
      // the standalone single-dive parse.
      final solo1 = parser.parse(dive1);
      final solo2 = parser.parse(dive2);
      expect(r1.dive.header.startTimestamp,
          equals(solo1.header.startTimestamp));
      expect(r2.dive.header.startTimestamp,
          equals(solo2.header.startTimestamp));
      expect(r1.dive.samples.length, equals(solo1.samples.length));
      expect(r2.dive.samples.length, equals(solo2.samples.length));
    });

    test('iterating parseOne demuxes all 8 fixture dives concatenated', () {
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      final fixtures = [
        for (final n in [711, 712, 713, 714, 715, 716, 717, 718])
          loadFixture('dive_$n.bin')
      ];
      final totalLen =
          fixtures.fold<int>(0, (sum, b) => sum + b.length);
      final blob = Uint8List(totalLen);
      var pos = 0;
      for (final f in fixtures) {
        blob.setRange(pos, pos + f.length, f);
        pos += f.length;
      }

      final results = <ParseResult>[];
      var off = 0;
      while (off < blob.length) {
        final r = parser.parseOne(blob, offset: off);
        results.add(r);
        off += r.bytesConsumed;
      }

      expect(results.length, equals(8));
      expect(off, equals(blob.length));
      for (var i = 0; i < 8; i++) {
        expect(results[i].bytesConsumed, equals(fixtures[i].length),
            reason: 'Dive ${i + 1} of 8 should consume its fixture length');
      }
    });
  });
}
