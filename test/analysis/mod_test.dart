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

  group('floorDepthTolerant', () {
    test('floors, never rounds', () {
      expect(floorDepthTolerant(66.9), 66);
      expect(floorDepthTolerant(66.999), 66);
      expect(floorDepthTolerant(67.0), 67);
      expect(floorDepthTolerant(0.4), 0);
    });

    test('floating-point noise just under a whole metre does not drop one', () {
      // (1.4 / 0.2 - 1) * 10 is 59.99999999999999 in doubles.
      expect(modMeters(0.2, 1.4), lessThan(60));
      expect(floorDepthTolerant(59.99999999999999), 60);
      expect(floorDepthTolerant(modMeters(0.2, 1.4)), 60);
    });

    test('exact whole-metre MODs at 0.1 % O2 steps survive the noise', () {
      // 28 % -> 40 m, 100 % -> 4 m, 10 % -> 130 m, all at 1.4 bar.
      expect(floorDepthTolerant(modMeters(0.28, 1.4)), 40);
      expect(floorDepthTolerant(modMeters(1.0, 1.4)), 4);
      expect(floorDepthTolerant(modMeters(0.10, 1.4)), 130);
    });

    test('a genuine fraction is never lifted to the next metre', () {
      // Every non-integer MOD at 0.1 % O2 and 0.01 bar ppO2 steps is at
      // least 1e-3 m below the next metre, far more than the tolerance.
      for (var p = 100; p <= 170; p++) {
        for (var k = 1; k <= 1000; k++) {
          // MOD = (p/100 / (k/1000) - 1) * 10 = 100 * p / k - 10
          final m = modMeters(k / 1000.0, p / 100.0);
          expect(floorDepthTolerant(m), (100 * p / k - 10).floor(),
              reason: 'O2 ${k / 10} % at ${p / 100} bar');
        }
      }
    });
  });

  group('roundToStopDepth', () {
    // The stop depth for the exact MOD of [fO2] at [ppO2].
    int stop(double fO2, double ppO2) =>
        roundToStopDepth(modMeters(fO2, ppO2), fO2);

    test('rounds to the nearest 3 m stop', () {
      expect(stop(0.50, 1.6), 21); // 22.0 m
      expect(stop(0.21, 1.4), 57); // 56.7 m
      expect(stop(0.32, 1.4), 33); // 33.75 m
      expect(stop(0.47, 1.6), 24); // 24.0 m, 1.598 bar there
      expect(stop(1.0, 1.6), 6); // 6.0 m, exactly 1.6 bar there
    });

    test('goes a stop shallower when the nearest one is above ppO2 1.6', () {
      expect(stop(0.49, 1.6), 21); // 22.7 m; 24 m would be 1.67
      expect(stop(0.52, 1.6), 18); // 20.8 m; 21 m would be 1.61
      expect(stop(0.80, 1.6), 9); // 10.0 m; 12 m would be 1.76
      expect(stop(0.21, 1.6), 66); // 66.2 m; 1.596 at 66 m
    });

    test('exactly halfway between two stops goes to the shallower one', () {
      expect(roundToStopDepth(22.5, 0.21), 21);
      expect(roundToStopDepth(22.5 + 1e-12, 0.21), 21);
      expect(roundToStopDepth(22.51, 0.21), 24);
    });

    test('never above the surface', () {
      expect(roundToStopDepth(0.0, 1.0), 0);
      expect(roundToStopDepth(1.0, 1.0), 0);
    });

    test('always the nearest stop at which the gas stays at or under 1.6', () {
      for (var p = 100; p <= 160; p += 5) {
        for (var k = 1; k <= 1000; k++) {
          final fO2 = k / 1000.0;
          final exact = modMeters(fO2, p / 100.0);
          if (exact < 0) continue;
          final d = roundToStopDepth(exact, fO2);
          final why = 'O2 ${k / 10} % at ${p / 100} bar, exact $exact m';
          bool allowed(int depth) => fO2 * (depth / 10 + 1) <= 1.6 + 1e-9;

          expect(d % 3, 0, reason: why);
          expect(d, greaterThanOrEqualTo(0), reason: why);
          expect(allowed(d), isTrue, reason: why);
          // No allowed stop is strictly nearer.
          if (allowed(d + 3)) {
            expect((d + 3 - exact).abs(),
                greaterThanOrEqualTo((d - exact).abs() - 1e-9),
                reason: why);
          }
          if (d >= 3) {
            expect((d - 3 - exact).abs(), greaterThan((d - exact).abs()),
                reason: why);
          }
        }
      }
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
