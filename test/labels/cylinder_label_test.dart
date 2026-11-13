import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

final _when = DateTime(2026, 10, 31, 18, 5);

/// A saved analysis of [o2]/[he], optionally with a desired mix of
/// [desiredO2]/[desiredHe]. Only the fields the label reads are varied.
GasAnalysis _analysis(
  double o2,
  double he, {
  int? desiredO2,
  int? desiredHe,
  GasRole? role,
  String? by,
}) =>
    GasAnalysis(
      id: 'a1',
      analysedBy: by,
      analysedAt: _when,
      o2Percent: o2,
      hePercent: he,
      stable: true,
      targetO2Percent: desiredO2,
      targetHePercent: desiredHe,
      gasRole: role ?? GasRole.bailout,
    );

CylinderLabel _label(GasAnalysis a, {bool use14 = false}) =>
    CylinderLabel.fromAnalysis(a, use14ForDeeperMixes: use14);

void main() {
  // Keep this group FIRST. The label's date formatter is created lazily, once
  // per isolate, so it only picks up a wrong (device) locale if this is the
  // first test to touch it. A test above this one would make a dropped
  // 'en_US' go unnoticed.
  group('device locale', () {
    setUpAll(() => initializeDateFormatting('nl_NL'));
    tearDown(() => Intl.defaultLocale = null);

    test('keeps the English date and "." decimals under nl_NL', () {
      Intl.defaultLocale = 'nl_NL';
      // Sanity: the device locale really would have changed the date.
      expect(DateFormat('d MMM yy').format(_when), '31 okt 26');
      final l = _label(_analysis(20.6, 33.8, desiredO2: 21, desiredHe: 35));
      expect(l.footerRight, '31 Oct 26');
      expect(l.footerLeft, 'O2 20.6  He 33.8');
      final dil = _label(_analysis(20.6, 33.8, role: GasRole.diluent));
      expect(dil.diluentLeft, '1.3: 54 m');
    });
  });

  group('limitDepthMeters', () {
    test('no desired mix: the nearest 3 m stop', () {
      // EAN50 at 1.6 is 22.0 m; Tx21/35 at 1.4 is 56.7 m.
      expect(limitDepthMeters(50.0, 1.6), 21);
      expect(limitDepthMeters(21.0, 1.4), 57);
    });

    test('never a stop at which the gas is above 1.6', () {
      // 49 % at 1.6 is 22.7 m; the nearest stop, 24 m, would be 1.67.
      expect(limitDepthMeters(49.0, 1.6), 21);
    });

    test('at or below the desired O2: the stop rule', () {
      expect(limitDepthMeters(50.0, 1.6, desiredO2Percent: 50), 21);
      expect(limitDepthMeters(49.0, 1.6, desiredO2Percent: 50), 21);
      // 47 % at 1.6 is 24.0 m, 1.598 bar there: deeper than EAN50's 21 m,
      // and allowed.
      expect(limitDepthMeters(47.0, 1.6, desiredO2Percent: 50), 24);
    });

    test('above the desired O2: the exact depth, rounded down', () {
      // 52 % at 1.6 is 20.8 m: 20, not the 18 m stop.
      expect(limitDepthMeters(52.0, 1.6, desiredO2Percent: 50), 20);
      // 21.5 % at 1.4 is 55.1 m: 55, not the 54 m stop.
      expect(limitDepthMeters(21.5, 1.4, desiredO2Percent: 21), 55);
    });

    test('"above" compares the O2 as shown, to one decimal', () {
      // 21.04 shows as 21.0, the same as the desired 21: stop rule, 57.
      expect(limitDepthMeters(21.04, 1.4, desiredO2Percent: 21), 57);
      // 21.1 is above: (1.4 / 0.211 - 1) * 10 = 56.35 -> 56.
      expect(limitDepthMeters(21.1, 1.4, desiredO2Percent: 21), 56);
    });

    test('an exact whole-metre depth is not lost to floating-point noise', () {
      // (1.4 / 0.2 - 1) * 10 and (1.4 / 0.28 - 1) * 10 are 59.999... and
      // 39.999... in doubles, but the true values are 60 and 40.
      expect(limitDepthMeters(20.0, 1.4), 60);
      expect(limitDepthMeters(28.0, 1.4, desiredO2Percent: 27), 40);
    });

    test('is null when there is no oxygen', () {
      expect(limitDepthMeters(0, 1.6), isNull);
      expect(limitDepthMeters(-1, 1.6), isNull);
    });

    test('is null when the gas exceeds the limit at the surface', () {
      // 200 % O2 is not a real gas, but it must not print a negative depth.
      expect(limitDepthMeters(200, 1.6), isNull);
    });

    test('a depth of 0 m is still a depth', () {
      // (1.6 / 1.6 - 1) * 10 = 0
      expect(limitDepthMeters(160, 1.6), 0);
    });
  });

  group('bailoutModPpo2', () {
    test('is 1.6 for every mix when the setting is off', () {
      expect(bailoutModPpo2(o2PercentForRule: 21, use14ForDeeperMixes: false),
          1.6);
      expect(bailoutModPpo2(o2PercentForRule: 49, use14ForDeeperMixes: false),
          1.6);
    });

    test('is 1.4 below 50 % O2 when the setting is on', () {
      expect(bailoutModPpo2(o2PercentForRule: 21, use14ForDeeperMixes: true),
          1.4);
      expect(bailoutModPpo2(o2PercentForRule: 49, use14ForDeeperMixes: true),
          1.4);
    });

    test('is 1.6 from 50 % O2 up when the setting is on', () {
      expect(bailoutModPpo2(o2PercentForRule: 50, use14ForDeeperMixes: true),
          1.6);
      expect(bailoutModPpo2(o2PercentForRule: 100, use14ForDeeperMixes: true),
          1.6);
    });
  });

  group('bailout label', () {
    test('Tx21/35 analysed 20.6/33.8, setting off', () {
      // 67.7 m at 1.6; the nearest stop, 69 m, would be 1.63, so 66.
      final l = _label(_analysis(20.6, 33.8, desiredO2: 21, desiredHe: 35));
      expect(l.kind, CylinderLabelKind.bailout);
      expect(l.mixName, 'Tx21/35');
      expect(l.headlineMeters, 66);
      expect(l.headlineText, '66');
      expect(l.headlineCaption, 'MOD 1.6');
      expect(l.headlinePpo2, 1.6);
    });

    test('Tx21/35 analysed 20.6/33.8, setting on', () {
      final l = _label(_analysis(20.6, 33.8, desiredO2: 21, desiredHe: 35),
          use14: true);
      expect(l.mixName, 'Tx21/35');
      expect(l.headlineText, '57');
      expect(l.headlineCaption, 'MOD 1.4');
    });

    test('EAN50 analysed 49.6 keeps 1.6 because the desired O2 is 50', () {
      final l = _label(_analysis(49.6, 0, desiredO2: 50, desiredHe: 0),
          use14: true);
      expect(l.mixName, 'EAN50');
      expect(l.headlineText, '21');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('EAN49 analysed 49.6 uses 1.4 because the desired O2 is 49', () {
      // Above the desired 49: the exact 18.2 m, rounded down.
      final l = _label(_analysis(49.6, 0, desiredO2: 49, desiredHe: 0),
          use14: true);
      expect(l.mixName, 'EAN49');
      expect(l.headlineText, '18');
      expect(l.headlineCaption, 'MOD 1.4');
    });

    test('no desired mix: names and rules on the analysed O2, 49.6 -> 50', () {
      final l = _label(_analysis(49.6, 0), use14: true);
      expect(l.mixName, 'EAN50');
      expect(l.headlineText, '21');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('no desired mix: analysed 49.4 rounds to 49, so 1.4', () {
      final l = _label(_analysis(49.4, 0), use14: true);
      expect(l.mixName, 'EAN49');
      expect(l.headlineText, '18');
      expect(l.headlineCaption, 'MOD 1.4');
    });

    test('no desired mix: analysed 49.5 rounds up to 50, so 1.6', () {
      final l = _label(_analysis(49.5, 0), use14: true);
      expect(l.mixName, 'EAN50');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('a 3-digit MOD: analysed 11.4/70.2 for desired 11/70 is 130', () {
      // Setting off: 1.6 / 0.114 = 14.035 -> 130.35 m. Above the desired 11,
      // so rounded down rather than to a stop.
      final l = _label(_analysis(11.4, 70.2, desiredO2: 11, desiredHe: 70));
      expect(l.mixName, 'Tx11/70');
      expect(l.headlineMeters, 130);
      expect(l.headlineText, '130');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('the same 3-digit mix with the setting on is 112 at 1.4', () {
      final l = _label(_analysis(11.4, 70.2, desiredO2: 11, desiredHe: 70),
          use14: true);
      expect(l.headlineText, '112');
      expect(l.headlineCaption, 'MOD 1.4');
    });

    test('oxygen: desired 100/0 analysed 99.6 is O2, 6 m', () {
      final l = _label(_analysis(99.6, 0, desiredO2: 100, desiredHe: 0),
          use14: true);
      expect(l.mixName, 'O2');
      expect(l.headlineText, '6');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('no usable MOD prints a dash', () {
      final l = _label(_analysis(0, 0));
      expect(l.headlineMeters, isNull);
      expect(l.headlineText, '–');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('has no diluent fields or tag', () {
      final l = _label(_analysis(20.6, 33.8, desiredO2: 21, desiredHe: 35));
      expect(l.barTag, isNull);
      expect(l.diluentLeft, isNull);
      expect(l.diluentRight, isNull);
      expect(l.setpointMeters, isNull);
      expect(l.mod16Meters, isNull);
    });
  });

  group('mismatch', () {
    test('hard: desired 50/0, analysed 32.0/0 prints the analysed gas', () {
      final a = _analysis(32.0, 0, desiredO2: 50, desiredHe: 0);
      expect(a.match?.level, MixMatchLevel.hard);
      final l = _label(a, use14: true);
      expect(l.mixName, 'EAN32');
      // The 50 % test uses the analysed 32, not the desired 50.
      expect(l.headlineCaption, 'MOD 1.4');
      expect(l.headlineText, '33');
    });

    test('hard on helium alone still prints the analysed gas', () {
      final a = _analysis(21.0, 10.0, desiredO2: 21, desiredHe: 35);
      expect(a.match?.level, MixMatchLevel.hard);
      final l = _label(a);
      expect(l.mixName, 'Tx21/10');
    });

    test('red keeps the desired name (setting off)', () {
      final a = _analysis(36.5, 0, desiredO2: 32, desiredHe: 0);
      expect(a.match?.level, MixMatchLevel.red);
      final l = _label(a);
      expect(l.mixName, 'EAN32');
      expect(l.headlineText, '33');
      expect(l.headlineCaption, 'MOD 1.6');
    });

    test('red: the depth comes from the analysed O2, not the desired', () {
      // Desired EAN32 would give 40 m at 1.6; the 36.5 % in the cylinder
      // gives 33 m. The label must show 33.
      final l = _label(_analysis(36.5, 0, desiredO2: 32, desiredHe: 0));
      expect(l.headlineMeters, 33);
      expect(l.o2Percent, 36.5);
    });

    test('red uses the desired O2 for the 1.4 rule, the analysed for depth',
        () {
      // 5.0 off is still red, so the desired 50 % decides the rule: 50 is
      // not below 50, so 1.6 even with the setting on. The analysed 45.0 %
      // would have given 1.4. The depth is still the analysed 45.0 %'s:
      // (1.6 / 0.45 - 1) * 10 = 25.56; the nearest stop, 27 m, would be
      // 1.67, so 24.
      final a = _analysis(45.0, 0, desiredO2: 50, desiredHe: 0);
      expect(a.match?.level, MixMatchLevel.red);
      final l = _label(a, use14: true);
      expect(l.mixName, 'EAN50');
      expect(l.headlineCaption, 'MOD 1.6');
      expect(l.headlineText, '24');
    });

    test('hard: the stop rule, even when the analysis is above the desired',
        () {
      // The label names the analysed EAN50, so it gets EAN50's 21 m stop,
      // not the 22 m exact depth a richer-than-desired gas would get.
      final a = _analysis(50.0, 0, desiredO2: 32, desiredHe: 0);
      expect(a.match?.level, MixMatchLevel.hard);
      final l = _label(a);
      expect(l.mixName, 'EAN50');
      expect(l.headlineText, '21');
    });
  });

  group('stop depths (#145)', () {
    String depth(double o2, {int? desired, bool use14 = false}) {
      final a = _analysis(o2, 0,
          desiredO2: desired, desiredHe: desired == null ? null : 0);
      return _label(a, use14: use14).headlineText;
    }

    test('EAN50 at 50, 49 and 47 % gets the stop; at 52 % the exact depth',
        () {
      expect(depth(50.0, desired: 50), '21');
      expect(depth(49.0, desired: 50), '21');
      expect(depth(47.0, desired: 50), '24');
      expect(depth(52.0, desired: 50), '20');
    });

    test('Tx21/35 at 1.4: 57 m, or 55 m when it analyses at 21.5 %', () {
      expect(depth(21.0, desired: 21, use14: true), '57');
      expect(depth(21.5, desired: 21, use14: true), '55');
    });
  });

  group('diluent label', () {
    final dil = _analysis(20.6, 33.8,
        desiredO2: 21, desiredHe: 35, role: GasRole.diluent);

    test('shows TOD 1.1 as the headline with 1.3 and MOD 1.6 below', () {
      // 20.6 % is below the desired 21, so every line is a stop:
      // 43.4 m -> 42, 53.1 m -> 54, 67.7 m -> 66 (69 m would be 1.63).
      final l = _label(dil);
      expect(l.kind, CylinderLabelKind.diluent);
      expect(l.barTag, 'DIL');
      expect(l.mixName, 'Tx21/35');
      expect(l.headlineMeters, 42);
      expect(l.headlineText, '42');
      expect(l.headlineCaption, 'TOD 1.1');
      expect(l.headlinePpo2, 1.1);
      expect(l.setpointMeters, 54);
      expect(l.mod16Meters, 66);
      expect(l.diluentLeft, '1.3: 54 m');
      expect(l.diluentRight, 'MOD 1.6: 66 m');
    });

    test('a diluent above its desired O2 gets exact depths, rounded down', () {
      // 21.5 %: 41.2 m, 50.5 m and 64.4 m.
      final l = _label(_analysis(21.5, 35.0,
          desiredO2: 21, desiredHe: 35, role: GasRole.diluent));
      expect(l.headlineText, '41');
      expect(l.diluentLeft, '1.3: 50 m');
      expect(l.diluentRight, 'MOD 1.6: 64 m');
    });

    test('the 1.4 setting does not change a diluent label', () {
      final off = _label(dil);
      final on = _label(dil, use14: true);
      expect(on.headlineText, off.headlineText);
      expect(on.headlineCaption, off.headlineCaption);
      expect(on.diluentLeft, off.diluentLeft);
      expect(on.diluentRight, off.diluentRight);
    });

    test('a hard mismatch prints the analysed gas on a diluent label', () {
      final l = _label(_analysis(21.0, 10.0,
          desiredO2: 21, desiredHe: 35, role: GasRole.diluent));
      expect(l.mixName, 'Tx21/10');
      expect(l.barTag, 'DIL');
    });

    test('no usable depth prints dashes', () {
      final l = _label(_analysis(0, 0, role: GasRole.diluent));
      expect(l.headlineText, '–');
      expect(l.diluentLeft, '1.3: –');
      expect(l.diluentRight, 'MOD 1.6: –');
    });

    test('bailout role (explicit and default) is a bailout label', () {
      final explicit = _label(_analysis(20.6, 33.8, role: GasRole.bailout));
      final byDefault = _label(GasAnalysis(
        id: 'a2',
        analysedAt: _when,
        o2Percent: 20.6,
        hePercent: 33.8,
        stable: true,
      ));
      for (final l in [explicit, byDefault]) {
        expect(l.kind, CylinderLabelKind.bailout);
        expect(l.barTag, isNull);
        expect(l.diluentLeft, isNull);
      }
    });
  });

  group('new roles', () {
    test('deco and backgas print like bailout', () {
      final base =
          _label(_analysis(50, 0, desiredO2: 50, desiredHe: 0));
      for (final role in [GasRole.deco, GasRole.backgas]) {
        final l = _label(
            _analysis(50, 0, desiredO2: 50, desiredHe: 0, role: role));
        expect(l.kind, CylinderLabelKind.bailout);
        expect(l.headlineMeters, base.headlineMeters);
      }
    });
  });

  group('text', () {
    test('helium below the noise floor is left out of the footer', () {
      final l = _label(_analysis(20.6, 0.4));
      expect(l.hePercent, isNull);
      expect(l.footerLeft, 'O2 20.6');
      expect(l.mixName, 'Air');
    });

    test('helium at the noise floor is shown', () {
      final l = _label(_analysis(20.6, 1.0));
      expect(l.hePercent, 1.0);
      expect(l.footerLeft, 'O2 20.6  He 1.0');
    });

    test('footer shows one decimal and two spaces before He', () {
      final l = _label(_analysis(20.6, 33.8));
      expect(l.o2Percent, 20.6);
      expect(l.hePercent, 33.8);
      expect(l.footerLeft, 'O2 20.6  He 33.8');
      expect(_label(_analysis(32.14, 0)).footerLeft, 'O2 32.1');
    });

    test('the date is d MMM yy', () {
      final l = _label(_analysis(20.6, 33.8));
      expect(l.analysedAt, _when);
      expect(l.footerRight, '31 Oct 26');
    });

    test('blank analysed-by is null, otherwise trimmed', () {
      expect(_label(_analysis(20.6, 33.8, by: '  ')).analysedBy, isNull);
      expect(_label(_analysis(20.6, 33.8, by: '')).analysedBy, isNull);
      expect(_label(_analysis(20.6, 33.8)).analysedBy, isNull);
      expect(_label(_analysis(20.6, 33.8, by: ' EdP ')).analysedBy, 'EdP');
    });
  });

  group('testLabel', () {
    test('is Tx21/35 analysed 20.6/33.8 with no initials', () {
      final l = CylinderLabel.testLabel(
          now: DateTime(2026, 10, 31), use14ForDeeperMixes: false);
      expect(l.kind, CylinderLabelKind.bailout);
      expect(l.mixName, 'Tx21/35');
      expect(l.headlineText, '66');
      expect(l.headlineCaption, 'MOD 1.6');
      expect(l.analysedBy, isNull);
      expect(l.footerLeft, 'O2 20.6  He 33.8');
      expect(l.footerRight, '31 Oct 26');
    });

    test('follows the 1.4 setting', () {
      final l = CylinderLabel.testLabel(
          now: DateTime(2026, 10, 31), use14ForDeeperMixes: true);
      expect(l.headlineText, '57');
      expect(l.headlineCaption, 'MOD 1.4');
    });
  });
}
