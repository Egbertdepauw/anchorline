/// Opens the app's PowerSync-managed SQLite file.
///
/// Lives alongside the existing Drift database (Phase 2.2a). The file is
/// empty until DAOs are repointed in Phase 2.2b — but PowerSync still
/// needs the schema declared so the SQLite views are materialised.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'powersync_schema.dart';

Future<PowerSyncDatabase> openPowerSyncDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final path = p.join(dir.path, 'powersync.db');
  final db = PowerSyncDatabase(schema: appSchema, path: path);
  await db.initialize();
  return db;
}
