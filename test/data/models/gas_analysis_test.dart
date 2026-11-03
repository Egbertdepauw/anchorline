import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

GasAnalysis analysis({
  String id = 'a',
  double o2 = 21.4,
  double he = 34.6,
  int? targetO2,
  int? targetHe,
  GasRole role = GasRole.bailout,
  String? analysedBy,
  String? notes,
}) =>
    GasAnalysis(
      id: id,
      analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
      o2Percent: o2,
      hePercent: he,
      stable: true,
      targetO2Percent: targetO2,
      targetHePercent: targetHe,
      gasRole: role,
      analysedBy: analysedBy,
      notes: notes,
    );

void main() {
  group('GasRole', () {
    test('dbValue is the stored string', () {
      expect(GasRole.bailout.dbValue, 'bailout');
      expect(GasRole.diluent.dbValue, 'diluent');
    });

    test('fromDb: only diluent is diluent', () {
      expect(GasRole.fromDb('diluent'), GasRole.diluent);
      expect(GasRole.fromDb(null), GasRole.bailout);
      expect(GasRole.fromDb('bailout'), GasRole.bailout);
      expect(GasRole.fromDb('stage'), GasRole.bailout);
      expect(GasRole.fromDb(''), GasRole.bailout);
    });

    test('gasRoleForCylinderRole: diluent cylinders are diluent', () {
      expect(gasRoleForCylinderRole('diluent'), GasRole.diluent);
      expect(gasRoleForCylinderRole('oxygen'), GasRole.bailout);
      expect(gasRoleForCylinderRole('offboard'), GasRole.bailout);
      expect(gasRoleForCylinderRole('bailout'), GasRole.bailout);
      expect(gasRoleForCylinderRole(null), GasRole.bailout);
    });
  });

  group('DesiredMix', () {
    test('name goes through gasMixName', () {
      expect(const DesiredMix(21, 35).name, 'Tx21/35');
      expect(const DesiredMix(21, 0).name, 'Air');
      expect(const DesiredMix(32, 0).name, 'EAN32');
    });

    test('value equality and hashCode', () {
      // Built at run time so they are two instances, not one const.
      DesiredMix mix(int o2, int he) => DesiredMix(o2, he);
      expect(mix(21, 35), mix(21, 35));
      expect(mix(21, 35).hashCode, mix(21, 35).hashCode);
      expect(mix(21, 35), isNot(mix(21, 30)));
      expect(mix(21, 35), isNot(mix(18, 35)));
      expect({mix(18, 45), mix(18, 45)}, hasLength(1));
    });
  });

  group('GasAnalysis desired mix', () {
    test('desiredMix is null without a target O2', () {
      expect(analysis().desiredMix, isNull);
      // A target He alone is not a desired mix.
      expect(analysis(targetHe: 35).desiredMix, isNull);
    });

    test('a null target He counts as 0', () {
      expect(analysis(targetO2: 32).desiredMix, const DesiredMix(32, 0));
      expect(analysis(targetO2: 21, targetHe: 35).desiredMix,
          const DesiredMix(21, 35));
    });

    test('match is null without a desired mix', () {
      expect(analysis().match, isNull);
      expect(analysis(targetHe: 35).match, isNull);
    });

    test('match grades the measured values against the desired mix', () {
      final m = analysis(o2: 21.4, he: 34.6, targetO2: 21, targetHe: 35).match!;
      expect(m.level, MixMatchLevel.match);
      expect(m.o2Off, 0.4);
      expect(m.heOff, 0.4);

      // Only a target O2: He is graded against 0.
      final m2 = analysis(o2: 32.4, he: 0, targetO2: 32).match!;
      expect(m2.level, MixMatchLevel.match);
      final m3 = analysis(o2: 32, he: 12, targetO2: 32).match!;
      expect(m3.level, MixMatchLevel.hard);
      expect(m3.heOff, 12.0);
    });
  });

  group('fromNew', () {
    test('copies every field of the new analysis', () {
      final n = NewGasAnalysis(
        cylinderId: 'c1',
        analysedBy: 'Egbert',
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 21.4,
        hePercent: 34.6,
        fillPressureBar: 232.5,
        tempC: 21.4,
        baroHpa: 1013.2,
        modPpo2s: const [1.1, 1.6],
        stable: true,
        notes: 'fill 3',
        desiredMix: const DesiredMix(21, 35),
        gasRole: GasRole.diluent,
        needsSignoff: true,
        captureSource: CaptureSource.bridgeOk,
        bridgeRecordId: 'a1b2c3d4e5f6/1a2b3c4d-7',
        analysedFor: 'Wendy',
      );
      final a = GasAnalysis.fromNew('id-1', n);
      expect(a.id, 'id-1');
      expect(a.cylinderId, 'c1');
      expect(a.analysedBy, 'Egbert');
      expect(a.analysedAt, DateTime.utc(2026, 10, 30, 18, 5));
      expect(a.o2Percent, 21.4);
      expect(a.hePercent, 34.6);
      expect(a.fillPressureBar, 232.5);
      expect(a.tempC, 21.4);
      expect(a.baroHpa, 1013.2);
      expect(a.modPpo2s, [1.1, 1.6]);
      expect(a.stable, isTrue);
      expect(a.notes, 'fill 3');
      expect(a.targetO2Percent, 21);
      expect(a.targetHePercent, 35);
      expect(a.desiredMix, const DesiredMix(21, 35));
      expect(a.gasRole, GasRole.diluent);
      expect(a.needsSignoff, isTrue);
      expect(a.captureSource, CaptureSource.bridgeOk);
      expect(a.bridgeRecordId, 'a1b2c3d4e5f6/1a2b3c4d-7');
      expect(a.analysedFor, 'Wendy');
    });

    test('no desired mix gives null targets and bailout by default', () {
      final a = GasAnalysis.fromNew(
        'id-2',
        NewGasAnalysis(
          analysedAt: DateTime.utc(2026, 10, 30),
          o2Percent: 32,
          hePercent: 0,
          stable: false,
        ),
      );
      expect(a.targetO2Percent, isNull);
      expect(a.targetHePercent, isNull);
      expect(a.desiredMix, isNull);
      expect(a.gasRole, GasRole.bailout);
      // A plain screen save: no flag, no bridge fields.
      expect(a.needsSignoff, isFalse);
      expect(a.captureSource, CaptureSource.screen);
      expect(a.bridgeRecordId, isNull);
      expect(a.analysedFor, isNull);
    });
  });

  group('CaptureSource', () {
    test('dbValue: a screen save stores null, the bridge stores bridge_ok',
        () {
      expect(CaptureSource.screen.dbValue, isNull);
      expect(CaptureSource.bridgeOk.dbValue, 'bridge_ok');
    });

    test('usb_ok round-trips', () {
      expect(CaptureSource.usbOk.dbValue, 'usb_ok');
      expect(CaptureSource.fromDb('usb_ok'), CaptureSource.usbOk);
    });

    test('fromDb: bridge_ok and usb_ok are captures, the rest screen saves',
        () {
      expect(CaptureSource.fromDb('bridge_ok'), CaptureSource.bridgeOk);
      expect(CaptureSource.fromDb(null), CaptureSource.screen);
      expect(CaptureSource.fromDb(''), CaptureSource.screen);
      expect(CaptureSource.fromDb('screen'), CaptureSource.screen);
      expect(CaptureSource.fromDb('something_new'), CaptureSource.screen);
    });
  });

  group('withNeedsSignoff', () {
    test('changes only the flag', () {
      final before = GasAnalysis(
        id: 'a',
        cylinderId: 'c1',
        cylinderLabel: 'S80 left',
        cylinderDeleted: true,
        analysedBy: 'Egbert',
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 21.4,
        hePercent: 34.6,
        fillPressureBar: 232.5,
        tempC: 21.4,
        baroHpa: 1013.2,
        modPpo2s: const [1.1, 1.4, 1.6],
        stable: true,
        notes: 'old',
        targetO2Percent: 18,
        targetHePercent: 45,
        gasRole: GasRole.diluent,
        needsSignoff: true,
        captureSource: CaptureSource.usbOk,
        bridgeRecordId: 'usb/1a2b3c4d-7',
        analysedFor: 'Wendy',
      );
      for (final value in [false, true]) {
        final after = before.withNeedsSignoff(value);
        expect(after.needsSignoff, value);
        expect(after.id, before.id);
        expect(after.cylinderId, before.cylinderId);
        expect(after.cylinderLabel, before.cylinderLabel);
        expect(after.cylinderDeleted, before.cylinderDeleted);
        expect(after.analysedBy, before.analysedBy);
        expect(after.analysedAt, before.analysedAt);
        expect(after.o2Percent, before.o2Percent);
        expect(after.hePercent, before.hePercent);
        expect(after.fillPressureBar, before.fillPressureBar);
        expect(after.tempC, before.tempC);
        expect(after.baroHpa, before.baroHpa);
        expect(after.modPpo2s, before.modPpo2s);
        expect(after.stable, before.stable);
        expect(after.notes, before.notes);
        expect(after.targetO2Percent, before.targetO2Percent);
        expect(after.targetHePercent, before.targetHePercent);
        expect(after.gasRole, before.gasRole);
        expect(after.captureSource, before.captureSource);
        expect(after.bridgeRecordId, before.bridgeRecordId);
        expect(after.analysedFor, before.analysedFor);
      }
    });

    test('leaves the original alone', () {
      final before = analysis();
      before.withNeedsSignoff(true);
      expect(before.needsSignoff, isFalse);
    });
  });

  group('applyEdit', () {
    test('changes only the editable fields', () {
      final before = GasAnalysis(
        id: 'a',
        cylinderId: 'c1',
        cylinderLabel: 'S80 left',
        cylinderDeleted: true,
        analysedBy: 'Egbert',
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 21.4,
        hePercent: 34.6,
        fillPressureBar: 232.5,
        tempC: 21.4,
        baroHpa: 1013.2,
        modPpo2s: const [1.1, 1.4, 1.6],
        stable: true,
        notes: 'old',
        targetO2Percent: 18,
        targetHePercent: 45,
        gasRole: GasRole.bailout,
        needsSignoff: true,
        captureSource: CaptureSource.bridgeOk,
        bridgeRecordId: 'a1b2c3d4e5f6/1a2b3c4d-7',
        analysedFor: 'Wendy',
      );
      final after = before.applyEdit(const GasAnalysisEdit(
        desiredMix: DesiredMix(21, 35),
        gasRole: GasRole.diluent,
        analysedBy: 'Sam',
        notes: 'new',
        cylinderId: 'c1', // the same cylinder
        fillPressureBar: 210,
        analysedFor: 'Alex',
      ));

      // Edited.
      expect(after.desiredMix, const DesiredMix(21, 35));
      expect(after.gasRole, GasRole.diluent);
      expect(after.analysedBy, 'Sam');
      expect(after.notes, 'new');
      expect(after.fillPressureBar, 210);
      expect(after.analysedFor, 'Alex');
      // The same cylinder keeps its joined label.
      expect(after.cylinderId, 'c1');
      expect(after.cylinderLabel, 'S80 left');
      expect(after.cylinderDeleted, isTrue);
      // Untouched.
      expect(after.id, 'a');
      expect(after.analysedAt, DateTime.utc(2026, 10, 30, 18, 5));
      expect(after.o2Percent, 21.4);
      expect(after.hePercent, 34.6);
      expect(after.tempC, 21.4);
      expect(after.baroHpa, 1013.2);
      expect(after.modPpo2s, [1.1, 1.4, 1.6]);
      expect(after.stable, isTrue);
      expect(after.captureSource, CaptureSource.bridgeOk);
      expect(after.bridgeRecordId, 'a1b2c3d4e5f6/1a2b3c4d-7');
      // No sign-off asked for: the flag stays.
      expect(after.needsSignoff, isTrue);
    });

    test('a different cylinder drops the joined label, null clears the link',
        () {
      final before = GasAnalysis(
        id: 'a',
        cylinderId: 'c1',
        cylinderLabel: 'S80 left',
        cylinderDeleted: true,
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
      );
      GasAnalysisEdit edit(String? cylinderId) => GasAnalysisEdit(
            desiredMix: null,
            gasRole: GasRole.bailout,
            analysedBy: null,
            notes: null,
            cylinderId: cylinderId,
            fillPressureBar: null,
            analysedFor: null,
          );

      final other = before.applyEdit(edit('c2'));
      expect(other.cylinderId, 'c2');
      expect(other.cylinderLabel, isNull);
      expect(other.cylinderDeleted, isFalse);

      final none = before.applyEdit(edit(null));
      expect(none.cylinderId, isNull);
      expect(none.cylinderLabel, isNull);
      expect(none.cylinderDeleted, isFalse);
      expect(none.cylinderDisplay, isNull);
    });

    test('signOff clears needsSignoff; without it the flag is kept', () {
      GasAnalysisEdit edit({required bool signOff}) => GasAnalysisEdit(
            desiredMix: null,
            gasRole: GasRole.bailout,
            analysedBy: null,
            notes: null,
            cylinderId: null,
            fillPressureBar: null,
            analysedFor: null,
            signOff: signOff,
          );
      final flagged = GasAnalysis(
        id: 'a',
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
        needsSignoff: true,
      );

      expect(flagged.applyEdit(edit(signOff: true)).needsSignoff, isFalse);
      expect(flagged.applyEdit(edit(signOff: false)).needsSignoff, isTrue);
      // Signing off an unflagged entry leaves it unflagged.
      final plain = GasAnalysis(
        id: 'b',
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 32,
        hePercent: 0,
        stable: true,
      );
      expect(plain.applyEdit(edit(signOff: true)).needsSignoff, isFalse);
      expect(plain.applyEdit(edit(signOff: false)).needsSignoff, isFalse);
    });

    test('an edit with no desired mix clears the targets', () {
      final after = analysis(targetO2: 18, targetHe: 45).applyEdit(
        const GasAnalysisEdit(
          desiredMix: null,
          gasRole: GasRole.bailout,
          analysedBy: null,
          notes: null,
          cylinderId: null,
          fillPressureBar: null,
          analysedFor: null,
        ),
      );
      expect(after.targetO2Percent, isNull);
      expect(after.targetHePercent, isNull);
      expect(after.desiredMix, isNull);
      expect(after.match, isNull);
    });
  });

  group('recentDesiredMixes', () {
    GasAnalysis withMix(int? o2, [int? he = 0]) =>
        analysis(targetO2: o2, targetHe: he);

    test('is empty with nothing to offer', () {
      expect(recentDesiredMixes(const []), isEmpty);
      expect(recentDesiredMixes([withMix(null)]), isEmpty);
    });

    test('the blend target comes first', () {
      final out = recentDesiredMixes(
        [withMix(32), withMix(21, 35)],
        blendTarget: const DesiredMix(18, 45),
      );
      expect(out, [
        const DesiredMix(18, 45),
        const DesiredMix(32, 0),
        const DesiredMix(21, 35),
      ]);
    });

    test('drops duplicates of the blend target and of each other', () {
      final out = recentDesiredMixes(
        [withMix(32), withMix(18, 45), withMix(32), withMix(21, 35)],
        blendTarget: const DesiredMix(18, 45),
      );
      expect(out, [
        const DesiredMix(18, 45),
        const DesiredMix(32, 0),
        const DesiredMix(21, 35),
      ]);
    });

    test('keeps the log order without a blend target', () {
      expect(
        recentDesiredMixes([withMix(21, 35), withMix(32), withMix(21, 35)]),
        [const DesiredMix(21, 35), const DesiredMix(32, 0)],
      );
    });

    test('only the first 10 analyses count', () {
      final log = [
        for (var i = 0; i < 10; i++) withMix(30 + i),
        withMix(50), // the 11th: excluded
      ];
      final out = recentDesiredMixes(log);
      expect(out, hasLength(10));
      expect(out, isNot(contains(const DesiredMix(50, 0))));
      expect(out.first, const DesiredMix(30, 0));
      expect(out.last, const DesiredMix(39, 0));
    });

    test('lookback is adjustable', () {
      final log = [withMix(30), withMix(31), withMix(32)];
      expect(recentDesiredMixes(log, lookback: 2),
          [const DesiredMix(30, 0), const DesiredMix(31, 0)]);
    });

    test('analyses without a desired mix are skipped', () {
      final out = recentDesiredMixes([
        withMix(null),
        withMix(32),
        withMix(null),
        withMix(21, 35),
      ]);
      expect(out, [const DesiredMix(32, 0), const DesiredMix(21, 35)]);
    });

    test('an analysis without a mix still uses up a lookback slot', () {
      final log = [
        withMix(null),
        withMix(null),
        withMix(32),
      ];
      expect(recentDesiredMixes(log, lookback: 2), isEmpty);
    });
  });
}
