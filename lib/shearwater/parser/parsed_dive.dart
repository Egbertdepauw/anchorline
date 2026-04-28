/// Immutable data classes emitted by the Shearwater dive parser.
///
/// All values are **raw** as read from the binary format.
/// Unit conversion (imperial→metric, raw→calibrated) happens in the
/// domain layer, not here. This keeps the parser a pure
/// byte-to-structure mapper.
library;

import 'dart:typed_data';

import 'constants.dart';

/// Complete parsed dive — the top-level output of [ShearwaterDiveParser].
class ParsedDive {
  final DiveHeader header;
  final DiveFooter footer;
  final List<GasMix> gasMixes;
  final List<TankInfo> tanks;
  final List<DiveSample> samples;
  final List<DiveEvent> events;
  final FinalRecord? finalRecord;

  ParsedDive({
    required this.header,
    required this.footer,
    required this.gasMixes,
    required this.tanks,
    required this.samples,
    required this.events,
    this.finalRecord,
  });
}

/// Header data extracted from opening records.
class DiveHeader {
  /// Unix timestamp (seconds since epoch) from opening[0] offset 12.
  final int startTimestamp;

  /// Dive mode detected from samples/header.
  final DiveMode diveMode;

  /// Deco model code from opening[2].
  final DecoModel decoModel;

  /// Gradient factors (0-100). Only meaningful if decoModel == gf.
  final int gfLow;
  final int gfHigh;

  /// VPM-B conservatism (0 if not VPM-B).
  final int vpmbConservatism;

  /// Sample interval in milliseconds (default 10000).
  final int sampleIntervalMs;

  /// Log version from opening[4] or legacy header byte 127.
  final int logVersion;

  /// 0=metric, 1=imperial — tells consumers how to interpret raw values.
  final int units;

  /// Sensor calibration factors (3 values, already divided by 100000).
  final List<double> sensorCalibration;

  /// Bitmask of which sensors are calibrated (bit 0=cell1, bit 1=cell2, bit 2=cell3).
  /// 0 if all sensors had default calibration (disabled).
  final int calibratedSensorMask;

  /// Air integration mode.
  final int aiMode;

  /// Atmospheric pressure in millibar.
  final int atmosphericPressureMbar;

  /// Water density in kg/m³ (1000=fresh, 1025=salt).
  final int waterDensity;

  /// Whether this is PNF (Petrel Native Format).
  final bool isPnf;

  /// Configured scrubber canister capacity in seconds (logVersion >= 11).
  /// Null when the diver hasn't enabled stack tracking.
  final int? configuredStackSeconds;

  /// Remaining scrubber stack at dive start, in seconds.
  /// Null when stack tracking isn't configured.
  final int? stackRemainingAtStartSeconds;

  /// Remaining scrubber stack at dive end, in seconds.
  /// Null when stack tracking isn't configured.
  final int? stackRemainingAtEndSeconds;

  DiveHeader({
    required this.startTimestamp,
    required this.diveMode,
    required this.decoModel,
    required this.gfLow,
    required this.gfHigh,
    this.vpmbConservatism = 0,
    this.sampleIntervalMs = 10000,
    required this.logVersion,
    required this.units,
    required this.sensorCalibration,
    required this.calibratedSensorMask,
    this.aiMode = aiOff,
    required this.atmosphericPressureMbar,
    required this.waterDensity,
    required this.isPnf,
    this.configuredStackSeconds,
    this.stackRemainingAtStartSeconds,
    this.stackRemainingAtEndSeconds,
  });
}

/// Footer data from closing records.
class DiveFooter {
  /// Max depth raw value (1/10 m in PNF, whole meters in legacy).
  /// Imperial vs metric depends on header.units.
  final int maxDepthRaw;

  /// Dive duration in seconds (PNF) or minutes (legacy, multiply by 60).
  final int diveTimeSeconds;

  DiveFooter({
    required this.maxDepthRaw,
    required this.diveTimeSeconds,
  });
}

/// Gas mix as stored in the dive log.
class GasMix {
  final int oxygenPercent; // 0-100
  final int heliumPercent; // 0-100
  final bool isDiluent;

  GasMix({
    required this.oxygenPercent,
    required this.heliumPercent,
    required this.isDiluent,
  });

  int get nitrogenPercent => 100 - oxygenPercent - heliumPercent;

  @override
  String toString() =>
      'GasMix(O2=$oxygenPercent He=$heliumPercent${isDiluent ? ' dil' : ''})';
}

/// Tank summary info gathered during the cache pass.
class TankInfo {
  final int beginPressureRaw; // units of 2 PSI (lower 12 bits)
  final int endPressureRaw;
  final int serial;
  final int pressureMax;
  final int pressureReserve;
  final String name; // 2-char name from opening record
  final TankUsage usage;

  TankInfo({
    required this.beginPressureRaw,
    required this.endPressureRaw,
    this.serial = 0,
    this.pressureMax = 0,
    this.pressureReserve = 0,
    this.name = '',
    this.usage = TankUsage.none,
  });
}

enum TankUsage { none, sidemount, oxygen, diluent }

/// A single dive sample (one per sample interval).
class DiveSample {
  /// Accumulated time in milliseconds from dive start.
  final int timeMs;

  /// Depth raw value (uint16, 1/10 m or ft depending on header.units).
  final int depthRaw;

  /// Temperature as signed byte (°C or °F depending on header.units).
  /// Negative temperature fix NOT applied here (raw value).
  final int temperatureRaw;

  /// Status flags byte.
  final int statusFlags;

  /// PPO2 averaged/voted value (byte at offset 6, 1/100 bar).
  final int ppo2Raw;

  /// O2 cell millivolt readings (raw bytes, 0 if not CCR).
  final int cellMv0;
  final int cellMv1;
  final int cellMv2;

  /// Setpoint (1/100 bar). Petrel: from sample. Predator: from header.
  final int setpointRaw;

  /// CNS percentage (raw byte / 100). Petrel only.
  final int cnsRaw;

  /// O2 and He percentages of the active gas.
  final int o2Percent;
  final int hePercent;

  /// Deco stop depth (raw uint16, 0 = NDL).
  final int decoStopDepthRaw;

  /// NDL or deco time in minutes.
  final int ndlOrDecoTimeMinutes;

  /// Time to surface in minutes.
  final int ttsMinutes;

  /// Remaining bottom time (minutes). 0xFF+ = special codes.
  final int rbt;

  /// Tank pressures for this sample. May be empty.
  final List<TankPressureReading> tankPressures;

  DiveSample({
    required this.timeMs,
    required this.depthRaw,
    required this.temperatureRaw,
    this.statusFlags = 0,
    this.ppo2Raw = 0,
    this.cellMv0 = 0,
    this.cellMv1 = 0,
    this.cellMv2 = 0,
    this.setpointRaw = 0,
    this.cnsRaw = 0,
    required this.o2Percent,
    required this.hePercent,
    this.decoStopDepthRaw = 0,
    this.ndlOrDecoTimeMinutes = 0,
    this.ttsMinutes = 0,
    this.rbt = 0,
    this.tankPressures = const [],
  });

  bool get isOc => (statusFlags & statusOc) != 0;
  bool get isCcr => !isOc;
}

/// Tank pressure reading within a sample.
class TankPressureReading {
  final int tankIndex;

  /// Raw 12-bit pressure in units of 2 PSI.
  final int pressureRaw;

  /// Battery level from upper 4 bits (0=normal, 1=critical, 2=warning).
  final int batteryLevel;

  TankPressureReading({
    required this.tankIndex,
    required this.pressureRaw,
    required this.batteryLevel,
  });
}

/// Dive event (bookmark, compass heading).
class DiveEvent {
  final int timeMs;
  final DiveEventType type;
  final int? bearing;
  final int? value;

  DiveEvent({
    required this.timeMs,
    required this.type,
    this.bearing,
    this.value,
  });
}

enum DiveEventType { bookmark, gasSwitch }

/// Data from the final record (if present in PNF format).
class FinalRecord {
  /// Device model byte from final record offset 13.
  final int model;

  /// Device serial from final record offset 2 (uint32BE).
  final int serial;

  /// Firmware version (BCD) from final record offset 10.
  final int firmware;

  /// Raw bytes of the final record for reference.
  final Uint8List raw;

  FinalRecord({
    required this.model,
    required this.serial,
    required this.firmware,
    required this.raw,
  });
}
