/// Per-dive surface-mV and peak-mV series for one sensor slot.
///
/// Ported from `EquipmentDao.mvSeriesForCell`, `_computeSurfaceMv` and
/// `_peakMvForSlot` in `lib/data/db/equipment_dao.dart` (as of 2026-11-08)
/// so the website shows the same numbers as the app. The DAO itself is not
/// imported because it pulls in Drift and PowerSync. If those definitions
/// change in the app, change them here too.
library;

import 'package:ccrlogger/data/models/sample_set.dart';

/// Same shape as `MvPoint` in `equipment_dao.dart`.
typedef MvPoint = ({DateTime date, double mv, String diveId});

/// A dive's decoded samples plus its start time.
typedef DiveSamples = ({String diveId, DateTime date, SampleSet samples});

/// [slot] is the 0-based mV column (0..2), i.e. `cell.slot - 1` in the DAO.
///
/// Surface mV = mean of `cellMv[slot]` over samples with `depthM < 1.0` AND
/// `cellMv >= 5.0`. Peak mV = max `cellMv[slot]` over samples with
/// `cellMv >= 5.0`. The lists may differ in length.
({List<MvPoint> surface, List<MvPoint> peak}) mvSeriesForSlot(
  Iterable<DiveSamples> dives,
  int slot,
) {
  final surface = <MvPoint>[];
  final peak = <MvPoint>[];
  if (slot < 0 || slot > 2) return (surface: surface, peak: peak);
  for (final dive in dives) {
    final s = _computeSurfaceMv(dive.samples, slot);
    if (s != null) {
      surface.add((date: dive.date, mv: s, diveId: dive.diveId));
    }
    final p = _peakMvForSlot(dive.samples, slot);
    if (p != null) peak.add((date: dive.date, mv: p, diveId: dive.diveId));
  }
  return (surface: surface, peak: peak);
}

List<double> _mvColumn(SampleSet s, int mvCol) => switch (mvCol) {
  0 => s.cellMv0,
  1 => s.cellMv1,
  _ => s.cellMv2,
};

double? _peakMvForSlot(SampleSet sample, int mvCol) {
  final mvs = _mvColumn(sample, mvCol);
  var peak = double.negativeInfinity;
  var any = false;
  for (var i = 0; i < sample.sampleCount; i++) {
    final v = mvs[i];
    if (v < 5.0) continue;
    if (v > peak) peak = v;
    any = true;
  }
  return any ? peak : null;
}

double? _computeSurfaceMv(SampleSet sample, int mvCol) {
  final depths = sample.depthMeters;
  final mvs = _mvColumn(sample, mvCol);
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < sample.sampleCount; i++) {
    if (depths[i] >= 1.0) continue;
    final v = mvs[i];
    if (v < 5.0) continue;
    sum += v;
    count++;
  }
  return count == 0 ? null : sum / count;
}
