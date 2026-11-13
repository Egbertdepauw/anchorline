import 'package:ccrlogger/analyzer/blend_closer.dart';
import 'package:ccrlogger/data/db/open_blends_dao.dart';
import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/fake_gas_analyses_dao.dart';
import '../_helpers/fake_open_blends_dao.dart';

const _tx1845 = DesiredMix(18, 45);

OpenBlend _blend(String id, DesiredMix target, DateTime at,
        {GasRole role = GasRole.diluent}) =>
    OpenBlend(
      id: id,
      target: target,
      targetPressureBar: 200,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 3,
      role: role,
      blendedBy: null,
      blendedAt: at,
    );

GasAnalysis _entry(
  String id, {
  double o2 = 18.1,
  double he = 45,
  DesiredMix? desired,
  bool needsSignoff = false,
  bool isResidual = false,
  GasRole role = GasRole.bailout,
}) =>
    GasAnalysis(
      id: id,
      cylinderId: 'c1',
      analysedBy: 'Egbert',
      analysedAt: DateTime(2026, 11, 13, 10),
      o2Percent: o2,
      hePercent: he,
      fillPressureBar: 150,
      stable: true,
      notes: 'note',
      targetO2Percent: desired?.o2Percent,
      targetHePercent: desired?.hePercent,
      gasRole: role,
      needsSignoff: needsSignoff,
      isResidual: isResidual,
      analysedFor: 'Anna',
    );

void main() {
  final t0 = DateTime(2026, 11, 13, 8);

  test('sign-off of an entry with a desired mix closes the oldest blend of '
      'that mix', () async {
    final blends = FakeOpenBlendsDao(blends: [
      _blend('new', _tx1845, t0.add(const Duration(hours: 1))),
      _blend('old', _tx1845, t0),
    ]);
    final analyses = FakeGasAnalysesDao(analyses: [_entry('a1', desired: _tx1845)]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: blends,
        analyses: analyses);
    expect(blends.closedBy, {'old': 'a1'});
    expect(analyses.updated, isEmpty);
  });

  test('sign-off without a desired mix matches by reading and gives the '
      'entry the blend\'s target and role', () async {
    final blends = FakeOpenBlendsDao(blends: [
      _blend('b1', _tx1845, t0, role: GasRole.diluent),
      _blend('b2', const DesiredMix(32, 0), t0),
    ]);
    final analyses = FakeGasAnalysesDao(analyses: [_entry('a1')]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: blends,
        analyses: analyses);
    expect(blends.closedBy, {'b1': 'a1'});
    final (id, edit) = analyses.updated.single;
    expect(id, 'a1');
    expect(edit.desiredMix, _tx1845);
    expect(edit.gasRole, GasRole.diluent);
    expect(edit.signOff, isFalse);
    expect(edit.analysedBy, 'Egbert');
    expect(edit.notes, 'note');
    expect(edit.cylinderId, 'c1');
    expect(edit.fillPressureBar, 150);
    expect(edit.analysedFor, 'Anna');
  });

  test('a reading that matches no blend closes nothing', () async {
    final blends = FakeOpenBlendsDao(blends: [_blend('b1', _tx1845, t0)]);
    final analyses =
        FakeGasAnalysesDao(analyses: [_entry('a1', o2: 32, he: 0)]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: blends,
        analyses: analyses);
    expect(blends.closedBy, isEmpty);
    expect(analyses.updated, isEmpty);
  });

  test('sign-off of a residual closes nothing', () async {
    final blends = FakeOpenBlendsDao(blends: [_blend('b1', _tx1845, t0)]);
    final analyses = FakeGasAnalysesDao(
        analyses: [_entry('a1', desired: _tx1845, isResidual: true)]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: blends,
        analyses: analyses);
    expect(blends.closedBy, isEmpty);
    expect(blends.closeOldestCalls, isEmpty);
  });

  test('an entry still needing sign-off closes nothing', () async {
    final blends = FakeOpenBlendsDao(blends: [_blend('b1', _tx1845, t0)]);
    final analyses = FakeGasAnalysesDao(
        analyses: [_entry('a1', desired: _tx1845, needsSignoff: true)]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: blends,
        analyses: analyses);
    expect(blends.closedBy, isEmpty);
  });

  test('calling it twice for the same entry closes only one blend', () async {
    final blends = FakeOpenBlendsDao(blends: [
      _blend('a', _tx1845, t0),
      _blend('b', _tx1845, t0.add(const Duration(hours: 1))),
    ]);
    final analyses =
        FakeGasAnalysesDao(analyses: [_entry('a1', desired: _tx1845)]);
    for (var i = 0; i < 2; i++) {
      await closeBlendOnSignOff(
          signedOff: analyses.analyses.single,
          openBlends: blends,
          analyses: analyses);
    }
    expect(blends.closedBy, {'a': 'a1'});
  });

  test('the entry gets the role of the blend actually closed after a '
      'fallback', () async {
    final ranked = _blend('ranked', _tx1845, t0, role: GasRole.diluent);
    final other = _blend('other', _tx1845, t0.add(const Duration(hours: 1)),
        role: GasRole.bailout);
    final blends = FakeOpenBlendsDao(blends: [ranked, other]);
    // The ranked blend is closed elsewhere between listOpen and closeBlend.
    blends.closedBy['ranked'] = 'elsewhere';
    final analyses = FakeGasAnalysesDao(analyses: [_entry('a1')]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: _RacingBlends(blends, ranked),
        analyses: analyses);
    expect(blends.closedBy['other'], 'a1');
    expect(analyses.updated.single.$2.gasRole, GasRole.bailout);
  });

  test('a failure is swallowed', () async {
    final analyses = FakeGasAnalysesDao(analyses: [_entry('a1', desired: _tx1845)]);
    await closeBlendOnSignOff(
        signedOff: analyses.analyses.single,
        openBlends: _ThrowingBlends(),
        analyses: analyses);
  });
}

class _ThrowingBlends extends FakeOpenBlendsDao {
  @override
  Future<String?> closeOldestOpen(DesiredMix target, String analysisId) =>
      throw StateError('boom');
}

/// Lists [stale] as still open, though it was closed meanwhile.
class _RacingBlends implements OpenBlendsDaoLike {
  _RacingBlends(this.inner, this.stale);
  final FakeOpenBlendsDao inner;
  final OpenBlend stale;

  @override
  Future<List<OpenBlend>> listOpen() async => [stale];
  @override
  Future<bool> closeBlend(OpenBlend b, String id) => inner.closeBlend(b, id);
  @override
  Future<OpenBlend?> blendClosedBy(String id) => inner.blendClosedBy(id);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
