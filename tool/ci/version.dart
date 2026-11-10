/// Command line wrapper around `lib/version_rules.dart` for CI.
///
/// Gathers facts from the git repository in the current directory, asks the
/// rules what this run is (release, nightly or dry run) and reports the answer
/// as `key=value` lines on stdout and, when `$GITHUB_OUTPUT` is set, appended
/// to that file. Imports only `dart:` libraries and its sibling, so
/// `dart <path>/tool/ci/version.dart` works from any directory. (Not
/// `dart run`: that runs the package's build hooks and writes their progress
/// to stdout.)
library;

import 'dart:convert';
import 'dart:io';

import 'lib/version_rules.dart';

const _usage = '''
Usage: dart tool/ci/version.dart
  --event <push|schedule|workflow_dispatch>
  --ref <github.ref>
  --run-number <n>
  --base <n>
  [--dry-run]
  [--last-delivered-sha <sha>]
  [--published <comma-separated versions>]
  [--notes-out <path>]''';

void main(List<String> args) {
  exitCode = _run(args);
}

int _run(List<String> args) {
  try {
    final options = _Options.parse(args);
    final plan = _plan(options);
    // A release's notes are its tag message, so they are read (and a missing
    // message is caught) before anything is reported or written.
    final notesOut = options.notesOut;
    final notes = plan.channel == Channel.release
        ? _releaseNotes(options.releaseTag)
        : (notesOut == null ? null : _commitNotes(options.lastDeliveredSha));
    if (notesOut != null && notes != null) {
      File(notesOut).parent.createSync(recursive: true);
      File(notesOut).writeAsStringSync(notes);
    }
    _writeOutputs(plan);
    return 0;
  } on VersionRuleError catch (e) {
    return _fail(e.message);
  } on _CliError catch (e) {
    if (e.showUsage) stderr.writeln(_usage);
    return _fail(e.message);
  } on FileSystemException catch (e) {
    return _fail(
      'Could not write ${e.path ?? 'a file'}: '
      '${e.osError?.message ?? e.message}',
    );
  }
}

/// Reports a failure the way GitHub Actions turns into an error annotation.
int _fail(String message) {
  stdout.writeln('::error::${_oneLine(message)}');
  return 1;
}

/// A problem with the invocation or the environment (not a broken rule).
class _CliError implements Exception {
  const _CliError(this.message, {this.showUsage = false});

  final String message;
  final bool showUsage;
}

class _Options {
  const _Options({
    required this.event,
    required this.ref,
    required this.runNumber,
    required this.base,
    required this.dryRun,
    required this.lastDeliveredSha,
    required this.published,
    required this.notesOut,
  });

  static const _valueFlags = {
    'event',
    'ref',
    'run-number',
    'base',
    'last-delivered-sha',
    'published',
    'notes-out',
  };

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    var dryRun = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--dry-run') {
        dryRun = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        throw _CliError("Unexpected argument '$arg'.", showUsage: true);
      }
      final name = arg.substring(2);
      if (!_valueFlags.contains(name)) {
        throw _CliError("Unknown flag '$arg'.", showUsage: true);
      }
      // An empty value is allowed (`--published ""`); a following flag is not.
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        throw _CliError('Flag $arg needs a value.', showUsage: true);
      }
      values[name] = args[++i];
    }

    String required(String name) =>
        values[name] ??
        (throw _CliError('Missing flag --$name.', showUsage: true));
    int number(String name) {
      final n = int.tryParse(required(name).trim());
      if (n == null || n < 0) {
        throw _CliError(
          "Flag --$name needs a whole number, got '${values[name]}'.",
          showUsage: true,
        );
      }
      return n;
    }

    final lastDelivered = values['last-delivered-sha']?.trim();
    return _Options(
      event: required('event'),
      ref: required('ref'),
      runNumber: number('run-number'),
      base: number('base'),
      dryRun: dryRun,
      lastDeliveredSha: (lastDelivered == null || lastDelivered.isEmpty)
          ? null
          : lastDelivered,
      published: (values['published'] ?? '')
          .split(',')
          .map((v) => v.trim())
          // `gh release list --json tagName` reports v1.2.0, the rules compare
          // plain versions.
          .map((v) => v.startsWith('v') ? v.substring(1) : v)
          .where((v) => v.isNotEmpty)
          .toSet(),
      notesOut: values['notes-out'],
    );
  }

  final String event;
  final String ref;
  final int runNumber;
  final int base;
  final bool dryRun;
  final String? lastDeliveredSha;
  final Set<String> published;
  final String? notesOut;

  static const _tagRefPrefix = 'refs/tags/';

  /// The tag a `push` run is about; only meaningful for tag refs.
  String get releaseTag => ref.substring(_tagRefPrefix.length);
}

BuildPlan _plan(_Options o) {
  final allTags = _gitText([
    'tag',
    '--list',
    'v*',
  ]).split('\n').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  switch (o.event) {
    case 'push':
      if (!o.ref.startsWith(_Options._tagRefPrefix)) {
        throw _CliError(
          "Event push is only supported for tag refs (refs/tags/...), "
          "got '${o.ref}'.",
        );
      }
      return planRelease(
        tag: _tagFacts(o.releaseTag),
        allTags: allTags,
        publishedVersions: o.published,
        base: o.base,
        runNumber: o.runNumber,
      );
    case 'schedule':
    case 'workflow_dispatch':
      final scheduled = o.event == 'schedule';
      if (!scheduled && (o.dryRun || o.ref != 'refs/heads/main')) {
        return planDryRun(
          allTags: allTags,
          base: o.base,
          runNumber: o.runNumber,
        );
      }
      return planNightly(
        allTags: allTags,
        base: o.base,
        runNumber: o.runNumber,
        scheduled: scheduled,
        headSha: _gitText(['rev-parse', 'HEAD']).trim(),
        lastDeliveredSha: o.lastDeliveredSha,
      );
    default:
      throw _CliError(
        "Unsupported event '${o.event}'; expected push, schedule or "
        'workflow_dispatch.',
        showUsage: true,
      );
  }
}

ProcessResult _git(List<String> args) =>
    Process.runSync('git', args, stdoutEncoding: utf8, stderrEncoding: utf8);

/// Stdout of a git command that has to succeed.
String _gitText(List<String> args) {
  final r = _git(args);
  if (r.exitCode != 0) {
    throw _CliError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return r.stdout as String;
}

bool _isAncestor(String commit, String of) =>
    _git(['merge-base', '--is-ancestor', commit, of]).exitCode == 0;

/// Whether [ref] resolves to a commit in this checkout.
bool _refExists(String ref) =>
    _git(['rev-parse', '--verify', '--quiet', '$ref^{commit}']).exitCode == 0;

/// What git says about the pushed tag. A missing `origin/release/X.Y` counts
/// as "not on it"; a missing `origin/main` is an error (it means the checkout
/// is too shallow, not that the tag is elsewhere).
TagFacts _tagFacts(String name) {
  final version = SemVer.parseTag(name);
  final ref = 'refs/tags/$name';
  final type = _git(['cat-file', '-t', ref]);
  if (version != null && type.exitCode != 0) {
    // Without this the rules would call a missing tag "not annotated".
    throw _CliError(
      'Tag $name was not found in this checkout; fetch tags before running '
      '(fetch-depth: 0).',
    );
  }
  if (version != null && !_refExists('origin/main')) {
    throw _CliError(
      'origin/main is missing in this checkout; check out with '
      'fetch-depth: 0 so tags and remote branches are present.',
    );
  }
  return TagFacts(
    name,
    annotated: type.exitCode == 0 && (type.stdout as String).trim() == 'tag',
    onMain: _isAncestor('$ref^{commit}', 'origin/main'),
    onReleaseBranch:
        version != null &&
        _isAncestor(
          '$ref^{commit}',
          'origin/release/${version.major}.${version.minor}',
        ),
  );
}

void _writeOutputs(BuildPlan plan) {
  final lines = [
    'channel=${_channelName(plan.channel)}',
    'version=${plan.version}',
    'build_number=${plan.buildNumber}',
    'build=${plan.build}',
    'reason=${_oneLine(plan.reason)}',
  ];
  final file = Platform.environment['GITHUB_OUTPUT'];
  if (file != null && file.isNotEmpty) {
    File(
      file,
    ).writeAsStringSync('${lines.join('\n')}\n', mode: FileMode.append);
  }
  lines.forEach(stdout.writeln);
}

String _channelName(Channel channel) => switch (channel) {
  Channel.release => 'release',
  Channel.nightly => 'nightly',
  Channel.dryRun => 'dry-run',
};

/// Outputs and annotations are line based; a value must stay on one line.
String _oneLine(String s) => s.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

/// PGP, SSH and X.509 (`git -c gpg.format=x509`) signatures all end up as a
/// block at the end of the tag message.
final _signatureBlock = RegExp(
  r'-----BEGIN (?:(?:PGP|SSH) SIGNATURE|SIGNED MESSAGE)-----[\s\S]*?'
  r'(?:-----END (?:(?:PGP|SSH) SIGNATURE|SIGNED MESSAGE)-----|$)',
);

/// The annotated tag's message (subject and body) without a signature block.
/// A tag without a message can't produce release notes, so that stops the run.
String _releaseNotes(String tag) {
  final message = _gitText(['tag', '-l', '--format=%(contents)', tag]);
  final notes = message.replaceAll(_signatureBlock, '').trim();
  if (notes.isEmpty) {
    throw _CliError(
      'Tag $tag has no message, and the release notes come from it. Nothing '
      'was built or published: delete the tag (locally and on origin) and '
      'push it again as an annotated tag with notes (git tag -a $tag).',
    );
  }
  return '$notes\n';
}

final _sha = RegExp(r'^[0-9a-fA-F]{7,64}$');

/// Commit subjects since the last delivered nightly, or the last 20 commits
/// when there is no usable SHA (none given, or unknown after a history
/// rewrite).
String _commitNotes(String? lastDeliveredSha) {
  if (lastDeliveredSha != null && _sha.hasMatch(lastDeliveredSha)) {
    final r = _git(['log', '--format=%s', '$lastDeliveredSha..HEAD']);
    if (r.exitCode == 0) return r.stdout as String;
  }
  return _gitText(['log', '--format=%s', '-n', '20', 'HEAD']);
}
