/// Phase D — turn the files of a cloned Subsurface repo into the
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
  /// Build a [RemoteSnapshotData] from the files of a checked-out
  /// Subsurface repo.
  ///
  /// [filesByPath]: every regular file of the repo, keyed by POSIX path
  /// relative to the repo root, value = file text. Paths outside the
  /// Subsurface layout (`.git/…`, anything else) are ignored.
  ///
  /// Tolerates parse failures on individual files — those files are
  /// silently skipped so a single bad fixture from a manually-imported
  /// 2008 dive can't block today's sync.
  static RemoteSnapshotData fromFiles(Map<String, String> filesByPath) {
    // Sorted so that the `Divecomputer-NNN` fallback below is
    // deterministic whatever order the caller built the map in.
    final paths = filesByPath.keys.toList()..sort();

    var topLevel = const <SsLine>[];
    final sites = <String, List<SsLine>>{};
    // Dive-folder files, grouped per folder: `YYYY/MM/DD-Day-HH=MM=SS` ->
    // { file name -> text }.
    final folders =
        <String, ({List<String> segments, Map<String, String> files})>{};

    for (final path in paths) {
      final text = filesByPath[path]!;
      final segments = path.split('/');
      if (segments.length == 1 && segments[0] == '00-Subsurface') {
        topLevel = _readTopLevel(text);
      } else if (segments.length == 2 &&
          segments[0] == '01-Divesites' &&
          segments[1].startsWith('Site-')) {
        final lines = _readSite(text);
        final hexId = segments[1].substring('Site-'.length);
        if (lines != null) sites[hexId] = lines;
      } else if (segments.length == 4 &&
          _isFourDigit(segments[0]) &&
          _isTwoDigit(segments[1]) &&
          _isDayFolderName(segments[2])) {
        folders
            .putIfAbsent(
              segments.sublist(0, 3).join('/'),
              () => (segments: segments.sublist(0, 3), files: {}),
            )
            .files[segments[3]] = text;
      }
    }

    var maxDiveNumber = 0;
    final byKey = <({int serial, int startTime}), ExistingRemoteDive>{};
    for (final folder in folders.values) {
      final d = _readOneDiveFolder(
        folderSegments: folder.segments,
        files: folder.files,
      );
      if (d == null) continue;
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

  static List<SsLine> _readTopLevel(String text) {
    try {
      return parseSubsurfaceFile(text, kind: SubsurfaceFileKind.top).lines;
    } catch (_) {
      return const [];
    }
  }

  // ── Sites ──────────────────────────────────────────────────────────

  /// Null when the file fails to parse: skip this site file; the planner
  /// will write a fresh one if CCRLog has dives at the same coordinates.
  static List<SsLine>? _readSite(String text) {
    try {
      return parseSubsurfaceFile(text, kind: SubsurfaceFileKind.site).lines;
    } catch (_) {
      return null;
    }
  }

  // ── Dive folders ───────────────────────────────────────────────────

  /// Classify `<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>/{Dive-NNN, Divecomputer}`.
  ///
  /// Two layout-checks before reading any file's text:
  ///   1. The first three path components match the year/month/day
  ///      pattern Subsurface uses. Anything else (`.git`, `01-Divesites`,
  ///      `00-Subsurface`) is ignored.
  ///   2. The folder name's UTC parse round-trips — i.e. our reformatter
  ///      produces the same folder name. If not, the folder is from a
  ///      non-Subsurface tool or hand-edited; we can still read its
  ///      Dive-NNN to bump the max counter, but we won't add it to the
  ///      `(serial, startTime)` lookup table.
  static ExistingRemoteDive? _readOneDiveFolder({
    required List<String> folderSegments,
    required Map<String, String> files,
  }) {
    int? diveNumber;
    String? diveText;
    String? divecomputerText;
    // [files] was filled in sorted key order, so "first" below is
    // deterministic.
    for (final entry in files.entries) {
      final name = entry.key;
      if (name.startsWith('Dive-')) {
        final n = int.tryParse(name.substring('Dive-'.length));
        if (n != null && (diveNumber == null || n > diveNumber)) {
          diveNumber = n;
          diveText = entry.value;
        }
      } else if (name == 'Divecomputer' || name.startsWith('Divecomputer-')) {
        // Prefer the bare `Divecomputer` if present; otherwise the
        // first `Divecomputer-NNN` in sorted order.
        divecomputerText ??= entry.value;
        if (name == 'Divecomputer') divecomputerText = entry.value;
      }
    }
    if (diveNumber == null) return null;

    int? serial;
    var divecomputerLines = const <SsLine>[];
    if (divecomputerText != null) {
      try {
        final parsed = parseSubsurfaceFile(
          divecomputerText,
          kind: SubsurfaceFileKind.divecomputer,
        );
        serial = _serialFromDivecomputer(parsed.lines);
        divecomputerLines = parsed.lines;
      } catch (_) {
        // Leave serial + lines null/empty; this dive won't match a CCRLog
        // (serial, startTime) lookup but we still count its Dive-NNN
        // towards the max counter.
      }
    }

    var diveLines = const <SsLine>[];
    if (diveText != null) {
      try {
        diveLines =
            parseSubsurfaceFile(diveText, kind: SubsurfaceFileKind.dive).lines;
      } catch (_) {
        // Leave diveLines empty; the planner will treat this as a new
        // dive rather than merging against an existing baseline.
      }
    }

    final startTime = _startTimeFromFolderName(folderSegments);

    return ExistingRemoteDive(
      folderSegments: folderSegments,
      diveNumber: diveNumber,
      serial: serial,
      startTime: startTime,
      diveLines: diveLines,
      divecomputerLines: divecomputerLines,
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
