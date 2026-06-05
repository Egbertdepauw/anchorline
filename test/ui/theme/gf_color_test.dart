import 'package:ccrlogger/ui/theme/gf_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('green within GF-high (boundary inclusive)', () {
    expect(gfBandColor(50, gfHigh: 85), const Color(0xFF4ADE80));
    expect(gfBandColor(85, gfHigh: 85), const Color(0xFF4ADE80));
  });

  test('amber above GF-high up to 100 (100 not yet red)', () {
    expect(gfBandColor(90, gfHigh: 85), const Color(0xFFF59E0B));
    expect(gfBandColor(100, gfHigh: 85), const Color(0xFFF59E0B));
  });

  test('red above 100', () {
    expect(gfBandColor(101, gfHigh: 85), const Color(0xFFDC2626));
  });

  test('default gfHigh is 85', () {
    expect(gfBandColor(90), const Color(0xFFF59E0B));
    expect(gfBandColor(80), const Color(0xFF4ADE80));
  });
}
