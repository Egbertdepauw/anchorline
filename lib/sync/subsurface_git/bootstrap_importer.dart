/// Bootstrap-import orchestrator: pulls every importable dive out of a
/// user's Subsurface Cloud repo and lands them in CCRLog as fresh dive
/// rows.
///
/// This is the read-direction counterpart to the (currently-disabled)
/// write-direction sync orchestrator. The two are deliberately distinct:
///
/// - The write sync rewrites Subsurface files from CCRLog state and is
///   on a safety hold (it can clobber Subsurface-side edits).
/// - The bootstrap importer is purely *additive*. It never writes to
///   Subsurface, never edits anything in CCRLog that already exists, and
///   never soft-deletes. The worst it can do on failure is leave CCRLog
///   with a partial set of dives, which a re-run will finish.
///
/// Flow inside [import]:
///
///   1. Platform gate ([SubsurfaceRepo.isPlatformSupported]).
///   2. Credentials gate.
///   3. ensureCloned() into `<localCloneRoot>/<email>-bootstrap/`. The
///      `-bootstrap` suffix keeps this clone separate from the
///      write-direction clone so a stale write-direction clone can't
///      pollute the read.
///   4. pull() — fast-forward only. "already up to date" is fine.
///   5. Walk every `<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>/` folder.
///   6. For each folder: parse `Dive-NNN` + `Divecomputer` (+ a
///      `Site-<id>` file via the dive's `divesiteid` line if present),
///      call the read
///      mapper, dedupe against CCRLog by `(dcSerial, startTimeUtcSec)`,
///      and `importDive` if new.
///   7. Stream progress events the whole way so the Settings UI can
///      render `imported 47 of 700`.
///
/// Cylinders are explicitly v1-out-of-scope: `ImportedSubsurfaceDive.cylindersByMixIndex`
/// is dropped on the floor. Matching `ProposedCylinder` to existing
/// `Cylinder` rows by label/role/volume is heuristic and not crucial for
/// the first run; the user wires per-mix cylinders manually in the
/// Equipment tab afterwards. Documenting here so the next pass knows
/// where to plug it back in.
///
/// Subsurface-imported dives store an empty `Uint8List(0)` rawBlob plus
/// a sentinel `parserVersion` of `0xff_ff_ff_ff` so future code can
/// distinguish them from BLE-imported dives. The re-parse path for
/// these dives is "re-import via BLE" — the source binary is not
/// recoverable from a Subsurface log.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../data/db/dive_dao.dart';
import '../../data/db/dive_annotations_dao.dart';
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/shearwater/parser/dive_converter.dart' show ConvertedDive;
import 'credentials.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_format.dart';
import 'package:subsurface_core/sync/subsurface_git/format/subsurface_parser.dart';
import 'repo.dart';
import 'package:subsurface_core/sync/subsurface_git/subsurface_to_ccrlog_mapper.dart';

/// Sentinel parser version stamped on dives the bootstrap importer
/// brings in. Distinguishes Subsurface-imported dives from BLE-imported
/// dives in `dives.parser_version` for any future debugging or
/// re-parse-from-raw decisions. **Must fit in Postgres `integer`
/// (signed 32-bit, max 2,147,483,647).** A previous value of
/// `0xFFFFFFFF` overflowed the column on upsert and the entire upload
/// queue stalled with `value "4294967295" is out of range for type
/// integer`. `-1` reads cleanly as "sentinel / not from a real
/// parser" and won't collide with any real Petrel parser version
/// (those are small positive ints).
const int kSubsurfaceImportedParserVersion = -1;

/// Aggregated outcome of one bootstrap import run.
class SubsurfaceBootstrapResult {
  SubsurfaceBootstrapResult({
    required this.divesImported,
    required this.divesSkipped,
    required this.divesUnmappable,
    required this.completedAt,
  });

  /// Newly added to CCRLog by this run.
  final int divesImported;

  /// Skipped because CCRLog already had a dive with the same
  /// `(dcSerial, startTime)` key. Includes dives previously imported by
  /// a Petrel BLE pull as well as dives imported by an earlier
  /// bootstrap run.
  final int divesSkipped;

  /// Subsurface dive folders the read mapper rejected (manual entries,
  /// non-Shearwater computers, broken records). Surfaced in the final
  /// status line so the user knows their "I had 700 dives but only 645
  /// imported" gap is intentional.
  final int divesUnmappable;

  final DateTime completedAt;
}

// ── Exceptions ──────────────────────────────────────────────────────

class SubsurfaceBootstrapException implements Exception {
  SubsurfaceBootstrapException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SubsurfaceBootstrapException: $message';
}

class NoCredentialsBootstrapException extends SubsurfaceBootstrapException {
  NoCredentialsBootstrapException([String? message])
      : super(message ?? 'No Subsurface Cloud credentials saved');
}

class AuthFailedBootstrapException extends SubsurfaceBootstrapException {
  AuthFailedBootstrapException(super.message, {super.cause});
}

class PlatformNotSupportedBootstrapException
    extends SubsurfaceBootstrapException {
  PlatformNotSupportedBootstrapException([String? message])
      : super(message ??
            'Subsurface bootstrap-import is not available on this platform');
}

// ── Progress events ─────────────────────────────────────────────────

/// Stream-based progress events emitted by [SubsurfaceBootstrapImporter.import].
sealed class SubsurfaceBootstrapEvent {
  const SubsurfaceBootstrapEvent();
}

/// Emitted once at the start, before any network I/O.
class CloningRepo extends SubsurfaceBootstrapEvent {
  const CloningRepo();
}

/// Emitted after the clone+pull, with the count of candidate dive
/// folders found on disk. The UI uses this to size the progress bar.
class WalkingRepo extends SubsurfaceBootstrapEvent {
  const WalkingRepo({required this.totalCandidateDives});
  final int totalCandidateDives;
}

/// Emitted before each dive is processed (including ones that turn out
/// to be already-imported or unmappable, so the count keeps moving).
/// [index] is 1-based and [total] is the total candidate count.
class ImportingDive extends SubsurfaceBootstrapEvent {
  const ImportingDive({
    required this.index,
    required this.total,
    required this.diveLabel,
  });
  final int index;
  final int total;

  /// Short human label, e.g. `Dive #705 — De kiekuut`. Falls back to
  /// the folder name when the mapper can't produce a real dive number
  /// or site name.
  final String diveLabel;
}

/// Terminal success event. Followed by stream completion.
class BootstrapDone extends SubsurfaceBootstrapEvent {
  const BootstrapDone(this.result);
  final SubsurfaceBootstrapResult result;
}

/// Terminal failure event. Followed by stream completion.
class BootstrapFailed extends SubsurfaceBootstrapEvent {
  const BootstrapFailed(this.exception);
  final SubsurfaceBootstrapException exception;
}

// ── Data-access seam ────────────────────────────────────────────────

/// Read/write seam the importer uses to interact with CCRLog state.
///
/// Defining it as an interface (rather than depending on the concrete
/// PowerSync-backed DAOs) is what lets the importer test cleanly with
/// in-memory fakes — booting PowerSync per test is expensive. The
/// production wiring is [DaoBootstrapDataSource], which is a thin
/// adapter over the real DAOs.
abstract class BootstrapDataSource {
  /// Existing-dive lookup keyed by `(dcSerial, startTimeUnixSeconds)`.
  /// The importer uses this to dedupe against dives already in CCRLog
  /// from a Petrel BLE pull or a previous bootstrap run.
  Future<Set<({int dcSerial, int startTime})>> existingDiveKeys();

  /// Atomically import a Subsurface-derived dive bundle. Mirrors
  /// `DiveDao.importDive`. The importer always passes
  /// `rawBlob: Uint8List(0)` and
  /// `parserVersion: kSubsurfaceImportedParserVersion`.
  Future<bool> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
  });

  /// Upsert the dive's annotation row.
  Future<void> upsertAnnotation(DiveAnnotation annotation);
}

/// Production [BootstrapDataSource] that delegates to the real DAOs.
///
/// Pure plumbing — no business logic, no caching. Lives alongside
/// [SubsurfaceBootstrapImporter] so app_shell.dart doesn't need to
/// import every DAO type just to build the importer.
class DaoBootstrapDataSource implements BootstrapDataSource {
  DaoBootstrapDataSource({
    required DiveDao diveDao,
    required DiveAnnotationsDao annotationsDao,
  })  : _diveDao = diveDao,
        _annotationsDao = annotationsDao;

  final DiveDao _diveDao;
  final DiveAnnotationsDao _annotationsDao;

  @override
  Future<Set<({int dcSerial, int startTime})>> existingDiveKeys() async {
    final dives = await _diveDao.getAllDives();
    return {
      for (final d in dives) (dcSerial: d.dcSerial, startTime: d.startTime),
    };
  }

  @override
  Future<bool> importDive({
    required ConvertedDive converted,
    required Uint8List rawBlob,
    required int parserVersion,
  }) =>
      _diveDao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: parserVersion,
      );

  @override
  Future<void> upsertAnnotation(DiveAnnotation annotation) =>
      _annotationsDao.upsert(annotation);
}

// ── Importer ────────────────────────────────────────────────────────

/// Repo-factory signature used so tests can substitute a fake
/// [SubsurfaceRepo] without booting libgit2 or hitting a file:// remote.
/// Production wiring uses the default factory which constructs a real
/// [SubsurfaceRepo].
typedef BootstrapRepoFactory = SubsurfaceRepo Function({
  required Directory localDir,
  required String remoteUrl,
  required SubsurfaceCredentialsSource credentials,
});

/// The bootstrap-import orchestrator.
///
/// Construct once per Settings-screen lifetime. Each call to [import]
/// returns a fresh [Stream] of [SubsurfaceBootstrapEvent]s; subsequent
/// calls work too (the clone is reused), but in practice the Settings
/// UI only invokes one run per user gesture.
class SubsurfaceBootstrapImporter {
  SubsurfaceBootstrapImporter({
    required SubsurfaceCredentialsSource credentials,
    required Directory localCloneRoot,
    required BootstrapDataSource dataSource,
    SubsurfaceToCcrlogMapper? mapper,
    BootstrapRepoFactory? repoFactory,
    DateTime Function()? clock,
  })  : _credentials = credentials,
        _localCloneRoot = localCloneRoot,
        _data = dataSource,
        _mapper = mapper ?? SubsurfaceToCcrlogMapper(),
        _repoFactory = repoFactory ??
            ((
                    {required Directory localDir,
                    required String remoteUrl,
                    required SubsurfaceCredentialsSource credentials}) =>
                SubsurfaceRepo(
                  localDir: localDir,
                  remoteUrl: remoteUrl,
                  credentials: credentials,
                )),
        _clock = clock ?? DateTime.now;

  final SubsurfaceCredentialsSource _credentials;
  final Directory _localCloneRoot;
  final BootstrapDataSource _data;
  final SubsurfaceToCcrlogMapper _mapper;
  final BootstrapRepoFactory _repoFactory;
  final DateTime Function() _clock;

  /// Mirrors [SubsurfaceRepo.isPlatformSupported]. False on iOS;
  /// callers (Settings UI) check this before enabling the button.
  bool get isPlatformSupported => SubsurfaceRepo.isPlatformSupported;

  /// In tests we sometimes want to point at a local file:// bare remote
  /// rather than Subsurface Cloud. Defaults to the cloud URL for the
  /// credentials' email.
  String? remoteUrlOverride;

  /// Run a full bootstrap import. Returns a one-shot stream of events
  /// terminated by either [BootstrapDone] or [BootstrapFailed]. The
  /// stream completes after the terminal event.
  Stream<SubsurfaceBootstrapEvent> import() {
    final controller = StreamController<SubsurfaceBootstrapEvent>();
    // Run the import asynchronously so the stream is returned to the
    // caller before any work happens — the UI subscribes synchronously
    // and would otherwise miss early events.
    scheduleMicrotask(() async {
      try {
        await _run(controller);
      } catch (e, st) {
        // _run() catches every expected exception and emits
        // BootstrapFailed; this catch is a last-resort safety net for
        // anything that slipped through (e.g. a bug in the mapper).
        controller.add(BootstrapFailed(SubsurfaceBootstrapException(
          'Unexpected error: $e',
          cause: e,
        )));
        // Surface the stack to debug logs without crashing the app.
        assert(() {
          // ignore: avoid_print
          print('Bootstrap import unexpected error: $e\n$st');
          return true;
        }());
      } finally {
        await controller.close();
      }
    });
    return controller.stream;
  }

  Future<void> _run(StreamController<SubsurfaceBootstrapEvent> out) async {
    // 1. Platform gate.
    if (!isPlatformSupported) {
      out.add(BootstrapFailed(PlatformNotSupportedBootstrapException()));
      return;
    }

    // 2. Credentials gate.
    final creds = await _credentials.read();
    if (creds == null) {
      out.add(BootstrapFailed(NoCredentialsBootstrapException()));
      return;
    }

    // 3. Build / open the local clone. Note the `-bootstrap` suffix —
    // the write-direction clone (currently dormant) lives at
    // `<root>/<email>/`; we use a separate dir so its state can never
    // bleed into ours.
    final repoDir = Directory(
      p.join(_localCloneRoot.path, '${creds.email}-bootstrap'),
    );
    if (!repoDir.existsSync()) {
      repoDir.createSync(recursive: true);
    }
    final repo = _repoFactory(
      localDir: repoDir,
      remoteUrl: remoteUrlOverride ?? SubsurfaceRepo.urlForEmail(creds.email),
      credentials: _credentials,
    );

    out.add(const CloningRepo());
    try {
      await repo.ensureCloned();
    } on PlatformNotSupportedException catch (e) {
      out.add(BootstrapFailed(PlatformNotSupportedBootstrapException(e.message)));
      return;
    } on GitAuthException catch (e) {
      out.add(BootstrapFailed(AuthFailedBootstrapException(e.message, cause: e)));
      return;
    } on GitException catch (e) {
      out.add(BootstrapFailed(SubsurfaceBootstrapException(
        'clone failed: ${e.message}',
        cause: e,
      )));
      return;
    }

    // 4. Pull (fast-forward only). PullConflictException is non-fatal
    // here — bootstrap is read-only; any divergence on the local clone
    // is irrelevant because we never push. The orchestrator's
    // write-direction policy doesn't apply.
    try {
      await repo.pull();
    } on GitAuthException catch (e) {
      out.add(BootstrapFailed(AuthFailedBootstrapException(e.message, cause: e)));
      return;
    } on PullConflictException {
      // Continue anyway — a divergent local clone might still hold
      // useful dive folders. If it doesn't, the walk just yields zero
      // candidates and we report 0 imported.
    } on GitException catch (e) {
      out.add(BootstrapFailed(SubsurfaceBootstrapException(
        'pull failed: ${e.message}',
        cause: e,
      )));
      return;
    }

    // 5. Walk the clone tree. We don't reuse RemoteSnapshot here —
    // its output shape is tailored to the WRITE planner and would
    // throw away too much of what the read mapper needs (the dive
    // file lines, the site lines).
    final candidates = _enumerateDiveFolders(repoDir);
    out.add(WalkingRepo(totalCandidateDives: candidates.length));

    // 6. Existing-key set — done once; any dive imported during the
    // walk is added to this set on success so a duplicate folder
    // (Subsurface multi-DC dives, hand-edited entries) is dedup'd
    // against the just-imported one too.
    final existing = await _data.existingDiveKeys();

    // Cache parsed sites lazily — the same site is referenced by many
    // dives (every "De Berendonck" dive points to the same Site-<id>),
    // so re-reading the file per dive is wasteful.
    final siteCache = <String, List<SsLine>?>{};

    var imported = 0;
    var skipped = 0;
    var unmappable = 0;

    for (var i = 0; i < candidates.length; i++) {
      final folder = candidates[i];
      // Best-effort label for the progress UI. Updated after parsing
      // when we have a real Dive-NNN.
      var label = folder.folderName;

      final parsed = _parseDiveFolder(folder);
      if (parsed == null) {
        // Folder didn't yield enough to even attempt mapping (no
        // Divecomputer file, malformed folder name, etc). Bucket as
        // unmappable.
        out.add(ImportingDive(index: i + 1, total: candidates.length, diveLabel: label));
        unmappable++;
        continue;
      }

      label = 'Dive #${parsed.diveNumber}';

      // Resolve site lines via divesiteid if present.
      List<SsLine>? siteLines;
      final siteId = _findDivesiteId(parsed.diveLines);
      if (siteId != null) {
        siteLines = siteCache.putIfAbsent(
          siteId,
          () => _readSiteFile(repoDir, siteId),
        );
      }

      out.add(ImportingDive(
        index: i + 1,
        total: candidates.length,
        diveLabel: label,
      ));

      final imported0 = _mapper.mapDive(
        diveLines: parsed.diveLines,
        divecomputerLines: parsed.divecomputerLines,
        siteLines: siteLines,
        startTime: parsed.startTime,
        subsurfaceDiveNumber: parsed.diveNumber,
      );
      if (imported0 == null) {
        unmappable++;
        continue;
      }

      final converted = imported0.converted;
      final key = (
        dcSerial: converted.dive.dcSerial,
        startTime:
            converted.dive.startTime.millisecondsSinceEpoch ~/ 1000,
      );
      if (existing.contains(key)) {
        skipped++;
        continue;
      }

      try {
        final isNew = await _data.importDive(
          converted: converted,
          rawBlob: Uint8List(0),
          parserVersion: kSubsurfaceImportedParserVersion,
        );
        if (imported0.annotation != null) {
          await _data.upsertAnnotation(imported0.annotation!);
        }
        if (isNew) {
          imported++;
          existing.add(key);
        } else {
          // DAO reported existing id — could happen on a re-run where
          // an earlier bootstrap import already brought this dive in
          // but our key set didn't include it (race / refresh delay).
          skipped++;
        }
      } catch (e) {
        // Per-dive failures don't abort the whole run; bucket as
        // unmappable so the user sees a non-zero count and we keep
        // going. A run with hundreds of dives would otherwise fail
        // cold on the first malformed fixture.
        unmappable++;
      }
    }

    out.add(BootstrapDone(SubsurfaceBootstrapResult(
      divesImported: imported,
      divesSkipped: skipped,
      divesUnmappable: unmappable,
      completedAt: _clock(),
    )));
  }

  // ── Filesystem walking ─────────────────────────────────────────────

  /// One discovered dive folder, ready for parsing.
  static List<_DiveFolder> _enumerateDiveFolders(Directory repoRoot) {
    final out = <_DiveFolder>[];
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
          if (!_dayFolderRe.hasMatch(dName)) continue;
          final startTime = _parseDayFolderName(yName, mName, dName);
          if (startTime == null) continue;
          out.add(_DiveFolder(
            folder: dEntity,
            yearSegment: yName,
            monthSegment: mName,
            daySegment: dName,
            folderName: '$yName/$mName/$dName',
            startTime: startTime,
          ));
        }
      }
    }
    // Stable order — chronological matches the user's intuition for a
    // progress bar ("oldest dive first → newest").
    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    return out;
  }

  /// Read + parse one dive folder. Returns null when the folder
  /// doesn't contain a `Divecomputer*` file or any `Dive-NNN` file —
  /// those are the minimum a Subsurface dive folder needs to be
  /// importable.
  static _ParsedDiveFolder? _parseDiveFolder(_DiveFolder f) {
    File? diveFile;
    int? diveNumber;
    File? dcFile;
    try {
      for (final entity in f.folder.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('Dive-')) {
          final n = int.tryParse(name.substring('Dive-'.length));
          if (n != null && (diveNumber == null || n > diveNumber)) {
            diveNumber = n;
            diveFile = entity;
          }
        } else if (name == 'Divecomputer' ||
            name.startsWith('Divecomputer-')) {
          // Prefer bare `Divecomputer`; otherwise the first
          // `Divecomputer-NNN` we encounter. Multiple-DC dives are rare
          // and the read mapper currently picks one DC's view of the
          // dive, same as Subsurface itself when there's no UI choice.
          dcFile ??= entity;
          if (name == 'Divecomputer') dcFile = entity;
        }
      }
    } on FileSystemException {
      return null;
    }

    if (diveFile == null || diveNumber == null || dcFile == null) {
      return null;
    }

    try {
      final diveText = diveFile.readAsStringSync();
      final dcText = dcFile.readAsStringSync();
      final diveParsed = parseSubsurfaceFile(
        diveText,
        kind: SubsurfaceFileKind.dive,
      );
      final dcParsed = parseSubsurfaceFile(
        dcText,
        kind: SubsurfaceFileKind.divecomputer,
      );
      return _ParsedDiveFolder(
        diveNumber: diveNumber,
        startTime: f.startTime,
        diveLines: diveParsed.lines,
        divecomputerLines: dcParsed.lines,
      );
    } catch (_) {
      return null;
    }
  }

  /// Pull `divesiteid <hex>` from a Dive-NNN file's parsed lines.
  /// Subsurface emits this as a [ScalarLine].
  static String? _findDivesiteId(List<SsLine> diveLines) {
    for (final l in diveLines) {
      if (l is ScalarLine && l.key == 'divesiteid') {
        final v = l.value.trim();
        if (v.isEmpty) return null;
        return v;
      }
    }
    return null;
  }

  /// Read + parse `01-Divesites/Site-<id>` for the given hex id.
  /// Returns null when the file is missing or fails to parse — the
  /// mapper tolerates a null `siteLines` (annotation just lacks site
  /// coords).
  static List<SsLine>? _readSiteFile(Directory repoRoot, String hexId) {
    final f = File(p.join(repoRoot.path, '01-Divesites', 'Site-$hexId'));
    if (!f.existsSync()) return null;
    try {
      final text = f.readAsStringSync();
      return parseSubsurfaceFile(text, kind: SubsurfaceFileKind.site).lines;
    } catch (_) {
      return null;
    }
  }

  /// Parse `<YYYY>/<MM>/<DD>-<Day>-<HH>=<MM>=<SS>` into a UTC
  /// [DateTime]. The Day-of-week token is ignored (it's redundant with
  /// the date and may not match for hand-edited folders).
  static DateTime? _parseDayFolderName(
    String yyyy,
    String mm,
    String dayPart,
  ) {
    final yi = int.tryParse(yyyy);
    final mi = int.tryParse(mm);
    if (yi == null || mi == null) return null;
    final m = _dayFolderRe.firstMatch(dayPart);
    if (m == null) return null;
    final dd = int.parse(m.group(1)!);
    final hh = int.parse(m.group(3)!);
    final mn = int.parse(m.group(4)!);
    final ss = int.parse(m.group(5)!);
    return DateTime.utc(yi, mi, dd, hh, mn, ss);
  }

  static final RegExp _dayFolderRe =
      RegExp(r'^(\d{2})-([A-Za-z]{3})-(\d{2})=(\d{2})=(\d{2})$');

  static bool _isFourDigit(String s) =>
      s.length == 4 && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  static bool _isTwoDigit(String s) =>
      s.length == 2 && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
}

class _DiveFolder {
  _DiveFolder({
    required this.folder,
    required this.yearSegment,
    required this.monthSegment,
    required this.daySegment,
    required this.folderName,
    required this.startTime,
  });

  final Directory folder;
  final String yearSegment;
  final String monthSegment;
  final String daySegment;

  /// Human-readable label, e.g. `2026/04/04-Sat-13=30=15`.
  final String folderName;

  /// UTC start moment derived from the folder name.
  final DateTime startTime;
}

class _ParsedDiveFolder {
  _ParsedDiveFolder({
    required this.diveNumber,
    required this.startTime,
    required this.diveLines,
    required this.divecomputerLines,
  });

  final int diveNumber;
  final DateTime startTime;
  final List<SsLine> diveLines;
  final List<SsLine> divecomputerLines;
}
