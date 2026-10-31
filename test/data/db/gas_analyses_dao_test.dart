import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' show PowerSyncDatabase;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> insertCylinder(PowerSyncDatabase ps, String id, String label,
          {int? deletedAt}) =>
      ps.execute(
        'INSERT INTO cylinders (id, owner_id, label, role, volume_liters, '
        'working_pressure_bar, created_at, updated_at, deleted_at, version, '
        'sync_status) VALUES (?, ?, ?, ?, 11.0, 232, 0, 0, ?, 1, 0)',
        [id, 'u1', label, 'bailout', deletedAt],
      );

  NewGasAnalysis analysis({
    String? cylinderId,
    DateTime? at,
    double o2 = 21.4,
    double he = 34.6,
    bool stable = true,
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
}
