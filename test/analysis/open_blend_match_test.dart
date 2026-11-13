import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/analysis/open_blend_match.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/data/models/open_blend.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 13, 12);

OpenBlend ob(
  String id,
  int o2,
  int he, {
  int minutesAgo = 0,
  GasRole role = GasRole.bailout,
}) =>
    OpenBlend(
      id: id,
      target: DesiredMix(o2, he),
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 11.1,
      role: role,
      blendedBy: null,
      blendedAt: _now.subtract(Duration(minutes: minutesAgo)),
    );

void main() {
  group('blendForAnalysis', () {
    test('oldest of two equal mixes is chosen', () {
      final open = [
        ob('new', 18, 45, minutesAgo: 30),
        ob('old', 18, 45, minutesAgo: 90),
      ];
      final b = blendForAnalysis(
        o2Percent: 18.4,
        hePercent: 44.5,
        choice: const AutoBlend(),
        residual: false,
        open: open,
      );
      expect(b?.id, 'old');
    });

    test('match beats orange', () {
      // 18/37 is an orange (O2 2.0, He 2.0 off), 21/35 a match, listed first.
      final open = [ob('orange', 18, 37), ob('match', 21, 35)];
      final r = rankOpenBlends(o2Percent: 20.0, hePercent: 35.0, open: open);
      expect(r.map((e) => e.grade.level),
          [MixMatchLevel.match, MixMatchLevel.orange]);
      expect(r.first.blend.id, 'match');
    });

    test('of two oranges the smaller O2 difference wins', () {
      final open = [ob('far', 18, 0), ob('near', 21, 0)];
      final r = rankOpenBlends(o2Percent: 19.6, hePercent: 0, open: open);
      expect(r.map((e) => e.grade.level),
          [MixMatchLevel.orange, MixMatchLevel.orange]);
      expect(r.first.blend.id, 'near');
    });

    test('no blend within orange closes nothing', () {
      final open = [ob('x', 50, 0)];
      expect(
        blendForAnalysis(
          o2Percent: 55.0,
          hePercent: 0,
          choice: const AutoBlend(),
          residual: false,
          open: open,
        ),
        isNull,
      );
      final n = nearestUnmatched(o2Percent: 55.0, hePercent: 0, open: open);
      expect(n?.blend.id, 'x');
      expect(n?.grade.level, MixMatchLevel.red);
    });

    test('nearestUnmatched is null for none or a match', () {
      expect(nearestUnmatched(o2Percent: 50, hePercent: 0, open: []), isNull);
      expect(
        nearestUnmatched(
            o2Percent: 50, hePercent: 0, open: [ob('x', 50, 0)]),
        isNull,
      );
    });

    test('a chosen mix closes the oldest blend of exactly that mix', () {
      final open = [ob('a', 21, 35, minutesAgo: 10), ob('b', 18, 45)];
      final b = blendForAnalysis(
        o2Percent: 18.0,
        hePercent: 45.0,
        choice: const AutoBlend(),
        chosenMix: const DesiredMix(21, 35),
        residual: false,
        open: open,
      );
      expect(b?.id, 'a');
    });

    test('a chosen mix with no blend of that mix closes nothing', () {
      final b = blendForAnalysis(
        o2Percent: 18.0,
        hePercent: 45.0,
        choice: const AutoBlend(),
        chosenMix: const DesiredMix(21, 35),
        residual: false,
        open: [ob('b', 18, 45)],
      );
      expect(b, isNull);
    });

    test('PickedBlend closes a hard-mismatched blend', () {
      final picked = ob('x', 50, 0);
      final b = blendForAnalysis(
        o2Percent: 55,
        hePercent: 0,
        choice: PickedBlend(picked),
        residual: false,
        open: [picked],
      );
      expect(b, same(picked));
    });

    test('NoBlend closes nothing', () {
      final b = blendForAnalysis(
        o2Percent: 50,
        hePercent: 0,
        choice: const NoBlend(),
        residual: false,
        open: [ob('x', 50, 0)],
      );
      expect(b, isNull);
    });

    test('residual never closes', () {
      final b = blendForAnalysis(
        o2Percent: 50,
        hePercent: 0,
        choice: const AutoBlend(),
        residual: true,
        open: [ob('x', 50, 0)],
      );
      expect(b, isNull);
    });
  });

  group('settleState', () {
    SettleState s(int minutes, int settle) => settleState(
        sinceBlended: Duration(minutes: minutes), settleMinutes: settle);
    test('thresholds', () {
      expect(s(29, 60), SettleState.red);
      expect(s(30, 60), SettleState.orange);
      expect(s(59, 60), SettleState.orange);
      expect(s(60, 60), SettleState.green);
      expect(s(0, 0), SettleState.green);
      expect(s(-5, 60), SettleState.red);
    });
  });

  group('guessBlendRole', () {
    RoleGuess g(int o2, double cap, double max) => guessBlendRole(
        targetO2Percent: o2, waterCapacityL: cap, diluentMaxL: max);
    test('rules', () {
      var r = g(33, 3, 3);
      expect(r.role, GasRole.bailout);
      expect(r.reason, 'O2 above 32%');
      r = g(32, 3, 3);
      expect(r.role, GasRole.diluent);
      expect(r.reason, '3 L');
      expect(g(21, 3.0, 3.0).role, GasRole.diluent);
      r = g(21, 7, 3);
      expect(r.role, GasRole.bailout);
      expect(r.reason, '7 L');
      expect(g(21, 7, 7).role, GasRole.diluent);
      expect(g(21, 11.1, 3).reason, '11.1 L');
    });
  });

  group('mixWarning', () {
    MixWarning? w(GasRole role, double o2, double he, DesiredMix t) =>
        mixWarning(
          role: role,
          o2Percent: o2,
          hePercent: he,
          target: t,
          use14ForDeeperMixes: false,
        );
    test('deco above target is loud', () {
      final r = w(GasRole.deco, 52.0, 0, const DesiredMix(50, 0));
      expect(r?.level, WarningLevel.loud);
      expect(r?.text, 'O2 52.0% instead of 50%: MOD at 1.6 is 20 m, not 21 m.');
    });
    test('backgas above target is loud', () {
      expect(w(GasRole.backgas, 22.5, 35, const DesiredMix(21, 35))?.level,
          WarningLevel.loud);
    });
    test('deco below target is mild', () {
      final r = w(GasRole.deco, 48.5, 0, const DesiredMix(50, 0));
      expect(r?.level, WarningLevel.mild);
      expect(r?.text, 'Analysed EAN49, target EAN50');
    });
    test('diluent above target is mild', () {
      expect(w(GasRole.diluent, 23.0, 35, const DesiredMix(21, 35))?.level,
          WarningLevel.mild);
    });
    test('helium-only mismatch is mild', () {
      expect(w(GasRole.backgas, 21.04, 38, const DesiredMix(21, 35))?.level,
          WarningLevel.mild);
      expect(w(GasRole.deco, 21.4, 38, const DesiredMix(21, 35))?.level,
          WarningLevel.mild);
    });
    test('deco 51.5 against 50 is loud', () {
      expect(w(GasRole.deco, 51.5, 0, const DesiredMix(50, 0))?.level,
          WarningLevel.loud);
    });
    test('hard mismatch matches the label', () {
      final r = mixWarning(
        role: GasRole.deco,
        o2Percent: 51.0,
        hePercent: 0,
        target: const DesiredMix(45, 0),
        use14ForDeeperMixes: true,
      );
      final label = CylinderLabel.fromAnalysis(
        GasAnalysis(
          id: 'a',
          analysedAt: _now,
          o2Percent: 51.0,
          hePercent: 0,
          stable: true,
          targetO2Percent: 45,
          targetHePercent: 0,
          gasRole: GasRole.deco,
        ),
        use14ForDeeperMixes: true,
      );
      expect(label.headlinePpo2, 1.6);
      expect(r?.level, WarningLevel.loud);
      expect(r?.text,
          'O2 51.0% instead of 45%: MOD at 1.6 is ${label.headlineMeters} m, not 24 m.');
    });
    test('a match is null', () {
      expect(w(GasRole.deco, 50.4, 0, const DesiredMix(50, 0)), isNull);
    });
  });
}
