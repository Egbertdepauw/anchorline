/// Exports one dive and one oxygen cell's mV history, anonymised, as the
/// website showcase JSON.
///
/// Usage (not `dart run`, which triggers the package's build hooks):
///   dart tool/site_showcase/export.dart --db `powersync.db` \
///       [--dive ID] [--cell ID] [--out showcase.json]
///
/// The human-readable summary (dive number, date, depth, cell label) goes to
/// stdout only; it is never written to the output file.
library;

import 'dart:convert';
import 'dart:io';

import 'lib/showcase.dart';
import 'lib/showcase_db.dart';

const _usage =
    'Usage: dart tool/site_showcase/export.dart --db <path> '
    '[--dive <id>] [--cell <id>] [--out <file>]';

Never _usageError(String message) {
  stderr.writeln(message);
  stderr.writeln(_usage);
  exit(1);
}

void main(List<String> args) {
  final opts = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!const {'--db', '--dive', '--cell', '--out'}.contains(a)) {
      _usageError('Unknown argument: $a');
    }
    if (i + 1 >= args.length) _usageError('Missing value for $a');
    opts[a] = args[++i];
  }
  final dbPath = opts['--db'];
  if (dbPath == null) _usageError('Missing --db');
  if (!File(dbPath).existsSync()) _usageError('Cannot read database: $dbPath');

  final ShowcaseExport result;
  final ShowcaseDb db;
  try {
    db = SqliteShowcaseDb(dbPath);
  } catch (e) {
    _usageError('Cannot open database $dbPath: $e');
  }
  try {
    result = buildShowcase(
      db: db,
      diveId: opts['--dive'],
      cellId: opts['--cell'],
    );
  } on ArgumentError catch (e) {
    _usageError('${e.message}');
  } on StateError catch (e) {
    _usageError(e.message);
  } finally {
    db.close();
  }

  final out = File(opts['--out'] ?? 'showcase.json');
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result.json)}\n',
  );
  stdout.writeln(result.summary);
  stdout.writeln('Wrote ${out.path}');
}
