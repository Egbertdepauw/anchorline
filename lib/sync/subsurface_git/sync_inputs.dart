/// The dive fields the write mapper and the planner read. The app builds
/// it from the Drift `Dive` row, the server from the `dives` Postgres row.
/// Encodings are the row's: epoch seconds, millimetres, raw enum codes
/// (`DiveMode.value`, `ShearwaterModel.index`), JSON text.
final class SubsurfaceDiveInput {
  const SubsurfaceDiveInput({
    required this.id,
    required this.dcSerial,
    required this.dcDiveNumber,
    required this.startTime,
    required this.durationSeconds,
    required this.maxDepthMm,
    required this.diveMode,
    required this.dcModel,
    required this.logVersion,
    required this.atmosphericPressureMbar,
    required this.waterDensity,
    this.dcFirmware,
    this.gfLow,
    this.gfHigh,
    this.sensorCalibrationJson,
    this.configuredStackSeconds,
    this.stackRemainingAtStartSeconds,
    this.stackRemainingAtEndSeconds,
  });
  final String id;
  final int dcSerial;
  final int dcDiveNumber;
  final int startTime; // unix seconds, as stored
  final int durationSeconds;
  final int maxDepthMm;
  final int diveMode; // DiveMode.value
  final int dcModel; // ShearwaterModel.index
  final int logVersion;
  final int atmosphericPressureMbar;
  final int waterDensity; // kg/m³
  final int? dcFirmware;
  final int? gfLow;
  final int? gfHigh;
  final String? sensorCalibrationJson;
  final int? configuredStackSeconds;
  final int? stackRemainingAtStartSeconds;
  final int? stackRemainingAtEndSeconds;
}

/// The cylinder fields the mapper reads for a `cylinder` line.
final class SubsurfaceCylinderInput {
  const SubsurfaceCylinderInput({
    required this.label,
    required this.volumeLiters,
    required this.workingPressureBar,
  });
  final String label;
  final double volumeLiters;
  final int workingPressureBar;
}

/// The dive-computer fields the mapper reads for a `divecomputerid` line.
final class SubsurfaceDiveComputerInput {
  const SubsurfaceDiveComputerInput({
    required this.serial,
    required this.model, // ShearwaterModel.index
    this.nickname,
  });
  final int serial;
  final int model;
  final String? nickname;
}
