import 'package:ccrlogger/analysis/mod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('modMeters', () {
    test('air (21 %)', () {
      expect(modMeters(0.21, 1.1), closeTo(42.38, 0.01));
      expect(modMeters(0.21, 1.4), closeTo(56.67, 0.01));
      expect(modMeters(0.21, 1.6), closeTo(66.19, 0.01));
    });

    test('EAN32', () {
      expect(modMeters(0.32, 1.1), closeTo(24.38, 0.01));
      expect(modMeters(0.32, 1.4), closeTo(33.75, 0.01));
      expect(modMeters(0.32, 1.6), closeTo(40.0, 0.01));
    });

    test('oxygen (100 %)', () {
      expect(modMeters(1.0, 1.1), closeTo(1.0, 1e-9));
      expect(modMeters(1.0, 1.4), closeTo(4.0, 1e-9));
      expect(modMeters(1.0, 1.6), closeTo(6.0, 1e-9));
    });

    test('no oxygen → unbounded', () {
      expect(modMeters(0, 1.4), double.infinity);
      expect(modMeters(-0.1, 1.4), double.infinity);
    });
  });

  group('minDepthMeters', () {
    test('10 % needs 6 m before it is breathable', () {
      expect(minDepthMeters(0.10), closeTo(6.0, 1e-9));
    });

    test('21 % is breathable at the surface (≤ 0)', () {
      expect(minDepthMeters(0.21), lessThanOrEqualTo(0));
    });

    test('custom floor', () {
      expect(minDepthMeters(0.10, ppO2Min: 0.18), closeTo(8.0, 1e-9));
    });

    test('no oxygen → never breathable', () {
      expect(minDepthMeters(0), double.infinity);
    });
  });
}
