import 'dart:io';

import 'package:ccrlogger/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:ccrlogger/shearwater/parser/hardware.dart';
import 'package:ccrlogger/data/models/dive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ParsedDive parsed718;
  late Dive dive718;
  late ConvertedDive converted718;

  setUpAll(() {
    final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    parsed718 = parser.parse(data);
    converted718 = DiveConverter.convert(
      parsed: parsed718,
      dcSerial: 0xB89641E4,
      dcDiveNumber: 718,
      dcModel: ShearwaterModel.petrel3,
    );
    dive718 = converted718.dive;
  });

  group('Dive ID generation', () {
    test('generates deterministic ID from serial + dive number + timestamp',
        () {
      final id1 = generateDiveId(0xB89641E4, 718, 0x69E4A356);
      final id2 = generateDiveId(0xB89641E4, 718, 0x69E4A356);
      expect(id1, equals(id2));
      expect(id1.length, equals(32));
    });

    test('different inputs produce different IDs', () {
      final id1 = generateDiveId(0xB89641E4, 718, 0x69E4A356);
      final id2 = generateDiveId(0xB89641E4, 717, 0x69E4A356);
      expect(id1, isNot(equals(id2)));
    });
  });

  group('Dive conversion', () {
    test('generates correct dive ID', () {
      final expectedId = generateDiveId(0xB89641E4, 718, 0x69E4A356);
      expect(dive718.id, equals(expectedId));
    });

    test('preserves dc serial and dive number', () {
      expect(dive718.dcSerial, equals(0xB89641E4));
      expect(dive718.dcDiveNumber, equals(718));
    });

    test('converts start time to DateTime', () {
      expect(dive718.startTime.isUtc, isTrue);
      expect(dive718.startTime.year, equals(2026));
      expect(dive718.startTime.month, equals(4));
    });

    test('computes end time from start + duration', () {
      expect(dive718.endTime.isAfter(dive718.startTime), isTrue);
      expect(
        dive718.endTime.difference(dive718.startTime),
        equals(dive718.duration),
      );
    });

    test('converts max depth to meters', () {
      // Max depth should be positive and reasonable for a dive
      expect(dive718.maxDepthMeters, greaterThan(0));
      expect(dive718.maxDepthMeters, lessThan(200)); // reasonable limit
    });

    test('preserves dive mode', () {
      expect(dive718.diveMode, equals(parsed718.header.diveMode));
    });

    test('preserves gas mixes', () {
      expect(dive718.gasMixes.length, equals(parsed718.gasMixes.length));
      for (var i = 0; i < dive718.gasMixes.length; i++) {
        expect(dive718.gasMixes[i].oxygenPercent,
            equals(parsed718.gasMixes[i].oxygenPercent));
      }
    });
  });

  group('SampleSet conversion', () {
    test('has correct sample count', () {
      expect(converted718.samples.sampleCount, equals(parsed718.samples.length));
    });

    test('depth values are in meters', () {
      final depths = converted718.samples.depthMeters;
      expect(depths.length, equals(parsed718.samples.length));
      // All depths should be non-negative
      for (var i = 0; i < depths.length; i++) {
        expect(depths[i], greaterThanOrEqualTo(0),
            reason: 'Depth at sample $i should be >= 0');
      }
    });

    test('PPO2 values are in bar', () {
      final ppo2 = converted718.samples.ppo2Bar;
      for (var i = 0; i < ppo2.length; i++) {
        // PPO2 should be 0-3 bar for any reasonable dive
        expect(ppo2[i], greaterThanOrEqualTo(0));
        expect(ppo2[i], lessThan(3.0));
      }
    });

    test('setpoint values are in bar', () {
      final sp = converted718.samples.setpointBar;
      for (var i = 0; i < sp.length; i++) {
        expect(sp[i], greaterThanOrEqualTo(0));
        expect(sp[i], lessThan(2.0)); // setpoints are typically 0.7-1.6
      }
    });

    test('temperature values are in Celsius', () {
      final temps = converted718.samples.temperatureCelsius;
      for (var i = 0; i < temps.length; i++) {
        // Reasonable water temperature range
        expect(temps[i], greaterThanOrEqualTo(-5));
        expect(temps[i], lessThan(40));
      }
    });
  });

  group('all fixture dives convert without error', () {
    test('converts all 8 dives', () {
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      for (final num in [711, 712, 713, 714, 715, 716, 717, 718]) {
        final data = File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        final parsed = parser.parse(data);
        final converted = DiveConverter.convert(
          parsed: parsed,
          dcSerial: 0xB89641E4,
          dcDiveNumber: num,
          dcModel: ShearwaterModel.petrel3,
        );
        expect(converted.dive.maxDepthMeters, greaterThan(0),
            reason: 'Dive $num should have max depth > 0');
        expect(converted.samples.sampleCount, greaterThan(0),
            reason: 'Dive $num should have samples');
      }
    });
  });
}
