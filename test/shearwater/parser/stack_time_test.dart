import 'dart:io';

import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ParsedDive dive718;

  setUpAll(() {
    final data = File('test/fixtures/dives/dive_718.bin').readAsBytesSync();
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    dive718 = parser.parse(data);
  });

  group('Petrel scrubber stack time', () {
    test('configured stack capacity is plausible', () {
      final cfg = dive718.header.configuredStackSeconds;
      expect(cfg, isNotNull);
      expect(cfg!, greaterThanOrEqualTo(60));
      expect(cfg, lessThanOrEqualTo(0xFFFF));
    });

    test('start remaining never exceeds configured capacity', () {
      final cfg = dive718.header.configuredStackSeconds!;
      final start = dive718.header.stackRemainingAtStartSeconds;
      expect(start, isNotNull);
      expect(start!, lessThanOrEqualTo(cfg));
    });

    test('end remaining never exceeds start remaining', () {
      final start = dive718.header.stackRemainingAtStartSeconds!;
      final end = dive718.header.stackRemainingAtEndSeconds;
      expect(end, isNotNull);
      expect(end!, lessThanOrEqualTo(start));
    });

    test('per-dive consumption is between 1 minute and 2 hours', () {
      final start = dive718.header.stackRemainingAtStartSeconds!;
      final end = dive718.header.stackRemainingAtEndSeconds!;
      final used = start - end;
      expect(used, greaterThanOrEqualTo(60));
      expect(used, lessThanOrEqualTo(7200));
    });

    test('all fixture dives have non-null stack values (logVersion=17)', () {
      final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
      for (final num in [711, 712, 713, 714, 715, 716, 717, 718]) {
        final data =
            File('test/fixtures/dives/dive_$num.bin').readAsBytesSync();
        final parsed = parser.parse(data);
        expect(parsed.header.logVersion, equals(17),
            reason: 'dive_$num logVersion');
        expect(parsed.header.configuredStackSeconds, isNotNull,
            reason: 'dive_$num configuredStackSeconds');
        expect(parsed.header.stackRemainingAtStartSeconds, isNotNull,
            reason: 'dive_$num stackRemainingAtStartSeconds');
        expect(parsed.header.stackRemainingAtEndSeconds, isNotNull,
            reason: 'dive_$num stackRemainingAtEndSeconds');
      }
    });
  });
}
