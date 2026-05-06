/// Converts [ParsedDive] (raw values) to domain model (metric, standardized).
///
/// Handles:
/// - Imperial → metric conversion (if header.units == imperial)
/// - Negative temperature fix (from libdc: add 102, clamp to 0)
/// - Cell mV raw values (calibration factors stay on Dive.sensorCalibration;
///   per-cell PPO2 is derived at display time as raw_mv × cal_factor)
/// - Tank pressure masking (lower 12 bits × 2 PSI → bar)
/// - PPO2 and setpoint to bar
library;

import 'dart:typed_data';

import '../../data/models/dive.dart';
import '../../data/models/sample_set.dart';
import 'constants.dart';
import 'hardware.dart';
import 'parsed_dive.dart';

/// Conversion constants.
const double _feetToMeters = 0.3048;

/// Result of converting a parsed dive.
class ConvertedDive {
  final Dive dive;
  final SampleSet samples;

  ConvertedDive({required this.dive, required this.samples});
}

/// Converts parsed dive data to domain model.
class DiveConverter {
  /// Convert a [ParsedDive] to a [Dive] + [SampleSet].
  static ConvertedDive convert({
    required ParsedDive parsed,
    required int dcSerial,
    required int dcDiveNumber,
    required ShearwaterModel dcModel,
  }) {
    final header = parsed.header;
    final footer = parsed.footer;
    final isImperial = header.units == unitsImperial;

    // ── Max depth conversion ──
    double maxDepthMeters;
    if (header.isPnf) {
      // PNF: raw is 1/10 m or 1/10 ft
      maxDepthMeters = footer.maxDepthRaw / 10.0;
    } else {
      // Legacy: raw is whole m or ft
      maxDepthMeters = footer.maxDepthRaw.toDouble();
    }
    if (isImperial) {
      maxDepthMeters *= _feetToMeters;
    }

    // ── Dive ID ──
    final diveId = generateDiveId(dcSerial, dcDiveNumber, header.startTimestamp);

    // ── Times ──
    final startTime = DateTime.fromMillisecondsSinceEpoch(
        header.startTimestamp * 1000,
        isUtc: true);
    final duration = Duration(seconds: footer.diveTimeSeconds);
    final endTime = startTime.add(duration);

    // ── Gas mixes ──
    final gasMixes = parsed.gasMixes
        .map((g) => DiveGasMix(
              oxygenPercent: g.oxygenPercent,
              heliumPercent: g.heliumPercent,
              isDiluent: g.isDiluent,
            ))
        .toList();

    // ── Tanks ──
    final tanks = <DiveTank>[];
    for (var i = 0; i < parsed.tanks.length; i++) {
      final t = parsed.tanks[i];
      if (t.usage == TankUsage.none &&
          t.beginPressureRaw == 0 &&
          t.endPressureRaw == 0) {
        continue;
      }
      tanks.add(DiveTank(
        slot: i,
        usage: t.usage,
        name: t.name,
        serial: t.serial,
        beginPressureBar: t.beginPressureRaw * tankPressureRawToBar,
        endPressureBar: t.endPressureRaw * tankPressureRawToBar,
        pressureMaxBar: t.pressureMax,
        pressureReserveBar: t.pressureReserve,
      ));
    }

    final dive = Dive(
      id: diveId,
      dcSerial: dcSerial,
      dcDiveNumber: dcDiveNumber,
      startTime: startTime,
      endTime: endTime,
      duration: duration,
      maxDepthMeters: maxDepthMeters,
      diveMode: header.diveMode,
      decoModel: header.decoModel,
      gfLow: header.gfLow,
      gfHigh: header.gfHigh,
      atmosphericPressureMbar: header.atmosphericPressureMbar,
      waterDensityKgM3: header.waterDensity,
      logVersion: header.logVersion,
      dcModel: dcModel,
      gasMixes: gasMixes,
      tanks: tanks,
      sampleIntervalMs: header.sampleIntervalMs,
      sensorCalibration: List<double>.from(header.sensorCalibration),
      configuredStackSeconds: header.configuredStackSeconds,
      stackRemainingAtStartSeconds: header.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: header.stackRemainingAtEndSeconds,
    );

    // ── Samples ──
    final n = parsed.samples.length;
    final depthMeters = Float32List(n);
    final temperatureCelsius = Float32List(n);
    final ppo2Bar = Float32List(n);
    final cellMv0 = Float32List(n);
    final cellMv1 = Float32List(n);
    final cellMv2 = Float32List(n);
    final setpointBar = Float32List(n);
    final cns = Float32List(n);
    final decoStopDepthMeters = Float32List(n);
    final decoTimeSeconds = Int32List(n);
    final ttsSeconds = Int32List(n);
    final gasMixIndex = Uint8List(n);
    final statusFlags = Uint8List(n);
    final tankPressuresBar = parsed.tanks.isEmpty
        ? const <Float32List>[]
        : List<Float32List>.generate(tanks.length, (_) => Float32List(n),
            growable: false);
    final slotForTankIndex = <int, int>{
      for (var i = 0; i < tanks.length; i++) tanks[i].slot: i,
    };

    for (var i = 0; i < n; i++) {
      final s = parsed.samples[i];

      // Depth: raw is 1/10 m or 1/10 ft (PNF), or whole (legacy)
      var depth = s.depthRaw / 10.0;
      if (isImperial) depth *= _feetToMeters;
      depthMeters[i] = depth;

      // Temperature: fix negative values per libdc
      var temp = s.temperatureRaw;
      if (temp < 0) {
        temp += 102;
        if (temp > 0) temp = 0;
      }
      if (isImperial) {
        temperatureCelsius[i] = (temp - 32.0) * (5.0 / 9.0);
      } else {
        temperatureCelsius[i] = temp.toDouble();
      }

      // PPO2 (voted average, 1/100 bar)
      ppo2Bar[i] = s.ppo2Raw / 100.0;

      // Cell mV (raw byte = mV directly; calibration factors stay on Dive)
      cellMv0[i] = s.cellMv0.toDouble();
      cellMv1[i] = s.cellMv1.toDouble();
      cellMv2[i] = s.cellMv2.toDouble();

      // Setpoint (1/100 bar)
      setpointBar[i] = s.setpointRaw / 100.0;

      // CNS (raw byte / 100)
      cns[i] = s.cnsRaw / 100.0;

      // Deco stop depth
      var decoDepth = s.decoStopDepthRaw.toDouble();
      if (isImperial) decoDepth *= _feetToMeters;
      decoStopDepthMeters[i] = decoDepth;

      // Deco/NDL time in seconds
      decoTimeSeconds[i] = s.ndlOrDecoTimeMinutes * 60;

      // TTS in seconds
      ttsSeconds[i] = s.ttsMinutes * 60;

      // Gas mix index (simplified: find matching mix)
      gasMixIndex[i] = _findGasMixIndex(parsed.gasMixes, s.o2Percent, s.hePercent);

      statusFlags[i] = s.statusFlags;

      // Per-sample tank pressures: map parser tankIndex (raw slot) to the
      // compacted DiveTank position via slotForTankIndex. Samples that
      // omit a tank stay at 0 in that channel (Float32List default).
      if (tankPressuresBar.isNotEmpty && s.tankPressures.isNotEmpty) {
        for (final p in s.tankPressures) {
          final ch = slotForTankIndex[p.tankIndex];
          if (ch == null) continue;
          tankPressuresBar[ch][i] = p.pressureRaw * tankPressureRawToBar;
        }
      }
    }

    final samples = SampleSet(
      diveId: diveId,
      sampleCount: n,
      sampleIntervalMs: header.sampleIntervalMs,
      depthMeters: depthMeters,
      temperatureCelsius: temperatureCelsius,
      ppo2Bar: ppo2Bar,
      cellMv0: cellMv0,
      cellMv1: cellMv1,
      cellMv2: cellMv2,
      setpointBar: setpointBar,
      cns: cns,
      decoStopDepthMeters: decoStopDepthMeters,
      decoTimeSeconds: decoTimeSeconds,
      ttsSeconds: ttsSeconds,
      gasMixIndex: gasMixIndex,
      statusFlags: statusFlags,
      tankPressuresBar: tankPressuresBar,
    );

    return ConvertedDive(dive: dive, samples: samples);
  }

  static int _findGasMixIndex(List<GasMix> mixes, int o2, int he) {
    for (var i = 0; i < mixes.length; i++) {
      if (mixes[i].oxygenPercent == o2 && mixes[i].heliumPercent == he) {
        return i;
      }
    }
    return 0;
  }
}
