/// Columnar sample data for a dive.
///
/// Samples are stored as parallel typed arrays (one per field)
/// rather than as individual row objects. This gives much better
/// storage density and rendering performance.
///
/// All values are in metric units (meters, °C, bar).
library;

import 'dart:typed_data';

class SampleSet {
  final String diveId;
  final int sampleCount;
  final int sampleIntervalMs;

  /// Depth in meters.
  final Float32List depthMeters;

  /// Temperature in °C.
  final Float32List temperatureCelsius;

  /// PPO2 averaged/voted in bar.
  final Float32List ppo2Bar;

  /// O2 cell millivolt readings (calibrated).
  final Float32List cellMv0;
  final Float32List cellMv1;
  final Float32List cellMv2;

  /// Setpoint in bar.
  final Float32List setpointBar;

  /// CNS percentage (0.0 - 1.0+).
  final Float32List cns;

  /// Deco stop depth in meters (0 = NDL).
  final Float32List decoStopDepthMeters;

  /// NDL or deco time in seconds.
  final Int32List decoTimeSeconds;

  /// TTS in seconds.
  final Int32List ttsSeconds;

  /// Gas mix index per sample.
  final Uint8List gasMixIndex;

  /// Status flags per sample.
  final Uint8List statusFlags;

  SampleSet({
    required this.diveId,
    required this.sampleCount,
    required this.sampleIntervalMs,
    required this.depthMeters,
    required this.temperatureCelsius,
    required this.ppo2Bar,
    required this.cellMv0,
    required this.cellMv1,
    required this.cellMv2,
    required this.setpointBar,
    required this.cns,
    required this.decoStopDepthMeters,
    required this.decoTimeSeconds,
    required this.ttsSeconds,
    required this.gasMixIndex,
    required this.statusFlags,
  });
}
