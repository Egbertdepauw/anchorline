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
    if (p <= 0.5) continue;
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
  for (var i = 0; i < n; i++) {
    final v = values[i];
    if (v < min) min = v;
    if (v > max) max = v;
    sum += v;
  }
  return (min: min, avg: sum / n, max: max);
}
