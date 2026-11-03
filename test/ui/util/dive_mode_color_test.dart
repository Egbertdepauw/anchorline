import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:ccrlogger/ui/theme/data_colors.dart';
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
  test('every mode maps to its DataColors constant', () {
    expect(diveModeColor(DiveMode.cc.value), DataColors.modeClosedCircuit);
    expect(diveModeColor(DiveMode.cc2.value), DataColors.modeClosedCircuit);
    expect(diveModeColor(DiveMode.ocTec.value), DataColors.modeOpenCircuit);
    expect(diveModeColor(DiveMode.ocRec.value), DataColors.modeOpenCircuit);
    expect(diveModeColor(DiveMode.avelo.value), DataColors.modeOpenCircuit);
    expect(diveModeColor(DiveMode.sc.value), DataColors.modeSemiClosed);
    expect(diveModeColor(DiveMode.gauge.value), DataColors.modeGauge);
    expect(diveModeColor(DiveMode.ppo2.value), DataColors.modeGauge);
    expect(diveModeColor(DiveMode.freedive.value), DataColors.modeFreedive);
  });
  test('diveModeLabel returns correct labels', () {
    expect(diveModeLabel(DiveMode.cc.value), equals('CC'));
    expect(diveModeLabel(DiveMode.ocTec.value), equals('OC'));
    expect(diveModeLabel(DiveMode.sc.value), equals('SC'));
    expect(diveModeLabel(DiveMode.gauge.value), equals('GA'));
    expect(diveModeLabel(DiveMode.freedive.value), equals('FD'));
  });
}
