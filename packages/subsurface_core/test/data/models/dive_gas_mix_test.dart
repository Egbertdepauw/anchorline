import 'package:subsurface_core/data/models/dive.dart';
import 'package:test/test.dart';

// Built at runtime so the compiler can't canonicalise them into one
// const instance, which would hide a missing operator ==.
DiveGasMix _mix(int o2, int he, {bool dil = false}) =>
    DiveGasMix(oxygenPercent: o2, heliumPercent: he, isDiluent: dil);

void main() {
  test('two instances of the same mix are equal and hash alike', () {
    final a = _mix(21, 0);
    final b = _mix(21, 0);
    expect(identical(a, b), isFalse);
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });

  test('the same mix is one map key and one set member', () {
    final tally = <DiveGasMix, double>{};
    for (final g in [_mix(21, 0), _mix(21, 0), _mix(21, 0)]) {
      tally.update(g, (v) => v + 1, ifAbsent: () => 1);
    }
    expect(tally, hasLength(1));
    expect(tally[_mix(21, 0)], 3);
    expect({_mix(18, 45), _mix(18, 45)}, hasLength(1));
  });

  test('oxygen, helium and the diluent flag each tell mixes apart', () {
    final base = _mix(21, 35);
    expect(base, isNot(equals(_mix(18, 35))));
    expect(base, isNot(equals(_mix(21, 45))));
    // A diluent and a bailout cylinder of the same mix stay apart.
    expect(base, isNot(equals(_mix(21, 35, dil: true))));
  });
}
