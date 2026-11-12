/// Builds a synthetic, contiguous [SampleSet] + virtual Drift [Dive] from a
/// set of merged dives, inserting flat surface-interval blocks between
/// segments. Pure: no I/O, no Flutter. This is "merge in the UI" performed at
/// the data-shaping layer — the existing ProfileChart / analysis consume the
/// output unchanged.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../data/db/database.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'merge_constants.dart';

/// One member of a merge: its (Drift) dive row + decoded samples.
typedef MergeMember = ({Dive dive, SampleSet samples});

/// Stitches [members] into one synthetic dive identified by [mergedId].
/// Members may be in any order; they are sorted by start time. All members
/// must share the same `sampleIntervalMs` (v1 limitation) or this throws.
({Dive dive, SampleSet samples}) buildMergedDive({
  required String mergedId,
  required List<MergeMember> members,
}) {
  if (members.length < 2) {
    throw ArgumentError('buildMergedDive requires at least 2 members');
  }
  final sorted = [...members]
    ..sort((x, y) => x.dive.startTime.compareTo(y.dive.startTime));
  final interval = sorted.first.samples.sampleIntervalMs;
  for (final m in sorted) {
    if (m.samples.sampleIntervalMs != interval) {
      throw ArgumentError(
          'All merged dives must share the same sample interval (v1)');
    }
  }

  // Merge gas-mix lists; build a per-member old->new index remap.
  final mergedGas = <Map<String, dynamic>>[];
  final remaps = <List<int>>[];
  for (final m in sorted) {
    final list =
        (jsonDecode(m.dive.gasMixesJson) as List).cast<Map<String, dynamic>>();
    final remap = <int>[];
    for (final g in list) {
      final at = mergedGas.indexWhere((e) =>
          e['o2'] == g['o2'] && e['he'] == g['he'] && e['dil'] == g['dil']);
      if (at >= 0) {
        remap.add(at);
      } else {
        remap.add(mergedGas.length);
        mergedGas.add({'o2': g['o2'], 'he': g['he'], 'dil': g['dil']});
      }
    }
    remaps.add(remap);
  }

  // Surface gaps (in samples) and total length. The drawn gap is clamped to
  // [kMergedSurfaceGapDisplayCap] so a long real surface interval doesn't bury
  // the recorded dive data under thousands of empty samples — the true
  // interval is surfaced as a label on the list tile. Short gaps still render
  // proportionally.
  final maxGapSamples =
      (kMergedSurfaceGapDisplayCap.inMilliseconds / interval).round();
  final gapSamples = <int>[];
  for (var i = 1; i < sorted.length; i++) {
    final gapSec = sorted[i].dive.startTime - sorted[i - 1].dive.endTime;
    final g = ((gapSec * 1000) / interval).round();
    gapSamples.add(g < 0 ? 0 : (g > maxGapSamples ? maxGapSamples : g));
  }
  var total = 0;
  for (final m in sorted) {
    total += m.samples.sampleCount;
  }
  for (final g in gapSamples) {
    total += g;
  }

  final depth = Float32List(total);
  final temp = Float32List(total);
  final ppo2 = Float32List(total);
  final cell0 = Float32List(total);
  final cell1 = Float32List(total);
  final cell2 = Float32List(total);
  final setpoint = Float32List(total);
  final cns = Float32List(total);
  final decoDepth = Float32List(total);
  final decoTime = Int32List(total);
  final tts = Int32List(total);
  final gasIdx = Uint8List(total);
  final status = Uint8List(total);

  final tankChannels = sorted
      .map((m) => m.samples.tankPressuresBar.length)
      .fold<int>(0, (a, b) => a > b ? a : b);
  final tanks = List.generate(tankChannels, (_) => Float32List(total));

  var w = 0;
  void fillSurface(int count) {
    for (var i = 0; i < count; i++) {
      depth[w] = 0.0;
      temp[w] = double.nan;
      ppo2[w] = double.nan;
      cell0[w] = double.nan;
      cell1[w] = double.nan;
      cell2[w] = double.nan;
      setpoint[w] = double.nan;
      cns[w] = double.nan;
      decoDepth[w] = double.nan;
      decoTime[w] = 0;
      tts[w] = 0;
      gasIdx[w] = 0;
      status[w] = 0;
      for (final t in tanks) {
        t[w] = double.nan;
      }
      w++;
    }
  }

  for (var mi = 0; mi < sorted.length; mi++) {
    if (mi > 0) fillSurface(gapSamples[mi - 1]);
    final s = sorted[mi].samples;
    final remap = remaps[mi];
    for (var i = 0; i < s.sampleCount; i++) {
      depth[w] = s.depthMeters[i];
      temp[w] = s.temperatureCelsius[i];
      ppo2[w] = s.ppo2Bar[i];
      cell0[w] = s.cellMv0[i];
      cell1[w] = s.cellMv1[i];
      cell2[w] = s.cellMv2[i];
      setpoint[w] = s.setpointBar[i];
      cns[w] = s.cns[i];
      decoDepth[w] = s.decoStopDepthMeters[i];
      decoTime[w] = s.decoTimeSeconds[i];
      tts[w] = s.ttsSeconds[i];
      final oldIdx = s.gasMixIndex[i];
      gasIdx[w] = (oldIdx < remap.length) ? remap[oldIdx] : 0;
      status[w] = s.statusFlags[i];
      for (var c = 0; c < tankChannels; c++) {
        tanks[c][w] = (c < s.tankPressuresBar.length)
            ? s.tankPressuresBar[c][i]
            : double.nan;
      }
      w++;
    }
  }

  final mergedSamples = SampleSet(
    diveId: mergedId,
    sampleCount: total,
    sampleIntervalMs: interval,
    depthMeters: depth,
    temperatureCelsius: temp,
    ppo2Bar: ppo2,
    cellMv0: cell0,
    cellMv1: cell1,
    cellMv2: cell2,
    setpointBar: setpoint,
    cns: cns,
    decoStopDepthMeters: decoDepth,
    decoTimeSeconds: decoTime,
    ttsSeconds: tts,
    gasMixIndex: gasIdx,
    statusFlags: status,
    tankPressuresBar: tanks,
  );

  final first = sorted.first.dive;
  final last = sorted.last.dive;
  var maxDepthMm = 0;
  var durationSeconds = 0;
  for (final m in sorted) {
    if (m.dive.maxDepthMm > maxDepthMm) maxDepthMm = m.dive.maxDepthMm;
    durationSeconds += m.dive.durationSeconds;
  }

  final mergedDive = Dive(
    id: mergedId,
    dcSerial: first.dcSerial,
    dcDiveNumber: first.dcDiveNumber,
    startTime: first.startTime,
    endTime: last.endTime,
    utcOffsetMinutes: first.utcOffsetMinutes,
    durationSeconds: durationSeconds,
    maxDepthMm: maxDepthMm,
    diveMode: first.diveMode,
    decoModel: first.decoModel,
    gfLow: first.gfLow,
    gfHigh: first.gfHigh,
    atmosphericPressureMbar: first.atmosphericPressureMbar,
    waterDensity: first.waterDensity,
    logVersion: first.logVersion,
    dcModel: first.dcModel,
    dcFirmware: first.dcFirmware,
    sampleIntervalMs: interval,
    gasMixesJson: jsonEncode(mergedGas),
    tanksJson: first.tanksJson,
    sensorCalibrationJson: first.sensorCalibrationJson,
    configuredStackSeconds: first.configuredStackSeconds,
    stackRemainingAtStartSeconds: first.stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: last.stackRemainingAtEndSeconds,
    rawBlob: Uint8List(0),
    parserVersion: first.parserVersion,
    importedAt: first.importedAt,
    subsurfaceUploadedAt: null,
    deletedAt: null,
  );

  return (dive: mergedDive, samples: mergedSamples);
}
