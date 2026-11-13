import 'package:ccrlogger/analysis/mix_match.dart';
import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> insertCylinder(PowerSyncDatabase ps, String id, String label,
          {int? deletedAt, String role = 'bailout'}) =>
      ps.execute(
        'INSERT INTO cylinders (id, owner_id, label, role, volume_liters, '
        'working_pressure_bar, created_at, updated_at, deleted_at, version, '
        'sync_status) VALUES (?, ?, ?, ?, 11.0, 232, 0, 0, ?, 1, 0)',
        [id, 'u1', label, role, deletedAt],
      );

  /// A row as an older build or another device could have written it: only
  /// the columns that existed before the label fields, plus whatever the
  /// test passes in [extra].
  Future<void> insertRawAnalysis(PowerSyncDatabase ps, String id,
      {Map<String, Object?> extra = const {}}) {
    final cols = <String, Object?>{
      'id': id,
      'owner_id': 'u1',
      'analysed_at': DateTime(2026, 10, 30, 18, 5).millisecondsSinceEpoch,
      'o2_percent': 32.0,
      'he_percent': 0.0,
      'stable': 1,
      'created_at': 0,
      'updated_at': 0,
      'version': 1,
      'sync_status': 0,
      ...extra,
    };
    return ps.execute(
      'INSERT INTO gas_analyses (${cols.keys.join(', ')}) '
      'VALUES (${List.filled(cols.length, '?').join(', ')})',
      cols.values.toList(),
    );
  }

  NewGasAnalysis analysis({
    String? cylinderId,
    DateTime? at,
    double o2 = 21.4,
    double he = 34.6,
    bool stable = true,
    DesiredMix? desiredMix,
    GasRole gasRole = GasRole.bailout,
    bool needsSignoff = false,
    bool isResidual = false,
    CaptureSource captureSource = CaptureSource.screen,
    String? bridgeRecordId,
    String? analysedFor,
  }) =>
      NewGasAnalysis(
        cylinderId: cylinderId,
        analysedBy: '  Egbert ',
        analysedAt: at ?? DateTime(2026, 10, 30, 18, 5),
        o2Percent: o2,
        hePercent: he,
        fillPressureBar: 232.5,
        tempC: 21.4,
        baroHpa: 1013.2,
        modPpo2s: const [1.1, 1.4, 1.6],
        stable: stable,
        notes: '',
        desiredMix: desiredMix,
        gasRole: gasRole,
        needsSignoff: needsSignoff,
        isResidual: isResidual,
        captureSource: captureSource,
        bridgeRecordId: bridgeRecordId,
        analysedFor: analysedFor,
      );

  test('add round-trips every stored field at full precision', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertCylinder(ps, 'c1', 'S80 #2');

    final id = await dao.add(analysis(cylinderId: 'c1'));
    final list = await dao.list();
    expect(list, hasLength(1));
    final a = list.single;
    expect(a.id, id);
    expect(a.cylinderId, 'c1');
    expect(a.cylinderLabel, 'S80 #2');
    expect(a.cylinderDisplay, 'S80 #2');
    expect(a.analysedBy, 'Egbert'); // trimmed
    expect(a.analysedAt, DateTime(2026, 10, 30, 18, 5));
    expect(a.o2Percent, 21.4);
    expect(a.hePercent, 34.6);
    expect(a.fillPressureBar, 232.5);
    expect(a.tempC, 21.4);
    expect(a.baroHpa, 1013.2);
    expect(a.modPpo2s, [1.1, 1.4, 1.6]);
    expect(a.stable, isTrue);
    expect(a.notes, isNull); // blank → null
    // Derived, not stored: whole-number mix name and MODs.
    expect(a.mixName, 'Tx21/35');
    expect(a.modAt(1.4), closeTo(55.42, 0.01));
  });

  test('insert stamps owner_id and sync metadata', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u-7'));
    final id = await dao.add(analysis(stable: false));
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['owner_id'], 'u-7');
    expect(row['version'], 1);
    expect(row['sync_status'], 0);
    expect(row['deleted_at'], isNull);
    expect(row['created_at'], isA<int>());
    expect(row['updated_at'], row['created_at']);
    expect(row['stable'], 0);
  });

  test('list is newest first and filters by cylinder', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(
        analysis(cylinderId: 'c1', at: DateTime(2026, 1, 1), o2: 32, he: 0));
    await dao.add(
        analysis(cylinderId: 'c2', at: DateTime(2026, 3, 1), o2: 50, he: 0));
    await dao.add(
        analysis(cylinderId: 'c1', at: DateTime(2026, 2, 1), o2: 21, he: 0));

    expect((await dao.list()).map((a) => a.mixName),
        ['EAN50', 'Air', 'EAN32']);
    expect((await dao.list(cylinderId: 'c1')).map((a) => a.mixName),
        ['Air', 'EAN32']);
  });

  test('list only returns the signed-in owner\'s rows', () async {
    final ps = await openPowerSyncForTest();
    await GasAnalysesDao(ps, FakeSessionSource()..setUserId('other'))
        .add(analysis());
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(analysis(o2: 32, he: 0));
    expect((await dao.list()).map((a) => a.mixName), ['EAN32']);
  });

  test('softDelete hides the row and bumps version', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis());
    await dao.softDelete(id);
    expect(await dao.list(), isEmpty);
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['deleted_at'], isNotNull);
    expect(row['version'], 2);
    // Unknown id is a no-op.
    await dao.softDelete('nope');
  });

  test('deleted and unknown cylinders still show the analysis', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertCylinder(ps, 'gone', 'Old AL40', deletedAt: 5);
    await dao.add(analysis(cylinderId: 'gone', at: DateTime(2026, 2, 1)));
    await dao
        .add(analysis(cylinderId: 'never-synced', at: DateTime(2026, 1, 1)));
    await dao.add(analysis(at: DateTime(2025, 1, 1)));

    final list = await dao.list();
    expect(list.map((a) => a.cylinderDisplay),
        ['Old AL40 (deleted)', 'Unknown cylinder', null]);
  });

  test('listCylinderChoices lists live cylinders by label', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertCylinder(ps, 'b', 'S80 b');
    await insertCylinder(ps, 'a', 'al40');
    await insertCylinder(ps, 'x', 'Deleted', deletedAt: 1);
    final choices = await dao.listCylinderChoices();
    expect(choices.map((c) => c.id), ['a', 'b']);
    expect(choices.map((c) => c.label), ['al40', 'S80 b']);
  });

  test('listCylinderChoices returns the cylinder role', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertCylinder(ps, 'a', 'al40'); // helper default: bailout
    await insertCylinder(ps, 'b', 'D7', role: 'diluent');
    final choices = await dao.listCylinderChoices();
    expect(choices.map((c) => c.role), ['bailout', 'diluent']);
    expect(gasRoleForCylinderRole(choices.last.role), GasRole.diluent);
  });

  test('add round-trips the desired mix and the gas role', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));

    final id = await dao.add(analysis(
      desiredMix: const DesiredMix(21, 35),
      gasRole: GasRole.diluent,
    ));
    final a = (await dao.list()).single;
    expect(a.desiredMix, const DesiredMix(21, 35));
    expect(a.targetO2Percent, 21);
    expect(a.targetHePercent, 35);
    expect(a.gasRole, GasRole.diluent);
    expect(a.match!.level, MixMatchLevel.match);

    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['target_o2_percent'], 21);
    expect(row['target_he_percent'], 35);
    expect(row['gas_role'], 'diluent');
  });

  test('add without a desired mix stores null targets and bailout', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis());
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['target_o2_percent'], isNull);
    expect(row['target_he_percent'], isNull);
    expect(row['gas_role'], 'bailout');
    final a = (await dao.list()).single;
    expect(a.desiredMix, isNull);
    expect(a.match, isNull);
    expect(a.gasRole, GasRole.bailout);
  });

  test('update changes the editable fields and bumps version', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(desiredMix: const DesiredMix(18, 45)));
    // Make updated_at observably change even within the same millisecond.
    await ps
        .execute('UPDATE gas_analyses SET updated_at = 0 WHERE id = ?', [id]);

    await dao.update(
      id,
      const GasAnalysisEdit(
        desiredMix: DesiredMix(21, 35),
        gasRole: GasRole.diluent,
        analysedBy: '  Sam  ',
        notes: ' topped up ',
        cylinderId: null,
        fillPressureBar: 232.5,
        analysedFor: null,
      ),
    );

    final a = (await dao.list()).single;
    expect(a.desiredMix, const DesiredMix(21, 35));
    expect(a.gasRole, GasRole.diluent);
    expect(a.analysedBy, 'Sam'); // trimmed
    expect(a.notes, 'topped up'); // trimmed

    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['version'], 2);
    expect(row['updated_at'], greaterThan(0));
    expect(row['deleted_at'], isNull);
    // Measured values are never touched.
    expect(row['o2_percent'], 21.4);
    expect(row['he_percent'], 34.6);
    expect(row['fill_pressure_bar'], 232.5);
    expect(row['analysed_at'],
        DateTime(2026, 10, 30, 18, 5).millisecondsSinceEpoch);
  });

  test('update with blanks clears the desired mix, name and notes', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(desiredMix: const DesiredMix(18, 45)));

    await dao.update(
      id,
      const GasAnalysisEdit(
        desiredMix: null,
        gasRole: GasRole.bailout,
        analysedBy: '   ',
        notes: '',
        cylinderId: null,
        fillPressureBar: 232.5,
        analysedFor: null,
      ),
    );

    final a = (await dao.list()).single;
    expect(a.desiredMix, isNull);
    expect(a.analysedBy, isNull);
    expect(a.notes, isNull);
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['target_o2_percent'], isNull);
    expect(row['target_he_percent'], isNull);
  });

  test('update of an unknown id does nothing', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis());
    await dao.update(
      'nope',
      const GasAnalysisEdit(
        desiredMix: DesiredMix(32, 0),
        gasRole: GasRole.diluent,
        analysedBy: 'x',
        notes: 'x',
        cylinderId: null,
        fillPressureBar: null,
        analysedFor: null,
      ),
    );
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['version'], 1);
    expect(row['gas_role'], 'bailout');
    expect(await ps.getAll('SELECT id FROM gas_analyses'), hasLength(1));
  });

  // -- Bridge fields and the sign-off flag (#113) --------------------------

  const bridgeId = 'a1b2c3d4e5f6/1a2b3c4d-7';

  /// An edit that changes nothing a test isn't about: the entry's own
  /// cylinder (none) and fill pressure ([analysis] saves 232.5), and the
  /// stated values of [analysis].
  GasAnalysisEdit sameEdit({
    String? cylinderId,
    double? fillPressureBar = 232.5,
    String? analysedFor,
    bool signOff = false,
  }) =>
      GasAnalysisEdit(
        desiredMix: null,
        gasRole: GasRole.bailout,
        analysedBy: 'Egbert',
        notes: null,
        cylinderId: cylinderId,
        fillPressureBar: fillPressureBar,
        analysedFor: analysedFor,
        signOff: signOff,
      );

  test('add round-trips the bridge fields', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(
      needsSignoff: true,
      captureSource: CaptureSource.bridgeOk,
      bridgeRecordId: bridgeId,
      analysedFor: '  Alex ',
    ));

    final a = (await dao.list()).single;
    expect(a.needsSignoff, isTrue);
    expect(a.captureSource, CaptureSource.bridgeOk);
    expect(a.bridgeRecordId, bridgeId);
    expect(a.analysedFor, 'Alex'); // trimmed

    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['needs_signoff'], 1);
    expect(row['capture_source'], 'bridge_ok');
    expect(row['bridge_record_id'], bridgeId);
    expect(row['analysed_for'], 'Alex');
  });

  test('add of a plain screen save stores 0 and nulls, never a null flag',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(analysedFor: '   '));
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['needs_signoff'], 0);
    expect(row['capture_source'], isNull);
    expect(row['bridge_record_id'], isNull);
    expect(row['analysed_for'], isNull); // blank -> null
  });

  test('a row without the new columns reads as an unflagged screen save',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertRawAnalysis(ps, 'old-1');
    final a = (await dao.list()).single;
    expect(a.needsSignoff, isFalse);
    expect(a.captureSource, CaptureSource.screen);
    expect(a.bridgeRecordId, isNull);
    expect(a.analysedFor, isNull);
  });

  test('addFromBridge inserts once per id', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    expect(
        await dao.addFromBridge(
            'id-1',
            analysis(
                needsSignoff: true,
                captureSource: CaptureSource.bridgeOk,
                bridgeRecordId: bridgeId)),
        isTrue);
    expect(await dao.addFromBridge('id-1', analysis(o2: 30)), isFalse);
    final a = (await dao.list()).single;
    expect(a.id, 'id-1');
    expect(a.o2Percent, 21.4);
    expect(a.needsSignoff, isTrue);
    expect(a.captureSource, CaptureSource.bridgeOk);
    expect(await ps.getAll('SELECT id FROM gas_analyses'), hasLength(1));
  });

  test('addFromBridge stamps owner_id and sync metadata like add', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u-7'));
    await dao.addFromBridge('id-1', analysis());
    final row =
        await ps.get('SELECT * FROM gas_analyses WHERE id = ?', ['id-1']);
    expect(row['owner_id'], 'u-7');
    expect(row['version'], 1);
    expect(row['sync_status'], 0);
    expect(row['deleted_at'], isNull);
    expect(row['updated_at'], row['created_at']);
  });

  test('addFromBridge never brings back a soft-deleted row', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.addFromBridge('id-1', analysis());
    await dao.softDelete('id-1');
    expect(await dao.addFromBridge('id-1', analysis()), isFalse);
    expect(await dao.list(), isEmpty);
    final row =
        await ps.get('SELECT * FROM gas_analyses WHERE id = ?', ['id-1']);
    expect(row['deleted_at'], isNotNull);
  });

  test('setNeedsSignoff bumps version and updated_at', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(needsSignoff: true));
    await ps
        .execute('UPDATE gas_analyses SET updated_at = 0 WHERE id = ?', [id]);

    await dao.setNeedsSignoff(id, false);

    expect((await dao.list()).single.needsSignoff, isFalse);
    var row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['needs_signoff'], 0);
    expect(row['version'], 2);
    expect(row['updated_at'], greaterThan(0));
    expect(row['deleted_at'], isNull);

    await dao.setNeedsSignoff(id, true);
    expect((await dao.list()).single.needsSignoff, isTrue);
    row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['needs_signoff'], 1);
    expect(row['version'], 3);

    // Unknown id is a no-op.
    await dao.setNeedsSignoff('nope', true);
    expect(await ps.getAll('SELECT id FROM gas_analyses'), hasLength(1));
  });

  test(
      'update writes cylinder, fill pressure and analysed for, never '
      'measured values', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertCylinder(ps, 'c1', 'S80 #2');
    await dao.addFromBridge(
        'b-1',
        analysis(
          needsSignoff: true,
          captureSource: CaptureSource.bridgeOk,
          bridgeRecordId: bridgeId,
        ));

    await dao.update(
      'b-1',
      sameEdit(cylinderId: 'c1', fillPressureBar: 210.0, analysedFor: ' Alex '),
    );

    final a = (await dao.list()).single;
    expect(a.cylinderId, 'c1');
    expect(a.cylinderLabel, 'S80 #2'); // re-joined on read
    expect(a.fillPressureBar, 210.0);
    expect(a.analysedFor, 'Alex'); // trimmed

    final row =
        await ps.get('SELECT * FROM gas_analyses WHERE id = ?', ['b-1']);
    expect(row['version'], 2);
    // Never written by an edit.
    expect(row['o2_percent'], 21.4);
    expect(row['he_percent'], 34.6);
    expect(row['temp_c'], 21.4);
    expect(row['baro_hpa'], 1013.2);
    expect(row['analysed_at'],
        DateTime(2026, 10, 30, 18, 5).millisecondsSinceEpoch);
    expect(row['stable'], 1);
    expect(row['capture_source'], 'bridge_ok');
    expect(row['bridge_record_id'], bridgeId);
    // No sign-off asked for, so the flag stays.
    expect(row['needs_signoff'], 1);

    // Null clears the cylinder, the fill pressure and the name.
    await dao.update(
        'b-1', sameEdit(cylinderId: null, fillPressureBar: null));
    final cleared = (await dao.list()).single;
    expect(cleared.cylinderId, isNull);
    expect(cleared.fillPressureBar, isNull);
    expect(cleared.analysedFor, isNull);
  });

  test('update with signOff clears needs_signoff; without it the flag stays',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(needsSignoff: true));

    await dao.update(id, sameEdit());
    expect((await dao.list()).single.needsSignoff, isTrue);

    await dao.update(id, sameEdit(signOff: true));
    expect((await dao.list()).single.needsSignoff, isFalse);
    final row = await ps.get('SELECT * FROM gas_analyses WHERE id = ?', [id]);
    expect(row['needs_signoff'], 0);
    expect(row['version'], 3);

    // Signing off an entry that isn't flagged leaves it unflagged.
    final other = await dao.add(analysis());
    await dao.update(other, sameEdit(signOff: true));
    expect(
        (await dao.list()).singleWhere((a) => a.id == other).needsSignoff,
        isFalse);
  });

  test('rows from older builds read as bailout with no desired mix', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final t = DateTime(2026, 10, 30, 18, 5).millisecondsSinceEpoch;
    // An unknown role string and null targets.
    await insertRawAnalysis(ps, 'weird',
        extra: {'gas_role': 'weird', 'analysed_at': t + 3});
    // Null role and null targets (a row saved before the columns existed).
    await insertRawAnalysis(ps, 'old', extra: {'analysed_at': t + 2});
    // A target O2 with a null target He.
    await insertRawAnalysis(ps, 'o2only',
        extra: {'target_o2_percent': 32, 'analysed_at': t + 1});
    // A target He with no target O2 is no desired mix at all.
    await insertRawAnalysis(ps, 'heonly',
        extra: {'target_he_percent': 35, 'analysed_at': t});

    final byId = {for (final a in await dao.list()) a.id: a};
    expect(byId, hasLength(4));
    expect(byId['weird']!.gasRole, GasRole.bailout);
    expect(byId['weird']!.desiredMix, isNull);
    expect(byId['weird']!.match, isNull);
    expect(byId['old']!.gasRole, GasRole.bailout);
    expect(byId['old']!.desiredMix, isNull);
    expect(byId['o2only']!.desiredMix, const DesiredMix(32, 0));
    expect(byId['o2only']!.match!.level, MixMatchLevel.match);
    expect(byId['heonly']!.desiredMix, isNull);
  });

  test('is_residual round-trips and an edit keeps it', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(analysis(isResidual: true));
    expect((await dao.list()).single.isResidual, isTrue);

    await dao.update(
      id,
      const GasAnalysisEdit(
        desiredMix: DesiredMix(21, 35),
        gasRole: GasRole.diluent,
        analysedBy: 'Sam',
        notes: null,
        cylinderId: null,
        fillPressureBar: 200,
        analysedFor: null,
      ),
    );
    expect((await dao.list()).single.isResidual, isTrue);
  });

  test('a row without is_residual reads as not residual', () async {
    final ps = await openPowerSyncForTest();
    final dao = GasAnalysesDao(ps, FakeSessionSource()..setUserId('u1'));
    await insertRawAnalysis(ps, 'old1');
    expect((await dao.list()).single.isResidual, isFalse);
  });
}
