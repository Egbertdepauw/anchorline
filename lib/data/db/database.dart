/// CCRLogger Drift database definition.
library;

import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Dives,
  DiveSamples,
  DiveAnnotations,
  DiveComputers,
  OxygenCells,
  ScrubberSessions,
  ImportStates,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
