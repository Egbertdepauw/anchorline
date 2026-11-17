/// What libdivecomputer's parser said about one dive, as plain Dart values.
/// Absent fields are null. Units are libdivecomputer's: meters, bar, degrees
/// Celsius, milliseconds, fractions for gas and CNS.
library;

/// `dc_usage_t`.
enum LibdcUsage {
  none,
  oxygen,
  diluent,
  sidemount;

  static LibdcUsage fromCode(int code) =>
      code >= 0 && code < values.length ? values[code] : none;
}

/// `dc_divemode_t`.
enum LibdcDiveMode { freedive, gauge, oc, ccr, scr }

/// `dc_water_t`.
enum LibdcWater { fresh, salt }

/// `dc_decomodel_type_t`.
enum LibdcDecoModelType { none, buhlmann, vpm, rgbm, dciem }

/// `dc_deco_type_t`.
enum LibdcDecoType { ndl, safetyStop, decoStop, deepStop }

class LibdcSalinity {
  const LibdcSalinity({required this.water, required this.density});
  final LibdcWater water;

  /// kg/m3, 0 when the computer does not say.
  final double density;
}

class LibdcGasMix {
  const LibdcGasMix({
    required this.oxygen,
    required this.helium,
    required this.usage,
  });

  /// Fractions, 0.0 to 1.0.
  final double oxygen;
  final double helium;
  final LibdcUsage usage;
}

class LibdcTank {
  const LibdcTank({
    this.gasMix,
    this.volumeLiters = 0,
    this.workPressureBar = 0,
    this.beginPressureBar = 0,
    this.endPressureBar = 0,
    this.usage = LibdcUsage.none,
  });

  /// Index into the parser's gas mixes, null when unknown.
  final int? gasMix;
  final double volumeLiters;
  final double workPressureBar;
  final double beginPressureBar;
  final double endPressureBar;
  final LibdcUsage usage;
}

class LibdcDecoModel {
  const LibdcDecoModel({required this.type, this.gfLow, this.gfHigh});
  final LibdcDecoModelType type;
  final int? gfLow;
  final int? gfHigh;
}

class LibdcDeco {
  const LibdcDeco({
    required this.type,
    required this.timeSeconds,
    required this.depthM,
    required this.ttsSeconds,
  });
  final LibdcDecoType type;
  final int timeSeconds;
  final double depthM;
  final int ttsSeconds;
}

class LibdcSampleEvent {
  const LibdcSampleEvent({
    required this.type,
    required this.flags,
    required this.value,
  });

  /// A `parser_sample_event_t` value.
  final int type;
  final int flags;
  final int value;
}

/// Everything libdivecomputer reported between two `DC_SAMPLE_TIME` samples.
class LibdcSampleRow {
  LibdcSampleRow({
    required this.timeMs,
    this.depthM,
    this.temperatureC,
    this.ppo2Voted,
    Map<int, double>? cells,
    this.setpoint,
    this.cns,
    this.deco,
    this.gasMix,
    Map<int, double>? pressures,
    List<LibdcSampleEvent>? events,
  }) : cells = cells ?? {},
       pressures = pressures ?? {},
       events = events ?? [];

  final int timeMs;
  double? depthM;
  double? temperatureC;

  /// The computer's own (voted) ppO2, when it logs one.
  double? ppo2Voted;

  /// Per-sensor ppO2 by sensor index.
  final Map<int, double> cells;
  double? setpoint;

  /// A fraction (0.5 = 50 %).
  double? cns;
  LibdcDeco? deco;

  /// Gas mix index into [LibdcParsedDive.gasMixes].
  int? gasMix;

  /// Tank pressure in bar by tank index.
  final Map<int, double> pressures;
  final List<LibdcSampleEvent> events;
}

class LibdcParsedDive {
  LibdcParsedDive({
    this.wallClock,
    this.timezoneSeconds,
    this.diveTimeSeconds,
    this.maxDepthM,
    this.atmosphericBar,
    this.salinity,
    this.gasMixes = const [],
    this.tanks = const [],
    this.diveMode,
    this.decoModel,
    this.rows = const [],
  });

  /// The `dc_datetime_t` fields as a UTC [DateTime]: the computer's wall
  /// clock, whatever zone it was in.
  final DateTime? wallClock;

  /// Offset from UTC, null for `DC_TIMEZONE_NONE`.
  final int? timezoneSeconds;
  final int? diveTimeSeconds;
  final double? maxDepthM;
  final double? atmosphericBar;
  final LibdcSalinity? salinity;
  final List<LibdcGasMix> gasMixes;
  final List<LibdcTank> tanks;
  final LibdcDiveMode? diveMode;
  final LibdcDecoModel? decoModel;
  final List<LibdcSampleRow> rows;
}
