import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contrastRatio', () {
    test('black on white is 21', () {
      expect(contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.001));
    });
    test('a colour against itself is 1', () {
      expect(contrastRatio(const Color(0xFF4ADE80), const Color(0xFF4ADE80)),
          closeTo(1.0, 0.0001));
    });
    test('is symmetric', () {
      const a = Color(0xFFE0E8EC), b = Color(0xFF0A1518);
      expect(contrastRatio(a, b), contrastRatio(b, a));
    });
    test('Wreck primary text on Wreck background is about 14.9', () {
      expect(contrastRatio(const Color(0xFFE0E8EC), const Color(0xFF0A1518)),
          closeTo(14.93, 0.05));
    });
  });

  group('deltaE2000Lab', () {
    // Reference pairs from Sharma, Wu & Dalal (2005), CIEDE2000 test data.
    test('matches published reference pairs', () {
      expect(
          deltaE2000Lab((l: 50, a: 2.6772, b: -79.7751),
              (l: 50, a: 0, b: -82.7485)),
          closeTo(2.0425, 0.0001));
      expect(
          deltaE2000Lab((l: 50, a: 3.1571, b: -77.2803),
              (l: 50, a: 0, b: -82.7485)),
          closeTo(2.8615, 0.0001));
      expect(
          deltaE2000Lab((l: 50, a: 2.8361, b: -74.0200),
              (l: 50, a: 0, b: -82.7485)),
          closeTo(3.4412, 0.0001));
      expect(deltaE2000Lab((l: 50, a: 2.5, b: 0), (l: 50, a: 0, b: -2.5)),
          closeTo(4.3065, 0.0001));
    });
  });

  group('deltaE2000', () {
    test('identical colours are 0', () {
      expect(deltaE2000(const Color(0xFF60A5FA), const Color(0xFF60A5FA)),
          closeTo(0, 0.0001));
    });
    test('black to white is 100', () {
      expect(deltaE2000(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(100, 0.01));
    });
    test('Wreck cell 1 and cell 2 are far apart (about 50)', () {
      expect(deltaE2000(const Color(0xFF4ADE80), const Color(0xFF60A5FA)),
          closeTo(50.0, 0.5));
    });
  });
}
