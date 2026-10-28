/// Immutable data class emitted by the gas-analyzer line parser.
///
/// Pure Dart: no Flutter, no I/O. Values are as sent by the analyzer;
/// no calibration or unit conversion happens here.
library;

/// One parsed measurement line from a gas analyzer (Divesoft SOLO and
/// the older Divesoft He/O2 analyzer).
///
/// Field semantics:
/// - `null`: the field was not present in the line.
/// - [double.nan]: the analyzer sent the field as asterisks (`***.*`),
///   which means a sensor/measurement error for that field.
class AnalyzerReading {
  /// Oxygen fraction in percent (e.g. 20.9).
  final double? o2;

  /// Helium fraction in percent. An O2-only SOLO sends no helium field;
  /// the parser reports that as 0.
  final double? he;

  /// Sensor temperature in degrees Celsius (`Ti xx.x ~C`).
  final double? tempC;

  /// Ambient (barometric) pressure in hPa.
  final double? baroHpa;

  /// Device clock time. The analyzer has no timezone, so this is a local
  /// [DateTime] built from the sent components. Null when absent or
  /// malformed.
  final DateTime? deviceTime;

  /// The original line, with trailing line terminators stripped.
  final String raw;

  const AnalyzerReading({
    this.o2,
    this.he,
    this.tempC,
    this.baroHpa,
    this.deviceTime,
    required this.raw,
  });
}
