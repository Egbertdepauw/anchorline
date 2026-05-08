// Round-trip tests for the Subsurface plain-text format parser/serializer.
//
// We assert two properties for every fixture:
//
//   1. `serialize(parse(input)) == input` — byte-for-byte. This is the
//      primary guarantee: anything we read from a real Subsurface git repo
//      must come back out unchanged.
//   2. `parse(serialize(parse(input))) == parse(input)` — structurally idem-
//      potent. Catches the corner case where the source string was lost or
//      mutated and the second-round parse produces a different model.

import 'dart:io';

import 'package:ccrlogger/sync/subsurface_git/format/subsurface_format.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_serializer.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixturesRoot = 'test/fixtures/subsurface';

void main() {
  group('SubsurfaceFile round-trip', () {
    test('top-level 00-Subsurface', () {
      _expectRoundTrip(
        '$_fixturesRoot/00-Subsurface',
        kind: SubsurfaceFileKind.top,
      );
    });

    group('Site files', () {
      const sites = [
        'Site-0a9f7232', // simple GPS site
        'Site-0acb7fe3', // simple, Dutch site name
        'Site-ecaf8184', // multi-line notes with embedded escaped quotes
      ];
      for (final s in sites) {
        test(s, () {
          _expectRoundTrip(
            '$_fixturesRoot/sites/$s',
            kind: SubsurfaceFileKind.site,
          );
        });
      }
    });

    group('Dive files', () {
      // Each entry is the relative path under `test/fixtures/subsurface/dives`.
      const dives = [
        // Modern Petrel CCR with multi-cylinder, multi-sensor, and a tonne
        // of keyvalue lines. ~700-line Divecomputer.
        '2026/04/04-Sat-13=30=15',
        // Petrel CCR with `o2pressure=` token and non-indexed `bar` form
        // (different sample-line shape).
        '2025/05/04-Sun-09=48=36',
        // Multi-line notes (raw newlines inside quoted string).
        '2026/04/27-Mon-11=33=43',
        // Old / minimal manual dive: no model line, `lastmanualtime`, sparse
        // samples, `weightsystem` line.
        '2004/06/19-Sat-09=00=00',
        // 2020 dive with airtemp / visibility / wavesize / current / surge /
        // chill / watersalinity, `model "manually added dive"`, multi-line
        // notes ending with a tab character.
        '2020/08/18-Tue-16=00=27',
      ];
      for (final d in dives) {
        test('$d / Dive', () {
          final dir = Directory('$_fixturesRoot/dives/$d');
          final diveFile = dir.listSync().firstWhere(
                (e) => e.path.split(Platform.pathSeparator).last.startsWith(
                      'Dive-',
                    ),
              );
          _expectRoundTrip(
            diveFile.path,
            kind: SubsurfaceFileKind.dive,
          );
        });
        test('$d / Divecomputer', () {
          _expectRoundTrip(
            '$_fixturesRoot/dives/$d/Divecomputer',
            kind: SubsurfaceFileKind.divecomputer,
          );
        });
      }
    });
  });

  group('Structured field access', () {
    test('site fields are typed', () {
      final raw = File('$_fixturesRoot/sites/Site-0a9f7232')
          .readAsStringSync();
      final file = parseSubsurfaceFile(raw, kind: SubsurfaceFileKind.site);
      final name = file.lines.whereType<QuotedLine>().firstWhere(
            (l) => l.key == 'name',
          );
      expect(name.value, 'Om Sid - Dahab');
      final gps = file.lines.whereType<GpsLine>().single;
      expect(gps.lat, '28.420550');
      expect(gps.lon, '34.457473');
      final geo = file.lines.whereType<GeoLine>().single;
      expect(geo.cat, '2');
      expect(geo.origin, '2');
      expect(geo.name, 'Egypte');
    });

    test('site notes preserve embedded escaped quotes and raw newlines', () {
      final raw =
          File('$_fixturesRoot/sites/Site-ecaf8184').readAsStringSync();
      final file = parseSubsurfaceFile(raw, kind: SubsurfaceFileKind.site);
      final notes = file.lines
          .whereType<QuotedLine>()
          .firstWhere((l) => l.key == 'notes');
      // Subsurface writes `\"Fortunal\"` in the source; after unescaping, the
      // value should contain a literal `"`.
      expect(notes.value.contains('"Fortunal"'), isTrue,
          reason: 'expected unescaped quotes in notes value');
      // Multi-line: the value must contain raw newlines.
      expect(notes.value.contains('\n'), isTrue);
    });

    test('cylinder fields preserve original key order', () {
      final raw = File(
        '$_fixturesRoot/dives/2026/04/04-Sat-13=30=15/Dive-705',
      ).readAsStringSync();
      final file = parseSubsurfaceFile(raw, kind: SubsurfaceFileKind.dive);
      final cylinders = file.lines.whereType<CylinderLine>().toList();
      expect(cylinders, isNotEmpty);
      // First cylinder: `vol`, `workpressure`, `description`, `o2`, `depth`.
      final firstKeys = cylinders.first.fields.map((e) => e.key).toList();
      expect(firstKeys, ['vol', 'workpressure', 'description', 'o2', 'depth']);
    });

    test('events parse with cylinder/o2/he tokens', () {
      final raw = File(
        '$_fixturesRoot/dives/2026/04/04-Sat-13=30=15/Divecomputer',
      ).readAsStringSync();
      final file =
          parseSubsurfaceFile(raw, kind: SubsurfaceFileKind.divecomputer);
      final events = file.lines.whereType<EventLine>().toList();
      expect(events, isNotEmpty);
      final first = events.first;
      expect(first.time, '0:05');
      final fields = Map.fromEntries(first.fields);
      expect(fields['type'], '25');
      expect(fields['flags'], '6');
      expect(fields['name'], '"gaschange"');
      expect(fields['cylinder'], '5');
      expect(fields['o2'], '18.0%');
      expect(fields['he'], '23.0%');
    });

    test('sample lines split positional vs key=value tokens', () {
      final raw = File(
        '$_fixturesRoot/dives/2026/04/04-Sat-13=30=15/Divecomputer',
      ).readAsStringSync();
      final file =
          parseSubsurfaceFile(raw, kind: SubsurfaceFileKind.divecomputer);
      final samples = file.lines.whereType<SampleLine>().toList();
      expect(samples.length, greaterThan(100));
      final first = samples.first;
      expect(first.time, '0:05');
      // `1.6m 11.0°C 207.946bar:0 139.964bar:1`
      expect(first.positional.length, 4);
      expect(first.positional.first, '1.6m');
      // Subsequent kv tokens.
      final firstKv = Map.fromEntries(first.kv);
      expect(firstKv.containsKey('tts'), isTrue);
      expect(firstKv.containsKey('sensor1'), isTrue);
      expect(firstKv['po2'], '0.7bar');
    });

    test('3-digit-minute sample timestamps are recognised (>= 100 min)', () {
      // Subsurface right-pads sample timestamps to 4 chars in the minute
      // field. Past 99 min the leading-space pad collapses to zero —
      // `100:00 1.2m ...` with no leading space. The detector must still
      // classify these as samples; otherwise long dives truncate at minute
      // 100 and CNS/OTU stop accumulating.
      const input = '  0:05 5.0m sensor1=0.7bar\n'
          ' 99:55 12.0m cns=87%\n'
          '100:00 12.0m cns=88%\n'
          '202:15 0.0m cns=168%\n';
      final file =
          parseSubsurfaceFile(input, kind: SubsurfaceFileKind.divecomputer);
      final samples = file.lines.whereType<SampleLine>().toList();
      expect(samples.length, 4);
      expect(samples[2].time, '100:00');
      expect(samples[3].time, '202:15');
      expect(Map.fromEntries(samples[3].kv)['cns'], '168%');
    });
  });

  group('Forward compatibility', () {
    test('unknown line keys are preserved verbatim', () {
      final input = 'someNewKey "with a value"\n'
          'duration 10:00 min\n'
          'another_unknown extra tokens here\n';
      final file = parseSubsurfaceFile(input, kind: SubsurfaceFileKind.dive);
      final out = serializeSubsurfaceFile(file);
      expect(out, input);
    });

    test('flag-only line ("invalid") is preserved', () {
      const input = 'duration 1:00 min\n'
          'invalid\n'
          'cylinder vol=5.0l\n';
      final file = parseSubsurfaceFile(input, kind: SubsurfaceFileKind.dive);
      final out = serializeSubsurfaceFile(file);
      expect(out, input);
    });
  });
}

/// Read [path], parse it with the given [kind], serialize, and assert byte-
/// equivalence. Then re-parse the serialized output and assert that the line
/// list is structurally equal to the first parse.
void _expectRoundTrip(
  String path, {
  required SubsurfaceFileKind kind,
}) {
  final raw = File(path).readAsStringSync();
  final parsed = parseSubsurfaceFile(raw, kind: kind);
  final serialized = serializeSubsurfaceFile(parsed);
  expect(
    serialized,
    raw,
    reason: 'serialize(parse($path)) must equal the original bytes',
  );
  final reparsed = parseSubsurfaceFile(serialized, kind: kind);
  expect(
    reparsed.lines.length,
    parsed.lines.length,
    reason: 're-parse line count must match',
  );
  for (var i = 0; i < parsed.lines.length; i++) {
    expect(
      reparsed.lines[i].runtimeType,
      parsed.lines[i].runtimeType,
      reason: 're-parse line $i type must match',
    );
    expect(
      reparsed.lines[i].source,
      parsed.lines[i].source,
      reason: 're-parse line $i source must match',
    );
  }
}
