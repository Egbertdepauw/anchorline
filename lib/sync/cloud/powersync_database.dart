/// Opens the app's PowerSync-managed SQLite file.
///
/// Lives alongside the existing Drift database (Phase 2.2a). The file is
/// empty until DAOs are repointed in Phase 2.2b — but PowerSync still
/// needs the schema declared so the SQLite views are materialised.
library;

import 'package:powersync/powersync.dart';

import '../../data/app_data_folder.dart';
import 'powersync_schema.dart';

Future<PowerSyncDatabase> openPowerSyncDatabase() async {
  final path = (await appDataPaths()).powerSyncDatabase;
  final db = PowerSyncDatabase(schema: appSchema, path: path);
  await db.initialize();
  return db;
}
