import 'dart:io';

import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the PowerSync Sync Streams file (issue #126). A table that is in
/// the client schema but has no stream query never syncs, and the failure
/// is silent: the rows just stay on the device that wrote them. The
/// `user_data` stream has one query per table; the four tables carrying
/// `dc_family` are split between `user_data` (`dc_family IS NULL`) and the
/// gated `libdc_dives` stream.
void main() {
  final config =
      File('infra/powersync-sync-streams.yaml').readAsStringSync();
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

  // Tables whose rows carry dc_family. A libdivecomputer dive (dc_family set)
  // may only reach builds that send dc_engines >= 2, so these tables are
  // split across two streams.
  const gatedTables = {
    'dives',
    'dive_samples',
    'dive_computers',
    'dive_bailout_carry',
  };
  const gateClause = "connection.parameter('dc_engines') >= 2";

  /// The query lines of one stream, from its header to the next stream.
  List<String> streamQueries(String name) {
    final block = RegExp(
      '^  $name:\\s*\\n((?:(?:    .*)?\\n)*)',
      multiLine: true,
    ).firstMatch(config);
    expect(block, isNotNull, reason: 'stream $name exists');
    return [
      for (final l in block!.group(1)!.split('\n'))
        if (l.trim().startsWith('- SELECT')) l.trim(),
    ];
  }

  String? tableOf(String line) => query.firstMatch(line)?.group(1);

  test('ungated tables have one query in user_data and none in libdc_dives',
      () {
    final schemaTables = appSchema.tables.map((t) => t.name).toSet();
    final userData = streamQueries('user_data');
    final libdc = streamQueries('libdc_dives');
    final userTables = [for (final l in userData) tableOf(l)!];
    expect(userTables.toSet(), schemaTables,
        reason: 'user_data covers every table in the client schema');
    expect(userTables.length, userTables.toSet().length,
        reason: 'no table is listed twice in user_data');
    final libdcTables = [for (final l in libdc) tableOf(l)!];
    expect(libdcTables.toSet().intersection(schemaTables.difference(gatedTables)),
        isEmpty);
  });

  test('gated tables have one dc_family IS NULL query in user_data and one '
      'gated dc_family IS NOT NULL query in libdc_dives', () {
    final userData = streamQueries('user_data');
    final libdc = streamQueries('libdc_dives');
    for (final t in gatedTables) {
      final u = userData.where((l) => tableOf(l) == t).toList();
      expect(u, hasLength(1), reason: '$t in user_data');
      expect(u.single,
          '- SELECT * FROM $t WHERE owner_id = auth.user_id() '
          'AND dc_family IS NULL');
      final g = libdc.where((l) => tableOf(l) == t).toList();
      expect(g, hasLength(1), reason: '$t in libdc_dives');
      expect(g.single,
          '- SELECT * FROM $t WHERE owner_id = auth.user_id() '
          'AND dc_family IS NOT NULL AND $gateClause');
    }
  });

  test('every ungated user_data line is exactly the bare owner-scoped query',
      () {
    // No ungated table has a deleted_at filter today; add the table here if
    // one is ever introduced on purpose.
    for (final l in streamQueries('user_data')) {
      final t = tableOf(l)!;
      if (gatedTables.contains(t)) continue;
      expect(l, '- SELECT * FROM $t WHERE owner_id = auth.user_id()',
          reason: 'no OR, no dc_family filter on an ungated table');
    }
  });

  test('libdc_dives selects only the gated tables and is auto-subscribed',
      () {
    final libdc = streamQueries('libdc_dives');
    expect({for (final l in libdc) tableOf(l)!}, gatedTables);
    expect(libdc.length, gatedTables.length);
    expect(
      config,
      contains(RegExp(r'^  libdc_dives:\s*\n    auto_subscribe: true\s*$',
          multiLine: true)),
    );
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
