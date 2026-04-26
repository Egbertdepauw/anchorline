import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
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
}
