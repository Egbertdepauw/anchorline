/// Glue between the dive DAO, annotations DAO, and the .ssrf encoder.
///
/// Knows how to:
///  - collect every pending dive (subsurface_uploaded_at IS NULL),
///  - bundle it with the latest annotation + samples,
///  - write the resulting XML into the app's documents directory, and
///  - mark the included dives as exported once a successful share returns.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/database.dart' as drift;
import '../data/db/dive_annotations_dao.dart';
import '../data/db/dive_dao.dart';
import '../data/models/dive.dart';
import '../shearwater/parser/constants.dart';
import '../shearwater/parser/hardware.dart';
import 'subsurface_xml_encoder.dart';

/// Result of a successful export to disk.
class SubsurfaceExportResult {
  final List<String> diveIds;
  final String filePath;

  SubsurfaceExportResult({required this.diveIds, required this.filePath});

  int get diveCount => diveIds.length;
}

/// Coordinates building, writing, and acknowledging a Subsurface XML export.
class SubsurfaceExporter {
  final DiveDao _diveDao;
  final DiveAnnotationsDao _annotationsDao;
  final SubsurfaceXmlEncoder _encoder;

  /// Directory provider override for tests. Returns the parent dir under
  /// which an `exports/` subfolder is created.
  final Future<Directory> Function() _resolveBaseDir;

  /// Clock override for tests.
  final DateTime Function() _now;

  SubsurfaceExporter({
    required DiveDao diveDao,
    required DiveAnnotationsDao annotationsDao,
    SubsurfaceXmlEncoder? encoder,
    Future<Directory> Function()? resolveBaseDir,
    DateTime Function()? now,
  })  : _diveDao = diveDao,
        _annotationsDao = annotationsDao,
        _encoder = encoder ?? SubsurfaceXmlEncoder(),
        _resolveBaseDir = resolveBaseDir ?? getApplicationDocumentsDirectory,
        _now = now ?? DateTime.now;

  /// Builds the .ssrf file for every dive whose `subsurfaceUploadedAt` is
  /// still null. Returns null when there is nothing to export.
  Future<SubsurfaceExportResult?> exportPending() async {
    final pending = await _diveDao.getPendingSubsurfaceUploads();
    if (pending.isEmpty) return null;

    final ids = [for (final d in pending) d.id];
    final annotations = await _annotationsDao.getAnnotationsForDives(ids);

    final exports = <SubsurfaceDiveExport>[];
    for (final row in pending) {
      final samples = await _diveDao.getSamples(row.id);
      exports.add(SubsurfaceDiveExport(
        dive: _rowToDomain(row),
        annotation: annotations[row.id],
        samples: samples,
      ));
    }

    final xml = _encoder.encode(exports);
    final file = await _writeFile(xml);
    return SubsurfaceExportResult(diveIds: ids, filePath: file.path);
  }

  /// Stamp `subsurfaceUploadedAt` for the dives in a successful share.
  Future<void> markExported(List<String> diveIds) async {
    final whenSeconds = _now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _diveDao.markSubsurfaceUploaded(diveIds, whenSeconds);
  }

  Future<File> _writeFile(String xml) async {
    final base = await _resolveBaseDir();
    final exportsDir = Directory(p.join(base.path, 'exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    final stamp = _formatStamp(_now());
    final file = File(p.join(exportsDir.path, 'ccrlogger-$stamp.ssrf'));
    await file.writeAsString(xml);
    return file;
  }

  /// Hydrates a Drift `Dive` row into the domain `Dive` the encoder needs.
  Dive _rowToDomain(drift.Dive row) {
    final gasMixes = (jsonDecode(row.gasMixesJson) as List)
        .map((e) => DiveGasMix.fromJson(e as Map<String, dynamic>))
        .toList();
    final tanks = row.tanksJson == null || row.tanksJson!.isEmpty
        ? const <DiveTank>[]
        : (jsonDecode(row.tanksJson!) as List)
            .map((e) => DiveTank.fromJson(e as Map<String, dynamic>))
            .toList();
    final start =
        DateTime.fromMillisecondsSinceEpoch(row.startTime * 1000, isUtc: true);
    final end =
        DateTime.fromMillisecondsSinceEpoch(row.endTime * 1000, isUtc: true);
    return Dive(
      id: row.id,
      dcSerial: row.dcSerial,
      dcDiveNumber: row.dcDiveNumber,
      startTime: start,
      endTime: end,
      utcOffsetMinutes: row.utcOffsetMinutes,
      duration: Duration(seconds: row.durationSeconds),
      maxDepthMeters: row.maxDepthMm / 1000.0,
      diveMode: DiveMode.fromValue(row.diveMode),
      decoModel: DecoModel.fromValue(row.decoModel),
      gfLow: row.gfLow ?? 0,
      gfHigh: row.gfHigh ?? 0,
      atmosphericPressureMbar: row.atmosphericPressureMbar,
      waterDensityKgM3: row.waterDensity,
      logVersion: row.logVersion,
      dcModel: ShearwaterModel.values[row.dcModel],
      gasMixes: gasMixes,
      tanks: tanks,
      sampleIntervalMs: row.sampleIntervalMs,
      configuredStackSeconds: row.configuredStackSeconds,
      stackRemainingAtStartSeconds: row.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: row.stackRemainingAtEndSeconds,
    );
  }

  String _formatStamp(DateTime dt) {
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year.toString().padLeft(4, '0')}-${two(l.month)}-${two(l.day)}'
        'T${two(l.hour)}${two(l.minute)}${two(l.second)}';
  }
}
