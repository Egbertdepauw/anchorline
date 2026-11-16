import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/ui/notifiers/blend_notifier.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SettingsNotifier settings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BlendNotifier> newNotifier() async {
    settings = SettingsNotifier();
    await settings.load();
    return BlendNotifier(settings: settings);
  }

  group('role guess', () {
    test('follows target O2 and capacity', () async {
      final n = await newNotifier();
      n.setTargetMix(18, 45);
      n.setWaterCapacity(3);
      expect(n.roleGuess.role, GasRole.diluent);
      n.setWaterCapacity(11.1);
      expect(n.roleGuess.role, GasRole.bailout);
      n.setTargetMix(50, 0);
      n.setWaterCapacity(3);
      expect(n.roleGuess.role, GasRole.bailout);
      expect(n.roleGuess.reason, 'O2 above 32%');
    });

    test('diluent size setting changes the guess', () async {
      final n = await newNotifier();
      n.setTargetMix(18, 45);
      n.setWaterCapacity(7);
      expect(n.role, GasRole.bailout);
      var notified = 0;
      n.addListener(() => notified++);
      await settings.setBlendDiluentMaxL(7);
      expect(notified, greaterThan(0));
      expect(n.role, GasRole.diluent);
    });

    test('override applies to this blend only', () async {
      final n = await newNotifier();
      n.setTargetMix(18, 45);
      n.setWaterCapacity(3);
      expect(n.roleOverridden, isFalse);
      n.overrideRole(GasRole.deco);
      expect(n.role, GasRole.deco);
      expect(n.roleOverridden, isTrue);
      n.openBlendSaved();
      expect(n.roleOverridden, isFalse);
      expect(n.role, GasRole.diluent);
    });
  });

  test('draftOpenBlend carries target, residual, top-off, capacity, role, '
      'name and time', () async {
    final n = await newNotifier();
    n.setTargetMix(18, 45);
    n.setTargetPressure(200);
    n.setCurrentMix(32, 10);
    n.setCurrentPressure(40);
    n.setTopoff(21, 0);
    n.setWaterCapacity(3);
    final at = DateTime.utc(2026, 11, 13, 9);
    final d = n.draftOpenBlend(blendedBy: '  Anna ', now: at);
    expect(d.target, const DesiredMix(18, 45));
    expect(d.targetPressureBar, 200);
    expect(d.residual, const DesiredMix(32, 10));
    expect(d.residualPressureBar, 40);
    expect(d.topoff, const DesiredMix(21, 0));
    expect(d.waterCapacityL, 3);
    expect(d.role, GasRole.diluent);
    expect(d.blendedBy, 'Anna');
    expect(d.blendedAt, at);
    expect(n.draftOpenBlend(blendedBy: '  ', now: at).blendedBy, isNull);
    expect(n.draftOpenBlend(now: at).blendedBy, isNull);
  });

  group('applyResidualAnalysis', () {
    test('rounds and fills', () async {
      final n = await newNotifier();
      n.applyResidualAnalysis(
          o2Percent: 31.6, hePercent: 9.4, pressureBar: 52.5);
      expect(n.currentOxygenPercent, 32);
      expect(n.currentHeliumPercent, 9);
      expect(n.currentPressureBar, 52.5);
    });

    test('null pressure keeps the pressure', () async {
      final n = await newNotifier();
      n.setCurrentPressure(40);
      n.applyResidualAnalysis(o2Percent: 21, hePercent: 0);
      expect(n.currentPressureBar, 40);
      expect(n.currentOxygenPercent, 21);
    });
  });
}
