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
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix, DiveTank;
import 'package:subsurface_core/data/models/sample_set.dart';

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
    this.divecomputerLines = const [],
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

  /// Parsed lines of the existing `<folder>/Divecomputer` file. CCRLog
  /// normally leaves this file alone (preserves what Subsurface
  /// recorded). The exception is when our mapper has data the existing
  /// file lacks — currently just "SP change" events for the setpoint
  /// trace. Empty when the file is missing or unreadable.
  final List<SsLine> divecomputerLines;
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
    'weightsystem',
    // divemaster is always emitted by the mapper as empty; treat as
    // owned so we don't trip a foreign-edit conflict on Subsurface's
    // identical empty line.
    'divemaster',
    // divesiteid is NOT owned. CCRLog's _siteIdFor() is a SHA-256 of
    // (lat,lon); Subsurface's UUIDs are random-at-site-creation. The
    // two never agree, so substituting CCRLog's hash here rewrites the
    // line on every existing dive that has a site (2026-05-11 smoke:
    // 273 dives flagged as "updated" purely due to this mismatch).
    // Preserving existing's hash keeps Dive-NNN ↔ Site-XXX pointers
    // stable across CCRLog→Subsurface pushes. The site-mapping step
    // below also reuses existing hexes when coords match an existing
    // Site file, so we don't create orphan Site-CCRLOGHASH duplicates.
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

    // Set of dive numbers already present in the remote. Used both to
    // detect collisions and to compute the next available slot for new
    // dives.
    final remoteDiveNumbers = <int>{
      for (final entry in existingDivesBySerialAndStart.values) entry.diveNumber,
    };

    // Whether the remote had any parseable Dive-NNN at the start of this
    // plan. Drives the dc-counter preference below: we only honour the
    // dive computer's own dive number when seeding a fresh Subsurface
    // repo. Once any live dive exists in Subsurface, we switch to
    // sequential numbering — the dive computer's counter may be far
    // ahead of the user's Subsurface logbook (Petrel reset, second-hand
    // DC, dives logged in another tool first) and continuing in lockstep
    // produces giant gaps like Dive-1146 sitting next to Dive-713.
    final remoteHadDives = remoteDiveNumbers.isNotEmpty;

    // Walk forward from the highest *parseable* Dive-NNN, not from
    // `existingMaxDiveNumber` (which counts ALL Dive-NNN filenames,
    // including orphans whose Divecomputer file failed to parse). An
    // orphan Dive-1145 left behind by a corrupted past sync would
    // otherwise push every new dive to 1146+ when the visible-in-
    // Subsurface max is only 712 and the user expects 713. The cost is
    // a theoretical eventual overwrite of the orphan when the sequence
    // catches up to it — fine, the orphan is broken anyway and the
    // existing-merge path would refuse to merge an unreadable Dive-NNN.
    var nextDiveNumber = 0;
    for (final n in remoteDiveNumbers) {
      if (n > nextDiveNumber) nextDiveNumber = n;
    }

    // Process bundles oldest-first so sequential allocations land in
    // chronological order in Subsurface. Without this, callers passing
    // newest-first lists (DiveDao.getAllDives is DESC by start_time)
    // would assign higher dive numbers to earlier dates — the user-
    // visible inversion that prompted this sort.
    final sortedDives = [...ccrlogDives]
      ..sort((a, b) => a.dive.startTime.compareTo(b.dive.startTime));

    // Build coords → existing hexId map from Subsurface's Site files.
    // Subsurface's UUIDs are random-at-creation; CCRLog's _siteIdFor is
    // SHA-256(lat,lon). They never agree, so when we map a CCRLog site
    // we must look up Subsurface's hex by coords instead of trusting
    // the mapper's hash — otherwise every site becomes an orphan
    // duplicate under CCRLog's hash.
    final existingHexByCoords = _indexSitesByCoords(existingSites);

    // Mapped sites accumulate keyed by hexId so two CCRLog dives at the
    // same lat/lon collapse to one Site write. Last writer wins on
    // collision (they're equivalent — same hexId implies same coords).
    final mappedSitesByHexId = <String, MappedSite>{};

    // Track the userDiveComputers we encountered (for the top-level
    // delta). The bundles all carry the same list, but we don't want to
    // assume that — gather seen ones and dedup by serial.
    final dcsBySerial = <int, DiveComputer>{};

    for (final bundle in sortedDives) {
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

        final mergedLines = _mergeDiveLines(
          existing: existing.diveLines,
          ours: ours.diveLines,
        );

        final mergedText = serializeSubsurfaceFile(
          SubsurfaceFile(lines: mergedLines),
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
        // The Divecomputer file is normally left alone on update (the
        // safety hold against the 2026-05-08 force-push regression).
        // Narrow exception: if our mapper has "SP change" events for the
        // setpoint trace AND the existing Divecomputer has none, inject
        // them in place. Subsurface keys its setpoint graph off these
        // events; the per-sample `dc_supplied_ppo2` line is not enough.
        // Subsurface's own Divecomputer files NEVER contain SP-change
        // events (its setpoint trace is driven exclusively by per-sample
        // `po2=` deltas). So any SP-change-named event in an existing
        // file is a sure CCRLog-origin signature. Earlier CCRLog builds
        // ALSO had the per-sample `po2` / `dc_supplied_ppo2` swapped, so
        // we rewrite the entire Divecomputer from the now-correct
        // mapper output. This is the only path that breaks the "never
        // rewrite Divecomputer on update" rule, and only for files we
        // ourselves wrote incorrectly.
        final ccrlogOriginSignature = existing.divecomputerLines
            .whereType<EventLine>()
            .any(_looksLikeSpChangeEvent);
        if (ccrlogOriginSignature) {
          final folderPath = folderSegments.join('/');
          filesToWrite['$folderPath/Divecomputer'] = serializeSubsurfaceFile(
            SubsurfaceFile(lines: ours.divecomputerLines),
          );
          if (!diveIdsPlanned.contains(dive.id)) {
            diveIdsPlanned.add(dive.id);
            updatedDives.add(dive);
          }
        }
      } else {
        // ── New dive: full Dive-NNN + Divecomputer write
        //
        // When the remote starts empty (first sync into a fresh
        // Subsurface repo), prefer the dive computer's own number —
        // that lets the user's lifetime Petrel count survive the
        // initial seed. Once any parseable dive exists in the remote,
        // switch to walk-forward: continuing to honour dcDiveNumber
        // creates unbounded gaps when the DC counter is far ahead of
        // the Subsurface logbook (Petrel reset, second-hand unit,
        // dives previously logged in another tool). That's what
        // produced the Dive-1146/1147 vs Dive-713 inversion bug.
        if (!remoteHadDives &&
            dive.dcDiveNumber > 0 &&
            !remoteDiveNumbers.contains(dive.dcDiveNumber)) {
          diveNumber = dive.dcDiveNumber;
          remoteDiveNumbers.add(diveNumber);
          if (diveNumber > nextDiveNumber) nextDiveNumber = diveNumber;
        } else {
          // Walk forward past any collisions so two new dives in one
          // sync don't grab the same fallback number.
          do {
            nextDiveNumber += 1;
          } while (remoteDiveNumbers.contains(nextDiveNumber));
          diveNumber = nextDiveNumber;
          remoteDiveNumbers.add(diveNumber);
        }
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
          // If Subsurface already has a Site file at the same coords
          // (under its own random UUID), reuse that hex instead of
          // writing a duplicate under CCRLog's SHA-256 hash.
          final resolvedHex =
              _resolveSiteHex(mappedSite, existingHexByCoords);
          final keyed = resolvedHex == mappedSite.hexId
              ? mappedSite
              : MappedSite(
                  hexId: resolvedHex,
                  lines: mappedSite.lines,
                );
          mappedSitesByHexId[resolvedHex] = keyed;
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
  /// only lines whose key is in [_ownedDiveLineKeys]. Non-owned lines
  /// are preserved verbatim — that's the data-loss protection.
  List<SsLine> _mergeDiveLines({
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

    // Note: an earlier iteration also rejected the merge when the mapper's
    // emission for a non-owned key (e.g. `cylinder`, `duration`) differed
    // byte-for-byte from what was on disk. In practice this fired on
    // every dive — CCRLog's serializer and Subsurface's serializer don't
    // agree on decimal precision, key order, or which optional fields to
    // emit — and made the push workflow unusable. The actual data-loss
    // protection is structural: we walk existing lines below and copy
    // every non-owned line verbatim, so a foreign edit on a non-owned key
    // can never be overwritten by our write. The byte-compare was extra
    // belt-and-suspenders that we don't need.
    //
    // Build merged output. Walk existing lines, swap owned ones for
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
    return merged;
  }

  /// True when the line is an SP-change-named event. Subsurface's own
  /// Divecomputer files never contain these, so the presence of any
  /// SP-change event is a CCRLog-origin signature — used by the merge
  /// to decide that a Divecomputer file needs a full rewrite (since
  /// older CCRLog builds also had the per-sample `po2` /
  /// `dc_supplied_ppo2` tokens swapped).
  static bool _looksLikeSpChangeEvent(EventLine e) {
    for (final field in e.fields) {
      if (field.key == 'name') {
        final v = field.value;
        return v == '"SP change"' || v == '"setpoint change"';
      }
    }
    return false;
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

  // ── Site merge ─────────────────────────────────────────────────────

  /// Build a coords → existing-hex index from Subsurface's Site files.
  /// Used to reuse Subsurface's site UUIDs when CCRLog's SHA-256 hash
  /// would otherwise create a duplicate under a different filename.
  /// Coordinates are quantized to the same lat-e5/lon-e5 precision the
  /// mapper uses, so float-to-string round-trip doesn't cause misses.
  Map<({int latE5, int lonE5}), String> _indexSitesByCoords(
    Map<String, List<SsLine>> existingSites,
  ) {
    final out = <({int latE5, int lonE5}), String>{};
    for (final entry in existingSites.entries) {
      final hex = entry.key;
      for (final line in entry.value) {
        if (line is GpsLine) {
          final lat = double.tryParse(line.lat);
          final lon = double.tryParse(line.lon);
          if (lat == null || lon == null) break;
          final latE5 = (lat * 1e5).round();
          final lonE5 = (lon * 1e5).round();
          out[(latE5: latE5, lonE5: lonE5)] = hex;
          break;
        }
      }
    }
    return out;
  }

  /// Resolve the hex CCRLog should write a site under. Subsurface uses
  /// random UUIDs at site creation; if the existing repo already has a
  /// Site file at the same coordinates, we reuse that hex instead of
  /// CCRLog's SHA-256 hash to avoid orphan duplicates.
  String _resolveSiteHex(
    MappedSite mapped,
    Map<({int latE5, int lonE5}), String> existingHexByCoords,
  ) {
    for (final line in mapped.lines) {
      if (line is GpsLine) {
        final lat = double.tryParse(line.lat);
        final lon = double.tryParse(line.lon);
        if (lat == null || lon == null) break;
        final latE5 = (lat * 1e5).round();
        final lonE5 = (lon * 1e5).round();
        final existing = existingHexByCoords[(latE5: latE5, lonE5: lonE5)];
        if (existing != null) return existing;
        break;
      }
    }
    return mapped.hexId;
  }

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
