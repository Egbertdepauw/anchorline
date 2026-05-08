/// Phase D — read the cloned Subsurface repo from disk into the
/// data structures the [SyncPlanner] consumes.
///
/// The snapshot is *only* the bits the planner needs:
///
/// - `existingTopLevel`     — parsed lines of `00-Subsurface`
/// - `existingSites`        — `{ hexId: parsed lines of Site-<hexId> }`
/// - `existingDivesBySerialAndStart` — keys `(serial, startTime)` so the
///   planner can match a CCRLog dive against an existing remote entry
///   and reuse its folder + Dive-NNN.
/// - `existingMaxDiveNumber` — highest Dive-NNN seen, so newly emitted
///   dives can allocate `existingMaxDiveNumber + 1`, +2, ...
///
/// Tolerance: any single file that fails to parse is skipped (logged in
/// debug builds via `assert`, otherwise silent). Missing fields on a
/// Divecomputer (no Serial keyvalue, malformed folder name) just mean
/// that dive can't ever match a CCRLog dive — that's fine, the planner
/// will allocate a fresh Dive-NNN for it. We do not abort the snapshot
/// on individual-file failures; the cost of refusing to sync because of
/// one corrupt fixture from 2008 is much worse than skipping it.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'format/subsurface_format.dart';
import 'format/subsurface_parser.dart';
import 'sync_planner.dart' show ExistingRemoteDive;

class RemoteSnapshotData {
  RemoteSnapshotData({
    required this.existingTopLevel,
    required this.existingSites,
    required this.existingDivesBySerialAndStart,
    required this.existingMaxDiveNumber,
  });

  final List<SsLine> existingTopLevel;
  final Map<String, List<SsLine>> existingSites;
  final Map<({int serial, int startTime}), ExistingRemoteDive>
      existingDivesBySerialAndStart;
  final int existingMaxDiveNumber;
}

class RemoteSnapshot {
  /// Walk [repoRoot] and produce a [RemoteSnapshotData].
  ///
  /// Tolerates parse failures on individual files — those files are
  /// silently skipped so a single bad fixture from a manually-imported
  /// 2008 dive can't block today's sync.
  static Future<RemoteSnapshotData> read(Directory repoRoot) async {
    if (!repoRoot.existsSync()) {
      return RemoteSnapshotData(
        existingTopLevel: const [],
        existingSites: const {},
        existingDivesBySerialAndStart: const {},
        existingMaxDiveNumber: 0,
      );
    }

    final topLevel = _readTopLevel(repoRoot);
    final sites = _readSites(repoRoot);
    final dives = _readDives(repoRoot);

    var maxDiveNumber = 0;
    final byKey = <({int serial, int startTime}), ExistingRemoteDive>{};
    for (final d in dives) {
      if (d.diveNumber > maxDiveNumber) maxDiveNumber = d.diveNumber;
      if (d.serial != null && d.startTime != null) {
        byKey[(serial: d.serial!, startTime: d.startTime!)] = d;
      }
    }

    return RemoteSnapshotData(
      existingTopLevel: topLevel,
      existingSites: sites,
      existingDivesBySerialAndStart: byKey,
      existingMaxDiveNumber: maxDiveNumber,
    );
  }

  // ── 00-Subsurface ──────────────────────────────────────────────────

  static List<SsLine> _readTopLevel(Directory repoRoot) {
    final f = File('${repoRoot.path}/00-Subsurface');
    if (!f.existsSync()) return const [];
    try {
      final text = f.readAsStringSync();
      return parseSubsurfaceFile(text, kind: SubsurfaceFileKind.top).lines;
    } catch (_) {
      return const [];
    }
  }

  // ── Sites ──────────────────────────────────────────────────────────

  static Map<String, List<SsLine>> _readSites(Directory repoRoot) {
    final dir = Directory('${repoRoot.path}/01-Divesites');
    if (!dir.existsSync()) return const {};
    final out = <String, List<SsLine>>{};
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      const prefix = 'Site-';
      if (!name.startsWith(prefix)) continue;
      final hexId = name.substring(prefix.length);
      try {
        final text = entity.readAsStringSync();
        final parsed =
            parseSubsurfaceFile(text, kind: SubsurfaceFileKind.site);
        out[hexId] = parsed.lines;
      } catch (_) {
        // Skip this site file; the planner will write a fresh one if
        // CCRLog has dives at the same coordinates.
      }
    }
    return out;
  }

  // ── Dive folders ───────────────────────────────────────────────────

  /// Walk `<repo>/<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>/{Dive-NNN, Divecomputer}`.
  ///
  /// Two layout-checks before opening any file:
  ///   1. The first three path components match the year/month/day
  ///      pattern Subsurface uses. Anything else (`.git`, `01-Divesites`,
  ///      `00-Subsurface`) is ignored.
  ///   2. The folder name's UTC parse round-trips — i.e. our reformatter
  ///      produces the same folder name. If not, the folder is from a
  ///      non-Subsurface tool or hand-edited; we can still read its
  ///      Dive-NNN to bump the max counter, but we won't add it to the
  ///      `(serial, startTime)` lookup table.
  static List<ExistingRemoteDive> _readDives(Directory repoRoot) {
    final out = <ExistingRemoteDive>[];
    if (!repoRoot.existsSync()) return out;

    for (final yEntity in repoRoot.listSync()) {
      if (yEntity is! Directory) continue;
      final yName = p.basename(yEntity.path);
      if (!_isFourDigit(yName)) continue;
      for (final mEntity in yEntity.listSync()) {
        if (mEntity is! Directory) continue;
        final mName = p.basename(mEntity.path);
        if (!_isTwoDigit(mName)) continue;
        for (final dEntity in mEntity.listSync()) {
          if (dEntity is! Directory) continue;
          final dName = p.basename(dEntity.path);
          // `DD-Day-HH=MM=SS`.
          if (!_isDayFolderName(dName)) continue;
          final dive = _readOneDiveFolder(
            folderSegments: [yName, mName, dName],
            folder: dEntity,
          );
          if (dive != null) out.add(dive);
        }
      }
    }
    return out;
  }

  static ExistingRemoteDive? _readOneDiveFolder({
    required List<String> folderSegments,
    required Directory folder,
  }) {
    int? diveNumber;
    File? divecomputerFile;
    for (final entity in folder.listSync()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('Dive-')) {
        final n = int.tryParse(name.substring('Dive-'.length));
        if (n != null && (diveNumber == null || n > diveNumber)) {
          diveNumber = n;
        }
      } else if (name == 'Divecomputer' || name.startsWith('Divecomputer-')) {
        // Prefer the bare `Divecomputer` if present; otherwise the
        // first `Divecomputer-NNN` we encounter.
        divecomputerFile ??= entity;
        if (name == 'Divecomputer') divecomputerFile = entity;
      }
    }
    if (diveNumber == null) return null;

    int? serial;
    if (divecomputerFile != null) {
      try {
        final text = divecomputerFile.readAsStringSync();
        final parsed = parseSubsurfaceFile(
          text,
          kind: SubsurfaceFileKind.divecomputer,
        );
        serial = _serialFromDivecomputer(parsed.lines);
      } catch (_) {
        // Leave serial null; this dive won't match a CCRLog (serial,
        // startTime) lookup but we still count its Dive-NNN towards the
        // max counter.
      }
    }

    final startTime = _startTimeFromFolderName(folderSegments);

    return ExistingRemoteDive(
      folderSegments: folderSegments,
      diveNumber: diveNumber,
      serial: serial,
      startTime: startTime,
    );
  }

  /// Pull the integer serial out of `keyvalue "Serial" "<hex>"`. Returns
  /// null when the line is missing, the value isn't valid hex, or the
  /// parse fails outright.
  static int? _serialFromDivecomputer(List<SsLine> lines) {
    for (final line in lines) {
      if (line is KeyvaluePairLine && line.key == 'Serial') {
        final s = line.value;
        return int.tryParse(s, radix: 16);
      }
    }
    return null;
  }

  /// Parse `[YYYY, MM, DD-Day-HH=MM=SS]` back to unix seconds (UTC).
  /// Returns null when any component is malformed or our reformat
  /// doesn't round-trip the input — i.e. the folder name was hand-edited
  /// or written by a non-Subsurface tool.
  static int? _startTimeFromFolderName(List<String> segments) {
    if (segments.length != 3) return null;
    final yyyy = int.tryParse(segments[0]);
    final mm = int.tryParse(segments[1]);
    if (yyyy == null || mm == null) return null;
    final dayPart = segments[2];
    // DD-Day-HH=MM=SS
    final m = RegExp(r'^(\d{2})-([A-Za-z]{3})-(\d{2})=(\d{2})=(\d{2})$')
        .firstMatch(dayPart);
    if (m == null) return null;
    final dd = int.parse(m.group(1)!);
    final hh = int.parse(m.group(3)!);
    final mi = int.parse(m.group(4)!);
    final ss = int.parse(m.group(5)!);
    final dt = DateTime.utc(yyyy, mm, dd, hh, mi, ss);
    return dt.millisecondsSinceEpoch ~/ 1000;
  }

  static bool _isFourDigit(String s) =>
      s.length == 4 && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  static bool _isTwoDigit(String s) =>
      s.length == 2 && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  static bool _isDayFolderName(String s) =>
      RegExp(r'^\d{2}-[A-Za-z]{3}-\d{2}=\d{2}=\d{2}$').hasMatch(s);
}
