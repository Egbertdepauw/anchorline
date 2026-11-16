import 'dart:io';

import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the PowerSync Sync Streams file (issue #126). A table that is in
/// the client schema but has no stream query never syncs, and the failure
/// is silent: the rows just stay on the device that wrote them.
void main() {
  final config =
      File('infra/powersync-sync-rules.yaml').readAsStringSync();
  final query = RegExp(
    r'^\s*-\s*SELECT \* FROM ([a-z_]+) WHERE owner_id = auth\.user_id\(\)([ \t].*)?$',
    multiLine: true,
  );
  final streamTables = [
    for (final m in query.allMatches(config)) m.group(1)!,
  ];

  test('uses Sync Streams edition 3, not the deprecated Sync Rules', () {
    expect(config, contains(RegExp(r'^config:\s*\n\s+edition: 3\s*$',
        multiLine: true)));
    expect(config, isNot(contains('bucket_definitions')));
    expect(config, isNot(contains('request.user_id()')));
  });

  test('auto-subscribes the user_data stream, so clients need no subscribe '
      'call', () {
    expect(
      config,
      contains(RegExp(r'^  user_data:\s*\n    auto_subscribe: true\s*$',
          multiLine: true)),
    );
  });

  test('has one owner-scoped query for every table in the client schema',
      () {
    final schemaTables = appSchema.tables.map((t) => t.name).toSet();
    expect(streamTables.toSet(), schemaTables);
    expect(streamTables.length, streamTables.toSet().length,
        reason: 'no table is listed twice');
  });

  test('every query line is owner-scoped', () {
    final selects = RegExp(r'^\s*-\s*SELECT', multiLine: true)
        .allMatches(config)
        .length;
    expect(selects, streamTables.length,
        reason: 'every query must be one line of the form '
            '"- SELECT * FROM <table> WHERE owner_id = auth.user_id() ..."; '
            'a query that does not start that way is either not owner-scoped '
            '(it would sync other users\' rows) or written in a form this '
            'test cannot read (a block scalar, a column list)');
  });
}
