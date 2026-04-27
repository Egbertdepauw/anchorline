// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dive_annotations_dao.dart';

// ignore_for_file: type=lint
mixin _$DiveAnnotationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $DivesTable get dives => attachedDatabase.dives;
  $DiveAnnotationsTable get diveAnnotations => attachedDatabase.diveAnnotations;
  $DiveCylindersTable get diveCylinders => attachedDatabase.diveCylinders;
  DiveAnnotationsDaoManager get managers => DiveAnnotationsDaoManager(this);
}

class DiveAnnotationsDaoManager {
  final _$DiveAnnotationsDaoMixin _db;
  DiveAnnotationsDaoManager(this._db);
  $$DivesTableTableManager get dives =>
      $$DivesTableTableManager(_db.attachedDatabase, _db.dives);
  $$DiveAnnotationsTableTableManager get diveAnnotations =>
      $$DiveAnnotationsTableTableManager(
        _db.attachedDatabase,
        _db.diveAnnotations,
      );
  $$DiveCylindersTableTableManager get diveCylinders =>
      $$DiveCylindersTableTableManager(_db.attachedDatabase, _db.diveCylinders);
}
