/// The command line of the publish command: reads the arguments and the
/// environment, runs a [Publisher] and reports in the way GitHub Actions
/// understands (`::error::` on stdout, exit code 1). Kept apart from
/// `publish.dart` so the tests can run it in process.
library;

import 'dart:io';

import 'bucket.dart';
import 'manifest.dart';
import 'publisher.dart';

const String publishUsage = '''
Usage: dart tool/publish/publish.dart <action> [options]

Actions:
  release   --version V --build N --notes-file F --file KEY=PATH ...
            [--force] [--dry-run]
  nightly   --version V --build N --file KEY=PATH ... [--notes-file F]
            [--dry-run]
  rollback  --version V [--dry-run]

KEY is windows-x64, linux-x64 or macos. PATH ends in .exe, .AppImage or .dmg.
--force replaces a release that is already published.
--dry-run reads the bucket and prints the list that would be written; it
uploads and writes nothing.

Environment: DOWNLOADS_BASE_URL (not for rollback), R2_ACCOUNT_ID, R2_BUCKET,
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.''';

/// Runs the publish command and returns its exit code. [environment] is the
/// process environment, [bucketFactory] makes the bucket from it (the AWS CLI
/// by default), [now] is the clock. Output goes to [out] (stdout) and, for
/// usage mistakes, [err] (stderr).
Future<int> runPublishCli(
  List<String> args, {
  required Map<String, String> environment,
  Bucket Function(Map<String, String> env)? bucketFactory,
  required DateTime Function() now,
  StringSink? out,
  StringSink? err,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  int fail(String message) {
    stdoutSink.writeln('::error::${_oneLine(message)}');
    return 1;
  }

  try {
    final options = _Options.parse(args);
    final env = _readEnvironment(environment, options.action);

    // Everything that can be checked without the bucket is checked first.
    final notes = options.action == _Action.rollback ? '' : _readNotes(options);
    final bucket = (bucketFactory ?? AwsCliBucket.fromEnvironment)(environment);
    final publisher = Publisher(
      bucket,
      baseUrl: env.baseUrl ?? '',
      now: now,
      dryRun: options.dryRun,
    );

    final String summary;
    switch (options.action) {
      case _Action.rollback:
        final result = await publisher.rollback(options.version);
        summary = _rollbackSummary(result, options);
      case _Action.release:
      case _Action.nightly:
        final lane = options.action == _Action.release
            ? Lane.releases
            : Lane.nightly;
        final result = await publisher.publish(
          lane: lane,
          version: options.version,
          build: options.build!,
          notes: notes,
          files: options.files,
          force: options.force,
        );
        summary = _publishSummary(lane, result, options);
    }
    stdoutSink.write(summary);
    return 0;
  } on _CliError catch (e) {
    if (e.showUsage) stderrSink.writeln(publishUsage);
    return fail(e.message);
  } on PublishError catch (e) {
    return fail(e.message);
  } on FileSystemException catch (e) {
    return fail(
      'could not read ${e.path ?? 'a file'}: ${e.osError?.message ?? e.message}',
    );
  }
}

/// One line, as an `::error::` annotation has to be.
String _oneLine(String message) =>
    message.replaceAll(RegExp(r'\s+'), ' ').trim();

/// A mistake in the command line or the environment.
class _CliError implements Exception {
  const _CliError(this.message, {this.showUsage = false});

  final String message;
  final bool showUsage;
}

enum _Action { release, nightly, rollback }

class _Options {
  _Options({
    required this.action,
    required this.version,
    required this.build,
    required this.notesFile,
    required this.files,
    required this.dryRun,
    required this.force,
  });

  factory _Options.parse(List<String> args) {
    if (args.isEmpty) {
      throw const _CliError(
        'Missing action: release, nightly or rollback.',
        showUsage: true,
      );
    }
    final action = _Action.values
        .where((a) => a.name == args.first)
        .firstOrNull;
    if (action == null) {
      throw _CliError(
        "Unknown action '${args.first}'; expected release, nightly or "
        'rollback.',
        showUsage: true,
      );
    }

    final values = <String, String>{};
    final files = <String, String>{};
    var dryRun = false;
    var force = false;
    for (var i = 1; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--dry-run') {
        dryRun = true;
        continue;
      }
      if (arg == '--force') {
        force = true;
        continue;
      }
      if (!arg.startsWith('--')) {
        throw _CliError("Unexpected argument '$arg'.", showUsage: true);
      }
      final name = arg.substring(2);
      if (!_valueFlags.contains(name)) {
        throw _CliError("Unknown flag '$arg'.", showUsage: true);
      }
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        throw _CliError('Flag $arg needs a value.', showUsage: true);
      }
      final value = args[++i];
      if (name != 'file') {
        values[name] = value;
        continue;
      }
      final eq = value.indexOf('=');
      if (eq <= 0 || eq == value.length - 1) {
        throw _CliError(
          "Flag --file needs key=path (for example windows-x64=app.exe), "
          "got '$value'.",
          showUsage: true,
        );
      }
      final key = value.substring(0, eq);
      if (files.containsKey(key)) {
        throw _CliError('Flag --file is given twice for $key.');
      }
      files[key] = value.substring(eq + 1);
    }

    if (force && action != _Action.release) {
      throw _CliError(
        '--force is only for release, not ${action.name}.',
        showUsage: true,
      );
    }
    if (action == _Action.rollback) {
      for (final flag in ['build', 'notes-file']) {
        if (values.containsKey(flag)) {
          throw _CliError('--$flag is not used by rollback.', showUsage: true);
        }
      }
      if (files.isNotEmpty) {
        throw const _CliError(
          '--file is not used by rollback.',
          showUsage: true,
        );
      }
    }

    final version = values['version'];
    if (version == null) {
      throw const _CliError('Missing flag --version.', showUsage: true);
    }

    int? build;
    if (action != _Action.rollback) {
      final text = values['build'];
      if (text == null) {
        throw const _CliError('Missing flag --build.', showUsage: true);
      }
      build = int.tryParse(text.trim());
      if (build == null || build <= 0) {
        throw _CliError(
          "Flag --build needs a positive whole number, got '$text'.",
          showUsage: true,
        );
      }
      if (files.isEmpty) {
        throw const _CliError(
          'Give at least one --file key=path.',
          showUsage: true,
        );
      }
      if (action == _Action.release && values['notes-file'] == null) {
        throw const _CliError(
          'A release needs --notes-file (the release notes, taken from the '
          'tag message).',
          showUsage: true,
        );
      }
    }

    return _Options(
      action: action,
      version: version,
      build: build,
      notesFile: values['notes-file'],
      files: files,
      dryRun: dryRun,
      force: force,
    );
  }

  static const _valueFlags = {'version', 'build', 'notes-file', 'file'};

  final _Action action;
  final String version;
  final int? build;
  final String? notesFile;

  /// Platform key to local path, in the order given.
  final Map<String, String> files;
  final bool dryRun;
  final bool force;
}

/// What the environment says; only its names are ever reported.
class _Environment {
  const _Environment(this.baseUrl);

  /// `DOWNLOADS_BASE_URL`, null for a rollback.
  final String? baseUrl;
}

/// The variables the bucket needs (and that CI maps from the R2 secrets).
const _bucketVariables = [
  'R2_ACCOUNT_ID',
  'R2_BUCKET',
  'AWS_ACCESS_KEY_ID',
  'AWS_SECRET_ACCESS_KEY',
];

/// Checks the environment of [action]. A missing or blank variable is listed
/// by name, all of them in one error; no value is ever put into a message.
_Environment _readEnvironment(Map<String, String> env, _Action action) {
  final needsBaseUrl = action != _Action.rollback;
  final required = [
    if (needsBaseUrl) 'DOWNLOADS_BASE_URL',
    ..._bucketVariables,
  ];
  final missing = [
    for (final name in required)
      if ((env[name] ?? '').trim().isEmpty) name,
  ];
  if (missing.isNotEmpty) {
    throw _CliError('Missing environment variables: ${missing.join(', ')}.');
  }
  if (!needsBaseUrl) return const _Environment(null);

  final baseUrl = env['DOWNLOADS_BASE_URL']!.trim();
  final uri = Uri.tryParse(baseUrl);
  if (uri == null ||
      !(uri.scheme == 'https' || uri.scheme == 'http') ||
      uri.host.isEmpty) {
    throw const _CliError(
      'DOWNLOADS_BASE_URL must be an http(s) URL such as https://downloads.example.',
    );
  }
  return _Environment(baseUrl);
}

/// The release notes: required and non-empty for a release, optional for a
/// nightly (empty without a file).
String _readNotes(_Options options) {
  final path = options.notesFile;
  if (path == null) return '';
  final file = File(path);
  if (!file.existsSync()) {
    throw _CliError('The notes file does not exist: $path');
  }
  final notes = file.readAsStringSync().trim();
  if (notes.isEmpty && options.action == _Action.release) {
    throw _CliError('The notes file is empty: $path');
  }
  return notes;
}

String _publishSummary(Lane lane, Manifest result, _Options options) {
  final all = [?result.latest, ...result.previous];
  final entry = all.firstWhere(
    (e) =>
        e.version == options.version &&
        (lane == Lane.releases || e.build == options.build),
  );
  final laneName = lane == Lane.releases ? 'release' : 'nightly';
  final b = StringBuffer(
    options.dryRun
        ? 'Dry run: $laneName ${entry.version} (build ${entry.build})\n'
        : 'Published $laneName ${entry.version} (build ${entry.build})\n',
  );
  for (final file in entry.files.entries) {
    b.writeln('  ${file.key.padRight(11)}  ${file.value.url}');
  }
  if (!identical(entry, result.latest)) {
    b.writeln(
      '${entry.version} is listed under previous; the latest release is '
      'still ${result.latest?.version}.',
    );
  }
  _writeManifestPart(b, manifestKey(lane), result, options.dryRun);
  return b.toString();
}

String _rollbackSummary(Manifest result, _Options options) {
  final b = StringBuffer(
    options.dryRun
        ? 'Dry run: rollback to ${options.version}\n'
        : 'Rolled back: ${options.version} is the latest release again; no '
              'file was deleted\n',
  );
  _writeManifestPart(b, manifestKey(Lane.releases), result, options.dryRun);
  return b.toString();
}

void _writeManifestPart(
  StringBuffer b,
  String key,
  Manifest result,
  bool dryRun,
) {
  if (!dryRun) {
    b.writeln('$key was updated.');
    return;
  }
  b
    ..writeln('$key would become:')
    ..write(result.encode())
    ..writeln('Nothing uploaded.');
}
