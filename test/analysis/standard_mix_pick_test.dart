import 'package:flutter_test/flutter_test.dart';

import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/analysis/standard_mix_pick.dart';
import 'package:ccrlogger/data/models/equipment.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';

void main() {
  group('pickDesiredMix', () {
    test('20.4/33.5 picks Tx21/35 as a match', () {
      final p = pickDesiredMix(o2Percent: 20.4, hePercent: 33.5)!;
      expect(p.mix, const DesiredMix(21, 35));
      expect(p.source, MixPickSource.standard);
      expect(p.level, MixMatchLevel.match);
    });
    test('49.2/0.3 picks EAN50', () => expect(pickDesiredMix(o2Percent: 49.2, hePercent: 0.3)!.mix, const DesiredMix(50, 0)));
    test('19.1/43.0 picks Tx18/45 as orange', () {
      final p = pickDesiredMix(o2Percent: 19.1, hePercent: 43.0)!;
      expect(p.mix, const DesiredMix(18, 45));
      expect(p.level, MixMatchLevel.orange);
    });
    test('20.9/0.4 picks Air', () => expect(pickDesiredMix(o2Percent: 20.9, hePercent: 0.4)!.mix, const DesiredMix(21, 0)));
    test('23.0/30.0 picks nothing (Tx21/35 is red)', () => expect(pickDesiredMix(o2Percent: 23.0, hePercent: 30.0), isNull));
    test('40.0/0.0 picks nothing', () => expect(pickDesiredMix(o2Percent: 40.0, hePercent: 0.0), isNull));
    test('a Blend target within orange beats a standard mix', () {
      final p = pickDesiredMix(o2Percent: 19.6, hePercent: 40.2, blendTarget: const DesiredMix(19, 40))!;
      expect(p.mix, const DesiredMix(19, 40));
      expect(p.source, MixPickSource.blendTarget);
    });
    test('a Blend target that grades red is ignored', () {
      final p = pickDesiredMix(o2Percent: 20.6, hePercent: 33.8, blendTarget: const DesiredMix(18, 45))!;
      expect(p.mix, const DesiredMix(21, 35));
      expect(p.source, MixPickSource.standard);
    });
    test('no result is ever red or hard', () {
      for (var o2 = 5.0; o2 <= 100; o2 += 0.7) {
        for (var he = 0.0; he + o2 <= 100; he += 1.3) {
          final p = pickDesiredMix(o2Percent: o2, hePercent: he);
          if (p != null) expect(p.level, anyOf(MixMatchLevel.match, MixMatchLevel.orange));
        }
      }
    });
  });

  group('role rule', () {
    test('gasRoleForMix: 30.0 is diluent, 30.1 is bailout', () {
      expect(gasRoleForMix(30.0), GasRole.diluent);
      expect(gasRoleForMix(30.1), GasRole.bailout);
      expect(gasRoleForMix(21), GasRole.diluent);
      expect(gasRoleForMix(100), GasRole.bailout);
    });
    test('resolveGasRole: a tapped role wins over cylinder and mix', () =>
        expect(resolveGasRole(tapped: GasRole.diluent, cylinderRole: CylinderRole.oxygen, o2PercentForRule: 50), GasRole.diluent));
    test('resolveGasRole: blend role wins over cylinder and mix; tapped wins '
        'over blend', () {
      expect(
          resolveGasRole(
              blendRole: GasRole.diluent,
              cylinderRole: CylinderRole.oxygen,
              o2PercentForRule: 50),
          GasRole.diluent);
      expect(resolveGasRole(blendRole: GasRole.diluent, o2PercentForRule: 50),
          GasRole.diluent);
      expect(
          resolveGasRole(
              tapped: GasRole.bailout,
              blendRole: GasRole.diluent,
              o2PercentForRule: 20),
          GasRole.bailout);
    });
    test('resolveGasRole: a known cylinder role wins over the mix', () =>
        expect(resolveGasRole(cylinderRole: CylinderRole.diluent, o2PercentForRule: 50), GasRole.diluent));
    test('resolveGasRole: a cylinder without a role follows the mix', () =>
        expect(resolveGasRole(cylinderRole: null, o2PercentForRule: 50), GasRole.bailout));
  });
}
