import 'package:ccrlogger/shearwater/parser/constants.dart';
import 'package:ccrlogger/ui/util/dive_mode_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CC mode returns cyan', () {
    expect(diveModeColor(DiveMode.cc.value), equals(const Color(0xFF4FC3F7)));
  });
  test('OC Tec mode returns orange', () {
    expect(diveModeColor(DiveMode.ocTec.value), equals(const Color(0xFFFF9800)));
  });
  test('SC mode returns purple', () {
    expect(diveModeColor(DiveMode.sc.value), equals(const Color(0xFFAB47BC)));
  });
  test('Gauge mode returns blue-grey', () {
    expect(diveModeColor(DiveMode.gauge.value), equals(const Color(0xFF78909C)));
  });
  test('Freedive mode returns teal', () {
    expect(diveModeColor(DiveMode.freedive.value), equals(const Color(0xFF26A69A)));
  });
  test('CC2 returns same as CC', () {
    expect(diveModeColor(DiveMode.cc2.value), equals(diveModeColor(DiveMode.cc.value)));
  });
  test('diveModeLabel returns correct labels', () {
    expect(diveModeLabel(DiveMode.cc.value), equals('CC'));
    expect(diveModeLabel(DiveMode.ocTec.value), equals('OC'));
    expect(diveModeLabel(DiveMode.sc.value), equals('SC'));
    expect(diveModeLabel(DiveMode.gauge.value), equals('GA'));
    expect(diveModeLabel(DiveMode.freedive.value), equals('FD'));
  });
}
