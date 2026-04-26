// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'equipment_dao.dart';

// ignore_for_file: type=lint
mixin _$EquipmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $DiveComputersTable get diveComputers => attachedDatabase.diveComputers;
  $OxygenCellsTable get oxygenCells => attachedDatabase.oxygenCells;
  $ScrubberSessionsTable get scrubberSessions =>
      attachedDatabase.scrubberSessions;
  $CylindersTable get cylinders => attachedDatabase.cylinders;
  $PressureMappingsTable get pressureMappings =>
      attachedDatabase.pressureMappings;
  EquipmentDaoManager get managers => EquipmentDaoManager(this);
}

class EquipmentDaoManager {
  final _$EquipmentDaoMixin _db;
  EquipmentDaoManager(this._db);
  $$DiveComputersTableTableManager get diveComputers =>
      $$DiveComputersTableTableManager(_db.attachedDatabase, _db.diveComputers);
  $$OxygenCellsTableTableManager get oxygenCells =>
      $$OxygenCellsTableTableManager(_db.attachedDatabase, _db.oxygenCells);
  $$ScrubberSessionsTableTableManager get scrubberSessions =>
      $$ScrubberSessionsTableTableManager(
        _db.attachedDatabase,
        _db.scrubberSessions,
      );
  $$CylindersTableTableManager get cylinders =>
      $$CylindersTableTableManager(_db.attachedDatabase, _db.cylinders);
  $$PressureMappingsTableTableManager get pressureMappings =>
      $$PressureMappingsTableTableManager(
        _db.attachedDatabase,
        _db.pressureMappings,
      );
}
