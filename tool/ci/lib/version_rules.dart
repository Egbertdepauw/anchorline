/// Decides channel, version and build number for a CI run from plain facts
/// about git tags. Pure Dart, `dart:` libraries only, so the CI command line
/// wrapper can run it with `dart run` from any directory.
///
/// The rules in short:
///
/// * Release tags look like `vX.Y.Z` and are annotated. A `vX.Y.0` tag sits on
///   `main`; a hotfix tag `vX.Y.Z` (Z > 0) sits on `release/X.Y`.
/// * A nightly is numbered as the *next* minor after the highest release tag
///   (`v1.2.1` is followed by nightly `1.3.0`), or `0.1.0` before any tag.
/// * Build number = a repository-wide base plus the workflow run number, so it
///   only ever grows and is never reused.
library;

/// A release version, parsed from a `vX.Y.Z` tag name.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch);

  static final RegExp _tagPattern = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');

  final int major;
  final int minor;
  final int patch;

  /// Parses a release tag such as `v1.2.0`. Returns null for anything that
  /// isn't exactly `vX.Y.Z` (`v1.4`, `v2.0.0-beta`, `release-1`, ...).
  static SemVer? parseTag(String tag) {
    final m = _tagPattern.firstMatch(tag);
    if (m == null) return null;
    final major = int.tryParse(m.group(1)!);
    final minor = int.tryParse(m.group(2)!);
    final patch = int.tryParse(m.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return SemVer(major, minor, patch);
  }

  /// The version without the leading `v`, e.g. `1.2.0`.
  String get name => '$major.$minor.$patch';

  /// Numeric comparison per component, so 1.10.0 is higher than 1.9.0.
  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      other is SemVer &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => name;
}

/// Which pipeline a run belongs to.
enum Channel {
  /// A tagged release.
  release,

  /// The nightly build of `main`.
  nightly,

  /// A trial run that builds packages but publishes nothing.
  dryRun,
}

/// What git says about a release tag. Gathering these facts is the caller's
/// job; the rules here only judge them.
class TagFacts {
  const TagFacts(
    this.name, {
    required this.annotated,
    required this.onMain,
    required this.onReleaseBranch,
  });

  /// The tag name, e.g. `v1.2.0`.
  final String name;

  /// True for an annotated tag, false for a lightweight one.
  final bool annotated;

  /// The tagged commit is on `origin/main`.
  final bool onMain;

  /// The tagged commit is on `origin/release/X.Y` for the tag's own X.Y.
  final bool onReleaseBranch;
}

/// The outcome of the rules for one run.
class BuildPlan {
  const BuildPlan({
    required this.channel,
    required this.version,
    required this.buildNumber,
    required this.build,
    required this.reason,
  });

  final Channel channel;

  /// The marketing version, e.g. `1.2.0`.
  final String version;

  /// The store/build number, always growing.
  final int buildNumber;

  /// False when the run should do nothing (an unchanged nightly).
  final bool build;

  /// A short human-readable sentence explaining the outcome, suitable for a
  /// workflow summary.
  final String reason;
}

/// A rule was broken. The message is meant to be shown to the person who
/// pushed the tag or started the run.
class VersionRuleError implements Exception {
  const VersionRuleError(this.message);

  final String message;

  @override
  String toString() => 'VersionRuleError: $message';
}

/// Build number = [base] plus the run number of the build workflow.
int buildNumberFor(int base, int runNumber) => base + runNumber;

/// The version a nightly carries: the highest valid release tag with its
/// minor incremented and its patch reset to 0, or `0.1.0` when there is none.
/// Names that aren't `vX.Y.Z` are ignored.
SemVer nextNightlyVersion(Iterable<String> tags) {
  SemVer? highest;
  for (final tag in tags) {
    final v = SemVer.parseTag(tag);
    if (v != null && (highest == null || v.compareTo(highest) > 0)) {
      highest = v;
    }
  }
  if (highest == null) return const SemVer(0, 1, 0);
  return SemVer(highest.major, highest.minor + 1, 0);
}

/// Judges a pushed release tag. Checks run in this order and the first
/// failure throws a [VersionRuleError]:
///
/// 1. the name is `vX.Y.Z`;
/// 2. the tag is annotated;
/// 3. a `vX.Y.0` tag is on `main`, a hotfix `vX.Y.Z` (Z > 0) is on
///    `release/X.Y`;
/// 4. the version isn't in [publishedVersions] yet (tags never get reused).
///
/// [allTags] is accepted so callers pass one consistent set of facts to every
/// planner; no rule reads it today.
BuildPlan planRelease({
  required TagFacts tag,
  required Iterable<String> allTags,
  required Set<String> publishedVersions,
  required int base,
  required int runNumber,
}) {
  final version = SemVer.parseTag(tag.name);
  if (version == null) {
    throw VersionRuleError(
      "Tag '${tag.name}' is not a release tag; release tags look like vX.Y.Z.",
    );
  }
  if (!tag.annotated) {
    throw VersionRuleError(
      'Release tag ${tag.name} must be an annotated tag '
      '(create it with git tag -a).',
    );
  }
  if (version.patch == 0) {
    if (!tag.onMain) {
      throw VersionRuleError(
        'Release tag ${tag.name} must be on main; a vX.Y.0 release is cut '
        'from main.',
      );
    }
  } else if (!tag.onReleaseBranch) {
    throw VersionRuleError(
      'Hotfix tag ${tag.name} must be on release/${version.major}.'
      '${version.minor}; a vX.Y.Z hotfix (Z > 0) is cut from its release '
      'branch.',
    );
  }
  if (publishedVersions.contains(version.name)) {
    throw VersionRuleError(
      'Version ${version.name} is already released; tags never move or get '
      'reused, so cut a new version instead.',
    );
  }
  final buildNumber = buildNumberFor(base, runNumber);
  return BuildPlan(
    channel: Channel.release,
    version: version.name,
    buildNumber: buildNumber,
    build: true,
    reason:
        'Release ${version.name} (build $buildNumber) from tag '
        '${tag.name}.',
  );
}

/// Plans the nightly build of `main`. A [scheduled] run does nothing when
/// [headSha] equals [lastDeliveredSha] (nothing changed since the last
/// delivered nightly); a manual run always builds.
BuildPlan planNightly({
  required Iterable<String> allTags,
  required int base,
  required int runNumber,
  required bool scheduled,
  required String headSha,
  String? lastDeliveredSha,
}) {
  final version = nextNightlyVersion(allTags).name;
  final buildNumber = buildNumberFor(base, runNumber);
  final unchanged = lastDeliveredSha != null && lastDeliveredSha == headSha;
  if (scheduled && unchanged) {
    return BuildPlan(
      channel: Channel.nightly,
      version: version,
      buildNumber: buildNumber,
      build: false,
      reason:
          'Skipped: main is unchanged since the last delivered nightly '
          '(${_short(headSha)}).',
    );
  }
  final trigger = scheduled ? 'scheduled run' : 'manual run';
  return BuildPlan(
    channel: Channel.nightly,
    version: version,
    buildNumber: buildNumber,
    build: true,
    reason:
        'Nightly $version (build $buildNumber) from main at '
        '${_short(headSha)}, $trigger.',
  );
}

/// Plans a dry run: it builds packages like a nightly (and carries the nightly
/// version) but the caller publishes nothing.
BuildPlan planDryRun({
  required Iterable<String> allTags,
  required int base,
  required int runNumber,
}) {
  final version = nextNightlyVersion(allTags).name;
  final buildNumber = buildNumberFor(base, runNumber);
  return BuildPlan(
    channel: Channel.dryRun,
    version: version,
    buildNumber: buildNumber,
    build: true,
    reason:
        'Dry run as nightly $version (build $buildNumber); '
        'nothing will be published.',
  );
}

/// The first 7 characters of a commit SHA, enough to recognise it in a log.
String _short(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;
