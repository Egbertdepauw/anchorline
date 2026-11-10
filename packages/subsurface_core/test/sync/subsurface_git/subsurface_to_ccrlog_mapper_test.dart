// Unit tests for the Subsurface → CCRLog mapper.
//
// We exercise the read-direction mapper against the real fixtures at
// `test/fixtures/subsurface/`. Each fixture covers a different shape:
//   - 2026/04/04: modern Petrel CCR with calibration keyvalues, multiple
//     cylinders, indexed tank pressures.
//   - 2025/05/04: Petrel CCR with un-indexed `bar` form for tank pressure
//     and `o2pressure=` kv tokens we drop on the floor.
//   - 2026/04/27: multi-line notes + multi-name buddy + suit.
//   - 2004/06/19: ancient manual-only dive (no model, no DC) — must
//     return null gracefully.
//   - Round-trip stability: domain Dive → write mapper → read mapper →
//     compare. Cell mV degrades (3-decimal bar lexeme), depth/temp/po2
//     are exact.

import 'dart:io';
import 'dart:typed_data';

import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/dive.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_format.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:subsurface_core/sync/subsurface_git/mapper.dart' as write_mapper;
import 'package:subsurface_core/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_inputs.dart';
import 'package:test/test.dart';

const _fixturesRoot = 'test/fixtures/subsurface';

void main() {
  group('SubsurfaceToCcrlogMapper.mapDive', () {
    test('modern Petrel 3 CCR dive (2026/04/04) maps fully', () {
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2026/04/04-Sat-13=30=15');

      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2026, 4, 4, 13, 30, 15),
        subsurfaceDiveNumber: 705,
      );

      expect(result, isNotNull, reason: 'modern Petrel CCR fixture maps');
      final r = result!;
      final dive = r.converted.dive;
      final samples = r.converted.samples;

      // ── Dive metadata ─────────────────────────────────────────────
      expect(dive.dcSerial, 0xb89641e4);
      expect(dive.dcModel, ShearwaterModel.petrel3);
      expect(dive.diveMode, DiveMode.cc);
      expect(dive.gfLow, 50);
      expect(dive.gfHigh, 95);
      expect(dive.atmosphericPressureMbar, 1001);
      expect(dive.waterDensityKgM3, 1000);
      expect(dive.logVersion, 17);
      expect(dive.configuredStackSeconds, 7 * 3600);
      expect(dive.stackRemainingAtStartSeconds, 3 * 3600 + 47);
      expect(dive.stackRemainingAtEndSeconds, 2 * 3600 + 2 * 60 + 27);
      expect(dive.maxDepthMeters, closeTo(18.0, 0.01));
      expect(dive.dcDiveNumber, 705);

      // Sensor calibration: each entry stored as bar-per-mV (i.e.
      // 21.00 bar/V / 1000 = 0.021 bar/mV). All three cells calibrated.
      expect(dive.sensorCalibration.length, 3);
      for (final c in dive.sensorCalibration) {
        expect(c, closeTo(0.021, 1e-6));
      }

      // ── Gas mixes / cylinders ─────────────────────────────────────
      // Six cylinders in Dive-705 → six gas mixes. Index 0 is the
      // bailout O2 (99%) per the cylinder ordering.
      expect(dive.gasMixes.length, 6);
      expect(dive.gasMixes[0].oxygenPercent, 99);
      expect(dive.gasMixes[0].heliumPercent, 0);
      expect(dive.gasMixes[0].isDiluent, isFalse);
      // Index 2 is trimix 20/48
      expect(dive.gasMixes[2].oxygenPercent, 20);
      expect(dive.gasMixes[2].heliumPercent, 48);
      // Index 3 is the diluent 50/0 (tagged use="diluent").
      expect(dive.gasMixes[3].isDiluent, isTrue);

      expect(r.cylindersByMixIndex.length, 6);
      final cyl0 = r.cylindersByMixIndex[0]!;
      expect(cyl0.volumeLiters, closeTo(3.0, 0.001));
      expect(cyl0.workingPressureBar, 232);
      expect(cyl0.o2Percent, 99);
      expect(cyl0.hePercent, 0);
      expect(cyl0.description, '3ℓ 232 bar');

      final cyl3 = r.cylindersByMixIndex[3]!;
      expect(cyl3.use, 'diluent');

      // ── Samples ────────────────────────────────────────────────────
      // Petrels emit a sample every 5 seconds.
      expect(samples.sampleIntervalMs, 5000);
      // Sample times in fixture run 0:05 → 58:30 inclusive at 5s
      // interval ⇒ 702 sample lines.
      expect(samples.sampleCount, 702);

      // First 5 sample depths come from the fixture verbatim:
      //  0:05 1.6m, 0:10 1.7m, 0:15 1.7m, 0:20 0.0m, 0:25 0.0m.
      expect(samples.depthMeters[0], closeTo(1.6, 0.01));
      expect(samples.depthMeters[1], closeTo(1.7, 0.01));
      expect(samples.depthMeters[2], closeTo(1.7, 0.01));
      expect(samples.depthMeters[3], closeTo(0.0, 0.01));
      expect(samples.depthMeters[4], closeTo(0.0, 0.01));

      // Temperature on sample 0 = 11.0°C.
      expect(samples.temperatureCelsius[0], closeTo(11.0, 0.01));

      // Cell mV reconstruction. Sample 0 has sensor1=0.714bar with
      // calibration 21.00 bar/V (0.021 bar/mV) → 0.714 / 0.021 = 34.0
      // mV. Allow 0.5 mV slack to absorb the float→bar→string→mV chain.
      expect(samples.cellMv0[0], closeTo(34.0, 0.5));
      // sensor2/sensor3 = 0.798bar → 0.798/0.021 = 38.0 mV.
      expect(samples.cellMv1[0], closeTo(38.0, 0.5));
      expect(samples.cellMv2[0], closeTo(38.0, 0.5));

      // PPO2: dc_supplied_ppo2=0.76bar on sample 0 — preferred over
      // the rounded `po2=0.7bar` because dc_supplied_ppo2 emits per
      // sample and gives the dynamic trace the user expects.
      expect(samples.ppo2Bar[0], closeTo(0.76, 0.001));

      // Sample 1's dc_supplied_ppo2=0.79 → updates state.
      expect(samples.ppo2Bar[1], closeTo(0.79, 0.001));

      // Tank pressures: the fixture starts with `207.946bar:0
      // 139.964bar:1`. We allocate 2 channels (max index 1 + 1).
      expect(samples.tankPressuresBar.length, 2);
      expect(samples.tankPressuresBar[0][0], closeTo(207.946, 0.01));
      expect(samples.tankPressuresBar[1][0], closeTo(139.964, 0.01));

      // Gas-mix index: the only gaschange event is at 0:05 → cylinder 5
      // (the trimix 18/23 diluent). All samples should have gasMixIndex
      // == 5 from the get-go.
      expect(samples.gasMixIndex[0], 5);
      expect(samples.gasMixIndex[100], 5);

      // ── Annotation ─────────────────────────────────────────────────
      expect(r.annotation, isNotNull);
      final ann = r.annotation!;
      expect(ann.diveId, dive.id);
      expect(ann.notes,
          'Nou rondje gedaan, niets gezien, Alex na een paar minuten kwijt....');
      expect(ann.buddies, ['Alex Marlin']);
      expect(ann.tags, ['CCR', 'X-CCR']);
      expect(ann.rating, 2);
      expect(ann.suit, isNull); // suit "" → empty → not stored
    });

    test('Petrel CCR with un-indexed bar form (2025/05/04) maps', () {
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2025/05/04-Sun-09=48=36');

      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2025, 5, 4, 9, 48, 36),
        subsurfaceDiveNumber: 656,
      );

      expect(result, isNotNull);
      final r = result!;
      final samples = r.converted.samples;
      // Un-indexed `187.951bar` → tank index 0 → single channel.
      expect(samples.tankPressuresBar.length, 1);
      expect(samples.tankPressuresBar[0][0], closeTo(187.951, 0.01));

      // 3 cylinders → 3 gas mixes. The first cylinder has no `o2=`
      // key in the fixture, so it should fall back to air defaults.
      expect(r.converted.dive.gasMixes.length, 3);
      // Cylinder index 1 is the O2 bottle (100%).
      expect(r.converted.dive.gasMixes[1].oxygenPercent, 100);
    });

    test('Information-tab fields (2025/05/04 Dive-656) — env ratings, '
        'air temp, and weightsystem round-trip into the annotation', () {
      // Dive-656's verbatim header (excerpt):
      //   rating 3 / visibility 3 / wavesize 3 / current 5 / surge 4 /
      //   chill 5 / weightsystem weight=2.3kg description="p-weight" /
      //   airtemp 22.0°C  (no watertemp line — common for shore dives)
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2025/05/04-Sun-09=48=36');

      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2025, 5, 4, 9, 48, 36),
        subsurfaceDiveNumber: 656,
      );

      expect(result, isNotNull);
      final ann = result!.annotation;
      expect(ann, isNotNull, reason: 'fixture has rating + many env fields');
      final a = ann!;

      // Five star ratings → 1..5, intact.
      expect(a.rating, 3);
      expect(a.visibility, 3);
      expect(a.wavesize, 3);
      expect(a.current, 5);
      expect(a.surge, 4);
      expect(a.chill, 5);

      // Air temp parsed (strip the °C unit). Water temp absent → null.
      expect(a.airTempC, closeTo(22.0, 1e-6));
      expect(a.waterTempC, isNull);

      // Single weightsystem line → one Weight entry.
      expect(a.weights, hasLength(1));
      expect(a.weights[0].weightKg, closeTo(2.3, 1e-6));
      expect(a.weights[0].description, 'p-weight');
    });

    test('manually-added dive (2020/08/18 Dive-365) carries full env + '
        'water temp + weightsystem into the annotation', () {
      // Dive-365 has the richest Information-tab fixture available:
      //   rating 1 / visibility 2 / wavesize 5 / current 5 / surge 5 /
      //   chill 5 / airtemp 25.0°C / watertemp 21.0°C /
      //   weightsystem weight=2.0kg description="backplate"
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2020/08/18-Tue-16=00=27');

      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2020, 8, 18, 16, 0, 27),
        subsurfaceDiveNumber: 365,
      );

      expect(result, isNotNull);
      final a = result!.annotation!;
      expect(a.visibility, 2);
      expect(a.wavesize, 5);
      expect(a.current, 5);
      expect(a.surge, 5);
      expect(a.chill, 5);
      expect(a.airTempC, closeTo(25.0, 1e-6));
      expect(a.waterTempC, closeTo(21.0, 1e-6));
      expect(a.weights, hasLength(1));
      expect(a.weights[0].weightKg, closeTo(2.0, 1e-6));
      expect(a.weights[0].description, 'backplate');
    });

    test('multi-line notes + multi-name buddy (2026/04/27)', () {
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2026/04/27-Mon-11=33=43');

      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2026, 4, 27, 11, 33, 43),
        subsurfaceDiveNumber: 710,
      );

      expect(result, isNotNull);
      final ann = result!.annotation!;
      // Multi-name buddy splits on `,` and trims.
      expect(ann.buddies, ['Alex Marlin', 'Robin Kelp']);
      // Notes preserve the raw embedded newline.
      expect(ann.notes, isNotNull);
      expect(ann.notes!.contains('\n'), isTrue);
      expect(ann.tags, ['X-CCR', 'CCR']);
      expect(ann.suit, 'ScubaForce Xpedition SE Droogpak - X-Nine onderpak');
      expect(ann.rating, 4);
    });

    test('Site lines populate site fields when supplied', () {
      // The 2026/04/27 fixture's `divesiteid a2315b95` doesn't match a
      // bundled Site file, so we synthesise a site lookup using the
      // 2025/05/04 fixture and the bundled Site-0a9f7232 (Om Sid - Dahab).
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2025/05/04-Sun-09=48=36');
      final siteRaw = File('$_fixturesRoot/sites/Site-0a9f7232')
          .readAsStringSync();
      final siteFile = parseSubsurfaceFile(
        siteRaw,
        kind: SubsurfaceFileKind.site,
      );

      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: siteFile.lines,
        startTime: DateTime.utc(2025, 5, 4, 9, 48, 36),
        subsurfaceDiveNumber: 656,
      );

      expect(result, isNotNull);
      final ann = result!.annotation!;
      expect(ann.siteName, 'Om Sid - Dahab');
      expect(ann.siteLatitude, closeTo(28.420550, 1e-6));
      expect(ann.siteLongitude, closeTo(34.457473, 1e-6));
    });

    test('manual-only dive without model imports with synthesised DC '
        '(2004/06/19)', () {
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2004/06/19-Sat-09=00=00');
      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2004, 6, 19, 9, 0, 0),
        subsurfaceDiveNumber: 13,
      );
      // No `model` line → synthesised: dcSerial=0, dcModel=unknown.
      // Annotation + cylinders still come through.
      expect(result, isNotNull);
      expect(result!.converted.dive.dcSerial, 0);
      expect(result.converted.dive.dcModel, ShearwaterModel.unknown);
      expect(result.converted.dive.dcDiveNumber, 13);
    });

    test('manually-added dive (model "manually added dive") imports '
        'with synthesised DC', () {
      final mapper = SubsurfaceToCcrlogMapper();
      final fx = _loadDive('2020/08/18-Tue-16=00=27');
      final result = mapper.mapDive(
        diveLines: fx.diveLines,
        divecomputerLines: fx.divecomputerLines,
        siteLines: null,
        startTime: DateTime.utc(2020, 8, 18, 16, 0, 27),
        subsurfaceDiveNumber: 365,
      );
      // model name "manually added dive" → unrecognised, but we no
      // longer reject. dcSerial=0 (no Serial keyvalue).
      expect(result, isNotNull);
      expect(result!.converted.dive.dcSerial, 0);
      expect(result.converted.dive.dcModel, ShearwaterModel.unknown);
      expect(result.converted.dive.dcDiveNumber, 365);
    });
  });

  group('Round-trip stability', () {
    test('write → read produces equivalent depth/temp/po2 channels', () {
      // Build a synthetic CCRLog dive, push it through the WRITE mapper,
      // then run the READ mapper on the resulting SsLines, and compare.
      // Channels with formatting precision-loss (cell mV) get a tolerance;
      // channels that round-trip exactly (depth at 0.1m, temperature at
      // 0.1°C, po2 at 0.1 bar) are checked exactly.
      final domainDive = _syntheticDive();
      final domainSamples = _syntheticSamples(domainDive.id);
      final annotation = DiveAnnotation(
        diveId: domainDive.id,
        notes: 'Round-trip test',
        buddies: const ['Alice', 'Bob'],
        tags: const ['CCR', 'Test'],
        rating: 4,
        siteName: 'Test Site',
        siteLatitude: 51.0,
        siteLongitude: 4.0,
        suit: 'Drysuit',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

      final writeMapper = write_mapper.CcrlogToSubsurfaceMapper();
      final dbDive = _domainDiveToInput(domainDive);
      final mapped = writeMapper.mapDive(
        dive: dbDive,
        samples: domainSamples,
        annotation: annotation,
        gasMixes: domainDive.gasMixes,
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: domainDive.dcDiveNumber,
      );
      final mappedSite = writeMapper.mapSite(annotation)!;

      final readMapper = SubsurfaceToCcrlogMapper();
      final round = readMapper.mapDive(
        diveLines: mapped.diveLines,
        divecomputerLines: mapped.divecomputerLines,
        siteLines: mappedSite.lines,
        startTime: domainDive.startTime,
        subsurfaceDiveNumber: domainDive.dcDiveNumber,
      );

      expect(round, isNotNull, reason: 'write→read should produce a dive');
      final r = round!;

      // Dive metadata round-trips.
      expect(r.converted.dive.dcSerial, domainDive.dcSerial);
      expect(r.converted.dive.dcModel, domainDive.dcModel);
      expect(r.converted.dive.diveMode, domainDive.diveMode);
      expect(r.converted.dive.gfLow, domainDive.gfLow);
      expect(r.converted.dive.gfHigh, domainDive.gfHigh);
      expect(r.converted.dive.logVersion, domainDive.logVersion);
      expect(r.converted.dive.gasMixes.length, domainDive.gasMixes.length);

      // Sample channels: depth at 0.1m precision, temp at 0.1°C, po2 at
      // 0.1bar — the lexeme precisions used by the write mapper.
      final n = domainSamples.sampleCount;
      expect(r.converted.samples.sampleCount, n);
      for (var i = 0; i < n; i++) {
        expect(r.converted.samples.depthMeters[i],
            closeTo(domainSamples.depthMeters[i], 0.05),
            reason: 'depth sample $i mismatch');
        expect(r.converted.samples.temperatureCelsius[i],
            closeTo(domainSamples.temperatureCelsius[i], 0.1),
            reason: 'temp sample $i mismatch');
        // po2 is rounded to 0.1bar by the write mapper, so allow that.
        expect(r.converted.samples.ppo2Bar[i],
            closeTo(domainSamples.ppo2Bar[i], 0.1),
            reason: 'ppo2 sample $i mismatch');
      }

      // Cell mV round-trips with up to ~0.5 mV loss because the bar
      // lexeme has 3 decimal places (~0.001 bar / 0.021 bar/mV ≈ 0.05
      // mV per ULP, but accumulated over the formatting chain up to
      // 0.5mV).
      for (var i = 0; i < n; i++) {
        expect(r.converted.samples.cellMv0[i],
            closeTo(domainSamples.cellMv0[i], 0.5),
            reason: 'cell mV0 sample $i mismatch');
      }

      // Annotation round-trips.
      final ann = r.annotation!;
      expect(ann.notes, annotation.notes);
      expect(ann.buddies, annotation.buddies);
      expect(ann.tags, annotation.tags);
      expect(ann.rating, annotation.rating);
      expect(ann.suit, annotation.suit);
      expect(ann.siteName, annotation.siteName);
      expect(ann.siteLatitude, closeTo(annotation.siteLatitude!, 1e-6));
      expect(ann.siteLongitude, closeTo(annotation.siteLongitude!, 1e-6));
    });
  });
}

// ── Fixture loading ────────────────────────────────────────────────────

class _LoadedDive {
  _LoadedDive({required this.diveLines, required this.divecomputerLines});

  final List<SsLine> diveLines;
  final List<SsLine> divecomputerLines;
}

_LoadedDive _loadDive(String relPath) {
  final dir = Directory('$_fixturesRoot/dives/$relPath');
  final diveFile = dir.listSync().firstWhere(
        (e) => e.path.split(Platform.pathSeparator).last.startsWith('Dive-'),
      );
  final dcFile = dir.listSync().firstWhere(
        (e) => e.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('Divecomputer'),
      );
  final dive = parseSubsurfaceFile(
    File(diveFile.path).readAsStringSync(),
    kind: SubsurfaceFileKind.dive,
  );
  final dc = parseSubsurfaceFile(
    File(dcFile.path).readAsStringSync(),
    kind: SubsurfaceFileKind.divecomputer,
  );
  return _LoadedDive(diveLines: dive.lines, divecomputerLines: dc.lines);
}

// ── Synthetic data for round-trip ─────────────────────────────────────

Dive _syntheticDive() {
  return Dive(
    id: 'test-dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    dcSerial: 0xb89641e4,
    dcDiveNumber: 1234,
    startTime: DateTime.utc(2026, 1, 15, 10, 30, 0),
    endTime: DateTime.utc(2026, 1, 15, 11, 5, 0),
    duration: const Duration(minutes: 35),
    maxDepthMeters: 30.0,
    diveMode: DiveMode.cc,
    decoModel: DecoModel.gf,
    gfLow: 50,
    gfHigh: 95,
    atmosphericPressureMbar: 1013,
    waterDensityKgM3: 1000,
    logVersion: 17,
    dcModel: ShearwaterModel.petrel3,
    gasMixes: [
      DiveGasMix(oxygenPercent: 18, heliumPercent: 23, isDiluent: true),
      DiveGasMix(oxygenPercent: 100, heliumPercent: 0, isDiluent: false),
    ],
    sampleIntervalMs: 10000,
    sensorCalibration: const [0.021, 0.021, 0.021],
    configuredStackSeconds: 7 * 3600,
    stackRemainingAtStartSeconds: 6 * 3600,
    stackRemainingAtEndSeconds: 5 * 3600,
  );
}

SampleSet _syntheticSamples(String diveId) {
  const n = 12;
  // Depths step from 0 → 30 → 0 in increments that round to one decimal.
  final depths = Float32List.fromList(
    [0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 25.0, 20.0, 15.0, 10.0, 0.0],
  );
  final temps = Float32List.fromList(
    [12.0, 12.0, 11.0, 11.0, 10.0, 10.0, 9.0, 9.0, 10.0, 10.0, 11.0, 12.0],
  );
  final ppo2 = Float32List.fromList(List.filled(n, 0.7));
  // Cell mV around 35 mV (which round-trips to 0.735bar with 0.021 cal).
  final mv = Float32List.fromList(List.filled(n, 35.0));
  final setpoint = Float32List.fromList(List.filled(n, 0.7));
  return SampleSet(
    diveId: diveId,
    sampleCount: n,
    sampleIntervalMs: 10000,
    depthMeters: depths,
    temperatureCelsius: temps,
    ppo2Bar: ppo2,
    cellMv0: mv,
    cellMv1: mv,
    cellMv2: mv,
    setpointBar: setpoint,
    cns: Float32List(n),
    decoStopDepthMeters: Float32List(n),
    decoTimeSeconds: Int32List(n),
    ttsSeconds: Int32List(n)..fillRange(0, n, -1),
    gasMixIndex: Uint8List(n),
    statusFlags: Uint8List(n),
  );
}

/// Build a `SubsurfaceDiveInput` (the type the write mapper expects) from a
/// domain `Dive`. The write mapper reads a fixed subset of fields; we
/// hand-fill them.
SubsurfaceDiveInput _domainDiveToInput(Dive d) {
  return SubsurfaceDiveInput(
    id: d.id,
    dcSerial: d.dcSerial,
    dcDiveNumber: d.dcDiveNumber,
    startTime: d.startTime.millisecondsSinceEpoch ~/ 1000,
    durationSeconds: d.duration.inSeconds,
    maxDepthMm: (d.maxDepthMeters * 1000).round(),
    diveMode: d.diveMode.value,
    gfLow: d.gfLow,
    gfHigh: d.gfHigh,
    atmosphericPressureMbar: d.atmosphericPressureMbar,
    waterDensity: d.waterDensityKgM3,
    logVersion: d.logVersion,
    dcModel: d.dcModel.index,
    configuredStackSeconds: d.configuredStackSeconds,
    stackRemainingAtStartSeconds: d.stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: d.stackRemainingAtEndSeconds,
  );
}
