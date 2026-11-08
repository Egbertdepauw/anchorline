/// Builds the anonymised showcase JSON (one dive, one cell's history).
library;

import 'dart:math' as math;

import 'package:ccrlogger/data/models/sample_set.dart';

import 'cell_series.dart';
import 'showcase_db.dart';

typedef ShowcaseExport = ({
  String diveId,
  String cellId,
  Map<String, Object?> json,
  String summary,
});

/// `DiveMode.cc` (0) and `DiveMode.cc2` (5) in
/// `lib/shearwater/parser/constants.dart`; both are closed circuit.
const _ccrModes = {0, 5};

double _round(num v, int digits) {
  final f = math.pow(10, digits).toDouble();
  return (v * f).round() / f;
}

/// Down-sampled profile channels; all lists have the same length.
class Decimated {
  Decimated({
    required this.intervalSeconds,
    required this.depthMeters,
    required this.ppo2Bar,
    required this.setpointBar,
    required this.cellMv,
  });

  final int intervalSeconds;
  final List<double> depthMeters;
  final List<double?> ppo2Bar;
  final List<double> setpointBar;
  final List<List<double?>> cellMv;
}

/// Keeps every k-th sample, `k = max(1, round(targetIntervalMs /
/// sampleIntervalMs))`. Per window: depth = max, PPO2 and cells = mean of
/// usable values (null when none; a cell reading of 0 is "missing"),
/// setpoint = last value.
Decimated decimate(SampleSet s, int targetIntervalMs) {
  final k = math.max(1, (targetIntervalMs / s.sampleIntervalMs).round());
  final depth = <double>[];
  final ppo2 = <double?>[];
  final setpoint = <double>[];
  final cells = <List<double?>>[[], [], []];
  final cellSrc = [s.cellMv0, s.cellMv1, s.cellMv2];

  double? mean(List<double> src, int from, int to, bool Function(double) ok) {
    var sum = 0.0;
    var n = 0;
    for (var i = from; i < to; i++) {
      final v = src[i];
      if (v.isNaN || !ok(v)) continue;
      sum += v;
      n++;
    }
    return n == 0 ? null : _round(sum / n, 2);
  }

  for (var from = 0; from < s.sampleCount; from += k) {
    final to = math.min(from + k, s.sampleCount);
    var maxDepth = 0.0;
    for (var i = from; i < to; i++) {
      if (s.depthMeters[i] > maxDepth) maxDepth = s.depthMeters[i];
    }
    depth.add(_round(maxDepth, 2));
    ppo2.add(mean(s.ppo2Bar, from, to, (_) => true));
    setpoint.add(_round(s.setpointBar[to - 1], 2));
    for (var c = 0; c < 3; c++) {
      final m = mean(cellSrc[c], from, to, (v) => v > 0);
      cells[c].add(m == null ? null : _round(m, 1));
    }
  }
  return Decimated(
    intervalSeconds: _round(k * s.sampleIntervalMs / 1000, 0).toInt(),
    depthMeters: depth,
    ppo2Bar: ppo2,
    setpointBar: setpoint,
    cellMv: cells,
  );
}

ShowcaseExport buildShowcase({
  required ShowcaseDb db,
  String? diveId,
  String? cellId,
}) {
  final dives = db.dives;
  final cache = <String, SampleSet?>{};
  SampleSet? samplesOf(DiveRow d) =>
      cache.putIfAbsent(d.id, () => db.samplesFor(d));

  // ── dive ──
  DiveRow? dive;
  if (diveId != null) {
    dive = dives.where((d) => d.id == diveId).firstOrNull;
    if (dive == null) throw ArgumentError('No such dive: $diveId');
  } else {
    final candidates =
        dives
            .where(
              (d) =>
                  _ccrModes.contains(d.diveMode) &&
                  d.durationSeconds >= 3600 &&
                  d.maxDepthMm >= 40000,
            )
            .toList()
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
    for (final d in candidates) {
      final s = samplesOf(d);
      if (s != null && s.decoStopDepthMeters.any((v) => v > 0)) {
        dive = d;
        break;
      }
    }
    if (dive == null) {
      throw StateError(
        'No CCR dive of >= 60 min and >= 40 m with deco found. '
        'Pass --dive explicitly.',
      );
    }
  }
  final diveSamples = samplesOf(dive);
  if (diveSamples == null) throw StateError('Dive has no sample data.');

  // ── cell ──
  List<DiveSamples> windowFor(CellRow c) {
    final inWindow = dives.where((d) {
      final ms = d.startTime * 1000;
      if (c.installedDate != null && ms < c.installedDate!) return false;
      if (c.retiredDate != null && ms >= c.retiredDate!) return false;
      return true;
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
    return [
      for (final d in inWindow)
        if (samplesOf(d) case final s?)
          (
            diveId: d.id,
            date: DateTime.fromMillisecondsSinceEpoch(d.startTime * 1000),
            samples: s,
          ),
    ];
  }

  ({List<MvPoint> surface, List<MvPoint> peak}) seriesOf(CellRow c) =>
      mvSeriesForSlot(windowFor(c), c.slot - 1);

  double medianOf(List<double> v) {
    final s = [...v]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  double drift(List<MvPoint> surface) {
    if (surface.isEmpty) return 0;
    final vals = [for (final p in surface) p.mv];
    final n = math.min(5, vals.length);
    return (medianOf(vals.sublist(vals.length - n)) -
            medianOf(vals.sublist(0, n)))
        .abs();
  }

  final allCells = db.cells;
  CellRow? cell;
  if (cellId != null) {
    cell = allCells.where((c) => c.id == cellId).firstOrNull;
    if (cell == null) throw ArgumentError('No such cell: $cellId');
  } else {
    var bestCount = -1;
    var bestDrift = -1.0;
    for (final c in allCells) {
      if (c.slot < 1 || c.slot > 3) continue;
      final surface = seriesOf(c).surface;
      final dr = drift(surface);
      if (surface.length > bestCount ||
          (surface.length == bestCount && dr > bestDrift)) {
        cell = c;
        bestCount = surface.length;
        bestDrift = dr;
      }
    }
    if (cell == null) throw StateError('No oxygen cells found.');
  }

  final series = seriesOf(cell);
  final surfaceById = {for (final p in series.surface) p.diveId: p.mv};
  final peakById = {for (final p in series.peak) p.diveId: p.mv};
  // One point per dive with a surface value (chronological); a dive with a
  // peak but no surface samples contributes no point.
  final ordered = [for (final p in series.surface) p.diveId];
  final dates = {for (final p in series.surface) p.diveId: p.date};
  final points = <Map<String, Object?>>[];
  for (var i = 0; i < ordered.length; i++) {
    final id = ordered[i];
    points.add({
      'dive': i + 1,
      'day': dates[id]!.difference(dates[ordered.first]!).inDays,
      'surfaceMv': _round(surfaceById[id]!, 1),
      'peakMv': _round(peakById[id]!, 1),
    });
  }

  final dec = decimate(diveSamples, 10000);
  final json = <String, Object?>{
    'format': 1,
    'dive': {
      'intervalSeconds': dec.intervalSeconds,
      'durationSeconds': dive.durationSeconds,
      'maxDepthMeters': _round(dive.maxDepthMm / 1000, 2),
      'depthMeters': dec.depthMeters,
      'ppo2Bar': dec.ppo2Bar,
      'setpointBar': dec.setpointBar,
      'cellMv': dec.cellMv,
    },
    'cell': {'slot': cell.slot, 'points': points},
  };

  final start = DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000);
  final summary =
      'Dive #${dive.diveNumber} on '
      '${start.toIso8601String().substring(0, 10)}, max depth '
      '${_round(dive.maxDepthMm / 1000, 1)} m, duration '
      '${(dive.durationSeconds / 60).round()} min. Cell: '
      '${cell.label ?? '(unlabelled)'} (slot ${cell.slot}), '
      '${points.length} dives in its history.';

  return (diveId: dive.id, cellId: cell.id, json: json, summary: summary);
}
