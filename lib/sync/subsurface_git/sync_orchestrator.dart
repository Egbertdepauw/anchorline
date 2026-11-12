/// Phase D — orchestrates an end-to-end Subsurface git sync.
///
/// This is the public entry point the Settings UI (Phase E) will call.
/// It stitches together everything Phase A-C built:
///
/// - Phase A — `format/` parser+serializer (called via [SyncPlanner]
///   and [RemoteSnapshot]).
/// - Phase B — [CcrlogToSubsurfaceMapper], used by [SyncPlanner].
/// - Phase C — [SubsurfaceRepo] for the actual git ops.
///
/// The flow inside [syncNow] is documented inline. The shape:
///
///     ensureCloned → pull → snapshot → bundle CCRLog dives → plan →
///     write files → stage → commit → push (with up-to-3 retries on
///     non-fast-forward) → mark `subsurface_uploaded_at` on success.
///
/// We separate the impure orchestration here from the pure-Dart planner
/// so 90% of the logic ([SyncPlanner]) can be unit-tested without git
/// or a database. The orchestrator's tests run against a local file://
/// bare remote to exercise the git seam end-to-end.
library;

import 'dart:convert';
import 'dart:io';

import '../../data/db/database.dart' show Cylinder, Dive, DiveComputer;
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/dive.dart' show DiveGasMix, DiveTank;
import 'package:subsurface_core/data/models/sample_set.dart';
import 'credentials.dart';
import 'drift_sync_inputs.dart';
import 'remote_repo_reader.dart';
import 'package:subsurface_core/sync/subsurface_git/remote_snapshot.dart';
import 'repo.dart';
import 'package:subsurface_core/sync/subsurface_git/sync_planner.dart' show AbortedDive, CcrlogDiveBundle, SyncPlanner;

/// Result of one [SubsurfaceSyncOrchestrator.syncNow] invocation.
class SubsurfaceSyncResult {
  SubsurfaceSyncResult({
    required this.divesPushed,
    required this.divesSkipped,
    required this.abortedDives,
    required this.commitSha,
    required this.completedAt,
  });

  /// Number of dives the orchestrator wrote to the working tree (new
  /// + updated). Equals the number of [SyncPlanStats.newDives] +
  /// [SyncPlanStats.updatedDives] from the *last* successful plan.
  final int divesPushed;

  /// Dives whose mapped output already matched the remote — no rewrite
  /// needed. The orchestrator does not stamp `subsurface_uploaded_at`
  /// on these.
  final int divesSkipped;

  /// Dives the planner declined to push because of a foreign edit on
  /// the Subsurface side. Surface as "Skipped" in the UI; not errors.
  final List<AbortedDive> abortedDives;

  /// Git SHA of the commit we pushed, or null if the plan was empty
  /// (nothing changed since the previous sync).
  final String? commitSha;

  final DateTime completedAt;
}

/// Base class for terminal sync errors. The Settings UI shows the
/// [message] verbatim and may inspect the subtype to render a
/// customised explanation (e.g. NoCredentials → "go to Settings →
/// Subsurface Cloud and enter your password").
class SubsurfaceSyncException implements Exception {
  SubsurfaceSyncException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SubsurfaceSyncException: $message';
}

/// The user hasn't saved their Subsurface Cloud credentials yet.
class NoCredentialsException extends SubsurfaceSyncException {
  NoCredentialsException([String? message])
      : super(message ?? 'No Subsurface Cloud credentials saved');
}

/// We're running on a platform where the in-process git library isn't
/// available (currently iOS only). The Settings UI surfaces this as a
/// "sync from a desktop / Android device" message.
class PlatformNotSupportedSyncException extends SubsurfaceSyncException {
  PlatformNotSupportedSyncException([String? message])
      : super(message ?? 'Subsurface git sync is not available on this platform');
}

/// Auth was rejected by Subsurface Cloud. Either the password changed
/// or the email is wrong.
class AuthFailedSyncException extends SubsurfaceSyncException {
  AuthFailedSyncException(super.message, {super.cause});
}

/// Local + remote diverged in a way `git pull` couldn't auto-resolve,
/// even after [SubsurfaceSyncOrchestrator._maxRetries] retries.
class UnresolvedConflictException extends SubsurfaceSyncException {
  UnresolvedConflictException(super.message, {super.cause});
}

// ── Data-access seam ─────────────────────────────────────────────────

/// Read-only view of the CCRLog state the orchestrator needs. Defining
/// this as an abstract interface (rather than depending on the
/// concrete DAOs) is what lets the orchestrator test cleanly with an
/// in-memory fake — the real DAOs are coupled to PowerSync, which is
/// expensive to boot per test. The production wiring uses
/// [DaoSubsurfaceSyncDataSource], a thin adapter over the real DAOs.
abstract class SubsurfaceSyncDataSource {
  /// All non-soft-deleted dives, ordered however the source likes.
  Future<List<Dive>> getAllDives();

  Future<SampleSet?> getSamples(String diveId);

  Future<DiveAnnotation?> getAnnotation(String diveId);

  /// Per-dive (gas_mix_index → cylinder) mapping, dereferenced to the
  /// actual [Cylinder] rows. The mapper takes `Map<int, Cylinder>`
  /// keyed by gas mix index, so that's what we return.
  Future<Map<int, Cylinder>> cylindersByMixIndex(String diveId);

  /// All registered dive computers — the mapper emits one
  /// `divecomputerid` line per unique serial.
  Future<List<DiveComputer>> listAllDiveComputers();

  /// Stamp `subsurface_uploaded_at` on the given dives.
  Future<void> markSubsurfaceUploaded(
      Iterable<String> diveIds, int whenSeconds);
}

// ── Orchestrator ────────────────────────────────────────────────────

/// Orchestrates a complete Subsurface Cloud git sync.
///
/// Construct once per Settings-screen lifetime; calling [syncNow] is
/// safe to do multiple times (idempotent on the no-op path; safe to
/// retry after a thrown [SubsurfaceSyncException]).
class SubsurfaceSyncOrchestrator {
  SubsurfaceSyncOrchestrator({
    required SubsurfaceSyncDataSource dataSource,
    required SubsurfaceCredentialsSource credentials,
    required Directory localCloneRoot,
    SyncPlanner? planner,
    SubsurfaceRepo Function({
      required Directory localDir,
      required String remoteUrl,
      required SubsurfaceCredentialsSource credentials,
    })? repoFactory,
    DateTime Function()? clock,
  })  : _data = dataSource,
        _credentials = credentials,
        _localCloneRoot = localCloneRoot,
        _planner = planner ?? SyncPlanner(),
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

  static const int _maxRetries = 3;

  final SubsurfaceSyncDataSource _data;
  final SubsurfaceCredentialsSource _credentials;
  final Directory _localCloneRoot;
  final SyncPlanner _planner;
  final SubsurfaceRepo Function({
    required Directory localDir,
    required String remoteUrl,
    required SubsurfaceCredentialsSource credentials,
  }) _repoFactory;
  final DateTime Function() _clock;

  /// Mirrors [SubsurfaceRepo.isPlatformSupported] so callers don't need
  /// both imports.
  bool get isPlatformSupported => SubsurfaceRepo.isPlatformSupported;

  /// In tests we sometimes want to point at a local file:// bare
  /// remote rather than Subsurface Cloud. The default is the cloud URL
  /// for the credentials' email.
  String? remoteUrlOverride;

  /// Run a full sync. See class docs for the sequence; throws
  /// [SubsurfaceSyncException] (or a subtype) on terminal failure.
  Future<SubsurfaceSyncResult> syncNow() async {
    // 1. Platform gate.
    if (!isPlatformSupported) {
      throw PlatformNotSupportedSyncException();
    }

    // 2. Credentials gate.
    final creds = await _credentials.read();
    if (creds == null) throw NoCredentialsException();

    // 3. Build / open the local clone.
    final repoDir = Directory('${_localCloneRoot.path}/${creds.email}');
    if (!repoDir.existsSync()) {
      repoDir.createSync(recursive: true);
    }
    final repo = _repoFactory(
      localDir: repoDir,
      remoteUrl: remoteUrlOverride ?? SubsurfaceRepo.urlForEmail(creds.email),
      credentials: _credentials,
    );

    try {
      await repo.ensureCloned();
    } on PlatformNotSupportedException catch (e) {
      throw PlatformNotSupportedSyncException(e.message);
    } on GitAuthException catch (e) {
      throw AuthFailedSyncException(e.message, cause: e);
    } on GitException catch (e) {
      throw SubsurfaceSyncException('clone failed: ${e.message}', cause: e);
    }

    // 4. Pull (fast-forward only).
    try {
      await repo.pull();
    } on GitAuthException catch (e) {
      throw AuthFailedSyncException(e.message, cause: e);
    } on PullConflictException catch (e) {
      throw UnresolvedConflictException(
        'remote has diverged and cannot fast-forward; '
        'manual reconciliation required',
        cause: e,
      );
    } on GitException catch (e) {
      throw SubsurfaceSyncException('pull failed: ${e.message}', cause: e);
    }

    // 5-6. Build bundles + plan + write + commit + push, with
    // up-to-3 retries on push rejection (someone else committed
    // between our pull and our push).
    SubsurfaceSyncResult? result;
    SubsurfaceSyncException? lastError;
    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        result = await _planAndPush(repoDir: repoDir, repo: repo);
        break;
      } on _RetryablePushConflict catch (e) {
        lastError = UnresolvedConflictException(
          'push rejected after ${attempt + 1} attempt(s)',
          cause: e.cause,
        );
        // Re-pull and try again.
        try {
          await repo.pull();
        } on PullConflictException catch (pullErr) {
          throw UnresolvedConflictException(
            'remote diverged and cannot fast-forward after push rejection',
            cause: pullErr,
          );
        } on GitAuthException catch (authErr) {
          throw AuthFailedSyncException(authErr.message, cause: authErr);
        } on GitException catch (gitErr) {
          throw SubsurfaceSyncException(
            'pull during retry failed: ${gitErr.message}',
            cause: gitErr,
          );
        }
        // Loop again with a fresh snapshot + plan.
      }
    }
    if (result == null) {
      throw lastError ??
          UnresolvedConflictException('push rejected $_maxRetries times');
    }

    return result;
  }

  /// Snapshot → plan → write → stage → commit → push. Throws
  /// [_RetryablePushConflict] on a non-fast-forward push rejection so
  /// [syncNow]'s retry loop can take over.
  Future<SubsurfaceSyncResult> _planAndPush({
    required Directory repoDir,
    required SubsurfaceRepo repo,
  }) async {
    // Snapshot the on-disk state.
    final snapshot =
        RemoteSnapshot.fromFiles(await readRemoteRepoFiles(repoDir));

    // Build CCRLog bundles. We load all dives + their satellites; in
    // practice 99% of dives are unchanged between sync runs, so this
    // could be optimized later by filtering on
    // `subsurface_uploaded_at` and `updated_at`. For now we plan
    // against all dives so the planner's `existing*` matching is the
    // single source of truth for what counts as new vs. updated.
    final dives = await _data.getAllDives();
    final allComputers = await _data.listAllDiveComputers();
    final computerInputs = allComputers.map(diveComputerInputFromRow).toList();

    final bundles = <CcrlogDiveBundle>[];
    for (final dive in dives) {
      final samples = await _data.getSamples(dive.id);
      if (samples == null) continue; // Sample row hasn't synced yet.
      final annotation = await _data.getAnnotation(dive.id);
      final cylinders = await _data.cylindersByMixIndex(dive.id);
      final gasMixes = _decodeGasMixes(dive.gasMixesJson);
      final tanks = _decodeTanks(dive.tanksJson);
      bundles.add(CcrlogDiveBundle(
        dive: diveInputFromRow(dive),
        samples: samples,
        annotation: annotation,
        gasMixes: gasMixes,
        tanks: tanks,
        cylindersByMixIndex: {
          for (final e in cylinders.entries)
            e.key: cylinderInputFromRow(e.value),
        },
        userDiveComputers: computerInputs,
      ));
    }

    final plan = _planner.plan(
      ccrlogDives: bundles,
      existingDivesBySerialAndStart: snapshot.existingDivesBySerialAndStart,
      existingMaxDiveNumber: snapshot.existingMaxDiveNumber,
      existingTopLevel: snapshot.existingTopLevel,
      existingSites: snapshot.existingSites,
    );

    // Write every staged file.
    for (final entry in plan.filesToWrite.entries) {
      final path = entry.key;
      final f = File('${repoDir.path}/$path');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(entry.value);
    }

    try {
      await repo.stageAll();
    } on GitException catch (e) {
      throw SubsurfaceSyncException('stage failed: ${e.message}', cause: e);
    }

    final divesChanged = plan.stats.newDives + plan.stats.updatedDives;
    final commitMessage = 'CCRLog sync — $divesChanged dive'
        '${divesChanged == 1 ? '' : 's'}';

    String? sha;
    try {
      sha = await repo.commit(commitMessage);
    } on GitException catch (e) {
      throw SubsurfaceSyncException('commit failed: ${e.message}', cause: e);
    }

    if (sha == null) {
      // Nothing changed since the last sync.
      return SubsurfaceSyncResult(
        divesPushed: 0,
        divesSkipped: plan.stats.skippedDives,
        abortedDives: plan.abortedDives,
        commitSha: null,
        completedAt: _clock(),
      );
    }

    try {
      await repo.push();
    } on PullConflictException catch (e) {
      throw _RetryablePushConflict(cause: e);
    } on GitAuthException catch (e) {
      throw AuthFailedSyncException(e.message, cause: e);
    } on GitException catch (e) {
      throw SubsurfaceSyncException('push failed: ${e.message}', cause: e);
    }

    // Mark all planned dives as uploaded.
    final nowSeconds = _clock().millisecondsSinceEpoch ~/ 1000;
    if (plan.diveIdsPlanned.isNotEmpty) {
      await _data.markSubsurfaceUploaded(plan.diveIdsPlanned, nowSeconds);
    }

    return SubsurfaceSyncResult(
      divesPushed: divesChanged,
      divesSkipped: plan.stats.skippedDives,
      abortedDives: plan.abortedDives,
      commitSha: sha,
      completedAt: _clock(),
    );
  }

  // ── JSON decode helpers ────────────────────────────────────────────

  List<DiveGasMix> _decodeGasMixes(String json) {
    if (json.isEmpty) return const [];
    try {
      final list = (jsonDecode(json) as List)
          .map((e) => DiveGasMix.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return const [];
    }
  }

  List<DiveTank> _decodeTanks(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return (jsonDecode(json) as List)
          .map((e) => DiveTank.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

/// Internal sentinel used to bounce out of [_planAndPush] back into
/// [syncNow]'s retry loop on a non-fast-forward rejection.
class _RetryablePushConflict implements Exception {
  _RetryablePushConflict({this.cause});
  final Object? cause;
}
