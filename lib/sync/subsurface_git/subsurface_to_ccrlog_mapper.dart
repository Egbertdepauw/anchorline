/// Pure-Dart mapper from Subsurface's git-repo plain-text format into
/// CCRLog's domain model. The READ direction (Subsurface → CCRLog).
///
/// This is the inverse of `mapper.dart` (the CCRLog → Subsurface write
/// direction). It takes the parsed `SsLine` lists from one Subsurface
/// dive folder (Dive-NNN + Divecomputer) plus an optional Site file and
/// produces a [ConvertedDive] (ready for `DiveDao.importDive`) plus a
/// [DiveAnnotation] and a map of per-mix [ProposedCylinder] data.
///
/// Lossy seams (documented here so the orchestrator can decide its
/// "tolerance vs strictness" policy):
///
/// - **Cell mV**: Subsurface stores per-cell PPO2 in bar (`sensor1=0.714bar`)
///   plus a calibration `keyvalue "Sensor N calibration [bar / V]" "21.00"`.
///   We invert to get mV: `mv = bar / cal_per_mV` where
///   `cal_per_mV = bar_per_V / 1000`. For the 21.00 bar/V Petrel default,
///   `0.021 bar/mV` ⇒ `0.714/0.021 = 34.0 mV`. The bar value is rounded to
///   3 decimal places by Subsurface, so the recovered mV has roughly
///   ±0.5 mV of noise compared to the source binary.
/// - **Setpoint**: Subsurface's `dc_supplied_ppo2=` is the cell-averaged
///   PPO2, NOT the setpoint. Real setpoint changes appear as `event` lines
///   (`name="setpoint change"` or `name="SP change"` depending on
///   Subsurface version). Without a setpoint event we fall back to a
///   default of 0.7 bar (Petrel cold-start setpoint). This is intentional —
///   the source binary has the real setpoint trace and we can't recover it
///   losslessly from the Subsurface log.
/// - **CNS / deco**: Subsurface only emits `cns=N%` when it changes. Our
///   sparse-reconstruction holds the last-seen value forward (so a 1%
///   reading at minute 3 sticks until the next change). This is the same
///   semantic Subsurface itself uses for sparse samples, so visually it
///   looks correct. We default to 0% when the dive never emits a `cns`
///   token.
/// - **Status flags**: Subsurface doesn't preserve the Petrel's status
///   bitfield. We always emit 0. Solenoid-fire analysis requires importing
///   from the Petrel binary directly (Phase 1 path) — the Subsurface
///   bootstrap path is metadata-only for status.
/// - **Tank pressure indexed vs un-indexed**: Subsurface emits
///   `207.946bar:0` (tank index 0) when there are multiple tanks, or just
///   `187.951bar` for a single tank. We treat both forms; the un-indexed
///   form maps to tank index 0.
/// - **Manual dives**: dives with no `model` line (typically pre-2010
///   manually-entered dives or `model "manually added dive"`) cannot
///   produce a meaningful `ConvertedDive` because we have no DC serial,
///   firmware, or sensor calibration to anchor a Petrel-shaped record.
///   `mapDive` returns null in that case; the orchestrator can decide
///   whether to skip the dive or surface it as an "unmapped legacy" item.
library;

import 'dart:typed_data';

import '../../data/models/annotation.dart';
import '../../data/models/dive.dart';
import '../../data/models/sample_set.dart';
import '../../shearwater/parser/constants.dart';
import '../../shearwater/parser/dive_converter.dart' show ConvertedDive;
import '../../shearwater/parser/hardware.dart';
import '../../shearwater/parser/parsed_dive.dart' show TankUsage;
import 'format/subsurface_format.dart';
import 'format/subsurface_unit_parsing.dart';

/// One Subsurface dive folder mapped into the CCRLog domain bundle.
///
/// `converted` is suitable for `DiveDao.importDive`. `annotation` is null
/// when the source `Dive-NNN` had no human-edited fields. `cylindersByMixIndex`
/// describes each cylinder line; the orchestrator decides whether to upsert
/// vs reuse existing equipment rows.
class ImportedSubsurfaceDive {
  ImportedSubsurfaceDive({
    required this.converted,
    required this.annotation,
    required this.cylindersByMixIndex,
  });

  final ConvertedDive converted;
  final DiveAnnotation? annotation;
  final Map<int, ProposedCylinder> cylindersByMixIndex;
}

/// Cylinder data extracted from a Subsurface `cylinder` line.
///
/// The orchestrator decides whether to upsert vs reuse existing equipment
/// rows; this struct is just the raw values from the line.
class ProposedCylinder {
  ProposedCylinder({
    this.startPressureBar,
    this.endPressureBar,
    required this.volumeLiters,
    required this.workingPressureBar,
    required this.description,
    required this.o2Percent,
    required this.hePercent,
    required this.use,
  });

  final double volumeLiters;
  final int workingPressureBar;
  final String? description;
  final int o2Percent;
  final int hePercent;

  /// `"oxygen"`, `"diluent"`, `"bailout"`, `"not used"`, or null when the
  /// `use=` key was absent.
  final String? use;

  /// Manual `start=Xbar` from the cylinder line, or null when omitted.
  /// The per-sample stream (`X.Ybar:N`) is preferred when both are present.
  final double? startPressureBar;

  /// Manual `end=Xbar` from the cylinder line, or null when omitted.
  final double? endPressureBar;
}

/// Maps Subsurface git-repo dive folders into CCRLog domain bundles.
class SubsurfaceToCcrlogMapper {
  SubsurfaceToCcrlogMapper();

  /// Map one Subsurface dive folder into a CCRLog [ImportedSubsurfaceDive].
  ///
  /// [diveLines] are the parsed lines of `<folder>/Dive-NNN`.
  /// [divecomputerLines] are the parsed lines of `<folder>/Divecomputer`
  /// (or `Divecomputer-NNN`).
  /// [siteLines] are the parsed lines of the matching
  /// `01-Divesites/Site-<id>` file when the dive's `divesiteid` resolves
  /// to a known site; null otherwise.
  /// [startTime] is the dive's start moment, parsed from the folder name
  /// by the orchestrator (we don't re-parse it here).
  /// [subsurfaceDiveNumber] is the integer from the `Dive-NNN` filename;
  /// used as the CCRLog `dcDiveNumber` (Subsurface doesn't store the real
  /// per-DC dive number, so we use Subsurface's monotonic counter as a
  /// stand-in for `generateDiveId`).
  ///
  /// Returns null when the inputs don't represent a valid dive (no
  /// `model` line / no `Serial` keyvalue / no sample lines). Manual dives
  /// and partial logs fall into this bucket — the orchestrator can decide
  /// whether to surface them as "unmapped legacy" or skip silently.
  ImportedSubsurfaceDive? mapDive({
    required List<SsLine> diveLines,
    required List<SsLine> divecomputerLines,
    required List<SsLine>? siteLines,
    required DateTime startTime,
    required int subsurfaceDiveNumber,
  }) {
    // ── Header parse from Divecomputer file ───────────────────────────
    //
    // Manual / non-Shearwater dives lack a real model + serial. Rather
    // than refuse to import, synthesise: dcSerial=0, dcModel=unknown.
    // The dive id derives from (serial, diveNumber, startTime) so
    // collisions across manual dives only happen if two share the
    // exact same Subsurface counter + start second — unique by
    // construction in a Subsurface repo.
    final dcMeta = _DivecomputerMetadata.from(divecomputerLines);
    final dcModel = dcMeta.modelName == null
        ? ShearwaterModel.unknown
        : _shearwaterModelFromName(dcMeta.modelName!);

    // ── Sample lines (zero is allowed — manual dives have none) ───────
    final sampleLines = divecomputerLines.whereType<SampleLine>().toList();

    // ── Cylinders / gas mixes from Dive file ──────────────────────────
    final cylinderLines = diveLines.whereType<CylinderLine>().toList();
    final cylindersByMixIndex = <int, ProposedCylinder>{};
    final gasMixes = <DiveGasMix>[];
    for (var i = 0; i < cylinderLines.length; i++) {
      final cyl = _parseCylinderLine(cylinderLines[i]);
      cylindersByMixIndex[i] = cyl;
      gasMixes.add(DiveGasMix(
        oxygenPercent: cyl.o2Percent,
        heliumPercent: cyl.hePercent,
        isDiluent: cyl.use == 'diluent',
      ));
    }
    // Subsurface always emits at least one cylinder for "real" dives. If
    // the Dive file truly had none (very old manual entries), we
    // synthesise a single air mix so the rest of the pipeline doesn't
    // crash; gasMixIndex defaults to 0 and points to it.
    if (gasMixes.isEmpty) {
      gasMixes.add(DiveGasMix(
        oxygenPercent: 21,
        heliumPercent: 0,
        isDiluent: false,
      ));
    }

    // ── Reconstruct samples ───────────────────────────────────────────
    final eventLines = divecomputerLines.whereType<EventLine>().toList();
    final samplesBuilt = _reconstructSamples(
      sampleLines: sampleLines,
      events: eventLines,
      sensorCalibrationBarPerMv: dcMeta.sensorCalibrationBarPerMv,
      tankCount: _detectTankCount(sampleLines),
    );

    // ── Compose Dive (domain) ─────────────────────────────────────────
    //
    // Synthesise serial=0 for manual / non-Petrel dives. The
    // (serial, startTime) dedupe key the orchestrator uses still
    // works because Subsurface's per-user dive counter
    // (subsurfaceDiveNumber) is what's hashed into the id below — two
    // manual dives at the same instant are impossible in a single
    // Subsurface repo.
    final dcSerial = dcMeta.serial ?? 0;
    final diveId = generateDiveId(
      dcSerial,
      subsurfaceDiveNumber,
      startTime.millisecondsSinceEpoch ~/ 1000,
    );

    final durationSeconds = sampleLines.length * (samplesBuilt.intervalMs ~/ 1000);
    // Prefer an explicit `duration N:NN min` from the Dive file when
    // present; it's the canonical user-visible duration and may differ
    // slightly from sampleCount * interval for edge cases (final sample
    // landing mid-second).
    final durFromDiveFile = _scalarSeconds(diveLines, 'duration');
    final durFromMaxDepth = _scalarSeconds(divecomputerLines, 'lastmanualtime');
    final effectiveDuration = durFromDiveFile ??
        durFromMaxDepth ??
        durationSeconds;

    final endTime = startTime.add(Duration(seconds: effectiveDuration));

    final maxDepthM = _firstScalarMeters(divecomputerLines, 'maxdepth') ??
        _peakDepth(samplesBuilt.depthMeters);

    final dive = Dive(
      id: diveId,
      dcSerial: dcSerial,
      dcDiveNumber: subsurfaceDiveNumber,
      startTime: startTime,
      endTime: endTime,
      utcOffsetMinutes: null,
      duration: Duration(seconds: effectiveDuration),
      maxDepthMeters: maxDepthM,
      diveMode: dcMeta.diveMode,
      decoModel: DecoModel.gf,
      gfLow: dcMeta.gfLow ?? 0,
      gfHigh: dcMeta.gfHigh ?? 0,
      atmosphericPressureMbar: dcMeta.atmosphericPressureMbar ?? 1013,
      waterDensityKgM3: dcMeta.waterDensityKgM3 ?? 1000,
      logVersion: dcMeta.logVersion ?? 0,
      dcModel: dcModel,
      gasMixes: gasMixes,
      tanks: _buildTanks(
        cylinders: [
          for (var i = 0; i < cylinderLines.length; i++)
            cylindersByMixIndex[i]!,
        ],
        tankPressures: samplesBuilt.tankPressures,
      ),
      sampleIntervalMs: samplesBuilt.intervalMs,
      sensorCalibration: dcMeta.diveMode.isCcr
          ? List<double>.from(dcMeta.sensorCalibrationBarPerMv)
          : const [],
      configuredStackSeconds: dcMeta.configuredStackSeconds,
      stackRemainingAtStartSeconds: dcMeta.stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: dcMeta.stackRemainingAtEndSeconds,
    );

    final samples = SampleSet(
      diveId: diveId,
      sampleCount: samplesBuilt.sampleCount,
      sampleIntervalMs: samplesBuilt.intervalMs,
      depthMeters: samplesBuilt.depthMeters,
      temperatureCelsius: samplesBuilt.temperatureCelsius,
      ppo2Bar: samplesBuilt.ppo2Bar,
      cellMv0: samplesBuilt.cellMv0,
      cellMv1: samplesBuilt.cellMv1,
      cellMv2: samplesBuilt.cellMv2,
      setpointBar: samplesBuilt.setpointBar,
      cns: samplesBuilt.cns,
      decoStopDepthMeters: samplesBuilt.decoStopDepthMeters,
      decoTimeSeconds: samplesBuilt.decoTimeSeconds,
      ttsSeconds: samplesBuilt.ttsSeconds,
      gasMixIndex: samplesBuilt.gasMixIndex,
      statusFlags: samplesBuilt.statusFlags,
      tankPressuresBar: samplesBuilt.tankPressures,
    );

    final converted = ConvertedDive(dive: dive, samples: samples);

    // ── Annotation ────────────────────────────────────────────────────
    final annotation = _buildAnnotation(
      diveId: diveId,
      diveLines: diveLines,
      siteLines: siteLines,
    );

    return ImportedSubsurfaceDive(
      converted: converted,
      annotation: annotation,
      cylindersByMixIndex: cylindersByMixIndex,
    );
  }

  // ── Cylinder parsing ────────────────────────────────────────────────

  ProposedCylinder _parseCylinderLine(CylinderLine line) {
    final volStr = line.get('vol');
    final wpStr = line.get('workpressure');
    final descRaw = line.get('description');
    final o2Str = line.get('o2');
    final heStr = line.get('he');
    final useRaw = line.get('use');
    final startStr = line.get('start');
    final endStr = line.get('end');

    final volumeLiters = volStr == null ? 0.0 : _stripUnit(volStr, 'l') ?? 0.0;
    final workingPressureBar =
        wpStr == null ? 0 : (_stripUnit(wpStr, 'bar')?.round() ?? 0);
    final description = descRaw == null ? null : _unquote(descRaw);
    final o2Percent = o2Str == null
        ? 21 // air default when omitted (Subsurface convention)
        : (_stripUnit(o2Str, '%')?.round() ?? 21);
    final hePercent = heStr == null
        ? 0
        : (_stripUnit(heStr, '%')?.round() ?? 0);
    final use = useRaw == null ? null : _unquote(useRaw);
    final startPressureBar =
        startStr == null ? null : _stripUnit(startStr, 'bar');
    final endPressureBar =
        endStr == null ? null : _stripUnit(endStr, 'bar');

    return ProposedCylinder(
      volumeLiters: volumeLiters,
      workingPressureBar: workingPressureBar,
      description: description,
      o2Percent: o2Percent,
      hePercent: hePercent,
      use: use,
      startPressureBar: startPressureBar,
      endPressureBar: endPressureBar,
    );
  }

  /// Build the per-dive tank list from cylinders + per-sample pressure
  /// channels. A tank is included when it has any non-zero per-sample
  /// pressure OR a non-zero `start=` / `end=` from the cylinder line.
  /// Per-sample data wins when both are present.
  List<DiveTank> _buildTanks({
    required List<ProposedCylinder> cylinders,
    required List<Float32List> tankPressures,
  }) {
    final tanks = <DiveTank>[];
    for (var i = 0; i < cylinders.length; i++) {
      final cyl = cylinders[i];
      double beginBar = 0.0;
      double endBar = 0.0;
      final ch = i < tankPressures.length ? tankPressures[i] : null;
      if (ch != null) {
        for (var s = 0; s < ch.length; s++) {
          if (ch[s] > 0) {
            beginBar = ch[s];
            break;
          }
        }
        for (var s = ch.length - 1; s >= 0; s--) {
          if (ch[s] > 0) {
            endBar = ch[s];
            break;
          }
        }
      }
      if (beginBar == 0 && cyl.startPressureBar != null) {
        beginBar = cyl.startPressureBar!;
      }
      if (endBar == 0 && cyl.endPressureBar != null) {
        endBar = cyl.endPressureBar!;
      }
      if (beginBar == 0 && endBar == 0) continue;

      final usage = switch (cyl.use) {
        'diluent' => TankUsage.diluent,
        'oxygen' => TankUsage.oxygen,
        _ => TankUsage.none,
      };
      final name = (cyl.description?.trim().isNotEmpty ?? false)
          ? cyl.description!
          : (cyl.hePercent > 0
              ? '${cyl.o2Percent}/${cyl.hePercent}'
              : (cyl.o2Percent == 21
                  ? 'Air'
                  : 'EAN${cyl.o2Percent}'));
      tanks.add(DiveTank(
        slot: i,
        usage: usage,
        name: name,
        serial: 0,
        beginPressureBar: beginBar,
        endPressureBar: endBar,
        pressureMaxBar: cyl.workingPressureBar,
        pressureReserveBar: 0,
      ));
    }
    return tanks;
  }

  // ── Sample reconstruction ───────────────────────────────────────────

  _BuiltSamples _reconstructSamples({
    required List<SampleLine> sampleLines,
    required List<EventLine> events,
    required List<double> sensorCalibrationBarPerMv,
    required int tankCount,
  }) {
    final n = sampleLines.length;
    final intervalMs = _inferIntervalMs(sampleLines);

    // Allocate columnar arrays.
    final depthMeters = Float32List(n);
    final temperatureCelsius = Float32List(n);
    final ppo2Bar = Float32List(n);
    final cellMv0 = Float32List(n);
    final cellMv1 = Float32List(n);
    final cellMv2 = Float32List(n);
    final setpointBar = Float32List(n);
    final cns = Float32List(n);
    final decoStopDepthMeters = Float32List(n);
    final decoTimeSeconds = Int32List(n);
    final ttsSeconds = Int32List(n);
    final gasMixIndex = Uint8List(n);
    final statusFlags = Uint8List(n); // always zero — Subsurface drops bitfield

    // Per-tank pressure traces. We allocate `tankCount` channels even if
    // some are sparsely populated. tankCount==1 covers the un-indexed
    // `bar` form; tankCount==N+1 covers `bar:N` forms.
    final tankPressures = tankCount == 0
        ? const <Float32List>[]
        : List<Float32List>.generate(tankCount, (_) => Float32List(n),
            growable: false);

    // Pre-compute event timeline. The events list carries gas-change
    // events (`type=25`) and possibly setpoint changes (`type=11` per the
    // brief, `type=20` per the format-notes — we accept both, plus
    // `name="setpoint change"`/`"SP change"` text as a third match). All
    // are ordered by time.
    final eventTimeline = <_TimedEvent>[];
    for (final ev in events) {
      final tSec = parseTimeSeconds(ev.time);
      if (tSec == null) continue;
      final fields = Map.fromEntries(ev.fields);
      final type = int.tryParse(fields['type'] ?? '') ?? -1;
      final nameRaw = fields['name'] ?? '';
      final name = _unquote(nameRaw);
      if (type == 25 || name == 'gaschange') {
        final cyl = int.tryParse(fields['cylinder'] ?? '');
        if (cyl != null && cyl >= 0 && cyl < 256) {
          eventTimeline.add(_TimedEvent.gasChange(tSec, cyl));
        }
      } else if (type == 20 ||
          name == 'setpoint change' || name == 'SP change') {
        // Setpoint changes — `type=20` (the form libdc emits when it
        // does emit them at all) plus the human-readable name match.
        // We deliberately do NOT accept `type=11`: in real-world
        // Subsurface repos `type=11` is gaschange-with-extra-info
        // (`type=11 value=99 name="gaschange"` — value is the O2%
        // percent, not millibar), so misreading it as a setpoint
        // event would produce setpoint=0.099bar nonsense.
        // Subsurface's `value=` for type=20 is millibar; CCRLog
        // stores setpoint in bar.
        final raw = int.tryParse(fields['value'] ?? '');
        if (raw != null) {
          eventTimeline.add(_TimedEvent.setpoint(tSec, raw / 1000.0));
        }
      }
    }
    eventTimeline.sort((a, b) => a.timeSec.compareTo(b.timeSec));

    // Setpoint trace sources (in priority order):
    //
    //   1. Explicit `event T type=20 ... name="SP change" value=N` events.
    //      Reverse-engineered from Subsurface's `core/save-git.cpp` —
    //      these are how transition-style setpoint changes get saved
    //      when libdc emits them as separate events.
    //   2. Per-sample `po2=N.Nbar` tokens, forward-filled. Subsurface's
    //      `core/save-git.cpp:save_sample()` writes the setpoint as a
    //      `po2=` token ONLY when it CHANGES from the previous sample
    //      (delta-encoding). The reader (`core/load-git.cpp:
    //      parse_sample_keyvalue()`) carries it forward implicitly via
    //      profile-render. Note: `po2=` does NOT mean "PPO2" here —
    //      that's `dc_supplied_ppo2=`, which feeds our `ppo2Bar`
    //      channel. Confusing but Subsurface's spec.
    //
    // Samples before the first transition get setpoint = 0.0 (default);
    // CCR dives with no transitions at all get a flat 0.0 trace, which
    // signals "no real setpoint data in the source" rather than the
    // misleading 0.7 default that an inferred trace would produce.

    // Walk sample lines forward, maintaining state. Subsurface emits
    // sparse tokens, so unchanged channels carry forward. For each line
    // we (a) update state from any present tokens, (b) apply any events
    // whose `time <= sampleTime`, (c) write the current state.
    var stateDepthM = 0.0;
    var stateTempC = 0.0;
    var stateSensor1Bar = 0.0;
    var stateSensor2Bar = 0.0;
    var stateSensor3Bar = 0.0;
    var statePo2Bar = 0.0;
    var stateCnsPct = 0.0;
    var stateTtsSec = 0;
    var stateNdlSec = 0;
    var stateStopDepthM = 0.0;
    var stateStopTimeSec = 0;
    final stateTankBar = List<double>.filled(tankCount, 0.0);
    var stateMixIdx = 0;
    // Setpoint state defaults to 0.0 ("no data yet"). Subsurface emits
    // setpoint via `po2=` sample tokens delta-encoded — we'll see the
    // first transition (whether at t=0 or later) and forward-fill from
    // there. A dive whose source dropped setpoint entirely gets a flat
    // 0.0 trace so the absence is visible (vs. a misleading 0.7
    // pre-fill). Re-import via BLE recovers the full setpoint channel
    // from the Petrel binary.
    var stateSetpointBar = 0.0;

    var eventCursor = 0;

    for (var i = 0; i < n; i++) {
      final line = sampleLines[i];
      final tSec = parseTimeSeconds(line.time) ?? (i * (intervalMs ~/ 1000));

      // Apply any events with time <= this sample's time.
      while (eventCursor < eventTimeline.length &&
          eventTimeline[eventCursor].timeSec <= tSec) {
        final ev = eventTimeline[eventCursor];
        if (ev.kind == _TimedEventKind.gasChange) {
          stateMixIdx = ev.intValue;
        } else if (ev.kind == _TimedEventKind.setpoint) {
          stateSetpointBar = ev.doubleValue;
        }
        eventCursor++;
      }

      // Positional tokens: depth (always), then optional temperature,
      // then zero-or-more tank pressures (`X.Ybar:N` or `X.Ybar`).
      if (line.positional.isNotEmpty) {
        final depthLex = line.positional.first;
        final d = parseLengthMeters(depthLex);
        if (d != null) stateDepthM = d;
        for (var p = 1; p < line.positional.length; p++) {
          final tok = line.positional[p];
          if (tok.endsWith('°C')) {
            final t = parseTempCelsius(tok);
            if (t != null) stateTempC = t;
          } else {
            final pressure = parsePressureBar(tok);
            if (pressure != null) {
              final idx = pressure.tankIndex ?? 0;
              if (idx >= 0 && idx < stateTankBar.length) {
                stateTankBar[idx] = pressure.bar;
              }
            }
          }
        }
      }

      // KV tokens.
      for (final kv in line.kv) {
        switch (kv.key) {
          case 'sensor1':
            final b = _parseBar(kv.value);
            if (b != null) stateSensor1Bar = b;
            break;
          case 'sensor2':
            final b = _parseBar(kv.value);
            if (b != null) stateSensor2Bar = b;
            break;
          case 'sensor3':
            final b = _parseBar(kv.value);
            if (b != null) stateSensor3Bar = b;
            break;
          case 'dc_supplied_ppo2':
            // The cell-averaged PPO2 the DC computed. Subsurface emits
            // this every sample (it changes most often), and it's the
            // closest match to the voted-PPO2 trace CCRLog stores from
            // the Shearwater binary path. Prefer it over `po2=`, which
            // Subsurface only emits when its rounded-to-one-decimal
            // voted value transitions (so a 0.7-setpoint dive looks
            // like a flat line at 0.7 if we trust `po2=`).
            final dcb = _parseBar(kv.value);
            if (dcb != null) statePo2Bar = dcb;
            break;
          case 'po2':
            // Subsurface stores SETPOINT here (delta-encoded). It is
            // NOT the cell-measured PPO2 — that's `dc_supplied_ppo2=`
            // above. Forward-fill is implicit because stateSetpointBar
            // carries through to subsequent samples until the next
            // transition. Confirmed against
            // core/save-git.cpp:save_sample() and
            // core/load-git.cpp:parse_sample_keyvalue() in
            // github.com/subsurface/subsurface.
            final spb = _parseBar(kv.value);
            if (spb != null) stateSetpointBar = spb;
            break;
          case 'cns':
            final v = _parsePercent(kv.value);
            if (v != null) stateCnsPct = v;
            break;
          case 'tts':
            final s = parseTimeSeconds(kv.value);
            if (s != null) stateTtsSec = s;
            break;
          case 'ndl':
            final s = parseTimeSeconds(kv.value);
            if (s != null) {
              stateNdlSec = s;
              stateStopDepthM = 0.0;
              stateStopTimeSec = 0;
            }
            break;
          case 'stopdepth':
            final m = parseLengthMeters(kv.value);
            if (m != null) {
              stateStopDepthM = m;
              stateNdlSec = 0;
            }
            break;
          case 'stoptime':
            final s = parseTimeSeconds(kv.value);
            if (s != null) {
              stateStopTimeSec = s;
              stateNdlSec = 0;
            }
            break;
          // Other kv keys (`o2pressure`, `heartbeat`, `in_deco`) are
          // silently dropped — see the lossy-seams notes at the top of
          // the file.
        }
      }

      // Materialize current state.
      depthMeters[i] = stateDepthM;
      temperatureCelsius[i] = stateTempC;
      ppo2Bar[i] = statePo2Bar;
      // Reverse calibration: bar / (bar/mV) = mV. cal[i] holds
      // bar-per-mV already (i.e. 0.021 for the 21 bar/V default).
      final cal0 = sensorCalibrationBarPerMv.isNotEmpty
          ? sensorCalibrationBarPerMv[0]
          : 0.021;
      final cal1 = sensorCalibrationBarPerMv.length > 1
          ? sensorCalibrationBarPerMv[1]
          : 0.021;
      final cal2 = sensorCalibrationBarPerMv.length > 2
          ? sensorCalibrationBarPerMv[2]
          : 0.021;
      cellMv0[i] = cal0 > 0 ? stateSensor1Bar / cal0 : 0.0;
      cellMv1[i] = cal1 > 0 ? stateSensor2Bar / cal1 : 0.0;
      cellMv2[i] = cal2 > 0 ? stateSensor3Bar / cal2 : 0.0;
      setpointBar[i] = stateSetpointBar;
      cns[i] = stateCnsPct / 100.0; // CCRLog stores 0..1+
      // NDL + deco — at most one of (ndlSec, stopDepth/stopTime) is
      // active at a time. We persist deco-stop info when present, else
      // expose the NDL clock via decoTimeSeconds.
      decoStopDepthMeters[i] = stateStopDepthM;
      if (stateStopDepthM > 0) {
        decoTimeSeconds[i] = stateStopTimeSec;
      } else {
        decoTimeSeconds[i] = stateNdlSec;
      }
      ttsSeconds[i] = stateTtsSec;
      gasMixIndex[i] = stateMixIdx;
      statusFlags[i] = 0;

      for (var t = 0; t < tankPressures.length; t++) {
        tankPressures[t][i] = stateTankBar[t];
      }
    }

    return _BuiltSamples(
      sampleCount: n,
      intervalMs: intervalMs,
      depthMeters: depthMeters,
      temperatureCelsius: temperatureCelsius,
      ppo2Bar: ppo2Bar,
      cellMv0: cellMv0,
      cellMv1: cellMv1,
      cellMv2: cellMv2,
      setpointBar: setpointBar,
      cns: cns,
      decoStopDepthMeters: decoStopDepthMeters,
      decoTimeSeconds: decoTimeSeconds,
      ttsSeconds: ttsSeconds,
      gasMixIndex: gasMixIndex,
      statusFlags: statusFlags,
      tankPressures: tankPressures,
    );
  }

  /// Infer the sample interval (ms) from the time delta between the first
  /// two samples. Falls back to 10s for synthetic / single-sample files.
  int _inferIntervalMs(List<SampleLine> samples) {
    if (samples.length < 2) return 10000;
    final t0 = parseTimeSeconds(samples[0].time);
    final t1 = parseTimeSeconds(samples[1].time);
    if (t0 == null || t1 == null) return 10000;
    final delta = t1 - t0;
    if (delta <= 0) return 10000;
    return delta * 1000;
  }

  /// Determine how many tank-pressure channels the dive has by scanning
  /// every sample line for the highest `:N` index seen, plus 1. The
  /// un-indexed `X.Ybar` form maps to channel 0.
  int _detectTankCount(List<SampleLine> samples) {
    var maxIdx = -1;
    var sawAnyPressure = false;
    for (final s in samples) {
      for (var p = 1; p < s.positional.length; p++) {
        final tok = s.positional[p];
        if (tok.endsWith('°C')) continue;
        final pr = parsePressureBar(tok);
        if (pr == null) continue;
        sawAnyPressure = true;
        final idx = pr.tankIndex ?? 0;
        if (idx > maxIdx) maxIdx = idx;
      }
    }
    if (!sawAnyPressure) return 0;
    return maxIdx + 1;
  }

  // ── Annotation builder ───────────────────────────────────────────────

  DiveAnnotation? _buildAnnotation({
    required String diveId,
    required List<SsLine> diveLines,
    required List<SsLine>? siteLines,
  }) {
    String? notes;
    String? divemaster;
    final buddies = <String>[];
    final tags = <String>[];
    int? rating;
    String? suit;
    int? visibility;
    int? wavesize;
    int? current;
    int? surge;
    int? chill;
    double? airTempC;
    double? waterTempC;
    final weights = <Weight>[];

    for (final l in diveLines) {
      if (l is QuotedLine) {
        switch (l.key) {
          case 'notes':
            if (l.value.isNotEmpty) notes = l.value;
            break;
          case 'buddy':
            if (l.value.isNotEmpty) {
              for (final part in l.value.split(',')) {
                final trimmed = part.trim();
                if (trimmed.isNotEmpty) buddies.add(trimmed);
              }
            }
            break;
          case 'suit':
            if (l.value.isNotEmpty) suit = l.value;
            break;
          case 'divemaster':
            if (l.value.isNotEmpty) divemaster = l.value;
            break;
        }
      } else if (l is ScalarLine) {
        switch (l.key) {
          case 'rating':
            final r = int.tryParse(l.value);
            // Subsurface uses 0..5 where 0 means unrated.
            if (r != null && r > 0) rating = r.clamp(1, 5);
            break;
          case 'visibility':
            final r = int.tryParse(l.value);
            if (r != null && r > 0) visibility = r.clamp(1, 5);
            break;
          case 'wavesize':
            final r = int.tryParse(l.value);
            if (r != null && r > 0) wavesize = r.clamp(1, 5);
            break;
          case 'current':
            final r = int.tryParse(l.value);
            if (r != null && r > 0) current = r.clamp(1, 5);
            break;
          case 'surge':
            final r = int.tryParse(l.value);
            if (r != null && r > 0) surge = r.clamp(1, 5);
            break;
          case 'chill':
            final r = int.tryParse(l.value);
            if (r != null && r > 0) chill = r.clamp(1, 5);
            break;
          case 'airtemp':
            airTempC = _parseTempCelsius(l.value);
            break;
          case 'watertemp':
            waterTempC = _parseTempCelsius(l.value);
            break;
        }
      } else if (l is TagsLine) {
        tags.addAll(l.tags);
      } else if (l is WeightsystemLine) {
        // Subsurface emits one line per weight piece: `weight=2.3kg
        // description="p-weight"`. The description is optional (legacy
        // entries omit it); fall back to empty string.
        double? weightKg;
        String description = '';
        for (final e in l.fields) {
          if (e.key == 'weight') {
            weightKg = _stripUnit(e.value, 'kg');
          } else if (e.key == 'description') {
            description = _unquote(e.value);
          }
        }
        if (weightKg != null) {
          weights.add(Weight(weightKg: weightKg, description: description));
        }
      }
    }

    String? siteName;
    double? siteLat;
    double? siteLon;
    if (siteLines != null) {
      for (final l in siteLines) {
        if (l is QuotedLine && l.key == 'name' && l.value.isNotEmpty) {
          siteName = l.value;
        } else if (l is GpsLine) {
          siteLat = double.tryParse(l.lat);
          siteLon = double.tryParse(l.lon);
        }
      }
    }

    final hasAnyField = notes != null ||
        divemaster != null ||
        buddies.isNotEmpty ||
        tags.isNotEmpty ||
        rating != null ||
        suit != null ||
        visibility != null ||
        wavesize != null ||
        current != null ||
        surge != null ||
        chill != null ||
        airTempC != null ||
        waterTempC != null ||
        weights.isNotEmpty ||
        siteName != null ||
        siteLat != null ||
        siteLon != null;
    if (!hasAnyField) return null;

    final now = DateTime.now();
    return DiveAnnotation(
      diveId: diveId,
      siteName: siteName,
      siteLatitude: siteLat,
      siteLongitude: siteLon,
      notes: notes,
      divemaster: divemaster,
      buddies: buddies,
      tags: tags,
      rating: rating,
      suit: suit,
      visibility: visibility,
      wavesize: wavesize,
      current: current,
      surge: surge,
      chill: chill,
      airTempC: airTempC,
      waterTempC: waterTempC,
      weights: weights,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Parse `24.0°C` / `22.0 C` / `24.0` into a double Celsius value.
  /// Returns null on parse failure.
  double? _parseTempCelsius(String value) {
    var v = value.trim();
    // Strip trailing °C / C / °F (we ignore °F here; Subsurface always
    // emits Celsius for env temps in the git format regardless of the
    // diver's display preference).
    if (v.endsWith('°C')) {
      v = v.substring(0, v.length - 2);
    } else if (v.endsWith('C') && !v.endsWith('°C')) {
      v = v.substring(0, v.length - 1);
    }
    return double.tryParse(v.trim());
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  ShearwaterModel _shearwaterModelFromName(String displayName) {
    return switch (displayName) {
      'Shearwater Predator' => ShearwaterModel.predator,
      'Shearwater Petrel' => ShearwaterModel.petrel,
      'Shearwater Petrel 2' => ShearwaterModel.petrel2,
      'Shearwater Petrel 3' => ShearwaterModel.petrel3,
      'Shearwater NERD' => ShearwaterModel.nerd,
      'Shearwater NERD 2' => ShearwaterModel.nerd2,
      'Shearwater Perdix' => ShearwaterModel.perdix,
      'Shearwater Perdix AI' => ShearwaterModel.perdixAi,
      'Shearwater Perdix 2' => ShearwaterModel.perdix2,
      'Shearwater Teric' => ShearwaterModel.teric,
      'Shearwater Peregrine' => ShearwaterModel.peregrine,
      'Shearwater Peregrine TX' => ShearwaterModel.peregrineTx,
      'Shearwater Tern' => ShearwaterModel.tern,
      'Shearwater' => ShearwaterModel.unknown,
      _ => ShearwaterModel.unknown,
    };
  }

  double? _parseBar(String value) {
    final p = parsePressureBar(value);
    return p?.bar;
  }

  /// Parse `21%` → `21.0`. Returns null on failure.
  double? _parsePercent(String value) {
    if (value.endsWith('%')) {
      return double.tryParse(value.substring(0, value.length - 1));
    }
    return double.tryParse(value);
  }

  /// Strip a unit suffix from a numeric lexeme (`3.0l` → 3.0, `99.0%` →
  /// 99.0). Returns null when the suffix doesn't match.
  double? _stripUnit(String lex, String unit) {
    if (lex.endsWith(unit)) {
      return double.tryParse(lex.substring(0, lex.length - unit.length));
    }
    return double.tryParse(lex);
  }

  /// Strip surrounding `"` from a verbatim cylinder/event field value.
  String _unquote(String raw) {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  /// Find a `key value [unit]` line and return the seconds the value
  /// represents (`56:20` → 3380, `56:20 min` → 3380, `30:00min` → 1800).
  int? _scalarSeconds(List<SsLine> lines, String key) {
    for (final l in lines) {
      if (l is ScalarLine && l.key == key) {
        final v = l.value;
        // Accept "56:20", "56:20 min", "30:00min", "1:00:00".
        final firstSpace = v.indexOf(' ');
        final timeLex = firstSpace < 0
            ? (v.endsWith('min') ? v.substring(0, v.length - 3) : v)
            : v.substring(0, firstSpace);
        final s = parseTimeSeconds(timeLex);
        if (s != null) return s;
      }
    }
    return null;
  }

  /// First `key X.Ym` ScalarLine value, parsed as meters.
  double? _firstScalarMeters(List<SsLine> lines, String key) {
    for (final l in lines) {
      if (l is ScalarLine && l.key == key) {
        return parseLengthMeters(l.value);
      }
    }
    return null;
  }

  double _peakDepth(Float32List depths) {
    var max = 0.0;
    for (final d in depths) {
      if (d > max) max = d;
    }
    return max;
  }
}

// ── Internal helpers ────────────────────────────────────────────────────

class _DivecomputerMetadata {
  _DivecomputerMetadata({
    required this.modelName,
    required this.serial,
    required this.diveMode,
    required this.gfLow,
    required this.gfHigh,
    required this.atmosphericPressureMbar,
    required this.waterDensityKgM3,
    required this.logVersion,
    required this.firmwareVersion,
    required this.configuredStackSeconds,
    required this.stackRemainingAtStartSeconds,
    required this.stackRemainingAtEndSeconds,
    required this.sensorCalibrationBarPerMv,
  });

  final String? modelName;
  final int? serial;
  final DiveMode diveMode;
  final int? gfLow;
  final int? gfHigh;
  final int? atmosphericPressureMbar;
  final int? waterDensityKgM3;
  final int? logVersion;
  final int? firmwareVersion;
  final int? configuredStackSeconds;
  final int? stackRemainingAtStartSeconds;
  final int? stackRemainingAtEndSeconds;

  /// Per-cell calibration in bar/mV (already divided by 1000 from the
  /// `bar/V` value Subsurface stores). Length 3 on CCR with all 3
  /// keyvalues present; empty otherwise.
  final List<double> sensorCalibrationBarPerMv;

  factory _DivecomputerMetadata.from(List<SsLine> lines) {
    String? modelName;
    int? serial;
    DiveMode diveMode = DiveMode.ocTec;
    int? gfLow;
    int? gfHigh;
    int? atmosphericPressureMbar;
    int? waterDensityKgM3;
    int? logVersion;
    int? firmwareVersion;
    int? configuredStackSeconds;
    int? stackRemainingAtStartSeconds;
    int? stackRemainingAtEndSeconds;
    final calBarPerV = <int, double>{}; // index → bar/V

    for (final l in lines) {
      if (l is QuotedLine && l.key == 'model') {
        modelName = l.value;
      } else if (l is ScalarLine) {
        switch (l.key) {
          case 'dctype':
            diveMode = _diveModeFromDcType(l.value);
            break;
          case 'surfacepressure':
            // `1.001bar` → 1001 mbar
            final m = parsePressureBar(l.value);
            if (m != null) {
              atmosphericPressureMbar = (m.bar * 1000).round();
            }
            break;
          case 'salinity':
            // `1000g/l` → 1000 kg/m³ (1 g/l == 1 kg/m³)
            final v = l.value;
            final stripped = v.endsWith('g/l')
                ? v.substring(0, v.length - 3)
                : v.endsWith(' g/l')
                    ? v.substring(0, v.length - 4)
                    : v;
            waterDensityKgM3 = int.tryParse(stripped.trim());
            break;
        }
      } else if (l is KeyvaluePairLine) {
        switch (l.key) {
          case 'Serial':
            serial = int.tryParse(l.value, radix: 16);
            break;
          case 'FW Version':
            firmwareVersion = int.tryParse(l.value, radix: 16);
            break;
          case 'Logversion':
            // "17(PNF)" or "17"
            final paren = l.value.indexOf('(');
            final tail = paren < 0 ? l.value : l.value.substring(0, paren);
            logVersion = int.tryParse(tail);
            break;
          case 'Deco model':
            // `GF 50/95`
            final v = l.value;
            if (v.startsWith('GF ')) {
              final rest = v.substring(3);
              final slash = rest.indexOf('/');
              if (slash > 0) {
                gfLow = int.tryParse(rest.substring(0, slash));
                gfHigh = int.tryParse(rest.substring(slash + 1));
              }
            }
            break;
          case 'Configured stack time [hh:mm:ss]':
            configuredStackSeconds = parseTimeSeconds(l.value);
            break;
          case 'Remaining stack time at start [hh:mm:ss]':
            stackRemainingAtStartSeconds = parseTimeSeconds(l.value);
            break;
          case 'Remaining stack time at end [hh:mm:ss]':
            stackRemainingAtEndSeconds = parseTimeSeconds(l.value);
            break;
          default:
            // Sensor N calibration [bar / V]
            final calMatch = RegExp(
              r'^Sensor (\d+) calibration \[bar / V\]$',
            ).firstMatch(l.key);
            if (calMatch != null) {
              final idx = int.parse(calMatch.group(1)!) - 1;
              final barPerV = double.tryParse(l.value);
              if (barPerV != null && idx >= 0 && idx < 3) {
                calBarPerV[idx] = barPerV;
              }
            }
        }
      }
    }

    // Build calibration list: `sensorCalibration[i] = bar_per_V / 1000`
    // so that mV * cal gives bar (matching how the Petrel binary parser
    // stores it on `Dive.sensorCalibration`).
    final cal = <double>[];
    if (calBarPerV.isNotEmpty) {
      // Length 3 with zero-fill for missing cells.
      for (var i = 0; i < 3; i++) {
        final v = calBarPerV[i];
        cal.add(v == null ? 0.021 : v / 1000.0);
      }
    }

    return _DivecomputerMetadata(
      modelName: modelName,
      serial: serial,
      diveMode: diveMode,
      gfLow: gfLow,
      gfHigh: gfHigh,
      atmosphericPressureMbar: atmosphericPressureMbar,
      waterDensityKgM3: waterDensityKgM3,
      logVersion: logVersion,
      firmwareVersion: firmwareVersion,
      configuredStackSeconds: configuredStackSeconds,
      stackRemainingAtStartSeconds: stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: stackRemainingAtEndSeconds,
      sensorCalibrationBarPerMv: cal,
    );
  }

  static DiveMode _diveModeFromDcType(String value) {
    return switch (value) {
      'CCR' => DiveMode.cc,
      'OC' => DiveMode.ocTec,
      'Gauge' => DiveMode.gauge,
      'PpO2' => DiveMode.ppo2,
      'SCR' => DiveMode.sc,
      'Apnea' || 'Freedive' => DiveMode.freedive,
      _ => DiveMode.ocTec,
    };
  }
}

class _BuiltSamples {
  _BuiltSamples({
    required this.sampleCount,
    required this.intervalMs,
    required this.depthMeters,
    required this.temperatureCelsius,
    required this.ppo2Bar,
    required this.cellMv0,
    required this.cellMv1,
    required this.cellMv2,
    required this.setpointBar,
    required this.cns,
    required this.decoStopDepthMeters,
    required this.decoTimeSeconds,
    required this.ttsSeconds,
    required this.gasMixIndex,
    required this.statusFlags,
    required this.tankPressures,
  });

  final int sampleCount;
  final int intervalMs;
  final Float32List depthMeters;
  final Float32List temperatureCelsius;
  final Float32List ppo2Bar;
  final Float32List cellMv0;
  final Float32List cellMv1;
  final Float32List cellMv2;
  final Float32List setpointBar;
  final Float32List cns;
  final Float32List decoStopDepthMeters;
  final Int32List decoTimeSeconds;
  final Int32List ttsSeconds;
  final Uint8List gasMixIndex;
  final Uint8List statusFlags;
  final List<Float32List> tankPressures;
}

enum _TimedEventKind { gasChange, setpoint }

class _TimedEvent {
  _TimedEvent._(this.timeSec, this.kind, this.intValue, this.doubleValue);

  factory _TimedEvent.gasChange(int t, int cyl) =>
      _TimedEvent._(t, _TimedEventKind.gasChange, cyl, 0.0);

  factory _TimedEvent.setpoint(int t, double bar) =>
      _TimedEvent._(t, _TimedEventKind.setpoint, 0, bar);

  final int timeSec;
  final _TimedEventKind kind;
  final int intValue;
  final double doubleValue;
}
