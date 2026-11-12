// Unit tests for the CCRLog → Subsurface mapper.
//
// We exercise the mapper at the domain-model level: synthesise a `Dive` +
// `SampleSet` + `DiveAnnotation` + cylinders in code, run the mapper, and
// assert on (a) the resulting `SsLine` structure and (b) the text produced
// when the lines are fed through the Phase-A serializer. Fixture files are
// not loaded — those exist for the format-layer round-trip tests; the
// mapper builds output from CCRLog state, not from any reference text.
//
// Coverage targets the contract laid out in the Phase-B brief:
//   1. CCR Petrel dive with three sensors, multiple gas mixes, samples →
//      well-formed Dive + Divecomputer + Site `SsLine` lists.
//   2. Sparse sample emission (only-changed tokens).
//   3. Site dedup (same lat/lon → same hex id).
//   4. Bare dive (no annotation) → empty buddy/notes/etc.
//   5. Stack-time keyvalue formatting.

import 'dart:typed_data';

import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix, DiveTank;
import 'package:subsurface_core/data/models/sample_set.dart';
import 'package:subsurface_core/shearwater/parser/parsed_dive.dart' show TankUsage;
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_format.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_serializer.dart';
import 'package:subsurface_core/sync/subsurface_git/mapper.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_inputs.dart';
import 'package:test/test.dart';

void main() {
  group('CcrlogToSubsurfaceMapper.mapDive', () {
    test('CCR Petrel dive emits well-formed Dive + Divecomputer lines', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final dive = _ccrPetrelDive();
      final samples = _threeMinSampleSet(diveId: dive.id);
      final annotation = _annotation(
        diveId: dive.id,
        rating: 4,
        buddies: ['Alex Marlin'],
        tags: ['CCR', 'X-CCR'],
        notes: 'Trim test, all cells happy.',
        suit: 'ScubaForce Xpedition SE',
        siteName: 'Om Sid - Dahab',
        siteLatitude: 28.420550,
        siteLongitude: 34.457473,
      );

      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: annotation,
        gasMixes: _threeGasMixes(),
        tanks: _threeTanks(),
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 705,
      );

      expect(result.subsurfaceDiveNumber, 705);
      // 1776591525 = 2026-04-19T09:38:45Z. Folder uses UTC components.
      expect(
        result.folderSegments,
        ['2026', '04', '19-Sun-09=38=45'],
      );
      expect(result.siteHexId, isNotNull);
      expect(result.siteHexId!.length, 8);

      // ── Dive-NNN file shape ────────────────────────────────────────
      final dive_ = result.diveLines;
      // Order is load-bearing; verify the prefix exactly.
      expect(_keyOf(dive_[0]), 'duration');
      expect(_keyOf(dive_[1]), 'rating');
      expect(dive_[2], isA<TagsLine>());
      expect(_keyOf(dive_[3]), 'divesiteid');
      expect(_keyOf(dive_[4]), 'divemaster');
      expect(_keyOf(dive_[5]), 'buddy');
      expect(_keyOf(dive_[6]), 'suit');
      expect(_keyOf(dive_[7]), 'notes');

      final duration =
          dive_.whereType<ScalarLine>().firstWhere((l) => l.key == 'duration');
      expect(duration.value, '57:30 min');

      final tagsLine = dive_.whereType<TagsLine>().single;
      expect(tagsLine.tags, ['CCR', 'X-CCR']);

      final buddy =
          dive_.whereType<QuotedLine>().firstWhere((l) => l.key == 'buddy');
      expect(buddy.value, 'Alex Marlin');

      final suit =
          dive_.whereType<QuotedLine>().firstWhere((l) => l.key == 'suit');
      expect(suit.value, 'ScubaForce Xpedition SE');

      // 3 cylinders for 3 gas mixes.
      final cyls = dive_.whereType<CylinderLine>().toList();
      expect(cyls.length, 3);
      // First cylinder has o2 + he (trimix), use="diluent".
      final cy0 = Map.fromEntries(cyls[0].fields);
      expect(cy0['o2'], '18.0%');
      expect(cy0['he'], '23.0%');
      expect(cy0['use'], '"diluent"');

      // ── Divecomputer file shape ────────────────────────────────────
      final dc = result.divecomputerLines;
      final dcQuoted = dc.whereType<QuotedLine>().toList();
      final dcScalars = dc.whereType<ScalarLine>().toList();
      final dcKeyvalues = dc.whereType<KeyvaluePairLine>().toList();

      expect(dcQuoted.first.key, 'model');
      expect(dcQuoted.first.value, 'Shearwater Petrel 3');
      expect(_scalar(dcScalars, 'dctype'), 'CCR');
      expect(_scalar(dcScalars, 'numberofoxygensensors'), '3');
      expect(_scalar(dcScalars, 'maxdepth'), endsWith('m'));
      expect(_scalar(dcScalars, 'salinity'), '1025g/l');
      expect(_scalar(dcScalars, 'surfacepressure'), '1.013bar');

      // Stack-time keyvalues are present and formatted as H:MM:SS.
      final stackConfigured =
          dcKeyvalues.firstWhere((l) => l.key.startsWith('Configured stack'));
      expect(stackConfigured.value, '7:00:00');
      final stackStart = dcKeyvalues
          .firstWhere((l) => l.key.startsWith('Remaining stack time at start'));
      expect(stackStart.value, '3:00:47');
      final stackEnd = dcKeyvalues
          .firstWhere((l) => l.key.startsWith('Remaining stack time at end'));
      expect(stackEnd.value, '2:02:27');

      // Logversion + Serial round-trip the right shape.
      expect(
        dcKeyvalues.firstWhere((l) => l.key == 'Logversion').value,
        '17(PNF)',
      );
      expect(
        dcKeyvalues.firstWhere((l) => l.key == 'Serial').value.length,
        8,
      );

      // First event is gas-change for mix 0 at time 0:00.
      final events = dc.whereType<EventLine>().toList();
      expect(events, isNotEmpty);
      final firstEvent = Map.fromEntries(events.first.fields);
      expect(firstEvent['type'], '25');
      expect(firstEvent['flags'], '6');
      expect(firstEvent['name'], '"gaschange"');
      expect(firstEvent['cylinder'], '0');
      expect(firstEvent['o2'], '18.0%');
      expect(firstEvent['he'], '23.0%');

      // Sample lines: count matches sampleCount.
      final samplesLines = dc.whereType<SampleLine>().toList();
      expect(samplesLines.length, samples.sampleCount);
      // First sample: time `0:00`, depth always emitted, and we expect
      // sensor1/sensor2/sensor3 + po2 because it's the first row.
      final first = samplesLines.first;
      expect(first.time, '0:00');
      expect(first.positional.first, '0.0m');
      final firstKv = Map.fromEntries(first.kv);
      expect(firstKv.containsKey('sensor1'), isTrue);
      expect(firstKv.containsKey('sensor2'), isTrue);
      expect(firstKv.containsKey('sensor3'), isTrue);
      expect(firstKv.containsKey('po2'), isTrue);

      // Both files serialize to non-empty text without throwing.
      final diveText =
          serializeSubsurfaceFile(SubsurfaceFile(lines: result.diveLines));
      final dcText = serializeSubsurfaceFile(
        SubsurfaceFile(lines: result.divecomputerLines),
      );
      expect(diveText, contains('duration 57:30 min\n'));
      expect(diveText, contains('rating 4\n'));
      expect(diveText, contains('cylinder vol='));
      expect(dcText, startsWith('model "Shearwater Petrel 3"\n'));
      expect(dcText, contains('dctype CCR\n'));
      expect(dcText, contains('event 0:00 type=25 flags=6 '
          'name="gaschange" cylinder=0 o2=18.0% he=23.0%\n'));
      // Sample-line padding (width 6 right-aligned) is enforced by the
      // serializer when source is null. `0:00` has 4 chars → 2 leading
      // spaces; the line begins with " 0:00 0.0m" preceded by a newline.
      expect(dcText, contains('\n  0:00 0.0m'));
    });

    test('sparse sample emission: tokens appear only when changed', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final dive = _ccrPetrelDive();
      // 6 samples. Depth oscillates every other sample. Temperature changes
      // every 5 samples. Constant cells.
      final n = 6;
      final depthM = Float32List(n);
      final tempC = Float32List(n);
      for (var i = 0; i < n; i++) {
        depthM[i] = (i % 2 == 0) ? 5.0 : 5.5;
        tempC[i] = (i < 5) ? 11.0 : 8.0;
      }
      final samples = SampleSet(
        diveId: dive.id,
        sampleCount: n,
        sampleIntervalMs: 10000,
        depthMeters: depthM,
        temperatureCelsius: tempC,
        ppo2Bar: Float32List(n),
        cellMv0: Float32List(n),
        cellMv1: Float32List(n),
        cellMv2: Float32List(n),
        setpointBar: Float32List(n),
        cns: Float32List(n),
        decoStopDepthMeters: Float32List(n),
        decoTimeSeconds: Int32List(n),
        ttsSeconds: Int32List(n)..fillRange(0, n, -1),
        gasMixIndex: Uint8List(n),
        statusFlags: Uint8List(n),
      );

      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );

      final lines =
          result.divecomputerLines.whereType<SampleLine>().toList();
      expect(lines.length, n);

      // Depth: positional always emitted (we always include depth on every
      // sample to match Subsurface's habit) — verify *value* alternates.
      expect(lines[0].positional.first, '5.0m');
      expect(lines[1].positional.first, '5.5m');
      expect(lines[2].positional.first, '5.0m');

      // Temperature: only the first sample and the change at index 5 should
      // emit a temperature positional.
      bool hasTempLexeme(SampleLine l) =>
          l.positional.any((p) => p.endsWith('°C'));
      expect(hasTempLexeme(lines[0]), isTrue);
      for (var i = 1; i < 5; i++) {
        expect(hasTempLexeme(lines[i]), isFalse,
            reason: 'sample $i should not re-emit unchanged temperature');
      }
      expect(hasTempLexeme(lines[5]), isTrue);
    });

    test('site dedup: identical lat/lon produce the same hex id', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final a = _annotation(
        diveId: 'dive-a',
        siteLatitude: 28.420550,
        siteLongitude: 34.457473,
        siteName: 'Om Sid - Dahab',
      );
      final b = _annotation(
        diveId: 'dive-b',
        siteLatitude: 28.420550,
        siteLongitude: 34.457473,
        siteName: 'Om Sid - Dahab',
      );
      final c = _annotation(
        diveId: 'dive-c',
        siteLatitude: 28.42060, // 5e-5 deg ≈ 5m, distinct after lat_e5
        siteLongitude: 34.457473,
        siteName: 'Om Sid - Dahab',
      );
      final mappedA = mapper.mapSite(a)!;
      final mappedB = mapper.mapSite(b)!;
      final mappedC = mapper.mapSite(c)!;
      expect(mappedA.hexId, mappedB.hexId);
      expect(mappedA.hexId, isNot(mappedC.hexId));
      expect(mappedA.hexId.length, 8);
      // Site lines include name + gps.
      final name = mappedA.lines.whereType<QuotedLine>().firstWhere(
            (l) => l.key == 'name',
          );
      expect(name.value, 'Om Sid - Dahab');
      final gps = mappedA.lines.whereType<GpsLine>().single;
      expect(gps.lat, '28.420550');
      expect(gps.lon, '34.457473');

      // mapSite returns null when there are no coordinates.
      final noCoord = _annotation(diveId: 'dive-d');
      expect(mapper.mapSite(noCoord), isNull);
    });

    test('bare dive (no annotation) produces empty buddy/suit/no notes', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final dive = _ccrPetrelDive();
      final samples = _threeMinSampleSet(diveId: dive.id);

      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );

      expect(result.siteHexId, isNull);

      final byKey = <String, QuotedLine>{
        for (final l in result.diveLines.whereType<QuotedLine>()) l.key: l,
      };
      expect(byKey['divemaster']?.value, '');
      expect(byKey['buddy']?.value, '');
      expect(byKey['suit']?.value, '');
      // No annotation → no notes line at all.
      expect(byKey.containsKey('notes'), isFalse);
      // No annotation → no rating, no tags, no divesiteid.
      final scalars = result.diveLines.whereType<ScalarLine>().toList();
      expect(scalars.where((s) => s.key == 'rating'), isEmpty);
      expect(scalars.where((s) => s.key == 'divesiteid'), isEmpty);
      expect(result.diveLines.whereType<TagsLine>(), isEmpty);
    });

    test('sensor1=cellMv*cal/1000 (calibration applied to raw mV)', () {
      // 33 mV × 0.021 bar/mV = 0.693 bar — the canonical Petrel-default
      // round number used to anchor the calibration math everywhere.
      final mapper = CcrlogToSubsurfaceMapper();
      final dive = _ccrPetrelDive(
        sensorCalibrationJson: '[0.021, 0.021, 0.021]',
      );
      final samples = _oneSampleSet(
        diveId: dive.id,
        cellMv0: 33,
        cellMv1: 33,
        cellMv2: 33,
      );
      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final sample =
          result.divecomputerLines.whereType<SampleLine>().single;
      final kv = Map.fromEntries(sample.kv);
      expect(kv['sensor1'], '0.693bar');
      expect(kv['sensor2'], '0.693bar');
      expect(kv['sensor3'], '0.693bar');
    });

    test('absent calibration falls back to the Petrel default 0.021', () {
      // No calibration persisted → should pick the 0.021 fallback,
      // producing the same 0.693bar for cellMv=33.
      final mapper = CcrlogToSubsurfaceMapper();
      final dive = _ccrPetrelDive(); // sensorCalibrationJson defaults to null
      final samples = _oneSampleSet(
        diveId: dive.id,
        cellMv0: 33,
        cellMv1: 33,
        cellMv2: 33,
      );
      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final sample =
          result.divecomputerLines.whereType<SampleLine>().single;
      final kv = Map.fromEntries(sample.kv);
      expect(kv['sensor1'], '0.693bar');
      expect(kv['sensor2'], '0.693bar');
      expect(kv['sensor3'], '0.693bar');
    });

    test('emits Sensor N calibration [bar / V] keyvalues on CCR dives', () {
      // Calibration is mV→bar (e.g. 0.021); Subsurface stores bar/V which
      // is `cal * 1000` (e.g. 21.00). Two-decimal formatting matches the
      // 2026/04/04 reference fixture verbatim.
      final mapper = CcrlogToSubsurfaceMapper();
      final dive = _ccrPetrelDive(
        sensorCalibrationJson: '[0.021, 0.022, 0.020]',
      );
      final samples = _threeMinSampleSet(diveId: dive.id);
      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final kvs =
          result.divecomputerLines.whereType<KeyvaluePairLine>().toList();
      expect(
        kvs.firstWhere((l) => l.key == 'Sensor 1 calibration [bar / V]').value,
        '21.00',
      );
      expect(
        kvs.firstWhere((l) => l.key == 'Sensor 2 calibration [bar / V]').value,
        '22.00',
      );
      expect(
        kvs.firstWhere((l) => l.key == 'Sensor 3 calibration [bar / V]').value,
        '20.00',
      );
      // Round-trip through the serializer: line text matches the fixture.
      final text = serializeSubsurfaceFile(
        SubsurfaceFile(lines: result.divecomputerLines),
      );
      expect(text,
          contains('keyvalue "Sensor 1 calibration [bar / V]" "21.00"\n'));
    });

    test('OC dives do not emit Sensor N calibration keyvalues', () {
      // CCR-only feature: numberofoxygensensors is gated on isCcr, and so
      // is the calibration emission.
      final mapper = CcrlogToSubsurfaceMapper();
      // diveMode 8 = OC (DiveMode.openCircuit.value); _ccrPetrelDive
      // hardcodes 0=CC so we build a fresh OC Dive here.
      final dive = SubsurfaceDiveInput(
        id: 'oc-dive-id-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        dcSerial: 0xb89641e4,
        dcDiveNumber: 706,
        startTime: 1776591525,
        durationSeconds: 600,
        maxDepthMm: 12000,
        diveMode: 8, // OC
        gfLow: 30,
        gfHigh: 80,
        atmosphericPressureMbar: 1013,
        waterDensity: 1025,
        logVersion: 17,
        dcModel: 3,
        dcFirmware: 0xa3,
      );
      final samples = _threeMinSampleSet(diveId: dive.id);
      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final kvs =
          result.divecomputerLines.whereType<KeyvaluePairLine>().toList();
      expect(kvs.where((l) => l.key.startsWith('Sensor ')), isEmpty);
    });

    test('stack-time keyvalues format as H:MM:SS', () {
      final mapper = CcrlogToSubsurfaceMapper();
      // Configured = 7h, start = 3h 0m 47s, end = 2h 2m 27s — matches the
      // 2026/04/04 fixture verbatim.
      final dive = _ccrPetrelDive(
        configuredStackSeconds: 25200,
        stackRemainingAtStartSeconds: 10847,
        stackRemainingAtEndSeconds: 7347,
      );
      final samples = _threeMinSampleSet(diveId: dive.id);
      final result = mapper.mapDive(
        dive: dive,
        samples: samples,
        annotation: null,
        gasMixes: _threeGasMixes(),
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );

      final kvs =
          result.divecomputerLines.whereType<KeyvaluePairLine>().toList();

      expect(
        kvs.firstWhere((l) => l.key == 'Configured stack time [hh:mm:ss]')
            .value,
        '7:00:00',
      );
      expect(
        kvs.firstWhere(
            (l) => l.key == 'Remaining stack time at start [hh:mm:ss]').value,
        '3:00:47',
      );
      expect(
        kvs.firstWhere(
            (l) => l.key == 'Remaining stack time at end [hh:mm:ss]').value,
        '2:02:27',
      );

      // Round-trip through the serializer to verify the output is valid
      // text (no broken padding, no stray quotes).
      final text = serializeSubsurfaceFile(
        SubsurfaceFile(lines: result.divecomputerLines),
      );
      expect(text,
          contains('keyvalue "Configured stack time [hh:mm:ss]" "7:00:00"\n'));
    });

    test('mapDive emits Information-tab fields when annotation carries them',
        () {
      final mapper = CcrlogToSubsurfaceMapper();
      final ann = DiveAnnotation(
        diveId: 'd1',
        visibility: 5,
        wavesize: 3,
        current: 4,
        surge: 4,
        chill: 5,
        airTempC: 24.0,
        waterTempC: 22.5,
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final mapped = mapper.mapDive(
        dive: _ccrPetrelDive(),
        samples: _threeMinSampleSet(diveId: _ccrPetrelDive().id),
        annotation: ann,
        gasMixes: const [],
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
      expect(text, contains('visibility 5'));
      expect(text, contains('wavesize 3'));
      expect(text, contains('current 4'));
      expect(text, contains('surge 4'));
      expect(text, contains('chill 5'));
      expect(text, contains('airtemp 24.0°C'));
      expect(text, contains('watertemp 22.5°C'));
    });

    test('mapDive emits one weightsystem line per Weight entry', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final ann = DiveAnnotation(
        diveId: 'd1',
        weights: const [
          Weight(weightKg: 2.0, description: 'backplate'),
          Weight(weightKg: 1.5, description: 'belt'),
        ],
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final mapped = mapper.mapDive(
        dive: _ccrPetrelDive(),
        samples: _threeMinSampleSet(diveId: _ccrPetrelDive().id),
        annotation: ann,
        gasMixes: const [],
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
      expect(text, contains('weightsystem weight=2.0kg description="backplate"'));
      expect(text, contains('weightsystem weight=1.5kg description="belt"'));
    });

    test('mapDive escapes double quotes in weight descriptions', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final ann = DiveAnnotation(
        diveId: 'd1',
        weights: const [
          Weight(weightKg: 2.0, description: 'lead "ankle" weights'),
        ],
        createdAt: DateTime.utc(2026, 5, 1),
        updatedAt: DateTime.utc(2026, 5, 1),
      );
      final mapped = mapper.mapDive(
        dive: _ccrPetrelDive(),
        samples: _threeMinSampleSet(diveId: _ccrPetrelDive().id),
        annotation: ann,
        gasMixes: const [],
        tanks: const [],
        cylindersByMixIndex: const {},
        nextSubsurfaceDiveNumber: 1,
      );
      final text = serializeSubsurfaceFile(SubsurfaceFile(lines: mapped.diveLines));
      // The inner quotes must be escaped; the line must round-trip back
      // through the parser as a single weightsystem entry with the
      // original description.
      expect(text, contains(r'description="lead \"ankle\" weights"'));
    });
  });

  group('CcrlogToSubsurfaceMapper.topLevelDelta', () {
    test('emits one fingerprint per dive and one divecomputerid per DC', () {
      final mapper = CcrlogToSubsurfaceMapper();
      final dive1 = _ccrPetrelDive();
      final dive2 = _ccrPetrelDive(diveId: 'second-dive-id');
      final dc = _diveComputer();
      final delta = mapper.topLevelDelta(
        dives: [dive1, dive2],
        diveComputers: [dc, dc], // same DC repeated → only one entry.
      );
      expect(delta.newFingerprints.length, 2);
      expect(delta.newDivecomputerIds.length, 1);
      // Fingerprint fields preserve insertion order: model, serial,
      // deviceid, diveid, data.
      final firstFp = delta.newFingerprints.first;
      expect(firstFp.fields.map((e) => e.key).toList(),
          ['model', 'serial', 'deviceid', 'diveid', 'data']);
    });
  });
}

// ── helpers ──────────────────────────────────────────────────────────────

String _keyOf(SsLine l) {
  if (l is ScalarLine) return l.key;
  if (l is QuotedLine) return l.key;
  if (l is FlagLine) return l.key;
  if (l is TagsLine) return 'tags';
  return l.runtimeType.toString();
}

String _scalar(List<ScalarLine> lines, String key) =>
    lines.firstWhere((l) => l.key == key).value;

SubsurfaceDiveInput _ccrPetrelDive({
  String diveId = 'dive-id-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  int? configuredStackSeconds = 25200,
  int? stackRemainingAtStartSeconds = 10847,
  int? stackRemainingAtEndSeconds = 7347,
  String? sensorCalibrationJson,
}) {
  // 1776591525 = 2026-04-04T13:18:45Z (UTC).
  return SubsurfaceDiveInput(
    id: diveId,
    dcSerial: 0xb89641e4,
    dcDiveNumber: 705,
    startTime: 1776591525,
    durationSeconds: 3450,
    maxDepthMm: 18000,
    diveMode: 0, // cc
    gfLow: 50,
    gfHigh: 95,
    atmosphericPressureMbar: 1013,
    waterDensity: 1025,
    logVersion: 17,
    dcModel: 3, // petrel3
    dcFirmware: 0xa3,
    sensorCalibrationJson: sensorCalibrationJson,
    configuredStackSeconds: configuredStackSeconds,
    stackRemainingAtStartSeconds: stackRemainingAtStartSeconds,
    stackRemainingAtEndSeconds: stackRemainingAtEndSeconds,
  );
}

SubsurfaceDiveComputerInput _diveComputer() {
  return const SubsurfaceDiveComputerInput(
    serial: 0xb89641e4,
    model: 3,
    nickname: 'Petrel 3',
  );
}

DiveAnnotation _annotation({
  required String diveId,
  String? siteName,
  double? siteLatitude,
  double? siteLongitude,
  String? notes,
  List<String> buddies = const [],
  List<String> tags = const [],
  int? rating,
  String? suit,
}) {
  final now = DateTime.fromMillisecondsSinceEpoch(0);
  return DiveAnnotation(
    diveId: diveId,
    siteName: siteName,
    siteLatitude: siteLatitude,
    siteLongitude: siteLongitude,
    notes: notes,
    buddies: buddies,
    tags: tags,
    rating: rating,
    suit: suit,
    createdAt: now,
    updatedAt: now,
  );
}

List<DiveGasMix> _threeGasMixes() => [
      DiveGasMix(oxygenPercent: 18, heliumPercent: 23, isDiluent: true),
      DiveGasMix(oxygenPercent: 50, heliumPercent: 0, isDiluent: false),
      DiveGasMix(oxygenPercent: 99, heliumPercent: 0, isDiluent: false),
    ];

List<DiveTank> _threeTanks() => [
      DiveTank(
        slot: 0,
        usage: TankUsage.diluent,
        name: 'D1',
        serial: 0,
        beginPressureBar: 207.0,
        endPressureBar: 115.0,
        pressureMaxBar: 232,
        pressureReserveBar: 70,
      ),
      DiveTank(
        slot: 1,
        usage: TankUsage.none,
        name: 'D2',
        serial: 0,
        beginPressureBar: 140.0,
        endPressureBar: 116.0,
        pressureMaxBar: 232,
        pressureReserveBar: 70,
      ),
      DiveTank(
        slot: 2,
        usage: TankUsage.oxygen,
        name: 'O2',
        serial: 0,
        beginPressureBar: 200.0,
        endPressureBar: 180.0,
        pressureMaxBar: 207,
        pressureReserveBar: 50,
      ),
    ];

/// A one-sample [SampleSet] with the per-cell mV channels populated to
/// the values supplied — used by calibration math tests where we need
/// deterministic, hand-picked sensor readings.
SampleSet _oneSampleSet({
  required String diveId,
  required double cellMv0,
  required double cellMv1,
  required double cellMv2,
}) {
  final s0 = Float32List(1)..[0] = cellMv0;
  final s1 = Float32List(1)..[0] = cellMv1;
  final s2 = Float32List(1)..[0] = cellMv2;
  return SampleSet(
    diveId: diveId,
    sampleCount: 1,
    sampleIntervalMs: 10000,
    depthMeters: Float32List(1),
    temperatureCelsius: Float32List(1),
    ppo2Bar: Float32List(1),
    cellMv0: s0,
    cellMv1: s1,
    cellMv2: s2,
    setpointBar: Float32List(1),
    cns: Float32List(1),
    decoStopDepthMeters: Float32List(1),
    decoTimeSeconds: Int32List(1),
    ttsSeconds: Int32List(1)..[0] = -1,
    gasMixIndex: Uint8List(1),
    statusFlags: Uint8List(1),
  );
}

/// A 3-minute sample set: depth descends to 18m and back, three cells
/// reading sane mV, two tank-pressure traces, gas-mix index switches at
/// 0s (mix 0), 60s (mix 1), 120s (mix 2).
SampleSet _threeMinSampleSet({required String diveId}) {
  // 18 samples × 10000ms = 180s = 3 min.
  const n = 18;
  final depth = Float32List(n);
  final temp = Float32List(n);
  final ppo2 = Float32List(n);
  final s0 = Float32List(n);
  final s1 = Float32List(n);
  final s2 = Float32List(n);
  final setpoint = Float32List(n);
  final cns = Float32List(n);
  final stopDepth = Float32List(n);
  final decoTime = Int32List(n);
  final tts = Int32List(n);
  final gasIdx = Uint8List(n);
  final status = Uint8List(n);
  final tank0 = Float32List(n);
  final tank1 = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    depth[i] = i < n / 2 ? 18.0 * (i / (n / 2)) : 18.0 * (1 - (i - n / 2) / (n / 2));
    temp[i] = i < 5 ? 16.0 : 11.0;
    ppo2[i] = 1.0 + 0.1 * t;
    setpoint[i] = 1.0;
    s0[i] = 0.95 + 0.05 * t;
    s1[i] = 0.97 + 0.05 * t;
    s2[i] = 0.96 + 0.05 * t;
    cns[i] = 0.01;
    stopDepth[i] = 0.0;
    decoTime[i] = 0;
    tts[i] = 60; // 1:00 throughout
    gasIdx[i] = i < 6 ? 0 : (i < 12 ? 1 : 2);
    status[i] = 0;
    tank0[i] = 207.0 - 1.0 * i;
    tank1[i] = 140.0 - 0.3 * i;
  }
  return SampleSet(
    diveId: diveId,
    sampleCount: n,
    sampleIntervalMs: 10000,
    depthMeters: depth,
    temperatureCelsius: temp,
    ppo2Bar: ppo2,
    cellMv0: s0,
    cellMv1: s1,
    cellMv2: s2,
    setpointBar: setpoint,
    cns: cns,
    decoStopDepthMeters: stopDepth,
    decoTimeSeconds: decoTime,
    ttsSeconds: tts,
    gasMixIndex: gasIdx,
    statusFlags: status,
    tankPressuresBar: [tank0, tank1],
  );
}
