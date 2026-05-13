import 'package:ccrlogger/analysis/deco/tissue_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zhl16cTissues has exactly 16 compartments', () {
    expect(zhl16cTissues, hasLength(16));
  });

  test('every compartment has positive N2 + He half-times', () {
    for (final c in zhl16cTissues) {
      expect(c.halfTimeN2Min, greaterThan(0));
      expect(c.halfTimeHeMin, greaterThan(0));
    }
  });

  test('every compartment has Bühlmann a/b for both gases', () {
    for (final c in zhl16cTissues) {
      expect(c.aN2, greaterThan(0));
      expect(c.bN2, inInclusiveRange(0.0, 1.0));
      expect(c.aHe, greaterThan(0));
      expect(c.bHe, inInclusiveRange(0.0, 1.0));
    }
  });

  test('compartments ordered fast→slow by N2 half-time', () {
    for (var i = 1; i < zhl16cTissues.length; i++) {
      expect(zhl16cTissues[i].halfTimeN2Min,
          greaterThan(zhl16cTissues[i - 1].halfTimeN2Min));
    }
  });

  test('compartment 1 N2 half-time = 4.0 min, a = 1.2599 (Subsurface canonical)', () {
    expect(zhl16cTissues[0].halfTimeN2Min, closeTo(4.0, 0.01));
    expect(zhl16cTissues[0].aN2, closeTo(1.2599, 0.001));
  });

  test('compartment 16 N2 half-time = 635 min (slowest)', () {
    expect(zhl16cTissues[15].halfTimeN2Min, closeTo(635.0, 0.5));
  });
}
