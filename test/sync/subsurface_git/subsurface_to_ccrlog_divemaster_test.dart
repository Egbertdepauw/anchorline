// Tests that the Subsurface → CCRLog mapper reads `divemaster` into the
// annotation. Mirrors the pattern established in
// subsurface_to_ccrlog_mapper_test.dart.

import 'dart:io';

import 'package:ccrlogger/sync/subsurface_git/format/subsurface_format.dart';
import 'package:ccrlogger/sync/subsurface_git/format/subsurface_parser.dart';
import 'package:ccrlogger/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixturesRoot = 'test/fixtures/subsurface';

void main() {
  group('SubsurfaceToCcrlogMapper — divemaster field', () {
    test('populated divemaster "Bob" maps to annotation.divemaster == "Bob"',
        () {
      // Build a minimal Dive file that has a divemaster line alongside
      // the minimum required Divecomputer block so mapDive can succeed.
      const diveText = '''
divemaster "Bob"
buddy ""
notes ""
''';
      final diveFile =
          parseSubsurfaceFile(diveText, kind: SubsurfaceFileKind.dive);

      // Load a real Divecomputer fixture so the mapper has a valid DC block.
      final dcLines = _loadDcLines('2026/04/04-Sat-13=30=15');

      final mapper = SubsurfaceToCcrlogMapper();
      final result = mapper.mapDive(
        diveLines: diveFile.lines,
        divecomputerLines: dcLines,
        siteLines: null,
        startTime: DateTime.utc(2026, 4, 4, 13, 30, 15),
        subsurfaceDiveNumber: 705,
      );

      expect(result, isNotNull);
      expect(result!.annotation, isNotNull,
          reason: 'divemaster "Bob" should produce a non-null annotation');
      expect(result.annotation!.divemaster, 'Bob');
    });

    test('empty divemaster "" maps to annotation.divemaster == null', () {
      // Subsurface emits `divemaster ""` when the field is not set. We must
      // treat this as absent rather than storing an empty string.
      const diveText = '''
divemaster ""
buddy "Alex"
notes ""
''';
      final diveFile =
          parseSubsurfaceFile(diveText, kind: SubsurfaceFileKind.dive);

      final dcLines = _loadDcLines('2026/04/04-Sat-13=30=15');

      final mapper = SubsurfaceToCcrlogMapper();
      final result = mapper.mapDive(
        diveLines: diveFile.lines,
        divecomputerLines: dcLines,
        siteLines: null,
        startTime: DateTime.utc(2026, 4, 4, 13, 30, 15),
        subsurfaceDiveNumber: 705,
      );

      expect(result, isNotNull);
      // annotation may still be non-null (buddy "Alex" is present), but
      // divemaster must be null — empty string is not stored.
      expect(result!.annotation!.divemaster, isNull);
    });
  });
}

// ── Helpers ──────────────────────────────────────────────────────────────

List<SsLine> _loadDcLines(String relPath) {
  final dir = Directory('$_fixturesRoot/dives/$relPath');
  final dcFile = dir.listSync().firstWhere(
        (e) => e.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('Divecomputer'),
      );
  return parseSubsurfaceFile(
    File(dcFile.path).readAsStringSync(),
    kind: SubsurfaceFileKind.divecomputer,
  ).lines;
}
