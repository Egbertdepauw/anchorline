import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

void main() {
  group('appSchema', () {
    test('declares all seven sync-eligible tables', () {
      final names = appSchema.tables.map((t) => t.name).toSet();
      expect(names, {
        'dive_annotations',
        'cylinders',
        'oxygen_cells',
        'scrubber_sessions',
        'pressure_mappings',
        'dive_cylinders',
        'dive_computers',
      });
    });

    test('no table declares its own id column (PowerSync auto-adds it)', () {
      // PowerSync's Table.validate() throws AssertionError if a column named
      // "id" is declared, so calling it serves as the assertion here too.
      for (final t in appSchema.tables) {
        t.validate();
        expect(t.columns.any((c) => c.name == 'id'), isFalse,
            reason: '${t.name} must not declare an id column');
      }
    });

    test('every table carries the sync-metadata columns', () {
      const required = {
        'owner_id',
        'created_at',
        'updated_at',
        'deleted_at',
        'version',
        'sync_status',
      };
      for (final t in appSchema.tables) {
        final cols = t.columns.map((c) => c.name).toSet();
        expect(cols.containsAll(required), isTrue,
            reason: '${t.name} missing one of $required (has $cols)');
      }
    });

    test('column types match the Postgres schema', () {
      Column col(String table, String name) => appSchema.tables
          .firstWhere((t) => t.name == table)
          .columns
          .firstWhere((c) => c.name == name);

      // jsonb -> text (we encode/decode in Dart)
      expect(col('dive_annotations', 'buddies_json').type, ColumnType.text);
      expect(col('dive_annotations', 'tags_json').type, ColumnType.text);
      // double precision -> real
      expect(col('cylinders', 'volume_liters').type, ColumnType.real);
      // bigint timestamps -> integer
      expect(col('dive_annotations', 'created_at').type, ColumnType.integer);
      expect(col('dive_computers', 'serial').type, ColumnType.integer);
    });

    test('no raw tables (everything is PowerSync-managed)', () {
      expect(appSchema.rawTables, isEmpty);
    });
  });
}
