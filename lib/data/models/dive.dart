/// Domain entity for a dive — converted to metric, standardized.
///
/// This is the app's canonical dive representation. All values are
/// metric. Created from [ParsedDive] via the dive converter.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../shearwater/parser/constants.dart';
import '../../shearwater/parser/hardware.dart';

/// Generate a stable dive ID from device serial, dive number, and timestamp.
///
/// `sha256('$dcSerial:$dcDiveNumber:$startTimestampUtc')` truncated to 32 hex chars.
String generateDiveId(int dcSerial, int dcDiveNumber, int startTimestampUtc) {
  final input = '$dcSerial:$dcDiveNumber:$startTimestampUtc';
  return sha256.convert(utf8.encode(input)).toString().substring(0, 32);
}

class Dive {
  /// Stable ID: hash(serial, diveNumber, startTimestamp).
  final String id;

  /// Dive computer serial number.
  final int dcSerial;

  /// Dive number on the computer.
  final int dcDiveNumber;

  /// Dive start time (UTC).
  final DateTime startTime;

  /// Dive end time (UTC).
  final DateTime endTime;

  /// UTC offset in minutes (if known from PNF opening[5]).
  final int? utcOffsetMinutes;

  /// Duration.
  final Duration duration;

  /// Max depth in meters (always metric).
  final double maxDepthMeters;

  /// Dive mode.
  final DiveMode diveMode;

  /// Decompression model.
  final DecoModel decoModel;

  /// Gradient factors.
  final int gfLow;
  final int gfHigh;

  /// Atmospheric pressure in millibar.
  final int atmosphericPressureMbar;

  /// Water density in kg/m³.
  final int waterDensityKgM3;

  /// Parser log version.
  final int logVersion;

  /// Dive computer model.
  final ShearwaterModel dcModel;

  /// Gas mixes used in this dive.
  final List<DiveGasMix> gasMixes;

  /// Sample interval in milliseconds.
  final int sampleIntervalMs;

  /// Per-cell calibration factors (length 3 on CCR; empty on OC).
  /// Used to derive per-cell PPO2 from raw mV at display time.
  final List<double> sensorCalibration;

  Dive({
    required this.id,
    required this.dcSerial,
    required this.dcDiveNumber,
    required this.startTime,
    required this.endTime,
    this.utcOffsetMinutes,
    required this.duration,
    required this.maxDepthMeters,
    required this.diveMode,
    required this.decoModel,
    required this.gfLow,
    required this.gfHigh,
    required this.atmosphericPressureMbar,
    required this.waterDensityKgM3,
    required this.logVersion,
    required this.dcModel,
    required this.gasMixes,
    required this.sampleIntervalMs,
    this.sensorCalibration = const [],
  });
}

/// Gas mix with percentages.
class DiveGasMix {
  final int oxygenPercent;
  final int heliumPercent;
  final bool isDiluent;

  DiveGasMix({
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.isDiluent,
  });

  int get nitrogenPercent => 100 - oxygenPercent - heliumPercent;

  Map<String, dynamic> toJson() => {
        'o2': oxygenPercent,
        'he': heliumPercent,
        'dil': isDiluent,
      };

  factory DiveGasMix.fromJson(Map<String, dynamic> json) => DiveGasMix(
        oxygenPercent: json['o2'] as int,
        heliumPercent: json['he'] as int,
        isDiluent: json['dil'] as bool,
      );
}
