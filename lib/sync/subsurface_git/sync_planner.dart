/// Phase D — pure-Dart sync planner.
///
/// The planner walks CCRLog state plus a parsed snapshot of the cloned
/// Subsurface repo and emits a [SyncPlan] describing every file write
/// the orchestrator should perform. This file does no I/O and knows
/// nothing about git — it's deliberately easy to unit-test.
///
/// Why pure-Dart: Phase A (parser/serializer) and Phase B (mapper) are
/// already pure-Dart, so layering the *planning* on top of them lets us
/// drive the whole CCRLog → Subsurface transformation in tests without
/// booting PowerSync, libgit2, or the filesystem. The orchestrator
/// (Phase D, [SubsurfaceSyncOrchestrator]) handles the impure half:
/// reading DAOs, calling [RemoteSnapshot], writing files, and pushing.
///
/// Two non-obvious behaviours, lifted from
/// `docs/subsurface_format_notes.md`:
///
/// 1. **Top-level `divecomputerid` dedup is keyed on `serial`, not on
///    `deviceid`.** Subsurface computes `deviceid` via a libdc-side
///    hash of (model + serial); we don't have that hash, so we emit a
///    stable derivative. If we deduped on our `deviceid` we'd happily
///    let two `divecomputerid` lines coexist for the same physical
///    computer — one libdc-imported, one CCRLog-emitted. We dedup on
///    `serial`, the field that actually identifies the hardware, and
///    keep whichever line is already in the file (so we don't blow
///    away a Subsurface-imported entry that has the "right" deviceid).
///
/// 2. **Existing dives are matched on `(serial, startTime)`.** When a
///    CCRLog dive matches an existing remote dive, we reuse its folder
///    name and `Dive-NNN` number rather than allocating a fresh NNN. This
///    avoids double-emitting the same dive after the user pushes once
///    from CCRLog and once via Subsurface itself.
library;

import 'format/subsurface_format.dart';
import 'format/subsurface_serializer.dart';
import 'mapper.dart';

import '../../data/db/database.dart' show Cylinder, Dive, DiveComputer;
import '../../data/models/annotation.dart';
import '../../data/models/dive.dart' show DiveGasMix, DiveTank;
import '../../data/models/sample_set.dart';

/// Bundles one CCRLog dive with everything the mapper needs to emit it.
///
/// The orchestrator builds these from its DAO calls and hands the list
/// to the planner. The planner doesn't talk to DAOs itself — that keeps
/// it pure.
class CcrlogDiveBundle {
  CcrlogDiveBundle({
    required this.dive,
    required this.samples,
    required this.annotation,
    required this.gasMixes,
    required this.tanks,
    required this.cylindersByMixIndex,
    required this.userDiveComputers,
  });

  final Dive dive;
  final SampleSet samples;
  final DiveAnnotation? annotation;
  final List<DiveGasMix> gasMixes;
  final List<DiveTank> tanks;
  final Map<int, Cylinder> cylindersByMixIndex;

  /// All known CCRLog dive computers — the mapper uses these to build
  /// the top-level `divecomputerid` lines. The same list is passed for
  /// every bundle (it's a property of the user's setup, not the dive).
  /// We carry it on the bundle for symmetry with the rest of the state.
  final List<DiveComputer> userDiveComputers;
}

/// One existing dive, recovered from the remote-repo snapshot.
class ExistingRemoteDive {
  ExistingRemoteDive({
    required this.folderSegments,
    required this.diveNumber,
    required this.serial,
    required this.startTime,
    required this.diveLines,
  });

  /// Folder path components, e.g. `['2026', '04', '04-Sat-13=30=15']`.
  final List<String> folderSegments;

  /// `Dive-NNN` integer found inside the folder.
  final int diveNumber;

  /// Decoded from the `Divecomputer` keyvalue `Serial` (hex-encoded).
  /// Null when the remote dive's `Divecomputer` had no `Serial` line
  /// (very old / manual entries) — those won't ever match a CCRLog dive
  /// because CCRLog dives always carry `dcSerial`.
  final int? serial;

  /// Decoded from the folder name's UTC components, mirroring how the
  /// mapper formats it. Null when the folder name was malformed.
  final int? startTime;

  /// The parsed lines of `<folder>/Dive-NNN` at scan time. The merge in
  /// the planner uses these as the existing baseline to substitute
  /// CCRLog-owned lines into. Empty list is valid (a Dive-NNN with no
  /// content); null is not — populated via [RemoteSnapshot.read].
  final List<SsLine> diveLines;
}

/// Diagnostic counters the orchestrator surfaces in its result.
class SyncPlanStats {
  SyncPlanStats({
    required this.newDives,
    required this.updatedDives,
    required this.skippedDives,
    required this.abortedDives,
  });

  final int newDives;
  final int updatedDives;

  /// CCRLog dives that already match the remote byte-for-byte — no
  /// rewrite needed. These don't appear in [SyncPlan.diveIdsPlanned]
  /// because the orchestrator should not stamp `subsurface_uploaded_at`
  /// on a dive that didn't actually end up in this commit.
  final int skippedDives;

  /// Dives the planner declined to write because of a foreign edit on
  /// the Subsurface side. Surfaced to the user as "Skipped".
  final int abortedDives;
}

/// Why a per-dive plan was aborted. Surfaced to the user in the UI's
/// "Skipped" status block; not an error condition.
enum AbortReason {
  /// CCRLog's planned write would change the Divecomputer file for a
  /// dive Subsurface already has. The Divecomputer file is sacred to
  /// the DC that recorded it — we never overwrite it in Phase 1.
  divecomputerProtected,

  /// The existing Dive-NNN file on disk has differences in lines
  /// CCRLog doesn't own (e.g. user-edited cylinder, a Subsurface-only
  /// scalar key we don't recognise, a manually-tuned duration). We
  /// decline to overwrite rather than risk losing the user's edits.
  foreignEditConflict,
}

/// One dive that the planner declined to write. Aborts are not
/// exceptions: sync still succeeds for the other dives in the same
/// run.
class AbortedDive {
  AbortedDive({
    required this.dive,
    required this.reason,
    required this.conflictingLines,
  });

  final Dive dive;
  final AbortReason reason;

  /// The line keys (e.g. `cylinder`, `duration`) that triggered a
  /// `foreignEditConflict`. Empty for other reasons. Surfaced to the
  /// user verbatim so they can find the offending field.
  final List<String> conflictingLines;
}

class SyncPlan {
  SyncPlan({
    required this.filesToWrite,
    required this.diveIdsPlanned,
    required this.stats,
    required this.abortedDives,
  });

  /// Files to (re)write. Keys are POSIX paths relative to the repo
  /// root. Includes Dive-NNN, Divecomputer, Site-XXXX, and the merged
  /// 00-Subsurface (when the merge produced a different output than the
  /// existing file).
  final Map<String, String> filesToWrite;

  /// CCRLog dive ids that the planner included in this plan, in the
  /// order they were planned. Used by the orchestrator to mark them
  /// uploaded after a successful push.
  final List<String> diveIdsPlanned;

  final SyncPlanStats stats;

  /// Dives the planner declined to write, with reasons.
  final List<AbortedDive> abortedDives;
}

class SyncPlanner {
  SyncPlanner({CcrlogToSubsurfaceMapper? mapper})
      : _mapper = mapper ?? CcrlogToSubsurfaceMapper();

  final CcrlogToSubsurfaceMapper _mapper;

  /// Dive-NNN line keys CCRLog owns. For existing dives the merge only
  /// replaces lines matching these keys when CCRLog has a non-empty
  /// value; every other key is left verbatim. Spec:
  /// docs/superpowers/specs/2026-05-11-subsurface-write-direction-phase-1-design.md
  static const _ownedDiveLineKeys = {
    'rating',
    'visibility',
    'wavesize',
    'current',
    'surge',
    'chill',
    'airtemp',
    'watertemp',
    'tags',
    'buddy',
    'suit',
    'notes',
    'divesiteid',
    'weightsystem',
    // divemaster is always emitted by the mapper as empty; treat as
    // owned so we don't trip a foreign-edit conflict on Subsurface's
    // identical empty line.
    'divemaster',
  };

  /// Build a plan from CCRLog state + the parsed remote-repo snapshot.
  ///
  /// See the type docs above for what each input means; in particular:
  /// - [existingDivesBySerialAndStart] is consulted to reuse folder /
  ///   dive-number assignments.
  /// - [existingMaxDiveNumber] is the highest `Dive-NNN` seen on the
  ///   remote so new dives get NNN+1, NNN+2, ...
  /// - [existingTopLevel] is merged into so we don't blow away
  ///   Subsurface- or libdc-imported state.
  /// - [existingSites] is merged into so user-typed
  ///   description/notes/geo lines on existing Site files are preserved
  ///   (CCRLog only owns `name` + `gps`).
  SyncPlan plan({
    required List<CcrlogDiveBundle> ccrlogDives,
    required Map<({int serial, int startTime}), ExistingRemoteDive>
        existingDivesBySerialAndStart,
    required int existingMaxDiveNumber,
    required List<SsLine> existingTopLevel,
    required Map<String, List<SsLine>> existingSites,
  }) {
    final filesToWrite = <String, String>{};
    final diveIdsPlanned = <String>[];
    final newDives = <Dive>[];
    final updatedDives = <Dive>[];
    final abortedDives = <AbortedDive>[];
    var skipped = 0;

    var nextDiveNumber = existingMaxDiveNumber;

    // Mapped sites accumulate keyed by hexId so two CCRLog dives at the
    // same lat/lon collapse to one Site write. Last writer wins on
    // collision (they're equivalent — same hexId implies same coords).
    final mappedSitesByHexId = <String, MappedSite>{};

    // Track the userDiveComputers we encountered (for the top-level
    // delta). The bundles all carry the same list, but we don't want to
    // assume that — gather seen ones and dedup by serial.
    final dcsBySerial = <int, DiveComputer>{};

    for (final bundle in ccrlogDives) {
      final dive = bundle.dive;
      final key = (serial: dive.dcSerial, startTime: dive.startTime);
      final existing = existingDivesBySerialAndStart[key];

      final int diveNumber;
      final List<String> folderSegments;

      if (existing != null) {
        // ── Existing dive: merge CCRLog-owned lines, never touch Divecomputer
        diveNumber = existing.diveNumber;
        folderSegments = existing.folderSegments;

        // If the scan failed to parse the on-disk Dive-NNN (corrupt or
        // unreadable file but the sibling Divecomputer parsed and gave us
        // the (serial, startTime) match), diveLines is empty. Merging
        // against an empty baseline would write the full CCRLog emission
        // as if it were a brand-new dive — exactly the silent-overwrite
        // class of bug Phase 1 exists to prevent. Abort instead.
        if (existing.diveLines.isEmpty) {
          abortedDives.add(AbortedDive(
            dive: dive,
            reason: AbortReason.foreignEditConflict,
            conflictingLines: const ['<unreadable Dive-NNN>'],
          ));
          continue;
        }

        final ours = _mapper.mapDive(
          dive: dive,
          samples: bundle.samples,
          annotation: bundle.annotation,
          gasMixes: bundle.gasMixes,
          tanks: bundle.tanks,
          cylindersByMixIndex: bundle.cylindersByMixIndex,
          nextSubsurfaceDiveNumber: diveNumber,
        );

        final mergeResult = _mergeDiveLines(
          existing: existing.diveLines,
          ours: ours.diveLines,
        );

        if (mergeResult.merged == null) {
          abortedDives.add(AbortedDive(
            dive: dive,
            reason: AbortReason.foreignEditConflict,
            conflictingLines: mergeResult.conflictingKeys,
          ));
          continue; // skip this dive entirely — no site/dc side-effects
        }

        final mergedText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mergeResult.merged!),
        );
        final existingText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: existing.diveLines),
        );

        if (mergedText == existingText) {
          skipped += 1;
          // Fall through so site / 00-Subsurface side-effects still run.
        } else {
          final folderPath = folderSegments.join('/');
          filesToWrite['$folderPath/Dive-$diveNumber'] = mergedText;
          diveIdsPlanned.add(dive.id);
          updatedDives.add(dive);
        }
        // CRITICAL: never emit the Divecomputer file for an existing dive.
      } else {
        // ── New dive: full Dive-NNN + Divecomputer write
        nextDiveNumber += 1;
        diveNumber = nextDiveNumber;
        folderSegments = _utcFolderSegments(dive.startTime);

        final mapped = _mapper.mapDive(
          dive: dive,
          samples: bundle.samples,
          annotation: bundle.annotation,
          gasMixes: bundle.gasMixes,
          tanks: bundle.tanks,
          cylindersByMixIndex: bundle.cylindersByMixIndex,
          nextSubsurfaceDiveNumber: diveNumber,
        );

        final folderPath = folderSegments.join('/');
        filesToWrite['$folderPath/Dive-$diveNumber'] = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mapped.diveLines),
        );
        filesToWrite['$folderPath/Divecomputer'] = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mapped.divecomputerLines),
        );
        diveIdsPlanned.add(dive.id);
        newDives.add(dive);
      }

      // Site: map → merge with existing → stage write.
      if (bundle.annotation != null) {
        final mappedSite = _mapper.mapSite(bundle.annotation!);
        if (mappedSite != null) {
          mappedSitesByHexId[mappedSite.hexId] = mappedSite;
        }
      }

      for (final dc in bundle.userDiveComputers) {
        dcsBySerial.putIfAbsent(dc.serial, () => dc);
      }
    }

    // Emit Site files (merged with existing user-edited fields).
    for (final entry in mappedSitesByHexId.entries) {
      final hexId = entry.key;
      final mapped = entry.value;
      final existingLines = existingSites[hexId];
      final mergedLines = existingLines == null
          ? mapped.lines
          : _mergeSiteLines(
              existing: existingLines,
              ours: mapped.lines,
            );
      final text = serializeSubsurfaceFile(
        SubsurfaceFile(lines: mergedLines),
      );
      filesToWrite['01-Divesites/Site-$hexId'] = text;
    }

    // 00-Subsurface: merge our delta into the existing top-level file.
    final delta = _mapper.topLevelDelta(
      dives: [...newDives, ...updatedDives],
      diveComputers: dcsBySerial.values,
    );
    final mergedTopLevel = _mergeTopLevel(
      existing: existingTopLevel,
      delta: delta,
    );
    final mergedTopLevelText = serializeSubsurfaceFile(
      SubsurfaceFile(lines: mergedTopLevel),
    );
    final existingTopLevelText = serializeSubsurfaceFile(
      SubsurfaceFile(lines: existingTopLevel),
    );
    if (mergedTopLevelText != existingTopLevelText) {
      filesToWrite['00-Subsurface'] = mergedTopLevelText;
    }

    return SyncPlan(
      filesToWrite: filesToWrite,
      diveIdsPlanned: diveIdsPlanned,
      stats: SyncPlanStats(
        newDives: newDives.length,
        updatedDives: updatedDives.length,
        skippedDives: skipped,
        abortedDives: abortedDives.length,
      ),
      abortedDives: abortedDives,
    );
  }

  // ── Dive-NNN merge ─────────────────────────────────────────────────

  /// Merge our CCRLog-emitted Dive-NNN lines into [existing], replacing
  /// only lines whose key is in [_ownedDiveLineKeys]. Returns either a
  /// merged line list (non-owned lines untouched) OR a non-empty
  /// [conflictingKeys] list if any non-owned line would change.
  ({List<SsLine>? merged, List<String> conflictingKeys}) _mergeDiveLines({
    required List<SsLine> existing,
    required List<SsLine> ours,
  }) {
    // Bucket our emission by key.
    final ourSingleByKey = <String, SsLine>{};
    final ourRepeatingByKey = <String, List<SsLine>>{};
    for (final line in ours) {
      final key = _lineKey(line);
      if (key == null) continue;
      if (key == 'weightsystem' || key == 'cylinder') {
        ourRepeatingByKey.putIfAbsent(key, () => []).add(line);
      } else {
        ourSingleByKey[key] = line;
      }
    }

    // 1) Detect conflicts on non-owned keys. If we emit anything for a
    // non-owned key (defensively) AND it would change the existing line,
    // flag. For non-owned repeating keys like `cylinder`, compare the
    // whole group.
    final conflictingKeys = <String>{};
    final seenKeys = <String>{};
    for (final line in existing) {
      final key = _lineKey(line);
      if (key == null) continue;
      if (_ownedDiveLineKeys.contains(key)) continue;
      if (seenKeys.contains(key)) continue; // already compared this group
      seenKeys.add(key);
      if (ourSingleByKey.containsKey(key)) {
        if (_renderLine(line) != _renderLine(ourSingleByKey[key]!)) {
          conflictingKeys.add(key);
        }
      } else if (ourRepeatingByKey.containsKey(key)) {
        final existingGroup = existing
            .where((l) => _lineKey(l) == key)
            .map(_renderLine)
            .toList();
        final ourGroup = ourRepeatingByKey[key]!.map(_renderLine).toList();
        if (!_listEquals(existingGroup, ourGroup)) {
          conflictingKeys.add(key);
        }
      }
    }
    if (conflictingKeys.isNotEmpty) {
      return (
        merged: null,
        conflictingKeys: conflictingKeys.toList()..sort(),
      );
    }

    // 2) Build merged output. Walk existing lines, swap owned ones for
    // ours when we have something. Track placement so we can append the
    // rest at the end (preserves insertion order from the mapper).
    final placedSingles = <String>{};
    final placedRepeating = <String>{};
    final merged = <SsLine>[];
    for (final line in existing) {
      final key = _lineKey(line);
      if (key == null) {
        merged.add(line);
        continue;
      }
      if (!_ownedDiveLineKeys.contains(key)) {
        merged.add(line);
        continue;
      }
      // Owned key.
      if (ourRepeatingByKey.containsKey(key)) {
        if (!placedRepeating.contains(key)) {
          merged.addAll(ourRepeatingByKey[key]!);
          placedRepeating.add(key);
        }
        // Drop the existing line — the whole group is replaced by ours.
        continue;
      }
      if (ourSingleByKey.containsKey(key)) {
        merged.add(ourSingleByKey[key]!);
        placedSingles.add(key);
        continue;
      }
      // CCRLog has nothing for this owned key. Leave existing.
      merged.add(line);
    }
    // 3) Append owned lines we have but the existing file didn't.
    // CRITICAL: only owned keys, otherwise non-owned keys we happen to
    // also emit (e.g. `duration`) get duplicated on top of the line
    // we already preserved verbatim from `existing`.
    for (final entry in ourSingleByKey.entries) {
      if (!_ownedDiveLineKeys.contains(entry.key)) continue;
      if (placedSingles.contains(entry.key)) continue;
      merged.add(entry.value);
    }
    for (final entry in ourRepeatingByKey.entries) {
      if (!_ownedDiveLineKeys.contains(entry.key)) continue;
      if (placedRepeating.contains(entry.key)) continue;
      merged.addAll(entry.value);
    }
    return (merged: merged, conflictingKeys: const []);
  }

  /// Return the key for any [SsLine] that has one, else null.
  ///
  /// `EventLine` / `SampleLine` live in `divecomputerLines`, not the
  /// `diveLines` this merge runs over — returning null for them (via the
  /// catch-all) is correct. If a future change ever emits them into
  /// `diveLines`, they would be treated as keyless and preserved verbatim;
  /// add explicit cases here if the conflict check should examine them.
  String? _lineKey(SsLine line) => switch (line) {
        ScalarLine l => l.key,
        QuotedLine l => l.key,
        TagsLine _ => 'tags',
        CylinderLine _ => 'cylinder',
        WeightsystemLine _ => 'weightsystem',
        GpsLine _ => 'gps',
        DivecomputerIdLine _ => 'divecomputerid',
        FingerprintLine _ => 'fingerprint',
        KeyvaluePairLine l => l.key,
        FlagLine l => l.key,
        _ => null,
      };

  /// Render a single line back to text so two lines can be byte-compared.
  String _renderLine(SsLine line) =>
      serializeSubsurfaceFile(SubsurfaceFile(lines: [line])).trimRight();

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Site merge ─────────────────────────────────────────────────────

  /// Replace the `name` and `gps` lines from [existing] with the values
  /// from [ours]. Everything else (description, notes, geo, anything we
  /// don't recognise) is preserved verbatim. The mapper's site output
  /// is always shaped as `[name, description, notes, gps]`; we pull
  /// those two fields out and overlay them onto the existing file.
  List<SsLine> _mergeSiteLines({
    required List<SsLine> existing,
    required List<SsLine> ours,
  }) {
    QuotedLine? ourName;
    GpsLine? ourGps;
    for (final l in ours) {
      if (l is QuotedLine && l.key == 'name') ourName = l;
      if (l is GpsLine) ourGps = l;
    }

    final result = <SsLine>[];
    var sawName = false;
    var sawGps = false;
    for (final line in existing) {
      if (line is QuotedLine && line.key == 'name' && ourName != null) {
        result.add(QuotedLine(key: 'name', value: ourName.value));
        sawName = true;
      } else if (line is GpsLine && ourGps != null) {
        result.add(GpsLine(lat: ourGps.lat, lon: ourGps.lon));
        sawGps = true;
      } else {
        result.add(line);
      }
    }
    // If existing didn't have a name/gps line at all, append ours so the
    // file is still valid Subsurface output.
    if (!sawName && ourName != null) result.add(ourName);
    if (!sawGps && ourGps != null) result.add(ourGps);
    return result;
  }

  // ── Top-level merge ────────────────────────────────────────────────

  /// Merge our delta into the existing 00-Subsurface lines. Rules:
  /// - `divecomputerid`: dedup on **serial** (not deviceid); keep the
  ///   existing entry when both are present, append new ones at the end
  ///   of the existing dc-id block.
  /// - `fingerprint`: dedup on `(model, serial, deviceid, diveid)`; keep
  ///   the existing entry when both are present, append new ones at the
  ///   end of the existing fingerprint block.
  /// - Everything else (`version`, `units`, `prefs`, raw lines) is left
  ///   in place.
  List<SsLine> _mergeTopLevel({
    required List<SsLine> existing,
    required TopLevelDelta delta,
  }) {
    final existingSerials = <String>{};
    for (final line in existing) {
      if (line is DivecomputerIdLine) {
        final s = _serialOf(line);
        if (s != null) existingSerials.add(s);
      }
    }

    final existingFingerprintKeys = <String>{};
    for (final line in existing) {
      if (line is FingerprintLine) {
        existingFingerprintKeys.add(_fingerprintKey(line));
      }
    }

    // Filter our delta to skip duplicates.
    final newDcIds = <DivecomputerIdLine>[];
    final newDcSerialsSeen = <String>{};
    for (final dc in delta.newDivecomputerIds) {
      final s = _serialOf(dc);
      if (s != null && existingSerials.contains(s)) continue;
      if (s != null && !newDcSerialsSeen.add(s)) continue;
      newDcIds.add(dc);
    }
    final newFps = <FingerprintLine>[];
    final newFpKeysSeen = <String>{};
    for (final fp in delta.newFingerprints) {
      final k = _fingerprintKey(fp);
      if (existingFingerprintKeys.contains(k)) continue;
      if (!newFpKeysSeen.add(k)) continue;
      newFps.add(fp);
    }

    if (newDcIds.isEmpty && newFps.isEmpty) {
      return existing;
    }

    // Find the index after the last existing divecomputerid line; insert
    // new dc-ids there. If there are no existing dc-ids, place them
    // right after the `version` line (if any) or at the start.
    var lastDcIdIdx = -1;
    var lastFingerprintIdx = -1;
    var versionIdx = -1;
    for (var i = 0; i < existing.length; i++) {
      final l = existing[i];
      if (l is DivecomputerIdLine) lastDcIdIdx = i;
      if (l is FingerprintLine) lastFingerprintIdx = i;
      if (l is ScalarLine && l.key == 'version' && versionIdx < 0) {
        versionIdx = i;
      }
    }

    final out = List<SsLine>.from(existing);

    // Insert new fingerprints first (we'll use lastFingerprintIdx that
    // hasn't shifted yet). Pick insertion points relative to the
    // unmodified [existing] list, then apply in reverse so earlier
    // indexes stay valid.
    if (newFps.isNotEmpty) {
      final fpInsertAt = lastFingerprintIdx >= 0
          ? lastFingerprintIdx + 1
          : (lastDcIdIdx >= 0
              ? lastDcIdIdx + 1
              : (versionIdx >= 0 ? versionIdx + 1 : 0));
      out.insertAll(fpInsertAt, newFps);
    }
    if (newDcIds.isNotEmpty) {
      final dcInsertAt = lastDcIdIdx >= 0
          ? lastDcIdIdx + 1
          : (versionIdx >= 0 ? versionIdx + 1 : 0);
      out.insertAll(dcInsertAt, newDcIds);
    }
    return out;
  }

  /// Pull the `serial` field out of a `divecomputerid` line. Field
  /// values are stored as raw lexemes (with surrounding quotes, when
  /// present); we strip the quotes for the dedup key.
  String? _serialOf(DivecomputerIdLine line) {
    for (final e in line.fields) {
      if (e.key == 'serial') {
        var v = e.value;
        if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
          v = v.substring(1, v.length - 1);
        }
        return v;
      }
    }
    return null;
  }

  /// Stable composite key for a fingerprint line — the union of the
  /// fields Subsurface itself uses to identify a unique dive log entry.
  String _fingerprintKey(FingerprintLine line) {
    String? get(String key) {
      for (final e in line.fields) {
        if (e.key == key) return e.value;
      }
      return null;
    }

    return [
      get('model') ?? '',
      get('serial') ?? '',
      get('deviceid') ?? '',
      get('diveid') ?? '',
    ].join('|');
  }

  /// Compute folder segments from a unix-seconds timestamp using UTC
  /// components. Mirrors the mapper's private `_folderSegments` so the
  /// planner can pre-compute paths *before* calling the mapper (we need
  /// the path to register `Dive-NNN` even when reusing an existing
  /// folder).
  List<String> _utcFolderSegments(int startTimeUnixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      startTimeUnixSeconds * 1000,
      isUtc: true,
    );
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final day = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        [(dt.weekday - 1) % 7];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return [yyyy, mm, '$dd-$day-$hh=$mi=$ss'];
  }
}
