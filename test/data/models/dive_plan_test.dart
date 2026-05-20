import 'package:ccrlogger/data/models/dive_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DivePlanGas JSON round-trip', () {
    const g = DivePlanGas(
        oxygenPercent: 21, heliumPercent: 35, isDiluent: true);
    final j = g.toJson();
    expect(DivePlanGas.fromJson(j), g);
  });

  test('DivePlanSegment JSON round-trip (CC with setpoint)', () {
    const s = DivePlanSegment(
      depthMeters: 50,
      durationMinutes: 20,
      gasMixIndex: 0,
      setpoint: 1.3,
    );
    expect(DivePlanSegment.fromJson(s.toJson()), s);
  });

  test('DivePlanSegment JSON round-trip (no setpoint)', () {
    const s = DivePlanSegment(
        depthMeters: 50, durationMinutes: 0, gasMixIndex: 1);
    expect(DivePlanSegment.fromJson(s.toJson()).setpoint, isNull);
  });

  test('DivePlanBailoutBottle JSON round-trip', () {
    const b = DivePlanBailoutBottle(
      gasMixIndex: 0,
      waterCapacityL: 5.7,
      fillPressureBar: 200,
    );
    expect(DivePlanBailoutBottle.fromJson(b.toJson()), b);
  });

  test('DivePlanSettings JSON round-trip with sparse fields', () {
    const s = DivePlanSettings(gfLow: 30, useVpmb: true);
    final json = s.toJson();
    final back = DivePlanSettings.fromJson(json);
    expect(back.gfLow, 30);
    expect(back.useVpmb, true);
    expect(back.gfHigh, isNull);
  });

  test('encodeGases / decodeGases handle empty + multi-mix lists', () {
    expect(decodeGases(encodeGases(const [])), isEmpty);
    const gases = [
      DivePlanGas(oxygenPercent: 21, heliumPercent: 35, isDiluent: true),
      DivePlanGas(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
    ];
    expect(decodeGases(encodeGases(gases)), gases);
  });
}
