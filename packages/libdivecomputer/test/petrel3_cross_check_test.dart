// libdivecomputer's output on a replayed Petrel 3 download, against the app's
// own Dart Shearwater reader.
//
// `fixtures/petrel3_expected.json` is what the Dart reader
// (`ShearwaterDiveParser` plus `DiveConverter.convert`) gives for the same
// eight dives; `fixtures/README.md` has the command that made it.
import 'dart:convert';
import 'dart:io';

import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:libdivecomputer/src/download/download.dart'
    show debugReplayWithLegacyParser;
import 'package:test/test.dart';

import 'support/digest.dart';
import 'support/petrel3_replay.dart';
import 'support/trace_link.dart';

void main() {
  late final List<LibdcDiveDownloaded> dives;
  late final List<Map<String, dynamic>> expected;

  setUpAll(() async {
    dives = await replayPetrel3Dives();
    final json =
        jsonDecode(File('test/fixtures/petrel3_expected.json').readAsStringSync())
            as Map<String, dynamic>;
    expected = [for (final d in json['dives'] as List) d as Map<String, dynamic>];
  });

  /// What it checks: start time (exact), duration (+-1 s), max depth (+-0.01
  /// m), the gas mixes (equal, in order), and on every grid point depth
  /// (+-0.01 m), temperature (+-0.1 C), voted ppO2 and setpoint (+-0.01 bar).
  ///
  /// Findings, the only differences between the two readers on these dives:
  ///
  /// * Time base of the first sample (grid length): libdivecomputer dates a
  ///   Shearwater's first sample one interval (5 s) into the dive; the Dart
  ///   reader's first sample is index 0. Anchorline's grid for a
  ///   libdivecomputer dive runs from 0 ms and holds the first value, so it
  ///   has one more point than the Dart reader's (`sampleCount` + 1, the
  ///   extra one leading). The test compares libdivecomputer's index i + 1
  ///   with the Dart reader's index i, and checks that the leading point is
  ///   the held first value. Duration and the last sample agree.
  ///
  /// Nothing else differs, so there is no mapping bug to fix. Shearwater
  /// dives are not parsed by libdivecomputer in the app; this guards the
  /// mapping, and the checked-family procedure in fixtures/README.md.
  test('libdivecomputer and the Dart reader agree on every Petrel 3 dive', () {
    expect(dives, hasLength(8));
    expect(expected, hasLength(8));
    final problems = <String>[];
    for (final d in dives) {
      final c = d.converted!;
      final epoch = c.dive.startTime.millisecondsSinceEpoch ~/ 1000;
      final e = expected.singleWhere(
        (x) => x['startTimeEpochSeconds'] == epoch,
        orElse: () => <String, dynamic>{},
      );
      if (e.isEmpty) {
        problems.add('no expected dive starts at $epoch');
        continue;
      }
      final tag = 'dive ${e['diveNumber']}';
      void check(bool ok, String what) {
        if (!ok) problems.add('$tag: $what');
      }

      check(
        (c.dive.duration.inSeconds - (e['durationSeconds'] as int)).abs() <= 1,
        'duration ${c.dive.duration.inSeconds} vs ${e['durationSeconds']}',
      );
      check(
        (c.dive.maxDepthMeters - (e['maxDepthM'] as num)).abs() <= 0.01,
        'max depth ${c.dive.maxDepthMeters} vs ${e['maxDepthM']}',
      );
      final gases = [
        for (final g in c.dive.gasMixes)
          '${g.oxygenPercent}/${g.heliumPercent}/${g.isDiluent}',
      ];
      final eGases = [
        for (final g in e['gasMixes'] as List)
          '${g['oxygenPercent']}/${g['heliumPercent']}/${g['isDiluent']}',
      ];
      check(
        gases.join(',') == eGases.join(','),
        'gas mixes $gases vs $eGases',
      );
      final s = c.samples;
      // Finding 1 (time base): libdivecomputer dates a Shearwater's first
      // sample one interval into the dive (5 s), where the Dart reader's
      // first sample is index 0. Our grid starts at 0 ms and holds the first
      // value, so libdivecomputer's grid has one extra leading point:
      // libdivecomputer index i + 1 is the Dart reader's index i.
      check(
        s.sampleIntervalMs == e['sampleIntervalMs'] &&
            s.sampleCount == (e['sampleCount'] as int) + 1,
        'grid ${s.sampleCount}x${s.sampleIntervalMs} ms vs '
        '${e['sampleCount']}x${e['sampleIntervalMs']} ms plus the leading point',
      );
      if (s.sampleCount == (e['sampleCount'] as int) + 1) {
        void arrays(String name, List<double> got, List want, double tol) {
          check(got[0] == got[1], '$name leading point is not held');
          var worst = 0.0;
          var at = 0;
          for (var i = 0; i < want.length; i++) {
            final diff = (got[i + 1] - (want[i] as num)).abs();
            if (diff > worst) {
              worst = diff;
              at = i;
            }
          }
          check(
            worst <= tol,
            '$name differs by $worst at sample $at '
            '(${got[at]} vs ${want[at]}, tolerance $tol)',
          );
        }

        arrays('depth', s.depthMeters, e['depthM'] as List, 0.01);
        arrays('temperature', s.temperatureCelsius, e['temperatureC'] as List, 0.1);
        arrays('ppO2', s.ppo2Bar, e['ppo2Bar'] as List, 0.01);
        arrays('setpoint', s.setpointBar, e['setpointBar'] as List, 0.01);
      }
    }
    expect(problems, isEmpty);
  });

  test('dc_parser_new and dc_parser_new2 give the same dive', () async {
    final events = await collect(
      debugReplayWithLegacyParser(
        descriptor: petrel3(),
        recording: petrelTrace(),
      ),
    );
    final both = divesOf(events);
    expect(both, hasLength(8));
    for (final d in both) {
      expect(
        d.debugLegacyConverted,
        isNotNull,
        reason: 'dc_parser_new(device) parsed the dive',
      );
      expect(
        mappingDigest(d.debugLegacyConverted!),
        mappingDigest(d.converted!),
        reason: 'dc_parser_new and dc_parser_new2 differ on ${d.diveId}',
      );
    }
  });
}
