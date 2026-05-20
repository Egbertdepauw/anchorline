import 'package:ccrlogger/data/db/database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dive_plans table exists and round-trips a row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customInsert(
      "INSERT INTO dive_plans "
      "(id, name, mode, gases_json, segments_json, bailout_json, "
      "settings_json, notes, created_at, updated_at, deleted_at, "
      "owner_id, version, sync_status) "
      "VALUES ('p1', NULL, 'cc', '[]', '[]', '[]', NULL, NULL, "
      "1700000000000, 1700000000000, NULL, NULL, 1, 0)",
    );
    final rows = await db.customSelect(
      "SELECT id, mode FROM dive_plans WHERE id = 'p1'",
    ).get();
    expect(rows.length, 1);
    expect(rows.first.data['mode'], 'cc');
    await db.close();
  });
}
