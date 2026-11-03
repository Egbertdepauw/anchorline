import 'package:ccrlogger/sync/cloud/powersync_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

void main() {
  group('appSchema', () {
    test('declares all sync-eligible tables', () {
      final names = appSchema.tables.map((t) => t.name).toSet();
      expect(names, {
        'dive_annotations',
        'cylinders',
        'oxygen_cells',
        'scrubber_sessions',
        'pressure_mappings',
        'dive_cylinders',
        'dive_bailout_carry',
        'dive_computers',
        // Phase 2.5: dive metadata + samples sync too.
        'dives',
        'dive_samples',
        // Phase 3: per-dive attachments (files + links).
        'dive_attachments',
        // Dive Plan tab: draft + saved plans.
        'dive_plans',
        // Merge dives: reversible stored grouping.
        'dive_merge_links',
        // Gas analyzer: cylinder analysis log.
        'gas_analyses',
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
      const baseRequired = {'owner_id', 'version', 'sync_status'};
      // `dives` is immutable imported data; created_at/updated_at don't
      // apply (it has imported_at instead). `dive_samples` is 1:1 with
      // dives so its soft-delete cascades — no deleted_at column.
      const exemptCreatedUpdated = {'dives'};
      const exemptDeletedAt = {'dive_samples'};
      for (final t in appSchema.tables) {
        final cols = t.columns.map((c) => c.name).toSet();
        expect(cols.containsAll(baseRequired), isTrue,
            reason: '${t.name} missing one of $baseRequired (has $cols)');
        if (!exemptCreatedUpdated.contains(t.name)) {
          expect(cols.contains('created_at'), isTrue,
              reason: '${t.name} missing created_at');
          expect(cols.contains('updated_at'), isTrue,
              reason: '${t.name} missing updated_at');
        }
        if (!exemptDeletedAt.contains(t.name)) {
          expect(cols.contains('deleted_at'), isTrue,
              reason: '${t.name} missing deleted_at (has $cols)');
        }
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
      // Cylinder label fields on gas_analyses (issue #114).
      expect(col('gas_analyses', 'target_o2_percent').type, ColumnType.integer);
      expect(col('gas_analyses', 'target_he_percent').type, ColumnType.integer);
      expect(col('gas_analyses', 'gas_role').type, ColumnType.text);
    });

    test('no raw tables (everything is PowerSync-managed)', () {
      expect(appSchema.rawTables, isEmpty);
    });
  });
}
