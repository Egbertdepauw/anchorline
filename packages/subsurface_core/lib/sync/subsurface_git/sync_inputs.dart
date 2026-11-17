import '../../shearwater/parser/hardware.dart' show kShearwaterVendor;

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
    this.dcVendor,
    this.dcFamily,
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

  /// The row's `dc_vendor`. Null on rows from before vendors were stored,
  /// which are Shearwater.
  final String? dcVendor;

  /// The row's `dc_family`: set on libdivecomputer dives, -1 on FIT dives,
  /// null on Shearwater dives and on Subsurface copies.
  final int? dcFamily;

  /// True for a dive from another brand, which the Shearwater-only writer
  /// never pushes as a new dive (see `SyncPlanner.plan`).
  bool get isOtherBrand => _isOtherBrand(dcVendor, dcFamily);

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
    this.dcVendor,
    this.dcFamily,
  });
  final int serial;
  final int model;
  final String? nickname;

  /// The row's `dc_vendor`; null is Shearwater.
  final String? dcVendor;

  /// The row's `dc_family`; set for a computer read through
  /// libdivecomputer.
  final int? dcFamily;

  /// True for a computer from another brand, which gets no
  /// `divecomputerid` line from the Shearwater-only writer.
  bool get isOtherBrand => _isOtherBrand(dcVendor, dcFamily);
}

/// Another brand: a set `dc_family` (libdivecomputer or FIT), or a vendor
/// that is set and isn't Shearwater. A null vendor is Shearwater.
bool _isOtherBrand(String? vendor, int? family) =>
    family != null || (vendor != null && vendor != kShearwaterVendor);
