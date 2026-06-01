import 'dart:math' as math;
import 'dart:typed_data';

/// NOAA OTU accumulation for a dive.
///
/// OTU/min = ((PO2 - 0.5) / 0.5) ^ (5/6) for PO2 > 0.5 atm; 0 otherwise.
/// Returns total OTU over the dive.
double computeOtu({
  required Float32List ppo2Bar,
  required int sampleCount,
  required int sampleIntervalMs,
}) {
  if (sampleCount == 0) return 0;
  final n = sampleCount < ppo2Bar.length ? sampleCount : ppo2Bar.length;
  final secondsPerSample = sampleIntervalMs / 1000.0;
  final minutesPerSample = secondsPerSample / 60.0;
  var total = 0.0;
  for (var i = 0; i < n; i++) {
    final p = ppo2Bar[i];
    // NaN guard: merged-dive surface gaps carry NaN. `NaN <= 0.5` is false,
    // so without this the pow() would propagate NaN into the total.
    if (p.isNaN || p <= 0.5) continue;
    total += math.pow((p - 0.5) / 0.5, 5.0 / 6.0) * minutesPerSample;
  }
  return total;
}

/// Returns (min, avg, max) of a Float32 series, or null if the series
/// is empty / all-zero (defaults to null when no real data).
({double min, double avg, double max})? minAvgMax(
    Float32List values, int sampleCount) {
  if (sampleCount == 0) return null;
  final n = sampleCount < values.length ? sampleCount : values.length;
  if (n == 0) return null;
  var min = double.infinity;
  var max = double.negativeInfinity;
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < n; i++) {
    final v = values[i];
    // Skip NaN: merged-dive surface gaps carry NaN, which would otherwise
    // poison the sum (avg → NaN) and crash the `.round()` in the stats row.
    if (v.isNaN) continue;
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
    count++;
  }
  if (count == 0) return null;
  return (min: min, avg: sum / count, max: max);
}

/// Worst-case vertical speed extremes from the sample depth track,
/// computed over a 5-second rolling window.
///
/// Returns ascent / descent in m/min as positive magnitudes. Descent is
/// depth increasing; ascent is depth decreasing. Both default to 0.0 if
/// fewer than two samples are available.
///
/// At Petrel-typical 5s sampling the window collapses to one interval
/// (sample-to-sample). At slower sampling (10s) the window still spans
/// at least one interval. This is essentially "instantaneous" — sensor
/// jitter shows through, but the user explicitly wanted the rawest
/// available signal so real bursts aren't smoothed out.
({
  double maxAscentMpm,
  int maxAscentEndIndex,
  double maxDescentMpm,
  int maxDescentEndIndex,
}) verticalSpeedExtremes({
  required Float32List depthMeters,
  required int sampleCount,
  required int sampleIntervalMs,
}) {
  if (sampleCount < 2 || sampleIntervalMs <= 0) {
    return (
      maxAscentMpm: 0.0,
      maxAscentEndIndex: 0,
      maxDescentMpm: 0.0,
      maxDescentEndIndex: 0,
    );
  }
  final n = sampleCount < depthMeters.length ? sampleCount : depthMeters.length;
  if (n < 2) {
    return (
      maxAscentMpm: 0.0,
      maxAscentEndIndex: 0,
      maxDescentMpm: 0.0,
      maxDescentEndIndex: 0,
    );
  }

  // Compare each sample to the one ~5s earlier. At ≥5s sampling that
  // collapses to one interval; for short dives the window collapses to
  // whatever's available.
  final windowSamples =
      math.max(1, math.min(n - 1, (5000 / sampleIntervalMs).ceil()));
  final windowSeconds = windowSamples * sampleIntervalMs / 1000.0;
  final perMin = 60.0 / windowSeconds;

  var maxDescent = 0.0;
  var maxAscent = 0.0;
  var descIdx = 0;
  var ascIdx = 0;
  for (var i = windowSamples; i < n; i++) {
    final delta = depthMeters[i] - depthMeters[i - windowSamples];
    final rate = delta * perMin;
    if (rate > maxDescent) {
      maxDescent = rate;
      descIdx = i;
    }
    if (-rate > maxAscent) {
      maxAscent = -rate;
      ascIdx = i;
    }
  }
  return (
    maxAscentMpm: maxAscent,
    maxAscentEndIndex: ascIdx,
    maxDescentMpm: maxDescent,
    maxDescentEndIndex: descIdx,
  );
}
