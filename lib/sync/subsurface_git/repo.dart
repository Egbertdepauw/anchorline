/// In-process git wrapper for the user's Subsurface Cloud repo.
///
/// This is the only place in the codebase that imports `git2dart`. The
/// API is intentionally narrow — clone, pull, stage-all, commit, push —
/// because Phase D's orchestrator only needs that much, and keeping the
/// surface small means less code to refactor if we ever swap the
/// underlying library out.
///
/// **iOS is not supported.** `git2dart_binaries` does not ship iOS
/// dylibs (verified 2026-05-08, see `docs/subsurface_git_library.md`).
/// Constructing a [SubsurfaceRepo] on iOS is fine — the UI layer may
/// instantiate before checking [SubsurfaceRepo.isPlatformSupported] —
/// but every action method throws [PlatformNotSupportedException]. The
/// Settings screen surfaces this as a friendly "sync from a desktop"
/// message.
///
/// **Pull strategy is fast-forward only.** If the local branch and the
/// remote have diverged, [pull] throws [PullConflictException] and the
/// orchestrator decides what to do. v1 policy is "force-overwrite our
/// state" — CCRLog is the canonical editor and we don't yet read
/// Subsurface's edits back.
///
/// **Auth is read fresh on every network op.** We don't cache the
/// `(email, password)` pair inside the repo instance — every clone /
/// pull / push pulls them from the [SubsurfaceCredentialsSource]. That
/// way a credential rotation in Settings is picked up immediately.
library;

import 'dart:io';

import 'package:git2dart/git2dart.dart';
import 'package:git2dart_binaries/git2dart_binaries.dart' show LibGit2Error;

import 'credentials.dart';

/// Subsurface Cloud's git endpoint for European customers. The cloud
/// service runs three regions (eu / us / asia); the user's account is
/// `eu`. If we ever need other regions, add a per-account override
/// rather than rewriting [urlForEmail] — different users may resolve
/// to different regions.
const String _subsurfaceCloudHost = 'ssrf-cloud-eu.subsurface-divelog.org';

/// In-process wrapper around `git2dart` scoped to a single Subsurface
/// Cloud repository.
///
/// Constructing a repo binds it to a `[localDir]` and a `[remoteUrl]`;
/// state lives entirely in `localDir/.git`. The wrapper is safe to
/// construct cheaply (no network I/O happens until you call one of the
/// action methods).
class SubsurfaceRepo {
  /// Build a repo handle. Does not touch disk or the network.
  ///
  /// [localDir] is where the working tree lives (created on first
  /// [ensureCloned]). [remoteUrl] is typically [urlForEmail]; tests
  /// pass a `file://` URL pointing at a fixture bare repo.
  /// [credentials] is consulted on every network op. [authorName] /
  /// [authorEmail] stamp every commit; defaults make CCRLog commits
  /// visually distinct in `git log`.
  SubsurfaceRepo({
    required this.localDir,
    required this.remoteUrl,
    required SubsurfaceCredentialsSource credentials,
    this.authorName = 'CCRLog',
    this.authorEmail = 'noreply@ccrlogger.app',
  }) : _credentials = credentials;

  final Directory localDir;
  final String remoteUrl;
  final String authorName;
  final String authorEmail;
  final SubsurfaceCredentialsSource _credentials;

  /// True when this platform has an in-process libgit2. False on iOS;
  /// true on macOS / Linux / Windows / Android.
  ///
  /// Callers (Phase D orchestrator and Phase E Settings UI) check this
  /// before doing anything sync-related and present a friendly
  /// not-supported message instead of letting [PlatformNotSupportedException]
  /// surface to the user.
  static bool get isPlatformSupported => !Platform.isIOS;

  /// Construct the Subsurface Cloud HTTPS URL for the given account
  /// email. Subsurface routes the user's repo as
  /// `https://ssrf-cloud-eu.subsurface-divelog.org/git/<email>`. The
  /// email goes in verbatim (Subsurface accepts it unencoded — that's
  /// what their own desktop client does).
  static String urlForEmail(String email) =>
      'https://$_subsurfaceCloudHost/git/$email';

  /// The branch name HEAD currently points at — Subsurface uses one
  /// branch per user, named with the user's literal email
  /// (e.g. `egbert@despaankamer.nl`). This is read off the local
  /// repository's HEAD, so [ensureCloned] must have run.
  ///
  /// Throws a [GitException] if the repo isn't open or HEAD is unborn
  /// / detached in a way that has no shorthand.
  String get currentBranch {
    _ensurePlatform();
    final repo = _openExisting();
    try {
      return repo.head.shorthand;
    } on LibGit2Error catch (e) {
      throw GitException('cannot read HEAD: $e', cause: e);
    } finally {
      repo.free();
    }
  }

  /// Clone [remoteUrl] into [localDir] if no git repository is there
  /// yet. Idempotent: the second call is a fast no-op (it simply
  /// notices the existing `.git` directory and returns).
  ///
  /// Auth comes from [credentials]; throws [GitAuthException] if no
  /// credentials are stored, [PullConflictException] is not relevant
  /// here, and any other libgit2 failure surfaces as [GitException].
  Future<void> ensureCloned() async {
    _ensurePlatform();
    if (_isAlreadyCloned()) return;

    final creds = await _readCredentialsOrThrow();
    if (!localDir.existsSync()) {
      localDir.createSync(recursive: true);
    }

    Repository? repo;
    try {
      repo = Repository.clone(
        url: remoteUrl,
        localPath: localDir.path,
        callbacks: Callbacks(
          credentials: UserPass(
            username: creds.email,
            password: creds.password,
          ),
        ),
      );
    } on LibGit2Error catch (e) {
      throw _classifyNetworkError(e, 'clone failed');
    } finally {
      repo?.free();
    }
  }

  /// Fetch from `origin` and fast-forward the current branch. Throws
  /// [PullConflictException] when the remote has diverged from local
  /// (i.e. needs a real merge). The orchestrator's policy is to
  /// force-overwrite local state in that case — see Phase D.
  ///
  /// Up-to-date is a no-op (no exception). Unborn-branch (freshly
  /// cloned but pre-branch state) is treated as fast-forward.
  Future<void> pull() async {
    _ensurePlatform();
    final creds = await _readCredentialsOrThrow();
    final repo = _openExisting();
    try {
      // Step 1: fetch.
      Remote? remote;
      try {
        remote = Remote.lookup(repo: repo, name: 'origin');
        remote.fetch(
          callbacks: Callbacks(
            credentials: UserPass(
              username: creds.email,
              password: creds.password,
            ),
          ),
        );
      } on LibGit2Error catch (e) {
        throw _classifyNetworkError(e, 'fetch failed');
      } finally {
        remote?.free();
      }

      // Step 2: figure out what we just fetched (the remote-tracking
      // tip of our branch) and decide whether we can fast-forward.
      final branchName = repo.head.shorthand;
      String theirSha;
      try {
        final remoteBranch = Branch.lookup(
          repo: repo,
          name: 'origin/$branchName',
          type: GitBranch.remote,
        );
        try {
          // Capture the SHA *before* freeing the branch — the Oid
          // returned from `target` shares memory with the underlying
          // git_reference and its pointer dangles after free().
          theirSha = remoteBranch.target.sha;
        } finally {
          remoteBranch.free();
        }
      } on LibGit2Error catch (e) {
        throw GitException('no remote-tracking branch for $branchName: $e',
            cause: e);
      }
      final theirHead = Oid.fromSHA(repo, theirSha);

      final analysis = Merge.analysis(repo: repo, theirHead: theirHead);
      if (analysis.result.contains(GitMergeAnalysis.upToDate)) {
        return;
      }
      if (analysis.result.contains(GitMergeAnalysis.fastForward) ||
          analysis.result.contains(GitMergeAnalysis.unborn)) {
        // Fast-forward: move the branch ref + HEAD to theirHead, then
        // checkout to update the working tree.
        try {
          // Update local branch ref.
          Reference.create(
            repo: repo,
            name: 'refs/heads/$branchName',
            target: theirHead,
            force: true,
          ).free();
          repo.setHead('refs/heads/$branchName');
          Checkout.head(repo: repo, strategy: {GitCheckout.force});
          return;
        } on LibGit2Error catch (e) {
          throw GitException('fast-forward failed: $e', cause: e);
        }
      }
      // Anything else (normal divergence) is a conflict — orchestrator
      // decides what to do.
      throw PullConflictException(
        'remote diverged from local; analysis=${analysis.result}',
      );
    } finally {
      repo.free();
    }
  }

  /// Stage every change in the working tree, including deletions.
  /// Mirrors `git add -A`. Does nothing else: the caller follows up
  /// with [commit] when ready.
  Future<void> stageAll() async {
    _ensurePlatform();
    final repo = _openExisting();
    try {
      final index = repo.index;
      try {
        // Pass `['*']` as pathspec to match every path. `addAll`
        // handles both new files and modifications; `updateAll` then
        // catches deletes (libgit2's addAll respects gitignore but
        // doesn't pick up removals).
        index.addAll(['*']);
        index.updateAll(['*']);
        index.write();
      } on LibGit2Error catch (e) {
        throw GitException('stageAll failed: $e', cause: e);
      } finally {
        index.free();
      }
    } finally {
      repo.free();
    }
  }

  /// Build a commit from whatever is staged. Returns the new commit's
  /// hex SHA, or `null` if the index has nothing pending against HEAD
  /// (so we don't create empty commits — Subsurface treats an empty
  /// commit as a no-op anyway, but we'd rather not litter `git log`).
  ///
  /// The commit's author/committer are fixed at construction time
  /// ([authorName] / [authorEmail]).
  Future<String?> commit(String message) async {
    _ensurePlatform();
    final repo = _openExisting();
    try {
      final index = repo.index;
      Signature? signature;
      try {
        // writeTree builds a tree from the current index. If the
        // resulting tree matches HEAD's tree, there's nothing to
        // commit. We check that before creating a commit so callers
        // can run a stage/commit pair unconditionally.
        final treeOid = index.writeTree();
        final tree = Tree.lookup(repo: repo, oid: treeOid);
        try {
          final isUnborn = repo.isEmpty || repo.isBranchUnborn;
          Commit? parent;
          if (!isUnborn) {
            parent = Commit.lookup(repo: repo, oid: repo.head.target);
            if (parent.tree.oid == tree.oid) {
              // Nothing changed.
              parent.free();
              return null;
            }
          }
          signature = Signature.create(
            name: authorName,
            email: authorEmail,
          );
          final oid = Commit.create(
            repo: repo,
            updateRef: 'HEAD',
            author: signature,
            committer: signature,
            message: message,
            tree: tree,
            parents: [?parent],
          );
          parent?.free();
          return oid.sha;
        } finally {
          tree.free();
        }
      } on LibGit2Error catch (e) {
        throw GitException('commit failed: $e', cause: e);
      } finally {
        signature?.free();
        index.free();
      }
    } finally {
      repo.free();
    }
  }

  /// Push the current branch to `origin`. Auth is read fresh from
  /// [credentials]. On a non-fast-forward rejection by the server,
  /// [PullConflictException] is thrown so the orchestrator can pull,
  /// re-stage, and retry. On a 401 / bad password, [GitAuthException].
  Future<void> push() async {
    _ensurePlatform();
    final creds = await _readCredentialsOrThrow();
    final repo = _openExisting();
    try {
      final branchName = repo.head.shorthand;
      final refspec = 'refs/heads/$branchName:refs/heads/$branchName';
      Remote? remote;
      String? rejection;
      try {
        remote = Remote.lookup(repo: repo, name: 'origin');
        remote.push(
          refspecs: [refspec],
          callbacks: Callbacks(
            credentials: UserPass(
              username: creds.email,
              password: creds.password,
            ),
            // libgit2 reports per-ref rejection through the
            // pushUpdateReference callback — message is empty when
            // the push was accepted, otherwise it's the server's
            // refusal text (typically containing "non-fast-forward").
            pushUpdateReference: (refname, message) {
              if (message.isNotEmpty) {
                rejection = message;
              }
            },
          ),
        );
      } on LibGit2Error catch (e) {
        throw _classifyNetworkError(e, 'push failed');
      } finally {
        remote?.free();
      }
      final r = rejection;
      if (r != null) {
        if (r.toLowerCase().contains('non-fast-forward') ||
            r.toLowerCase().contains('rejected')) {
          throw PullConflictException('push rejected: $r');
        }
        throw GitException('push rejected: $r');
      }
    } finally {
      repo.free();
    }
  }

  // ── internals ──────────────────────────────────────────────────────

  void _ensurePlatform() {
    if (!isPlatformSupported) {
      throw PlatformNotSupportedException(
        'in-process git is not available on iOS',
      );
    }
  }

  bool _isAlreadyCloned() {
    final dotGit = Directory('${localDir.path}/.git');
    return dotGit.existsSync();
  }

  Repository _openExisting() {
    try {
      return Repository.open(localDir.path);
    } on LibGit2Error catch (e) {
      throw GitException(
        'cannot open repository at ${localDir.path}: $e',
        cause: e,
      );
    }
  }

  Future<({String email, String password})> _readCredentialsOrThrow() async {
    final creds = await _credentials.read();
    if (creds == null) {
      throw GitAuthException('no Subsurface Cloud credentials saved');
    }
    return creds;
  }

  /// Map a libgit2 network error to one of our typed exceptions. We
  /// look at the message text because libgit2's error class enum is
  /// not reliably exposed across all the bindings.
  GitException _classifyNetworkError(LibGit2Error e, String prefix) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('authentication') ||
        msg.contains('401') ||
        msg.contains('unauthorized')) {
      return GitAuthException('$prefix: $e', cause: e);
    }
    return GitException('$prefix: $e', cause: e);
  }
}

/// Base class for everything this wrapper throws. Carries a [message]
/// and an optional [cause] (the underlying `LibGit2Error` or other
/// exception, when applicable).
class GitException implements Exception {
  GitException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'GitException: $message';
}

/// Thrown when [SubsurfaceRepo.pull] cannot fast-forward (the local and
/// remote branches have diverged) or when [SubsurfaceRepo.push] is
/// rejected by the server with a non-fast-forward error. The
/// orchestrator's reaction in v1 is to overwrite local state from the
/// remote and retry.
class PullConflictException extends GitException {
  PullConflictException(super.message, {super.cause});

  @override
  String toString() => 'PullConflictException: $message';
}

/// Thrown when the credentials are missing, wrong, or the server
/// returns 401 / unauthorized. Settings UI should show a "check your
/// Subsurface Cloud password" prompt.
class GitAuthException extends GitException {
  GitAuthException(super.message, {super.cause});

  @override
  String toString() => 'GitAuthException: $message';
}

/// Thrown by every action method on platforms without an in-process
/// libgit2 (currently iOS). Construction itself is allowed —
/// [SubsurfaceRepo.isPlatformSupported] lets callers branch *before*
/// constructing if they prefer.
class PlatformNotSupportedException extends GitException {
  PlatformNotSupportedException(super.message, {super.cause});

  @override
  String toString() => 'PlatformNotSupportedException: $message';
}
