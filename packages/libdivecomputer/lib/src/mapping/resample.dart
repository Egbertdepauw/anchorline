import 'dart:typed_data';

import '../parse/parsed_dive.dart';
import '../parse/status.dart';

/// Anchorline's samples sit on a fixed grid; libdivecomputer's rows do not
/// (some computers log on change, some skip samples). This puts the rows onto
/// that grid, in the units `SampleSet` uses.
///
/// Every column has exactly [count] entries, including the zero-filled ones.
class ResampledRows {
  ResampledRows({
    required this.intervalMs,
    required this.count,
    required this.depth,
    required this.temperature,
    required this.ppo2,
    required this.cellPpo2,
    required this.setpoint,
    required this.cns,
    required this.decoStopDepth,
    required this.decoTime,
    required this.tts,
    required this.gasMixIndex,
    required this.tankPressures,
  });

  final int intervalMs;
  final int count;
  final Float32List depth;
  final Float32List temperature;

  /// The voted ppO2, else the median of the cells, else 0.
  final Float32List ppo2;

  /// One channel per cell index seen, from 0 up to the highest seen (at most
  /// 3).
  final List<Float32List> cellPpo2;
  final Float32List setpoint;
  final Float32List cns;
  final Float32List decoStopDepth;
  final Int32List decoTime;
  final Int32List tts;
  final Uint8List gasMixIndex;

  /// One channel per tank, `tankCount` of them.
  final List<Float32List> tankPressures;
}

const int _maxCells = 4;

/// A grid always may span this long.
const int _minSpanMs = 24 * 3600 * 1000;

/// The most grid points ever allocated.
const int _maxPoints = 2000000;

/// The most common positive gap between row times; the smaller one on a
/// tie. 1000 ms when there is no gap to measure.
int _interval(List<LibdcSampleRow> rows) {
  final counts = <int, int>{};
  for (var i = 1; i < rows.length; i++) {
    final gap = rows[i].timeMs - rows[i - 1].timeMs;
    if (gap > 0) counts[gap] = (counts[gap] ?? 0) + 1;
  }
  var best = 1000;
  var bestCount = 0;
  counts.forEach((gap, n) {
    if (n > bestCount || (n == bestCount && gap < best)) {
      best = gap;
      bestCount = n;
    }
  });
  return best;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// [rows] in time order. libdivecomputer delivers them in order, so that is
/// the common case and the list is returned as is; otherwise a stable sort
/// keeps the delivery order of rows with the same time.
List<LibdcSampleRow> rowsInTimeOrder(List<LibdcSampleRow> rows) {
  var ordered = true;
  for (var i = 1; i < rows.length; i++) {
    if (rows[i].timeMs < rows[i - 1].timeMs) {
      ordered = false;
      break;
    }
  }
  if (ordered) return rows;
  final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
  indexed.sort((a, b) {
    final c = a.$2.timeMs.compareTo(b.$2.timeMs);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final r in indexed) r.$2];
}

/// Puts [rows] on a grid from 0 ms to the last row's time.
///
/// Depth is interpolated linearly between the nearest rows that have one;
/// every other channel carries its last value forward. [gasIndex] translates
/// a row's gas mix index; null means "this row names no usable gas" and the
/// previous index stays. [tankIndexes] are the parser's tank indexes; tank
/// channel `i` carries the pressures of `tankIndexes[i]`, other tanks are
/// dropped.
///
/// Before the first row that carries a channel, the grid holds that
/// channel's first value (as depth always did), not 0.
///
/// Throws [LibdcParseException] (`dataFormat`) when the grid would exceed
/// `max(2 * diveTimeSeconds, 24 h)` of time or 2,000,000 points, which means a
/// row time is corrupt.
ResampledRows resample(
  List<LibdcSampleRow> rows, {
  int? Function(int index)? gasIndex,
  List<int> tankIndexes = const [],
  int? diveTimeSeconds,
}) {
  final sorted = rowsInTimeOrder(rows);
  final interval = _interval(sorted);
  final last = sorted.isEmpty ? 0 : sorted.last.timeMs;
  final count = sorted.isEmpty ? 0 : (last + interval - 1) ~/ interval + 1;
  // Limit the grid in time, not in points: the dive time is not trusted (it
  // can be absent, shorter than the rows, or corrupt). Rows may span twice
  // the reported dive time or a day, whichever is longer, and never more than
  // an absolute number of points.
  final spanLimitMs = [(diveTimeSeconds ?? 0) * 2000, _minSpanMs].reduce(
    (a, b) => a > b ? a : b,
  );
  if (last > spanLimitMs || count > _maxPoints) {
    throw const LibdcParseException(LibdcStatus.dataFormat);
  }
  final tankChannel = {
    for (var i = 0; i < tankIndexes.length; i++) tankIndexes[i]: i,
  };
  final tankCount = tankIndexes.length;

  var cellChannels = 0;
  for (final r in sorted) {
    for (final k in r.cells.keys) {
      if (k >= 0 && k < _maxCells && k + 1 > cellChannels) cellChannels = k + 1;
    }
  }

  final depth = Float32List(count);
  final temperature = Float32List(count);
  final ppo2 = Float32List(count);
  final cells = List.generate(cellChannels, (_) => Float32List(count));
  final setpoint = Float32List(count);
  final cns = Float32List(count);
  final decoStop = Float32List(count);
  final decoTime = Int32List(count);
  final tts = Int32List(count);
  final gas = Uint8List(count);
  final pressures = List.generate(tankCount, (_) => Float32List(count));

  // Rows that carry a depth, for interpolation.
  final depthTimes = <int>[];
  final depthValues = <double>[];
  for (final r in sorted) {
    final d = r.depthM;
    if (d != null) {
      depthTimes.add(r.timeMs);
      depthValues.add(d);
    }
  }

  // Carried-forward state, starting from each channel's first value so the
  // grid before the first row is not zero.
  var j = 0;
  var dj = 0; // index of the last depth row at or before t
  double temp = 0, voted = double.nan, sp = 0, cn = 0;
  LibdcDeco? deco;
  var gasNow = 0;
  final cellNow = <int, double>{};
  final pressureNow = <int, double>{};
  var haveTemp = false,
      haveVoted = false,
      haveSp = false,
      haveCns = false,
      haveGas = false;
  for (final r in sorted) {
    if (!haveTemp && r.temperatureC != null) {
      temp = r.temperatureC!;
      haveTemp = true;
    }
    if (!haveVoted && r.ppo2Voted != null) {
      voted = r.ppo2Voted!;
      haveVoted = true;
    }
    if (!haveSp && r.setpoint != null) {
      sp = r.setpoint!;
      haveSp = true;
    }
    if (!haveCns && r.cns != null) {
      cn = r.cns!;
      haveCns = true;
    }
    deco ??= r.deco;
    if (!haveGas && r.gasMix != null) {
      final mapped = gasIndex == null ? r.gasMix : gasIndex(r.gasMix!);
      if (mapped != null) {
        gasNow = mapped;
        haveGas = true;
      }
    }
    r.cells.forEach((k, v) {
      if (k >= 0 && k < _maxCells) cellNow.putIfAbsent(k, () => v);
    });
    r.pressures.forEach((k, v) {
      final ch = tankChannel[k];
      if (ch != null) pressureNow.putIfAbsent(ch, () => v);
    });
  }

  for (var g = 0; g < count; g++) {
    final t = g * interval;
    while (j < sorted.length && sorted[j].timeMs <= t) {
      final r = sorted[j++];
      if (r.temperatureC != null) temp = r.temperatureC!;
      if (r.ppo2Voted != null) voted = r.ppo2Voted!;
      r.cells.forEach((k, v) {
        if (k >= 0 && k < _maxCells) cellNow[k] = v;
      });
      if (r.setpoint != null) sp = r.setpoint!;
      if (r.cns != null) cn = r.cns!;
      if (r.deco != null) deco = r.deco;
      if (r.gasMix != null) {
        final mapped = gasIndex == null ? r.gasMix : gasIndex(r.gasMix!);
        if (mapped != null) gasNow = mapped;
      }
      r.pressures.forEach((k, v) {
        final ch = tankChannel[k];
        if (ch != null) pressureNow[ch] = v;
      });
    }

    // Depth: the nearest depth rows on both sides of t.
    while (dj + 1 < depthTimes.length && depthTimes[dj + 1] <= t) {
      dj++;
    }
    if (depthTimes.isNotEmpty) {
      if (t < depthTimes[0]) {
        depth[g] = depthValues[0];
      } else if (dj + 1 >= depthTimes.length) {
        depth[g] = depthValues[dj];
      } else {
        final t0 = depthTimes[dj], t1 = depthTimes[dj + 1];
        final d0 = depthValues[dj], d1 = depthValues[dj + 1];
        depth[g] = t1 == t0 ? d0 : d0 + (d1 - d0) * (t - t0) / (t1 - t0);
      }
    }

    temperature[g] = temp;
    if (!voted.isNaN) {
      ppo2[g] = voted;
    } else if (cellNow.isNotEmpty) {
      ppo2[g] = _median(cellNow.values.toList());
    }
    cellNow.forEach((k, v) => cells[k][g] = v);
    setpoint[g] = sp;
    cns[g] = cn;
    final dc = deco;
    if (dc != null) {
      final isStop =
          dc.type == LibdcDecoType.decoStop ||
          dc.type == LibdcDecoType.deepStop;
      decoStop[g] = isStop ? dc.depthM : 0;
      decoTime[g] = dc.timeSeconds;
      tts[g] = dc.ttsSeconds;
    }
    gas[g] = gasNow.clamp(0, 255);
    pressureNow.forEach((k, v) => pressures[k][g] = v);
  }

  return ResampledRows(
    intervalMs: interval,
    count: count,
    depth: depth,
    temperature: temperature,
    ppo2: ppo2,
    cellPpo2: cells,
    setpoint: setpoint,
    cns: cns,
    decoStopDepth: decoStop,
    decoTime: decoTime,
    tts: tts,
    gasMixIndex: gas,
    tankPressures: pressures,
  );
}
