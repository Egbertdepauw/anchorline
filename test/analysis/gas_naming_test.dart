import 'package:ccrlogger/analysis/gas_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gasMixName (whole percentages)', () {
    test('Air band edges classify after rounding', () {
      expect(gasMixName(20.4, 0), 'Hypoxic 20');
      expect(gasMixName(20.5, 0), 'Air');
      expect(gasMixName(20.6, 0), 'Air');
      expect(gasMixName(21, 0), 'Air');
      expect(gasMixName(21.4, 0), 'Air');
      expect(gasMixName(21.5, 0), 'EAN22');
      expect(gasMixName(21.6, 0), 'EAN22');
    });

    test('oxygen edge', () {
      expect(gasMixName(99.4, 0), 'EAN99');
      expect(gasMixName(99.5, 0), 'O2');
      expect(gasMixName(99.6, 0), 'O2');
      expect(gasMixName(100, 0), 'O2');
    });

    test('nitrox', () {
      expect(gasMixName(32, 0), 'EAN32');
      expect(gasMixName(50, 0), 'EAN50');
    });

    test('hypoxic without helium', () {
      expect(gasMixName(18, 0), 'Hypoxic 18');
      expect(gasMixName(10, 0), 'Hypoxic 10');
    });

    test('trimix', () {
      expect(gasMixName(21, 35), 'Tx21/35');
      expect(gasMixName(18, 45), 'Tx18/45');
      expect(gasMixName(10, 70), 'Tx10/70');
      expect(gasMixName(10, 88), 'Tx10/88');
    });

    test('heliox when O2 + He >= 99', () {
      expect(gasMixName(10, 90), 'Hx10/90');
      expect(gasMixName(10, 89), 'Hx10/89');
      expect(gasMixName(2, 97), 'Hx2/97');
      expect(gasMixName(2, 96), 'Tx2/96');
    });

    test('rounds half away from zero', () {
      expect(gasMixName(21.3, 34.2), 'Tx21/34');
      expect(gasMixName(21.6, 34.5), 'Tx22/35');
    });

    test('helium that rounds to zero is not trimix', () {
      expect(gasMixName(20.9, 0.4), 'Air');
    });

    test('accepts int and double', () {
      expect(gasMixName(32, 0), gasMixName(32.0, 0.0));
    });
  });

  group('gasMixNameDecimal (analyzer readout)', () {
    test('one decimal by default', () {
      expect(gasMixNameDecimal(21.4, 34.2), 'Tx21.4/34.2');
      expect(gasMixNameDecimal(32.4, 0), 'EAN32.4');
      expect(gasMixNameDecimal(18.2, 0), 'Hypoxic 18.2');
      expect(gasMixNameDecimal(10.1, 89.6), 'Hx10.1/89.6');
    });

    test('Air and O2 classified from the raw decimals', () {
      expect(gasMixNameDecimal(20.4, 0), 'Hypoxic 20.4');
      expect(gasMixNameDecimal(20.5, 0), 'Air');
      expect(gasMixNameDecimal(20.9, 0), 'Air');
      expect(gasMixNameDecimal(21.5, 0), 'Air');
      expect(gasMixNameDecimal(21.6, 0), 'EAN21.6');
      expect(gasMixNameDecimal(99.4, 0), 'EAN99.4');
      expect(gasMixNameDecimal(99.5, 0), 'O2');
    });

    test('helium noise below display resolution counts as zero', () {
      expect(gasMixNameDecimal(20.9, 0.02), 'Air');
      expect(gasMixNameDecimal(20.9, -0.1), 'Air');
    });

    test('custom decimals', () {
      expect(gasMixNameDecimal(21.43, 34.21, decimals: 2), 'Tx21.43/34.21');
    });
  });
}
