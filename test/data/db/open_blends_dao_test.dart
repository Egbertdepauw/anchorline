import 'package:ccrlogger/data/db/gas_analyses_dao.dart';
import 'package:ccrlogger/data/db/open_blends_dao.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_helpers/powersync_test_helper.dart';

NewOpenBlend _blend({
  DesiredMix target = const DesiredMix(18, 45),
  DateTime? blendedAt,
  GasRole role = GasRole.bailout,
}) =>
    NewOpenBlend(
      target: target,
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 30,
      topoff: const DesiredMix(32, 0),
      waterCapacityL: 11.1,
      role: role,
      blendedBy: 'Egbert',
      blendedAt: blendedAt ?? DateTime.fromMillisecondsSinceEpoch(1000000),
    );

NewGasAnalysis _analysis() => NewGasAnalysis(
      analysedAt: DateTime.fromMillisecondsSinceEpoch(2000000),
      o2Percent: 18,
      hePercent: 45,
      stable: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('add stores owner, fields and sync metadata', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));

    final id = await dao.add(_blend(role: GasRole.diluent));

    final row = (await ps.getAll('SELECT * FROM open_blends')).single;
    expect(row['id'], id);
    expect((row['id'] as String).length, 36);
    expect(row['owner_id'], 'u1');
    expect(row['target_o2_percent'], 18);
    expect(row['target_he_percent'], 45);
    expect(row['target_pressure_bar'], 200);
    expect(row['residual_o2_percent'], 21);
    expect(row['residual_he_percent'], 0);
    expect(row['residual_pressure_bar'], 30);
    expect(row['topoff_o2_percent'], 32);
    expect(row['topoff_he_percent'], 0);
    expect(row['water_capacity_l'], 11.1);
    expect(row['gas_role'], 'diluent');
    expect(row['blended_by'], 'Egbert');
    expect(row['blended_at'], 1000000);
    expect(row['closed_by_analysis_id'], isNull);
    expect(row['created_at'], row['updated_at']);
    expect(row['deleted_at'], isNull);
    expect(row['version'], 1);
    expect(row['sync_status'], 0);

    final b = (await dao.listOpen()).single;
    expect(b.id, id);
    expect(b.target, const DesiredMix(18, 45));
    expect(b.residual, const DesiredMix(21, 0));
    expect(b.topoff, const DesiredMix(32, 0));
    expect(b.role, GasRole.diluent);
    expect(b.blendedAt.millisecondsSinceEpoch, 1000000);
  });

  test('listOpen is oldest first and leaves out dismissed and closed',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));

    final late = await dao.add(_blend(
        target: const DesiredMix(21, 35),
        blendedAt: DateTime.fromMillisecondsSinceEpoch(3000)));
    final early = await dao.add(_blend(
        target: const DesiredMix(10, 50),
        blendedAt: DateTime.fromMillisecondsSinceEpoch(1000)));
    final dismissed = await dao.add(_blend(
        target: const DesiredMix(32, 0),
        blendedAt: DateTime.fromMillisecondsSinceEpoch(2000)));
    final closed = await dao.add(_blend(
        target: const DesiredMix(50, 0),
        blendedAt: DateTime.fromMillisecondsSinceEpoch(2500)));
    await dao.dismiss(dismissed);
    await dao.closeOldestOpen(const DesiredMix(50, 0), 'x1');

    expect([for (final b in await dao.listOpen()) b.id], [early, late]);
    expect(closed, isNot(anyOf(early, late)));
  });

  test('closeBlend twice on one blend closes it once', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(_blend());
    final b = (await dao.listOpen()).single;

    expect(await dao.closeBlend(b, 'x1'), isTrue);
    expect(await dao.closeBlend(b, 'x2'), isFalse);

    final row = (await ps.getAll('SELECT * FROM open_blends')).single;
    expect(row['closed_by_analysis_id'], 'x1');
    expect(row['version'], 2);
  });

  test('closeBlend falls back to the oldest open blend of the same target',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    final a = await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(1000)));
    final bId = await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(2000)));
    final blendA = (await dao.listOpen()).first;
    expect(blendA.id, a);

    expect(await dao.closeBlend(blendA, 'x1'), isTrue);
    expect(await dao.closeBlend(blendA, 'x2'), isTrue);

    final rows = await ps.getAll(
        'SELECT id, closed_by_analysis_id FROM open_blends');
    final byId = {for (final r in rows) r['id']: r['closed_by_analysis_id']};
    expect(byId[a], 'x1');
    expect(byId[bId], 'x2');
    expect(await dao.listOpen(), isEmpty);
  });

  test('closeOldestOpen with a cutoff leaves out a newer blend', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    final older = await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(1000)));
    final newer = await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(5000)));
    const t = DesiredMix(18, 45);
    final cutoff = DateTime.fromMillisecondsSinceEpoch(2000);

    expect(await dao.closeOldestOpen(t, 'x1', blendedNoLaterThan: cutoff),
        older);
    // Only the newer blend is left, and it is past the cutoff.
    expect(await dao.closeOldestOpen(t, 'x2', blendedNoLaterThan: cutoff),
        isNull);
    expect([for (final b in await dao.listOpen()) b.id], [newer]);
  });

  test('closeBlend fallback with a cutoff leaves out a newer blend', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(1000)));
    await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(5000)));
    final first = (await dao.listOpen()).first;
    final cutoff = DateTime.fromMillisecondsSinceEpoch(2000);

    expect(await dao.closeBlend(first, 'x1', blendedNoLaterThan: cutoff),
        isTrue);
    // first is closed; the fallback would pick the newer one, past the
    // cutoff.
    expect(await dao.closeBlend(first, 'x2', blendedNoLaterThan: cutoff),
        isFalse);
    expect(await dao.listOpen(), hasLength(1));
  });

  test('a second close for the same analysis id closes nothing', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(1000)));
    await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(2000)));
    final first = (await dao.listOpen()).first;

    expect(await dao.closeBlend(first, 'x1'), isTrue);
    expect(await dao.closeBlend(first, 'x1'), isFalse);
    expect(await dao.closeOldestOpen(const DesiredMix(18, 45), 'x1'), isNull);
    expect(await dao.listOpen(), hasLength(1));
  });

  test('blendClosedBy returns the closed blend, null for unknown or dismissed',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(_blend());
    await dao.closeOldestOpen(const DesiredMix(18, 45), 'x1');
    expect((await dao.blendClosedBy('x1'))?.id, id);
    expect(await dao.blendClosedBy('nope'), isNull);
    await dao.dismiss(id);
    expect(await dao.blendClosedBy('x1'), isNull);
  });

  test('closeOldestOpen picks the oldest of the target and ignores other mixes',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    final newer = await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(2000)));
    final older = await dao.add(
        _blend(blendedAt: DateTime.fromMillisecondsSinceEpoch(1000)));
    final other = await dao.add(_blend(
        target: const DesiredMix(21, 35),
        blendedAt: DateTime.fromMillisecondsSinceEpoch(500)));

    expect(await dao.closeOldestOpen(const DesiredMix(18, 45), 'x1'), older);
    expect(await dao.closeOldestOpen(const DesiredMix(10, 70), 'x2'), isNull);
    expect([for (final b in await dao.listOpen()) b.id], [other, newer]);
  });

  test('deleting the closing analysis reopens the blend', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u1');
    final dao = OpenBlendsDao(ps, session);
    final analyses = GasAnalysesDao(ps, session);
    await dao.add(_blend());
    final analysisId = await analyses.add(_analysis());

    await dao.closeOldestOpen(const DesiredMix(18, 45), analysisId);
    expect(await dao.listOpen(), isEmpty);

    await analyses.softDelete(analysisId);
    expect((await dao.listOpen()).single.target, const DesiredMix(18, 45));
  });

  test('a closing analysis not on this device keeps the blend closed',
      () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(_blend());

    await dao.closeOldestOpen(const DesiredMix(18, 45), 'missing-id');

    expect(await dao.listOpen(), isEmpty);
  });

  test('dismiss is a soft delete with a version bump', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    final id = await dao.add(_blend());

    await dao.dismiss(id);

    final row = (await ps.getAll('SELECT * FROM open_blends')).single;
    expect(row['deleted_at'], isA<int>());
    expect(row['version'], 2);
    expect(await dao.listOpen(), isEmpty);
  });

  test('listOpen is scoped to the signed-in owner', () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u1');
    final dao = OpenBlendsDao(ps, session);
    await dao.add(_blend());
    session.setUserId('u2');
    expect(await dao.listOpen(), isEmpty);
    expect(await dao.closeOldestOpen(const DesiredMix(18, 45), 'x'), isNull);
  });

  test('watchOpen emits after a close', () async {
    final ps = await openPowerSyncForTest();
    final dao = OpenBlendsDao(ps, FakeSessionSource()..setUserId('u1'));
    await dao.add(_blend());

    final emissions = <int>[];
    final sub = dao.watchOpen().listen((l) => emissions.add(l.length));
    await pumpUntil(() => emissions.isNotEmpty);
    expect(emissions.first, 1);

    await dao.closeOldestOpen(const DesiredMix(18, 45), 'x1');
    await pumpUntil(() => emissions.contains(0));
    expect(emissions.last, 0);
    await sub.cancel();
  });

  test('watchOpen emits the blend again when the closing analysis is deleted',
      () async {
    final ps = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('u1');
    final dao = OpenBlendsDao(ps, session);
    final analyses = GasAnalysesDao(ps, session);
    await dao.add(_blend());
    final analysisId = await analyses.add(_analysis());
    await dao.closeOldestOpen(const DesiredMix(18, 45), analysisId);

    final emissions = <int>[];
    final sub = dao.watchOpen().listen((l) => emissions.add(l.length));
    await pumpUntil(() => emissions.isNotEmpty);
    expect(emissions.last, 0);

    await analyses.softDelete(analysisId);
    await pumpUntil(() => emissions.last == 1);
    expect(emissions.last, 1);
    await sub.cancel();
  });
}

Future<void> pumpUntil(bool Function() cond) async {
  for (var i = 0; i < 100 && !cond(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
