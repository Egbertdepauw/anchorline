import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:flutter_test/flutter_test.dart';

/// Grades [o2]/[he] against the Tx21/35 target used throughout these tests.
MixMatch _grade(double o2, double he) => gradeMix(
      o2Percent: o2,
      hePercent: he,
      targetO2Percent: 21,
      targetHePercent: 35,
    );

void main() {
  group('gradeMix O2 boundaries (He on target)', () {
    test('up to 1.0 off is a match', () {
      expect(_grade(22.0, 35.0).level, MixMatchLevel.match);
    });

    test('over 1.0 up to 2.0 off is orange', () {
      expect(_grade(22.1, 35.0).level, MixMatchLevel.orange);
      expect(_grade(23.0, 35.0).level, MixMatchLevel.orange);
    });

    test('over 2.0 up to 5.0 off is red', () {
      expect(_grade(23.1, 35.0).level, MixMatchLevel.red);
      expect(_grade(26.0, 35.0).level, MixMatchLevel.red);
    });

    test('over 5.0 off is a hard mismatch', () {
      expect(_grade(26.1, 35.0).level, MixMatchLevel.hard);
    });

    test('below the target grades the same as above it', () {
      expect(_grade(19.9, 35.0).level, MixMatchLevel.orange);
      expect(_grade(20.0, 35.0).level, MixMatchLevel.match);
      expect(_grade(18.9, 35.0).level, MixMatchLevel.red);
      expect(_grade(15.9, 35.0).level, MixMatchLevel.hard);
    });
  });

  group('gradeMix He boundaries (O2 on target)', () {
    test('up to 2.0 off is a match', () {
      expect(_grade(21.0, 37.0).level, MixMatchLevel.match);
    });

    test('over 2.0 up to 4.0 off is orange', () {
      expect(_grade(21.0, 37.1).level, MixMatchLevel.orange);
      expect(_grade(21.0, 39.0).level, MixMatchLevel.orange);
    });

    test('over 4.0 up to 10.0 off is red', () {
      expect(_grade(21.0, 39.1).level, MixMatchLevel.red);
      expect(_grade(21.0, 45.0).level, MixMatchLevel.red);
    });

    test('over 10.0 off is a hard mismatch', () {
      expect(_grade(21.0, 45.1).level, MixMatchLevel.hard);
    });

    test('below the target grades the same as above it', () {
      expect(_grade(21.0, 33.0).level, MixMatchLevel.match);
      expect(_grade(21.0, 32.9).level, MixMatchLevel.orange);
      expect(_grade(21.0, 25.0).level, MixMatchLevel.red);
      expect(_grade(21.0, 24.9).level, MixMatchLevel.hard);
    });
  });

  group('gradeMix combined', () {
    test('the worse of O2 and He wins, and both offsets are reported', () {
      final m = _grade(22.5, 39.5);
      expect(m.level, MixMatchLevel.red);
      expect(m.o2Off, 1.5);
      expect(m.heOff, 4.5);
    });

    test('a hard mismatch in one gas wins over a match in the other', () {
      expect(_grade(21.0, 50.0).level, MixMatchLevel.hard);
      expect(_grade(30.0, 35.0).level, MixMatchLevel.hard);
    });

    test('an exact analysis is a match with zero offsets', () {
      final m = _grade(21.0, 35.0);
      expect(m.level, MixMatchLevel.match);
      expect(m.o2Off, 0.0);
      expect(m.heOff, 0.0);
    });

    test('offsets are rounded to 0.1 so float noise cannot leak through', () {
      // 22.1 - 21 is 1.1000000000000014 in IEEE doubles.
      expect(_grade(22.1, 35.0).o2Off, 1.1);
      expect(_grade(19.9, 35.0).o2Off, 1.1);
    });

    test('rounding happens before the threshold compare', () {
      // 22.04 - 21 = 1.04 rounds to 1.0, so it is still a match.
      expect(_grade(22.04, 35.0).level, MixMatchLevel.match);
      // 22.06 - 21 = 1.06 rounds to 1.1, so it is orange.
      expect(_grade(22.06, 35.0).level, MixMatchLevel.orange);
    });
  });

  group('mixMatchText', () {
    test('a match says so', () {
      expect(mixMatchText(_grade(21.4, 35.2), 'Tx21/35'), 'Matches Tx21/35');
    });

    test('lists O2 alone when only O2 is above its match bound', () {
      expect(mixMatchText(_grade(22.5, 35.0), 'Tx21/35'),
          'O2 1.5 off Tx21/35');
    });

    test('lists both gases when both are above their match bound', () {
      expect(mixMatchText(_grade(22.5, 39.5), 'Tx21/35'),
          'O2 1.5, He 4.5 off Tx21/35');
    });

    test('lists He alone when only He is above its match bound', () {
      expect(mixMatchText(_grade(21.0, 38.0), 'Tx21/35'),
          'He 3.0 off Tx21/35');
    });

    test('leaves out a gas that is off but still within its match bound', () {
      // O2 is 1.0 off (a match), He is 3.0 off (orange): only He is listed.
      expect(mixMatchText(_grade(22.0, 38.0), 'Tx21/35'),
          'He 3.0 off Tx21/35');
    });

    test('uses the desired name it is given, not one derived from the grade',
        () {
      final m = gradeMix(
        o2Percent: 51.5,
        hePercent: 0.0,
        targetO2Percent: 50,
        targetHePercent: 0,
      );
      expect(mixMatchText(m, 'EAN50'), 'O2 1.5 off EAN50');
    });
  });
}
