/// Builds the subsurface_core input records from Drift rows. This is the only
/// place the app translates between the two; the server has its own builder
/// from Postgres rows.
library;

import '../../data/db/database.dart' show Cylinder, Dive, DiveComputer;
import 'sync_inputs.dart';

SubsurfaceDiveInput diveInputFromRow(Dive row) => SubsurfaceDiveInput(
      id: row.id,
      dcSerial: row.dcSerial,
      dcDiveNumber: row.dcDiveNumber,
      startTime: row.startTime,
      durationSeconds: row.durationSeconds,
      maxDepthMm: row.maxDepthMm,
      diveMode: row.diveMode,
      dcModel: row.dcModel,
      logVersion: row.logVersion,
      atmosphericPressureMbar: row.atmosphericPressureMbar,
      waterDensity: row.waterDensity,
      dcFirmware: row.dcFirmware,
      gfLow: row.gfLow,
      gfHigh: row.gfHigh,
      sensorCalibrationJson: row.sensorCalibrationJson,
      configuredStackSeconds: row.configuredStackSeconds,
      stackRemainingAtStartSeconds: row.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: row.stackRemainingAtEndSeconds,
    );

SubsurfaceCylinderInput cylinderInputFromRow(Cylinder row) =>
    SubsurfaceCylinderInput(
      label: row.label,
      volumeLiters: row.volumeLiters,
      workingPressureBar: row.workingPressureBar,
    );

SubsurfaceDiveComputerInput diveComputerInputFromRow(DiveComputer row) =>
    SubsurfaceDiveComputerInput(
      serial: row.serial,
      model: row.model,
      nickname: row.nickname,
    );
