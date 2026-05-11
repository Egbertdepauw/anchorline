/// Pure-Dart mapper from CCRLog's domain model into Subsurface's git-repo
/// plain-text format.
///
/// This is the bridge between the CCRLog database (Drift `Dive` row +
/// columnar `SampleSet` + `DiveAnnotation` + cylinders/equipment) and the
/// Phase-A `SsLine` model in `format/`. The serializer in `format/` turns
/// the `SsLine` lists this mapper produces into the byte-for-byte text that
/// gets committed to the user's Subsurface git repo.
///
/// Architectural notes:
/// - No Flutter, no I/O, no git — same constraint as the format layer.
/// - All numeric values are emitted as fixed-precision string lexemes so
///   round-tripping back through the parser is byte-stable. Never let a
///   `double.toString()` reach the output.
/// - Folder name + `Dive-NNN` filename are computed here; the orchestrator
///   (Phase C) is responsible for actually writing them.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/db/database.dart' show Cylinder, Dive, DiveComputer;
import '../../data/models/annotation.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';
import '../../shearwater/parser/constants.dart' show DiveMode;
import '../../shearwater/parser/hardware.dart';
import '../../shearwater/parser/parsed_dive.dart' show TankUsage;
import 'format/subsurface_format.dart';

/// Result of mapping one CCRLog dive into the two `SsLine` lists Subsurface
/// stores per dive folder. Pure data; the caller writes them to disk + git.
class MappedDive {
  MappedDive({
    required this.folderSegments,
    required this.subsurfaceDiveNumber,
    required this.diveLines,
    required this.divecomputerLines,
    required this.siteHexId,
  });

  /// Folder path components, e.g. `['2026', '04', '04-Sat-13=30=15']`.
  final List<String> folderSegments;

  /// The integer Subsurface assigns to the `Dive-NNN` filename.
  final int subsurfaceDiveNumber;

  /// Lines for `<folder>/Dive-NNN`.
  final List<SsLine> diveLines;

  /// Lines for `<folder>/Divecomputer`.
  final List<SsLine> divecomputerLines;

  /// 8-char hex id of the `Site-<id>` this dive references, or null when
  /// the annotation has no GPS coordinates. Caller is responsible for
  /// writing/merging the matching `01-Divesites/Site-<id>` file.
  final String? siteHexId;
}

/// A site file built from one or more annotations sharing the same lat/lon.
class MappedSite {
  MappedSite({required this.hexId, required this.lines});

  final String hexId;
  final List<SsLine> lines;
}

/// Delta to merge into the existing `00-Subsurface` top-level file.
///
/// Caller is responsible for de-duplicating against the existing file's
/// `divecomputerid`/`fingerprint` lines — this struct only tells the caller
/// what *new* metadata this batch of dives needs to introduce.
class TopLevelDelta {
  TopLevelDelta({
    required this.newDivecomputerIds,
    required this.newFingerprints,
  });

  final List<DivecomputerIdLine> newDivecomputerIds;
  final List<FingerprintLine> newFingerprints;
}

class CcrlogToSubsurfaceMapper {
  CcrlogToSubsurfaceMapper();

  // ── Dive ──────────────────────────────────────────────────────────────

  /// One CCRLog dive → the two `SsLine` lists Subsurface stores per dive
  /// folder, plus the folder-name segments.
  ///
  /// `nextSubsurfaceDiveNumber` is the per-user counter for the
  /// `Dive-NNN` filename — Subsurface assigns it monotonically per branch.
  /// The orchestrator passes the next free integer (tracked in
  /// `00-Subsurface` state).
  MappedDive mapDive({
    required Dive dive,
    required SampleSet samples,
    required DiveAnnotation? annotation,
    required List<DiveGasMix> gasMixes,
    required List<DiveTank> tanks,
    required Map<int, Cylinder> cylindersByMixIndex,
    required int nextSubsurfaceDiveNumber,
  }) {
    final folder = _folderSegments(dive.startTime);
    final siteId = annotation == null ? null : _siteIdFor(annotation);

    final diveLines = _buildDiveLines(
      dive: dive,
      samples: samples,
      annotation: annotation,
      gasMixes: gasMixes,
      tanks: tanks,
      cylindersByMixIndex: cylindersByMixIndex,
      siteId: siteId,
    );
    final divecomputerLines = _buildDivecomputerLines(
      dive: dive,
      samples: samples,
      gasMixes: gasMixes,
      tanks: tanks,
    );

    return MappedDive(
      folderSegments: folder,
      subsurfaceDiveNumber: nextSubsurfaceDiveNumber,
      diveLines: diveLines,
      divecomputerLines: divecomputerLines,
      siteHexId: siteId,
    );
  }

  // ── Site ──────────────────────────────────────────────────────────────

  /// Build a Subsurface Site file from a dive annotation. Returns null
  /// when the annotation has no GPS coordinates.
  ///
  /// The id is `sha256("$latE5:$lonE5").hex.substring(0, 8)`, where lat_e5
  /// is `(lat * 1e5).round()`. Two annotations at the same coordinates
  /// produce the same id and so deduplicate naturally on disk.
  MappedSite? mapSite(DiveAnnotation annotation) {
    final id = _siteIdFor(annotation);
    if (id == null) return null;
    final lat = annotation.siteLatitude!;
    final lon = annotation.siteLongitude!;
    final name = annotation.siteName ?? '';

    final lines = <SsLine>[
      QuotedLine(key: 'name', value: name),
      QuotedLine(key: 'description', value: ''),
      QuotedLine(key: 'notes', value: ''),
      GpsLine(lat: _gpsLexeme(lat), lon: _gpsLexeme(lon)),
    ];
    return MappedSite(hexId: id, lines: lines);
  }

  // ── Top-level delta ───────────────────────────────────────────────────

  /// Build the new fingerprint + divecomputerid lines this batch needs to
  /// add to `00-Subsurface`. Caller merges with the existing file
  /// (preserving Subsurface-side state).
  TopLevelDelta topLevelDelta({
    required Iterable<Dive> dives,
    required Iterable<DiveComputer> diveComputers,
  }) {
    final dcIds = <DivecomputerIdLine>[];
    final seenSerials = <int>{};
    for (final dc in diveComputers) {
      if (!seenSerials.add(dc.serial)) continue;
      final modelEnum = _shearwaterModelOf(dc.model);
      dcIds.add(DivecomputerIdLine(
        model: _modelDisplayName(modelEnum),
        fields: [
          MapEntry('deviceid', _deviceIdHex(dc.serial)),
          MapEntry('serial', '"${_paddedHex(dc.serial)}"'),
          if (dc.nickname != null && dc.nickname!.isNotEmpty)
            MapEntry('nickname', '"${dc.nickname!}"'),
        ],
      ));
    }

    final fingerprints = <FingerprintLine>[];
    for (final dive in dives) {
      fingerprints.add(FingerprintLine(fields: [
        MapEntry('model', _paddedHex(dive.dcModel)),
        MapEntry('serial', _paddedHex(dive.dcSerial)),
        MapEntry('deviceid', _deviceIdHex(dive.dcSerial)),
        MapEntry('diveid', dive.id.substring(0, 8)),
        MapEntry('data', '""'),
      ]));
    }

    return TopLevelDelta(
      newDivecomputerIds: dcIds,
      newFingerprints: fingerprints,
    );
  }

  // ── Dive file builder ─────────────────────────────────────────────────

  List<SsLine> _buildDiveLines({
    required Dive dive,
    required SampleSet samples,
    required DiveAnnotation? annotation,
    required List<DiveGasMix> gasMixes,
    required List<DiveTank> tanks,
    required Map<int, Cylinder> cylindersByMixIndex,
    required String? siteId,
  }) {
    final lines = <SsLine>[];
    lines.add(ScalarLine(
      key: 'duration',
      value: '${_formatDurationMmSs(dive.durationSeconds)} min',
    ));
    final rating = annotation?.rating;
    if (rating != null) {
      lines.add(ScalarLine(key: 'rating', value: rating.toString()));
    }
    final tags = annotation?.tags ?? const [];
    if (tags.isNotEmpty) {
      lines.add(TagsLine(tags: List.of(tags)));
    }
    // Information-tab star ratings — Subsurface convention is 1..5.
    void emitStar(String key, int? value) {
      if (value != null && value > 0) {
        lines.add(ScalarLine(key: key, value: value.toString()));
      }
    }
    emitStar('visibility', annotation?.visibility);
    emitStar('wavesize', annotation?.wavesize);
    emitStar('current', annotation?.current);
    emitStar('surge', annotation?.surge);
    emitStar('chill', annotation?.chill);
    // Environment temperatures — Subsurface writes with °C suffix.
    void emitTemp(String key, double? celsius) {
      if (celsius == null) return;
      final formatted = celsius == celsius.roundToDouble()
          ? '${celsius.toStringAsFixed(1)}°C'
          : '${celsius.toStringAsFixed(1)}°C';
      lines.add(ScalarLine(key: key, value: formatted));
    }
    emitTemp('airtemp', annotation?.airTempC);
    emitTemp('watertemp', annotation?.waterTempC);
    if (siteId != null) {
      lines.add(ScalarLine(key: 'divesiteid', value: siteId));
    }
    lines.add(QuotedLine(key: 'divemaster', value: ''));
    final buddy = (annotation?.buddies ?? const <String>[]).join(', ');
    lines.add(QuotedLine(key: 'buddy', value: buddy));
    lines.add(QuotedLine(key: 'suit', value: annotation?.suit ?? ''));
    final notes = annotation?.notes;
    if (notes != null && notes.isNotEmpty) {
      lines.add(QuotedLine(key: 'notes', value: notes));
    }
    // Weights — one `weightsystem` line per entry.
    final weights = annotation?.weights ?? const <Weight>[];
    for (final w in weights) {
      final desc = w.description;
      lines.add(WeightsystemLine(
        fields: [
          MapEntry('weight', '${_formatDecimal(w.weightKg, 1)}kg'),
          MapEntry('description', '"$desc"'),
        ],
      ));
    }

    for (var i = 0; i < gasMixes.length; i++) {
      lines.add(_cylinderLineFor(
        index: i,
        mix: gasMixes[i],
        cylinder: cylindersByMixIndex[i],
        tank: _tankForMixIndex(tanks, i),
        samples: samples,
      ));
    }

    return lines;
  }

  CylinderLine _cylinderLineFor({
    required int index,
    required DiveGasMix mix,
    required Cylinder? cylinder,
    required DiveTank? tank,
    required SampleSet samples,
  }) {
    final fields = <MapEntry<String, String>>[];
    final volumeLiters = cylinder?.volumeLiters ?? 3.0;
    final workPressure = cylinder?.workingPressureBar ?? 232;
    final description =
        cylinder?.label ?? '${volumeLiters.toStringAsFixed(0)}L tank';

    fields
      ..add(MapEntry('vol', '${_formatDecimal(volumeLiters, 1)}l'))
      ..add(MapEntry(
          'workpressure', '${_formatDecimal(workPressure.toDouble(), 1)}bar'))
      ..add(MapEntry('description', '"$description"'))
      ..add(MapEntry('o2', '${_formatDecimal(mix.oxygenPercent.toDouble(), 1)}%'));

    if (mix.heliumPercent > 0) {
      fields.add(MapEntry(
          'he', '${_formatDecimal(mix.heliumPercent.toDouble(), 1)}%'));
    }

    // Subsurface omits start/end if the cylinder wasn't pressure-monitored.
    // We only emit them when we have real per-tank pressure data.
    if (tank != null) {
      if (tank.beginPressureBar > 0) {
        fields.add(MapEntry('start',
            '${_formatDecimal(tank.beginPressureBar, 1)}bar'));
      }
      if (tank.endPressureBar > 0) {
        fields.add(
            MapEntry('end', '${_formatDecimal(tank.endPressureBar, 1)}bar'));
      }
    }

    final useValue = _useValueFor(mix, tank);
    if (useValue != null) {
      fields.add(MapEntry('use', '"$useValue"'));
    }

    final firstDepthM = _firstDepthForMix(samples, index);
    if (firstDepthM != null) {
      fields.add(MapEntry('depth', '${_formatDecimal(firstDepthM, 3)}m'));
    }

    return CylinderLine(fields: fields);
  }

  /// Map a CCRLog gas mix + tank to Subsurface's `use="..."` value.
  /// Returns null when no `use` key should be emitted (Subsurface default).
  String? _useValueFor(DiveGasMix mix, DiveTank? tank) {
    if (tank != null) {
      switch (tank.usage) {
        case TankUsage.oxygen:
          return 'oxygen';
        case TankUsage.diluent:
          return 'diluent';
        case TankUsage.sidemount:
          return null;
        case TankUsage.none:
          break;
      }
    }
    if (mix.isDiluent) return 'diluent';
    if (mix.oxygenPercent >= 99) return 'oxygen';
    return null;
  }

  DiveTank? _tankForMixIndex(List<DiveTank> tanks, int mixIndex) {
    for (final t in tanks) {
      if (t.slot == mixIndex) return t;
    }
    return null;
  }

  /// First depth (in meters) at which a sample uses [mixIndex]. Used to
  /// stamp the cylinder's `depth=` field, which Subsurface uses to place
  /// the gas-switch marker on the profile.
  double? _firstDepthForMix(SampleSet samples, int mixIndex) {
    for (var i = 0; i < samples.sampleCount; i++) {
      if (samples.gasMixIndex[i] == mixIndex) {
        return samples.depthMeters[i];
      }
    }
    return null;
  }

  // ── Divecomputer file builder ─────────────────────────────────────────

  List<SsLine> _buildDivecomputerLines({
    required Dive dive,
    required SampleSet samples,
    required List<DiveGasMix> gasMixes,
    required List<DiveTank> tanks,
  }) {
    final lines = <SsLine>[];
    final modelEnum = _shearwaterModelOf(dive.dcModel);
    final isCcr = DiveMode.fromValue(dive.diveMode).isCcr;

    lines.add(QuotedLine(key: 'model', value: _modelDisplayName(modelEnum)));
    lines.add(ScalarLine(key: 'deviceid', value: _deviceIdHex(dive.dcSerial)));
    lines.add(ScalarLine(key: 'diveid', value: dive.id.substring(0, 8)));
    if (isCcr) {
      lines.add(ScalarLine(key: 'dctype', value: 'CCR'));
      lines.add(ScalarLine(key: 'numberofoxygensensors', value: '3'));
    }

    final maxDepthM = dive.maxDepthMm / 1000.0;
    lines.add(ScalarLine(
        key: 'maxdepth', value: '${_formatDecimal(maxDepthM, 1)}m'));

    final mean = _meanDepthMeters(samples);
    if (mean != null) {
      lines.add(ScalarLine(
          key: 'meandepth', value: '${_formatDecimal(mean, 3)}m'));
    }
    final temp = _meanTempCelsius(samples);
    if (temp != null) {
      lines.add(ScalarLine(
          key: 'watertemp', value: '${_formatDecimal(temp, 1)}°C'));
    }
    lines.add(ScalarLine(
      key: 'surfacepressure',
      value: '${_formatDecimal(dive.atmosphericPressureMbar / 1000.0, 3)}bar',
    ));
    lines.add(ScalarLine(
      key: 'salinity',
      value: '${dive.waterDensity}g/l',
    ));

    // Stack-time keyvalues — only emitted when stack tracking was enabled.
    if (dive.configuredStackSeconds != null) {
      lines.add(KeyvaluePairLine(
        key: 'Configured stack time [hh:mm:ss]',
        value: _formatHhMmSs(dive.configuredStackSeconds!),
      ));
    }
    if (dive.stackRemainingAtStartSeconds != null) {
      lines.add(KeyvaluePairLine(
        key: 'Remaining stack time at start [hh:mm:ss]',
        value: _formatHhMmSs(dive.stackRemainingAtStartSeconds!),
      ));
    }
    if (dive.stackRemainingAtEndSeconds != null) {
      lines.add(KeyvaluePairLine(
        key: 'Remaining stack time at end [hh:mm:ss]',
        value: _formatHhMmSs(dive.stackRemainingAtEndSeconds!),
      ));
    }

    lines.add(KeyvaluePairLine(
      key: 'Logversion',
      value: '${dive.logVersion}(PNF)',
    ));
    lines.add(KeyvaluePairLine(
      key: 'Serial',
      value: _paddedHex(dive.dcSerial),
    ));
    if (dive.dcFirmware != null) {
      lines.add(KeyvaluePairLine(
        key: 'FW Version',
        value: dive.dcFirmware!.toRadixString(16),
      ));
    }
    if (dive.gfLow != null && dive.gfHigh != null) {
      lines.add(KeyvaluePairLine(
        key: 'Deco model',
        value: 'GF ${dive.gfLow}/${dive.gfHigh}',
      ));
    }

    // Per-cell calibration (bar / V) — persisted at import time. Three
    // entries on CCR; falls back to the Petrel factory default 0.021
    // mV→bar (= 21.00 bar/V) for OC dives or pre-Phase-3 imports that
    // don't have calibration stored.
    final cal = _decodeSensorCalibration(dive);
    if (isCcr) {
      for (var i = 0; i < 3; i++) {
        // mV→bar factor (e.g. 0.021) → bar/V (e.g. 21.00) via × 1000.
        // Two-decimal formatting matches the Subsurface fixture verbatim
        // (`"21.00"`).
        lines.add(KeyvaluePairLine(
          key: 'Sensor ${i + 1} calibration [bar / V]',
          value: (cal[i] * 1000).toStringAsFixed(2),
        ));
      }
    }

    // Events: gas-change events on `gasMixIdx` transitions. v1: gas changes
    // are the load-bearing event type; setpoint changes / bookmarks come
    // later.
    lines.addAll(_buildGasChangeEvents(samples, gasMixes));

    // Samples: sparse columnar emission.
    lines.addAll(_buildSampleLines(samples, tanks: tanks, cellCal: cal));

    return lines;
  }

  /// Per-cell mV→bar calibration as a 3-element list. Reads
  /// [Dive.sensorCalibrationJson] and pads with the Petrel factory
  /// default 0.021 for any missing/invalid entries (older imports,
  /// OC dives, or rows from a device that hadn't migrated yet).
  static const double _defaultCellCal = 0.021;
  List<double> _decodeSensorCalibration(Dive dive) {
    final raw = dive.sensorCalibrationJson;
    final out = List<double>.filled(3, _defaultCellCal);
    if (raw == null || raw.isEmpty) return out;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (var i = 0; i < 3 && i < decoded.length; i++) {
          final v = decoded[i];
          if (v is num && v.isFinite && v > 0) {
            out[i] = v.toDouble();
          }
        }
      }
    } catch (_) {
      // Malformed JSON falls through to the default-filled list.
    }
    return out;
  }

  // ── Events ────────────────────────────────────────────────────────────

  List<EventLine> _buildGasChangeEvents(
    SampleSet samples,
    List<DiveGasMix> gasMixes,
  ) {
    final events = <EventLine>[];
    if (samples.sampleCount == 0) return events;
    int? prevMix;
    for (var i = 0; i < samples.sampleCount; i++) {
      final mix = samples.gasMixIndex[i];
      if (prevMix == mix) continue;
      prevMix = mix;
      if (mix < 0 || mix >= gasMixes.length) continue;
      final timeSec = (i * samples.sampleIntervalMs) ~/ 1000;
      final g = gasMixes[mix];
      events.add(EventLine(
        time: _formatMmSs(timeSec),
        fields: [
          const MapEntry('type', '25'),
          const MapEntry('flags', '6'),
          const MapEntry('name', '"gaschange"'),
          MapEntry('cylinder', mix.toString()),
          MapEntry(
              'o2', '${_formatDecimal(g.oxygenPercent.toDouble(), 1)}%'),
          if (g.heliumPercent > 0)
            MapEntry(
                'he', '${_formatDecimal(g.heliumPercent.toDouble(), 1)}%'),
        ],
      ));
    }
    return events;
  }

  // ── Sample emission (sparse) ──────────────────────────────────────────

  /// Emit one [SampleLine] per sample, with each token included only when
  /// its value differs from the previously-emitted value for that channel.
  /// The first sample emits everything that is non-null in its row.
  ///
  /// [cellCal] is the per-cell mV→bar calibration (length 3, padded with
  /// the Petrel default 0.021 by the caller); we apply it to the raw mV
  /// channels here so the emitted sensor1/2/3 lexemes are bar PPO2.
  List<SampleLine> _buildSampleLines(
    SampleSet samples, {
    required List<DiveTank> tanks,
    required List<double> cellCal,
  }) {
    final out = <SampleLine>[];
    if (samples.sampleCount == 0) return out;

    // Per-channel "last emitted lexeme" state. We emit a token only when
    // its newly-formatted lexeme differs from the previously-emitted one.
    String? lastDepth;
    String? lastTemp;
    final lastTankPressure = <int, String>{};
    String? lastTts;
    String? lastCns;
    String? lastSensor1;
    String? lastSensor2;
    String? lastSensor3;
    String? lastDcSuppliedPpo2;
    String? lastPo2;
    String? lastNdl;
    String? lastStopdepth;
    String? lastStoptime;

    for (var i = 0; i < samples.sampleCount; i++) {
      final timeSec = (i * samples.sampleIntervalMs) ~/ 1000;
      final positional = <String>[];
      final kv = <MapEntry<String, String>>[];

      // Depth (always positional, always emitted on first sample). NaN/zero
      // counts as a real reading because the dive computer logs surface
      // samples too.
      final depthM = samples.depthMeters[i];
      final depthLex = '${_formatDecimal(depthM, 1)}m';
      if (depthLex != lastDepth) {
        positional.add(depthLex);
        lastDepth = depthLex;
      } else {
        // Subsurface always seems to emit *some* depth on every sample, even
        // when unchanged. Match that.
        positional.add(depthLex);
      }

      // Temperature — only when changed.
      final tempC = samples.temperatureCelsius[i];
      if (tempC.isFinite && tempC != 0) {
        final tempLex = '${_formatDecimal(tempC, 1)}°C';
        if (tempLex != lastTemp) {
          positional.add(tempLex);
          lastTemp = tempLex;
        }
      }

      // Tank pressures (indexed form when we have multi-tank data).
      if (samples.tankPressuresBar.isNotEmpty) {
        for (var t = 0; t < samples.tankPressuresBar.length; t++) {
          final value = samples.tankPressuresBar[t][i];
          if (value <= 0 || !value.isFinite) continue;
          final lex = '${_formatDecimal(value, 3)}bar:$t';
          final last = lastTankPressure[t];
          if (lex != last) {
            positional.add(lex);
            lastTankPressure[t] = lex;
          }
        }
      }

      // tts (seconds → MM:SS).
      final ttsSec = samples.ttsSeconds[i];
      if (ttsSec >= 0) {
        final ttsLex = _formatMmSs(ttsSec);
        if (ttsLex != lastTts) {
          kv.add(MapEntry('tts', ttsLex));
          lastTts = ttsLex;
        }
      }

      // ndl: when not in deco (decoStopDepth == 0) and decoTime > 0, emit
      // it as the NDL clock. We emit it only on changes.
      final stopDepthM = samples.decoStopDepthMeters[i];
      final decoTimeSec = samples.decoTimeSeconds[i];
      if (stopDepthM <= 0 && decoTimeSec > 0) {
        final lex = _formatMmSs(decoTimeSec);
        if (lex != lastNdl) {
          kv.add(MapEntry('ndl', lex));
          lastNdl = lex;
        }
      } else if (stopDepthM > 0) {
        final stopLex = '${_formatDecimal(stopDepthM, 1)}m';
        if (stopLex != lastStopdepth) {
          kv.add(MapEntry('stopdepth', stopLex));
          lastStopdepth = stopLex;
        }
        final stopTimeLex = _formatMmSs(decoTimeSec);
        if (stopTimeLex != lastStoptime) {
          kv.add(MapEntry('stoptime', stopTimeLex));
          lastStoptime = stopTimeLex;
        }
      }

      // CNS (0..1 in our model → integer percent in Subsurface).
      final cns = samples.cns[i];
      if (cns.isFinite && cns > 0) {
        final pct = (cns * 100).round();
        final lex = '$pct%';
        if (lex != lastCns) {
          kv.add(MapEntry('cns', lex));
          lastCns = lex;
        }
      }

      // Per-cell mV → bar PPO2 via the persisted calibration. Each
      // calibration entry is a bar/V factor read from the Shearwater
      // header at import time; the conversion is `mV * cal / 1000 = bar`.
      // When calibration is absent (older imports, OC dives) the caller
      // populates `cellCal` with the Petrel default 0.021 so the math
      // still works.
      final s1 = samples.cellMv0[i];
      if (s1.isFinite && s1 > 0) {
        final ppo2 = s1 * cellCal[0];
        final lex = '${_formatDecimal(ppo2, 3)}bar';
        if (lex != lastSensor1) {
          kv.add(MapEntry('sensor1', lex));
          lastSensor1 = lex;
        }
      }
      final s2 = samples.cellMv1[i];
      if (s2.isFinite && s2 > 0) {
        final ppo2 = s2 * cellCal[1];
        final lex = '${_formatDecimal(ppo2, 3)}bar';
        if (lex != lastSensor2) {
          kv.add(MapEntry('sensor2', lex));
          lastSensor2 = lex;
        }
      }
      final s3 = samples.cellMv2[i];
      if (s3.isFinite && s3 > 0) {
        final ppo2 = s3 * cellCal[2];
        final lex = '${_formatDecimal(ppo2, 3)}bar';
        if (lex != lastSensor3) {
          kv.add(MapEntry('sensor3', lex));
          lastSensor3 = lex;
        }
      }

      // dc_supplied_ppo2: the cell-averaged PPO2 the DC computed before
      // voting. We don't store this separately, but the per-cell sensors
      // above give the rest. Emit when our setpoint differs (proxy).
      final sp = samples.setpointBar[i];
      if (sp.isFinite && sp > 0) {
        final lex = '${_formatDecimal(sp, 2)}bar';
        if (lex != lastDcSuppliedPpo2) {
          kv.add(MapEntry('dc_supplied_ppo2', lex));
          lastDcSuppliedPpo2 = lex;
        }
      }

      // po2: the voted value. CCRLog stores voted PPO2 in `samples.ppo2Bar`.
      final ppo2 = samples.ppo2Bar[i];
      if (ppo2.isFinite && ppo2 > 0) {
        final lex = '${_formatDecimal(ppo2, 1)}bar';
        if (lex != lastPo2) {
          kv.add(MapEntry('po2', lex));
          lastPo2 = lex;
        }
      }

      out.add(SampleLine(
        time: _formatMmSs(timeSec),
        positional: positional,
        kv: kv,
      ));
    }
    return out;
  }

  // ── Helpers (numeric / time / hex) ────────────────────────────────────

  /// Folder segments derived from the dive's start time. Subsurface uses
  /// the *local* calendar moment as recorded by the dive computer; the
  /// Shearwater binary stores that as a unix-epoch lexeme without
  /// timezone, and CCRLog stores that same value verbatim in
  /// `Dive.startTime` (despite the column comment claiming UTC). We
  /// therefore decode it as UTC components here so the resulting folder
  /// matches the diver's wall-clock time.
  List<String> _folderSegments(int startTimeUnixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      startTimeUnixSeconds * 1000,
      isUtc: true,
    );
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final day = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][
        (dt.weekday - 1) % 7];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return [yyyy, mm, '$dd-$day-$hh=$mi=$ss'];
  }

  String _formatDecimal(double value, int decimals) =>
      value.toStringAsFixed(decimals);

  String _formatMmSs(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final m = s ~/ 60;
    final ss = s % 60;
    return '$m:${ss.toString().padLeft(2, '0')}';
  }

  String _formatHhMmSs(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    return '$h:${m.toString().padLeft(2, '0')}:'
        '${ss.toString().padLeft(2, '0')}';
  }

  String _formatDurationMmSs(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final m = s ~/ 60;
    final ss = s % 60;
    return '$m:${ss.toString().padLeft(2, '0')}';
  }

  String _paddedHex(int value) {
    final hex = value.toUnsigned(32).toRadixString(16);
    return hex.padLeft(8, '0');
  }

  /// Subsurface's `deviceid` is a 32-bit hash of (model + serial). We
  /// approximate it by re-using the serial as 8-char zero-padded hex —
  /// this matches what the fixtures show for our serial (`b89641e4` →
  /// deviceid `18545bf0` is a Subsurface-side computation we can't
  /// reproduce exactly without the libdc hash, so we emit a stable
  /// derivative from sha256(serial) instead). See the format-notes doc
  /// for the assumption.
  String _deviceIdHex(int serial) {
    final digest = sha256.convert(utf8.encode('ccrlog:device:$serial'));
    return digest.toString().substring(0, 8);
  }

  String _gpsLexeme(double value) => value.toStringAsFixed(6);

  String? _siteIdFor(DiveAnnotation annotation) {
    final lat = annotation.siteLatitude;
    final lon = annotation.siteLongitude;
    if (lat == null || lon == null) return null;
    final latE5 = (lat * 1e5).round();
    final lonE5 = (lon * 1e5).round();
    final digest = sha256.convert(utf8.encode('$latE5:$lonE5'));
    return digest.toString().substring(0, 8);
  }

  ShearwaterModel _shearwaterModelOf(int index) {
    if (index < 0 || index >= ShearwaterModel.values.length) {
      return ShearwaterModel.unknown;
    }
    return ShearwaterModel.values[index];
  }

  String _modelDisplayName(ShearwaterModel m) => switch (m) {
        ShearwaterModel.predator => 'Shearwater Predator',
        ShearwaterModel.petrel => 'Shearwater Petrel',
        ShearwaterModel.petrel2 => 'Shearwater Petrel 2',
        ShearwaterModel.petrel3 => 'Shearwater Petrel 3',
        ShearwaterModel.nerd => 'Shearwater NERD',
        ShearwaterModel.nerd2 => 'Shearwater NERD 2',
        ShearwaterModel.perdix => 'Shearwater Perdix',
        ShearwaterModel.perdixAi => 'Shearwater Perdix AI',
        ShearwaterModel.perdix2 => 'Shearwater Perdix 2',
        ShearwaterModel.teric => 'Shearwater Teric',
        ShearwaterModel.peregrine => 'Shearwater Peregrine',
        ShearwaterModel.peregrineTx => 'Shearwater Peregrine TX',
        ShearwaterModel.tern => 'Shearwater Tern',
        ShearwaterModel.unknown => 'Shearwater',
      };

  double? _meanDepthMeters(SampleSet samples) {
    if (samples.sampleCount == 0) return null;
    var sum = 0.0;
    var count = 0;
    for (var i = 0; i < samples.sampleCount; i++) {
      final v = samples.depthMeters[i];
      if (!v.isFinite) continue;
      sum += v;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  double? _meanTempCelsius(SampleSet samples) {
    if (samples.sampleCount == 0) return null;
    var count = 0;
    var minSeen = double.infinity;
    for (var i = 0; i < samples.sampleCount; i++) {
      final v = samples.temperatureCelsius[i];
      if (!v.isFinite || v == 0) continue;
      count++;
      if (v < minSeen) minSeen = v;
    }
    if (count == 0) return null;
    // Subsurface's `watertemp` field is the *minimum* (coldest), not the
    // mean — verified across the fixture corpus (`watertemp 7.0°C` in
    // 2026/04/04 vs the average ~10°C from the samples). Use the minimum.
    return minSeen;
  }
}
